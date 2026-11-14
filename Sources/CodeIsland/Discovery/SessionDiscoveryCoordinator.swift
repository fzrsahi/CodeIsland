import Foundation
import CoreServices
import os.log
import CodeIslandCore

private let log = Logger(subsystem: "com.codeisland", category: "AppState")

/// FSEventStream context target. Callbacks hold an unretained pointer to this
/// box (not the coordinator), and reach the owner only through `weak`, so
/// queued main-queue deliveries stay safe if the coordinator tears down off
/// the main actor.
private final class ProjectsWatcherBox: @unchecked Sendable {
    weak var coordinator: SessionDiscoveryCoordinator?
    private let lock = NSLock()
    private var cancelled = false
    /// The queue the FSEvents callback runs on. Reading the event paths (and
    /// deciding they are uninteresting) happens here, not on the main thread.
    let queue = DispatchQueue(label: "com.codeisland.discovery.fsevents", qos: .utility)

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    /// Runs on `queue`. Only the path filter happens here — reading the
    /// coordinator (a `@MainActor` weak reference) off the main thread would be
    /// a data race — and a batch worth scanning hops to the main actor.
    func handleChange(paths: [String]) {
        lock.lock()
        let isCancelled = cancelled
        lock.unlock()
        guard !isCancelled else { return }
        let tailed = SessionDiscovery.tailedTranscriptPathsSnapshot()
        guard DiscoveryScanPolicy.hasInterestingEvent(paths: paths, tailedPaths: tailed) else { return }
        Task { @MainActor [weak self] in
            self?.coordinator?.handleInterestingProjectsDirChange()
        }
    }
}

/// Runs session discovery for AppState: the FSEvents watcher on the agents'
/// session stores, the scans it triggers, and the low-frequency Codex Desktop
/// poll the cleanup tick asks for. Scans run off the main actor (they read
/// every process and the stores under ~); each scan's sessions are handed to
/// `onDiscovered` on the main actor, where AppState integrates them.
@MainActor
final class SessionDiscoveryCoordinator {
    /// What discovery reads, injectable for tests. The live scanners read the
    /// machine: every process and the agents' session stores under ~, and
    /// each session a scan returns gets a process monitor — and the orphan
    /// reaper — on one of the user's real CLIs. A test process reads nothing
    /// (`inert`) unless a test installs a scanner.
    struct Scanners: Sendable {
        /// The full scan, over every enabled source.
        var sessions: @Sendable () -> [DiscoveredSession]
        /// Codex Desktop threads from Codex's state database.
        var codexDesktopSessions: @Sendable () -> [DiscoveredSession]
        /// The Cursor Agent Task index: a walk of `~/.cursor/projects`.
        var cursorSubagentIndex: @Sendable () -> CursorSubagentTranscriptIndex
        /// The session stores the watcher follows (none: no watcher).
        var watchRoots: @Sendable () -> [String]

        static let live = Scanners(
            sessions: { SessionDiscovery.findDiscoveredSessions() },
            codexDesktopSessions: {
                ConfigInstaller.isEnabled(source: "codex")
                    ? CodexDiscovery.findRecentCodexDesktopSessions()
                    : []
            },
            cursorSubagentIndex: {
                CursorSubagentTranscriptIndex.scan(home: FileManager.default.homeDirectoryForCurrentUser.path)
            },
            watchRoots: { SessionDiscovery.discoveryWatchRoots() }
        )

        static let inert = Scanners(
            sessions: { [] },
            codexDesktopSessions: { [] },
            cursorSubagentIndex: { CursorSubagentTranscriptIndex(pathsBySessionId: [:], builtAt: Date()) },
            watchRoots: { [] }
        )

        /// `inert` in a test process, `live` otherwise.
        static var current: Scanners {
            RuntimeEnvironment.isRunningTests ? .inert : .live
        }
    }

    var scanners: Scanners
    /// Receives each scan's sessions, on the main actor.
    var onDiscovered: ([DiscoveredSession]) -> Void = { _ in }

