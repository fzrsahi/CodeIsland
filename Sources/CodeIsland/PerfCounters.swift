import Foundation

/// Event counters for `scripts/perf/bench.sh`.
///
/// Off unless the app is launched with `CODEISLAND_PERF_COUNTERS=<file.json>`:
/// then `shared` exists, and the counts are written to that file every 5
/// seconds and when the app quits. Without the variable `shared` is nil and
/// every call site costs one nil check.
final class PerfCounters: @unchecked Sendable {
    enum Name: String {
        /// Cleanup ticks that ran their sweep.
        case cleanupTickWork
        /// Cleanup ticks that returned before sweeping.
        case cleanupTickSkipped
        /// Session discovery scans started.
        case discoveryScan
        /// Buddy (ESP32) flush attempts, connected or not.
        case publishESP32
        /// Companion flush attempts, enabled or not.
        case publishCompanion
        /// `layout()` passes of the panel's hosting view.
        case hostingLayoutPass
        /// PrayerTimeManager ticks that did work.
        case prayerTick
        /// NowPlaying timer ticks (idle discovery and progress).
        case nowPlayingTick
    }

    static let shared: PerfCounters? = {
        guard let path = ProcessInfo.processInfo.environment["CODEISLAND_PERF_COUNTERS"],
              !path.isEmpty else { return nil }
        return PerfCounters(url: URL(fileURLWithPath: path))
    }()

    private let url: URL
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private let started = Date()
    private var timer: DispatchSourceTimer?

    private init(url: URL) {
        self.url = url
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 5, repeating: 5, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in self?.write() }
        timer.resume()
        self.timer = timer
        write()
    }

    func bump(_ name: Name, by amount: Int = 1) {
        bump(name.rawValue, by: amount)
    }

    /// PROTOTYPE (ca-music-visuals): read a counter for the switcher panel.
    func count(_ name: Name) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[name.rawValue] ?? 0
    }

    /// AppleScript runs per target (`spotify`, `music`, a browser's raw value).
    func bumpAppleScript(target: String) {
        bump("appleScriptExec.\(target)")
    }

    private func bump(_ key: String, by amount: Int = 1) {
        lock.lock()
        counts[key, default: 0] += amount
        lock.unlock()
    }

    /// Writes the current counts. Also called at quit.
    func write() {
        lock.lock()
        let snapshot = counts
        lock.unlock()
        let body: [String: Any] = [
            "uptimeSeconds": Date().timeIntervalSince(started),
            "counters": snapshot,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