    // Torn down from `deinit`, which may run off the main actor (AppState is
    // released there by async XCTest ARC). Only mutated on the main actor.
    nonisolated(unsafe) private var fsEventStream: FSEventStreamRef?
    nonisolated(unsafe) private var projectsWatcherBox: ProjectsWatcherBox?
    nonisolated(unsafe) private var scanTask: Task<Void, Never>?
    private var pendingRescan = false
    nonisolated(unsafe) private var codexDesktopScanTask: Task<Void, Never>?
    private var lastCodexDesktopPollAt: Date?
    /// Leading + trailing scan throttle (see `DiscoveryScanThrottle`).
    private var scanThrottle = DiscoveryScanThrottle()
    private var trailingScanTask: Task<Void, Never>?
    /// Bumped by `stop()`: a scan from before it lands dropped, and leaves
    /// alone the handle of a scan started since.
    private var generation = 0
    /// From `stop()` until `start()`: a cleanup tick or watcher event still
    /// queued from before starts no scan.
    private var isStopped = false

    init(scanners: Scanners = .current) {
        self.scanners = scanners
    }

    deinit {
        // Must not use MainActor.assumeIsolated: this may run off the main
        // actor. Weak-boxed FSEvents + main-synced teardown keep it crash-free.
        tearDownProjectsWatcher()
        scanTask?.cancel()
        codexDesktopScanTask?.cancel()
    }

    /// Start discovering: the initial scan, then the watcher. Discovery runs
    /// from creation; this resumes it after `stop()`.
    func start() {
        isStopped = false
        requestScan()
        startProjectsWatcher()
    }

    /// Scan every enabled source; a request made while a scan runs is
    /// coalesced into one rescan after it.
    func requestScan() {
        guard !isStopped else { return }
        if scanTask != nil {
            pendingRescan = true
            return
        }

        pendingRescan = false
        PerfCounters.shared?.bump(.discoveryScan)
        let scan = scanners.sessions
        let generation = self.generation
        scanTask = Task.detached { [weak self] in
            let started = Date()
            // One process snapshot for the whole scan: every source shares the
            // paths it reads instead of asking the kernel again.
            ProcessTable.beginScanSnapshot()
            let discovered = scan()
            ProcessTable.endScanSnapshot()
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            PerfCounters.shared?.bump(.discoveryScanMs, by: elapsedMs)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.generation == generation else { return }
                guard !Task.isCancelled else {
                    self.scanTask = nil
                    return
                }
                self.onDiscovered(discovered)
                self.scanTask = nil
                if self.pendingRescan {
                    self.pendingRescan = false
                    self.requestScan()
                }
            }
        }
    }

    /// FSEvents is not guaranteed to report every append below
    /// `~/.codex/sessions` on all macOS/filesystem combinations. Reuse the
    /// cleanup tick as a low-frequency fallback, but only while Codex Desktop
    /// is running and only after the polling interval has elapsed.
    nonisolated static func shouldPollCodexDesktopDiscovery(
        runningBundleIdentifiers: Set<String>,
        lastPollAt: Date?,
        now: Date,
        interval: TimeInterval = 6
    ) -> Bool {
        guard runningBundleIdentifiers.contains(AppState.codexAppBundleId) else { return false }
        guard let lastPollAt else { return true }
        return now.timeIntervalSince(lastPollAt) >= interval
    }

    /// The cleanup tick's Codex Desktop poll (`shouldPollCodexDesktopDiscovery`).
    /// `runningBundleIdentifiers` is only asked for once the interval has
    /// elapsed: building it goes out to LaunchServices.
    func pollCodexDesktopIfDue(now: Date, runningBundleIdentifiers: () -> Set<String>) {
        guard !isStopped else { return }
        // Check the cheap clock predicate before the expensive app list: the poll
        // is rate-limited to every 6s, so five of every six ticks can skip it.
        let codexPollIntervalElapsed = lastCodexDesktopPollAt.map {
            now.timeIntervalSince($0) >= 6
        } ?? true
        if codexPollIntervalElapsed, Self.shouldPollCodexDesktopDiscovery(
            runningBundleIdentifiers: runningBundleIdentifiers(),
            lastPollAt: lastCodexDesktopPollAt,
            now: now
        ) {
            lastCodexDesktopPollAt = now
            requestCodexDesktopScan()
        }
    }

    /// Read Codex Desktop's threads from its state database; a request made
    /// while one read runs is dropped.
    func requestCodexDesktopScan() {
        guard !isStopped, codexDesktopScanTask == nil else { return }
        let scan = scanners.codexDesktopSessions
        let generation = self.generation
        codexDesktopScanTask = Task.detached { [weak self] in
            let discovered = scan()
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.generation == generation else { return }
                guard !Task.isCancelled else {
                    self.codexDesktopScanTask = nil
                    return
                }
                self.onDiscovered(discovered)
                self.codexDesktopScanTask = nil
            }
        }
    }

    /// FSEventStream on known session-store roots — fires when transcript/event files change.
    func startProjectsWatcher() {
        guard !isStopped, fsEventStream == nil else { return }
        let watchRoots = scanners.watchRoots()
        guard !watchRoots.isEmpty else { return }

        let box = ProjectsWatcherBox()
        box.coordinator = self

        var context = FSEventStreamContext()
        // Unretained box is owned by `projectsWatcherBox` until
        // `tearDownProjectsWatcher()`; the weak back-pointer keeps callbacks
        // safe across an off-main deinit.
        context.info = Unmanaged.passUnretained(box).toOpaque()

        let stream = FSEventStreamCreate(
            nil,
            { (_, info, eventCount, eventPaths, _, _) in
                guard let info else { return }
                let box = Unmanaged<ProjectsWatcherBox>.fromOpaque(info).takeUnretainedValue()
                // Without `UseCFTypes` the payload is `count` C strings.
                let entries = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>?.self)
                let paths = (0..<Int(eventCount)).compactMap { entries[$0].map { String(cString: $0) } }
                box.handleChange(paths: paths)
            },
            &context,
            watchRoots as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0,  // 2-second latency (coalesces rapid writes)
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagNoDefer
                    | kFSEventStreamCreateFlagFileEvents
            )
        )

        guard let stream = stream else { return }
        FSEventStreamSetDispatchQueue(stream, box.queue)
        FSEventStreamStart(stream)
        self.projectsWatcherBox = box
        self.fsEventStream = stream
        log.info("Discovery watcher started on \(watchRoots.joined(separator: ", "))")
    }

    /// Re-arm the watcher after the watched roots changed, and rescan at once
    /// so sessions already running under a newly added root show up.
    func restartProjectsWatcher() {
        guard !isStopped else { return }
        tearDownProjectsWatcher()
        startProjectsWatcher()
        requestScan()
    }

    /// Stop watching and scanning until `start()`: the watcher, both scans in
    /// flight (what they find is dropped), a pending rescan and the Codex
    /// Desktop poll's clock.
    func stop() {
        isStopped = true
        generation += 1
        tearDownProjectsWatcher()
        scanTask?.cancel()
        scanTask = nil
        pendingRescan = false
        codexDesktopScanTask?.cancel()
        codexDesktopScanTask = nil
        lastCodexDesktopPollAt = nil
        trailingScanTask?.cancel()
        trailingScanTask = nil
        scanThrottle.reset()
    }

    /// A batch worth scanning for: throttled leading + trailing. The trailing
    /// scan is kept on a timer, so the last lifecycle write of a burst is read
    /// even when the burst is still going when the gap expires.
    fileprivate func handleInterestingProjectsDirChange() {
        guard !isStopped else { return }
        let now = Date()
        switch scanThrottle.decide(hasInterestingEvent: true, now: now) {
        case .ignore:
            return
        case .scanNow:
            scanThrottle.noteScanStarted(at: now)
            trailingScanTask?.cancel()
            trailingScanTask = nil
            requestScan()
        case .scanLater(let due):
            guard trailingScanTask == nil else { return }
            let delay = max(0, due.timeIntervalSince(now))
            trailingScanTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.trailingScanTask = nil
                guard !self.isStopped else { return }
                self.scanThrottle.noteScanStarted(at: Date())
                self.requestScan()
            }
        }
    }

    /// Stops the FSEvents watcher on the main queue so Stop/Invalidate cannot
    /// race a queued callback. Safe to call from `deinit` (any thread).
    nonisolated private func tearDownProjectsWatcher() {
        let run = { [self] in tearDownProjectsWatcherAssumingMain() }
        if Thread.isMainThread {
            run()
        } else {
            DispatchQueue.main.sync(execute: run)
        }
    }

    /// FSEvents teardown; caller must already be on the main queue.
    nonisolated private func tearDownProjectsWatcherAssumingMain() {
        // Flip cancel before stopping so any already-queued callback no-ops
        // instead of touching a dying coordinator / freed box.
        projectsWatcherBox?.cancel()
        if let stream = fsEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            fsEventStream = nil
        }
        let box = projectsWatcherBox
        projectsWatcherBox = nil
        // Keep the box alive until after previously queued main-queue
        // callbacks drain (Invalidate does not flush them).
        if let box {
            DispatchQueue.main.async { _ = box }
        }
    }
}
