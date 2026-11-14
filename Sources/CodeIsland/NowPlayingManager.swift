import Foundation
import Combine
import AppKit
import SwiftUI
import ApplicationServices
import os

private let log = Logger(subsystem: "com.codeisland", category: "NowPlaying")

// MARK: - Synced Lyric Model

struct LyricLine: Identifiable, Equatable, Sendable {
    let id: Int
    let timestamp: Double
    let text: String
}

// MARK: - Supported Web Browsers, Web Music Services & Playback Source Models

enum WebMusicService: String, CaseIterable, Equatable, Hashable, Sendable {
    case spotifyWeb = "spotify"
    case youtubeMusic = "ytmusic"
    case appleMusicWeb = "applemusic"

    var domainSubstring: String {
        switch self {
        case .spotifyWeb: return "open.spotify.com"
        case .youtubeMusic: return "music.youtube.com"
        case .appleMusicWeb: return "music.apple.com"
        }
    }

    var badgePrefix: String {
        switch self {
        case .spotifyWeb: return "SPOTIFY"
        case .youtubeMusic: return "YT MUSIC"
        case .appleMusicWeb: return "APPLE MUSIC"
        }
    }

    func badge(for browser: SpotifyWebBrowser) -> String {
        "\(badgePrefix) · \(browser.shortBrowserName)"
    }

    /// Lower wins. Desktop players outrank browsers; among browsers the Spotify probe is the
    /// most mature, so it outranks the two title-only-friendly services.
    var priority: Int {
        switch self {
        case .spotifyWeb: return 2
        case .youtubeMusic: return 3
        case .appleMusicWeb: return 4
        }
    }
}

enum SpotifyWebBrowser: String, CaseIterable, Equatable, Hashable, Sendable {
    case safari = "com.apple.Safari"
    case brave = "com.brave.Browser"
    case chrome = "com.google.Chrome"
    case arc = "company.thebrowser.Browser"
    case edge = "com.microsoft.edgemac"

    var bundleIdentifier: String { rawValue }

    var applicationName: String {
        switch self {
        case .safari: return "Safari"
        case .brave: return "Brave Browser"
        case .chrome: return "Google Chrome"
        case .arc: return "Arc"
        case .edge: return "Microsoft Edge"
        }
    }

    var shortBrowserName: String {
        switch self {
        case .safari: return "SAFARI"
        case .brave: return "BRAVE"
        case .chrome: return "CHROME"
        case .arc: return "ARC"
        case .edge: return "EDGE"
        }
    }

    var shortBadge: String {
        WebMusicService.spotifyWeb.badge(for: self)
    }

    var isSafari: Bool {
        self == .safari
    }

    var jsPermissionHint: String {
        switch self {
        case .safari:
            return "Enable Safari → Develop → Allow JavaScript from Apple Events for full sync & controls"
        case .brave:
            return "Enable Brave → View → Developer → Allow JavaScript from Apple Events for full sync & controls"
        case .chrome:
            return "Enable Chrome → View → Developer → Allow JavaScript from Apple Events for full sync & controls"
        case .arc:
            return "Enable Arc → View → Developer → Allow JavaScript from Apple Events for full sync & controls"
        case .edge:
            return "Enable Edge → View → Developer → Allow JavaScript from Apple Events for full sync & controls"
        }
    }
}

enum PlaybackSourceKind: Equatable, Hashable, Sendable {
    case spotifyDesktop
    case appleMusic
    case webMusic(service: WebMusicService, browser: SpotifyWebBrowser)

    static func spotifyWeb(_ browser: SpotifyWebBrowser) -> PlaybackSourceKind {
        .webMusic(service: .spotifyWeb, browser: browser)
    }

    var displayBadge: String {
        switch self {
        case .spotifyDesktop:
            return "Spotify"
        case .appleMusic:
            return "Music"
        case .webMusic(let service, let browser):
            return service.badge(for: browser)
        }
    }

    /// Lower wins. Explicit so `resolvePreferredSnapshot` never depends on the order
    /// `fetchPlaybackDetails` happens to append candidates in.
    var priority: Int {
        switch self {
        case .spotifyDesktop: return 0
        case .appleMusic: return 1
        case .webMusic(let service, _): return service.priority
        }
    }
}

struct PlaybackSnapshot: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String
    let position: Double
    let duration: Double
    let artworkURLOrPath: String
    let isPlaying: Bool
    let source: PlaybackSourceKind
    let isJSBridgeAvailable: Bool
}

/// Claims the single playback-probe slot. Thread-safe because the probe queue releases it.
/// Dropping a poll while a probe is in flight is deliberate: queueing them lets a browser stuck
/// on a modal dialog pile up work, and discarding their results freezes the HUD.
final class FetchGate: @unchecked Sendable {
    private let lock = NSLock()
    private var running = false

    /// True when this caller took the slot. False when a probe is already in flight.
    func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if running { return false }
        running = true
        return true
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        running = false
    }
}

/// Observes currently playing tracks from Apple Music, Spotify Desktop, and Web Music Players (Spotify Web, YouTube Music, Apple Music Web) across macOS browsers.
@MainActor
final class NowPlayingManager: ObservableObject {
    static let shared = NowPlayingManager()

    @Published var isPlaying: Bool = false
    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var album: String = ""
    @Published var player: String = "" // "Spotify", "Music", "SPOTIFY · BRAVE", "YT MUSIC · CHROME", etc.
    @Published var artworkURL: String = ""
    @Published var artworkImage: NSImage? {
        didSet {
            updateAlbumPalette(from: artworkImage)
        }
    }
    @Published var albumPalette: AlbumArtPalette = .fallback
    /// Bumped per artwork request so a slow load cannot land on a newer track.
    private var artworkToken = 0
    /// Where the track was, when, and how fast it is moving from there.
    /// The position is derived from this, so a playing track does not need a
    /// 4 Hz publish: the bar reads the anchor and interpolates locally.
    struct PlaybackAnchor: Equatable, Sendable {
        var position: Double
        var at: Date
        var rate: Double

        func position(at now: Date) -> Double {
            position + rate * max(0, now.timeIntervalSince(at))
        }
    }

    @Published private(set) var playbackAnchor = PlaybackAnchor(position: 0, at: Date(), rate: 0)

    /// The current position, interpolated from the anchor. Published only
    /// through `playbackAnchor`, which changes on play, pause, seek and track
    /// change — not four times a second.
    var playerPosition: Double { playbackAnchor.position(at: Date()) }

    /// The position as of a specific instant (the progress bar's timeline).
    func position(at date: Date) -> Double {
        min(trackDuration > 0 ? trackDuration : .greatestFiniteMagnitude,
            playbackAnchor.position(at: date))
    }

    /// Move the anchor and, with it, the published position.
    private func setAnchor(position: Double, playing: Bool, at now: Date = Date()) {
        let anchor = PlaybackAnchor(position: position, at: now, rate: playing ? 1 : 0)
        if playbackAnchor != anchor { playbackAnchor = anchor }
    }
    @Published var trackDuration: Double = 0
    @Published var showToast: Bool = false
    @Published var lyrics: [LyricLine] = []
    @Published var currentLyricIndex: Int = 0
    @Published var lyricsLoading: Bool = false
    @Published var activeSource: PlaybackSourceKind?
    @Published var isBrowserJSHintVisible: Bool = false
    @Published var browserJSHintText: String = ""

    private var toastDismissTimer: Timer?
    private var progressTimer: Timer?
    /// The policy's next probe. One-shot: it is re-armed from the answer.
    private var probeTimer: Timer?
    /// Players and browsers that are running, kept by NSWorkspace's launch and
    /// terminate notifications plus one snapshot at start. A probe never asks
    /// Launch Services, and never scripts an app that is not there.
    private var runningTargets: Set<NowPlayingProbeTarget> = []
    /// When the last play/pause/seek/track change landed, for the pause reset.
    private var lastPlaybackChangeAt = Date()
    /// Last notification-driven probe per target, so a chatty player cannot
    /// turn into a probe storm.
    private var lastNotifiedProbeAt: [NowPlayingProbeTarget: Date] = [:]
    private(set) var isDisplayAsleep = false
    private(set) var isScreenLocked = false
    private(set) var isSessionActive = true
    /// Set by the panel: an expanded island may be looked at, so it probes more.
    var isIslandExpanded = false {
        didSet { if isIslandExpanded != oldValue { armProbeTimer() } }
    }
    /// Set by `startSimulatedPlayback`: no player is asked anything any more.
    private(set) var isSimulated = false
    private var lastFetchedLyricsKey: String = ""
    private var lastBrowserSnapshots: [PlaybackSourceKind: PlaybackSnapshot] = [:]
    private let probeQueue = DispatchQueue(label: "com.codeisland.nowplaying.probe", qos: .userInitiated)
    private let fetchGate = FetchGate()

    init() {
        setupObservers()
        guard !RuntimeEnvironment.isRunningTests else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.requestAutomationPermissionIfNeeded()
        }
        refreshRunningTargets()
        fetchPlaybackDetails()
        armProbeTimer()
    }

    nonisolated func requestAutomationPermissionIfNeeded() {
        guard !RuntimeEnvironment.isRunningTests else { return }
        let targets = ["com.spotify.client", "com.apple.Music"]
        for target in targets {
            let desc = NSAppleEventDescriptor(bundleIdentifier: target)
            if let aeDescPtr = desc.aeDesc {
                var addressDesc = aeDescPtr.pointee
                _ = AEDeterminePermissionToAutomateTarget(&addressDesc, typeWildCard, typeWildCard, true)
                AEDisposeDesc(&addressDesc)
            }
        }
    }

    private func setupObservers() {
        let center = DistributedNotificationCenter.default()

        // Apple Music observer
        center.addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAppleMusicNotification(notification)
            }
        }

        // Spotify observer
        center.addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleSpotifyNotification(notification)
            }
        }

        // Display sleep and wake observers for energy efficiency
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDisplaySleep()
            }
        }
        wsCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDisplayWake()
            }
        }

        // Locked screen / inactive session: nobody is looking, so no probe.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isScreenLocked = true
                self?.armProbeTimer()
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isScreenLocked = false
                self?.probeNowAfterResume()
            }
        }
        for name in [NSNotification.Name("com.apple.sessionDidResignActive")] {
            DistributedNotificationCenter.default().addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.isSessionActive = false
                    self?.armProbeTimer()
                }
            }
        }
        for name in [NSNotification.Name("com.apple.sessionDidBecomeActive")] {
            DistributedNotificationCenter.default().addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.isSessionActive = true
                    self?.probeNowAfterResume()
                }
            }
        }

        // Which players exist, kept by the workspace rather than by polling.
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            wsCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleId = app.bundleIdentifier,
                      NowPlayingProbeTarget.target(for: bundleId) != nil else { return }
                Task { @MainActor in
                    self?.refreshRunningTargets()
                    // A player that just appeared may already be playing.
                    if note.name == NSWorkspace.didLaunchApplicationNotification {
                        self?.probeNowAfterResume()
                    } else {
                        self?.armProbeTimer()
                    }
                }
            }
        }
    }

    /// Read which of the players and browsers are running right now.
    private func refreshRunningTargets() {
        var running: Set<NowPlayingProbeTarget> = []
        for target in NowPlayingProbeTarget.allCases {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleIdentifier)
            if apps.contains(where: { !$0.isTerminated }) { running.insert(target) }
        }
        // Browser probes only exist while the web-music detection setting is on.
        if !Self.isWebMusicDetectionEnabled() {
            running = running.filter { !$0.isBrowser }
        }
        runningTargets = running
    }

    /// The current state, as the pure policy sees it.
    private var pollState: NowPlayingPollState {
        NowPlayingPollState(
            runningTargets: runningTargets,
            isPlaying: isPlaying,
            isPaused: !isPlaying && !title.isEmpty && !lyricsLoading,
            activeTarget: activeSource.flatMap(Self.target(for:)),
            lastTarget: activeSource.flatMap(Self.target(for:)),
            isExpanded: isIslandExpanded,
            isDisplayAsleep: isDisplayAsleep,
            isScreenLocked: isScreenLocked,
            isSessionActive: isSessionActive,
            secondsSinceLastChange: Date().timeIntervalSince(lastPlaybackChangeAt)
        )
    }

    private static func target(for source: PlaybackSourceKind) -> NowPlayingProbeTarget? {
        switch source {
        case .spotifyDesktop: return .spotifyDesktop
        case .appleMusic: return .appleMusic
        case .webMusic(_, let browser): return .target(for: browser.bundleIdentifier)
        }
    }

    /// (Re)arm the single pending probe from the policy. Nothing to probe, or
    /// nobody to see the answer, means no timer at all.
    private func armProbeTimer() {
        probeTimer?.invalidate()
        probeTimer = nil
        guard let plan = NowPlayingPollPolicy.nextProbe(pollState) else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: plan.interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.probeTimer = nil
                PerfCounters.shared?.bump(.nowPlayingTick)
                self.fetchPlaybackDetails(targets: plan.targets)
                // Re-armed after the probe lands, so the next interval is
                // measured from the answer rather than from the request.
                self.armProbeTimer()
            }
        }
        timer.tolerance = plan.interval * 0.1
        probeTimer = timer
    }

    /// Back from sleep or lock: one probe right away, then the normal cadence.
    private func probeNowAfterResume() {
        refreshRunningTargets()
        let targets = runningTargets
        if !targets.isEmpty {
            PerfCounters.shared?.bump(.nowPlayingTick)
            fetchPlaybackDetails(targets: targets)
        }
        armProbeTimer()
    }

    /// A player's own notification is evidence, but not a licence to probe
    /// everything: at most one probe per second, to that player only.
    private func probeAfterNotification(_ target: NowPlayingProbeTarget) {
        let now = Date()
        if let last = lastNotifiedProbeAt[target], now.timeIntervalSince(last) < 1 { return }
        lastNotifiedProbeAt[target] = now
        PerfCounters.shared?.bump(.nowPlayingTick)
        fetchPlaybackDetails(targets: [target])
    }

    // Suspend the probe schedule when the display is asleep.
    private func handleDisplaySleep() {
        isDisplayAsleep = true
        armProbeTimer()
    }

    // Resume it, with one probe to catch up, when the display wakes.
    private func handleDisplayWake() {
        isDisplayAsleep = false
        probeNowAfterResume()
        if isPlaying { startProgressTimer() }
    }

    private func extractDouble(from dict: [AnyHashable: Any], keys: [String]) -> Double? {
        for key in keys {
            if let val = dict[key] {
                if let num = val as? NSNumber {
                    return num.doubleValue
                } else if let d = val as? Double {
                    return d
                } else if let i = val as? Int {
                    return Double(i)
                } else if let s = val as? String, let parsed = Double(s) {
                    return parsed
                }
            }
        }
        return nil
    }

    private var isMusicFeatureEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.musicEnabled) as? Bool ?? SettingsDefaults.musicEnabled
    }

    private func handleAppleMusicNotification(_ notification: Notification) {
        guard !isSimulated, isMusicFeatureEnabled, let info = notification.userInfo else { return }
        let state = info["Player State"] as? String ?? ""
        let playing = (state == "Playing")

        let trackTitle = info["Name"] as? String ?? ""
        let trackArtist = info["Artist"] as? String ?? ""
        let trackAlbum = info["Album"] as? String ?? ""

        var rawDuration = extractDouble(from: info, keys: ["Total Time", "Duration"]) ?? 0
        if rawDuration > 1000 {
            rawDuration /= 1000.0
        }

        let rawPos = extractDouble(from: info, keys: ["Player Position", "Position"]) ?? 0

        if playing || activeSource == .appleMusic || activeSource == nil {
            activeSource = .appleMusic
            isBrowserJSHintVisible = false
            browserJSHintText = ""
            updateBasicInfo(
                playing: playing,
                title: trackTitle,
                artist: trackArtist,
                album: trackAlbum,
                source: PlaybackSourceKind.appleMusic.displayBadge,
                position: rawPos,
                duration: rawDuration > 0 ? rawDuration : nil
            )
        }
        probeAfterNotification(.appleMusic)
    }

    private func handleSpotifyNotification(_ notification: Notification) {
        guard !isSimulated, isMusicFeatureEnabled, let info = notification.userInfo else { return }
        let state = info["Player State"] as? String ?? ""
        let playing = (state == "Playing")

        let trackTitle = info["Name"] as? String ?? ""
        let trackArtist = info["Artist"] as? String ?? ""
        let trackAlbum = info["Album"] as? String ?? ""

        var rawDuration = extractDouble(from: info, keys: ["Duration", "duration", "Total Time"]) ?? 0
        if rawDuration > 1000 {
            rawDuration /= 1000.0
        }

        var rawPos = extractDouble(from: info, keys: ["Playback Position", "Position", "position", "Player Position"]) ?? 0
        if rawPos > 1000 && rawDuration > 0 && rawPos > rawDuration {
            rawPos /= 1000.0
        }
        // Spotify macOS audio pipeline outputs audio ahead of its IPC/CEF state clock.
        // Compensate position (+1.65s, adjusted by -0.50s from +2.15s) so default offset 0.0 strictly synchronizes with Spotify audio output.
        if playing && rawPos > 0 {
            rawPos += 1.65
        }
        if rawDuration > 0 {
            rawPos = min(rawDuration, rawPos)
        }

        if playing || activeSource == .spotifyDesktop || activeSource == nil {
            activeSource = .spotifyDesktop
            isBrowserJSHintVisible = false
            browserJSHintText = ""
            updateBasicInfo(
                playing: playing,
                title: trackTitle,
                artist: trackArtist,
                album: trackAlbum,
                source: PlaybackSourceKind.spotifyDesktop.displayBadge,
                position: rawPos,
                duration: rawDuration > 0 ? rawDuration : nil
            )
        }
        probeAfterNotification(.spotifyDesktop)
    }

    private func updateBasicInfo(
        playing: Bool,
        title: String,
        artist: String,
        album: String,
        source: String,
        position: Double? = nil,
        duration: Double? = nil
    ) {
        let trackChanged = (self.title != title || self.artist != artist) && !title.isEmpty
        self.isPlaying = playing
        self.title = title
        self.artist = artist
        self.album = album
        self.player = source

        if let duration = duration, duration > 0 {
            self.trackDuration = duration
        }

        if trackChanged {
            self.setAnchor(position: position ?? 0.0, playing: playing)
            self.currentLyricIndex = 0
            self.lyrics = []
            triggerToast()
            fetchLyrics(title: title, artist: artist)
        } else if let position = position {
            self.setAnchor(position: position, playing: isPlaying)
            self.updateCurrentLyricIndex()
        }

        if self.trackDuration > 0 && self.playerPosition > self.trackDuration {
            self.setAnchor(position: 0, playing: isPlaying)
            self.updateCurrentLyricIndex()
        }

        if playing {
            startProgressTimer()
        } else {
            stopProgressTimer()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                showToast = false
            }
            toastDismissTimer?.invalidate()
        }
    }

    func triggerToast() {
        toastDismissTimer?.invalidate()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            showToast = true
        }
        toastDismissTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                    self?.showToast = false
                }
            }
        }
    }

    public func triggerTestToast() {
        if title.isEmpty {
            title = "Midnight City"
            artist = "M83"
        }
        triggerToast()
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    // MARK: - Playback Progress & Adaptive Polling


    /// No interpolation timer any more: the position comes from the anchor,
    /// and the one thing that still has to happen on time is the lyric line
    /// changing. One timer, armed for the next line's timestamp.
    private func startProgressTimer() {
        updateCurrentLyricIndex()
        scheduleNextLyricWake()
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    /// Arm one timer for the moment the next lyric line starts. Re-armed
    /// whenever the anchor moves (seek, pause, new track) and after each line.
    private func scheduleNextLyricWake() {
        progressTimer?.invalidate()
        progressTimer = nil
        guard isPlaying, !isDisplayAsleep, !lyrics.isEmpty else { return }
        let offset = UserDefaults.standard.double(forKey: SettingsKey.lyricSyncOffset)
        let position = playerPosition + offset
        guard let delay = Self.nextLyricDelay(lyrics: lyrics, position: position) else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.progressTimer = nil
                self.updateCurrentLyricIndex()
                self.scheduleNextLyricWake()
            }
        }
        // A line a few hundredths of a second late is invisible.
        timer.tolerance = min(0.2, delay * 0.1)
        progressTimer = timer
    }

    var currentLyricText: String {
        guard !lyrics.isEmpty else { return "" }
        if let line = lyrics.first(where: { $0.id == currentLyricIndex }) {
            return line.text
        }
        if currentLyricIndex >= 0 && currentLyricIndex < lyrics.count {
            return lyrics[currentLyricIndex].text
        }
        return ""
    }

    private func updateCurrentLyricIndex() {
        guard !lyrics.isEmpty else { return }
        let offset = UserDefaults.standard.double(forKey: SettingsKey.lyricSyncOffset)
        let effectiveTime = max(0, playerPosition + offset)
        if let idx = lyrics.lastIndex(where: { $0.timestamp <= effectiveTime }) {
            let targetId = lyrics[idx].id
            if self.currentLyricIndex != targetId {
                withAnimation(.easeInOut(duration: 0.35)) {
                    self.currentLyricIndex = targetId
                }
            }
        } else {
            let firstId = lyrics.first?.id ?? 0
            if self.currentLyricIndex != firstId {
                withAnimation(.easeInOut(duration: 0.35)) {
                    self.currentLyricIndex = firstId
                }
            }
        }
    }

    // MARK: - Pure Parsing, Sanitization & Priority Helpers

    nonisolated static func sanitizeForLyricsSearch(title: String, artist: String) -> (title: String, artist: String) {
        var cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)

        let noisePatterns = [
            #"\s*\(\s*(?:official\s+(?:music\s+)?video|official\s+audio|official\s+lyric\s+video|official\s+visualizer|lyric\s+video|lyrics?|audio|video|visualizer|hd|4k|hq|remastered[^)]*)\s*\)"#,
            #"\s*\[\s*(?:official\s+(?:music\s+)?video|official\s+audio|official\s+lyric\s+video|official\s+visualizer|lyric\s+video|lyrics?|audio|video|visualizer|hd|4k|hq|remastered[^\]]*)\s*\]"#
        ]

        for pattern in noisePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(cleanTitle.startIndex..<cleanTitle.endIndex, in: cleanTitle)
                cleanTitle = regex.stringByReplacingMatches(in: cleanTitle, options: [], range: range, withTemplate: "")
            }
        }
        cleanTitle = cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        if let topicRegex = try? NSRegularExpression(pattern: #"\s*-\s*topic$"#, options: [.caseInsensitive]) {
            let range = NSRange(cleanArtist.startIndex..<cleanArtist.endIndex, in: cleanArtist)
            cleanArtist = topicRegex.stringByReplacingMatches(in: cleanArtist, options: [], range: range, withTemplate: "")
        }
        // Strip a trailing VEVO channel suffix. A run-together result ("KatyPerryVEVO" ->
        // "KatyPerry") is left as-is: it matches LRCLIB no better or worse than the original,
        // and re-spacing it would mangle real names such as "McCartney".
        if let vevoRegex = try? NSRegularExpression(pattern: #"\s*vevo$"#, options: [.caseInsensitive]) {
            let range = NSRange(cleanArtist.startIndex..<cleanArtist.endIndex, in: cleanArtist)
            cleanArtist = vevoRegex.stringByReplacingMatches(in: cleanArtist, options: [], range: range, withTemplate: "")
        }
        cleanArtist = cleanArtist.trimmingCharacters(in: .whitespacesAndNewlines)

        return (
            title: cleanTitle.isEmpty ? title : cleanTitle,
            artist: cleanArtist.isEmpty ? artist : cleanArtist
        )
    }

    nonisolated static func parseTimecode(_ raw: String) -> Double? {
        let trimmed = raw.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var sign: Double = 1.0
        var body = trimmed
        if body.hasPrefix("-") || body.hasPrefix("−") {
            sign = -1.0
            body = String(body.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        if body.contains(":") {
            let parts = body.components(separatedBy: ":")
            if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
                return sign * (m * 60.0 + s)
            } else if parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) {
                return sign * (h * 3600.0 + m * 60.0 + s)
            }
            return nil
        }

        if let val = Double(body) {
            return sign * val
        }
        return nil
    }

    nonisolated static func parseWebTabTitle(_ rawTitle: String, service: WebMusicService = .spotifyWeb) -> (title: String, artist: String)? {
        var trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("▶") {
            trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        let lower = trimmed.lowercased()
        if lower == "spotify" || lower.hasPrefix("spotify – web player") || lower.hasPrefix("spotify - web player") || lower.hasPrefix("spotify — web player") ||
           lower == "youtube music" || lower == "apple music" || lower.hasPrefix("apple music - web player") || lower.hasPrefix("apple music – web player") {
            return nil
        }

        let suffixes = [
            " - YouTube Music", " – YouTube Music", " | YouTube Music",
            " - Apple Music", " – Apple Music", " — Apple Music", " | Apple Music",
            " - Spotify", " – Spotify", " | Spotify"
        ]
        for suffix in suffixes {
            if trimmed.lowercased().hasSuffix(suffix.lowercased()) {
                trimmed = String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let separators = [" • ", " · ", " - ", " – ", " — "]
        for sep in separators {
            if let range = trimmed.range(of: sep) {
                let track = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let artistPart = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !track.isEmpty {
                    return (track, artistPart)
                }
            }
        }

        if service == .youtubeMusic && !trimmed.isEmpty {
            return (trimmed, "")
        }
        return nil
    }

    nonisolated static func parseBrowserScriptOutput(
        _ rawOutput: String,
        browser: SpotifyWebBrowser,
        previousSnapshot: PlaybackSnapshot?
    ) -> PlaybackSnapshot? {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.components(separatedBy: "|||")
        guard let mode = parts.first else { return nil }

        if mode == "DOM" {
            let service: WebMusicService
            let offset: Int
            if parts.count >= 9, let matchedService = WebMusicService(rawValue: parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
                service = matchedService
                offset = 2
            } else if parts.count >= 8 {
                service = .spotifyWeb
                offset = 1
            } else {
                return nil
            }

            let title = parts[offset].trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = parts[offset + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            let album = parts[offset + 2].trimmingCharacters(in: .whitespacesAndNewlines)
            let posRaw = parts[offset + 3].trimmingCharacters(in: .whitespacesAndNewlines)
            let durRaw = parts[offset + 4].trimmingCharacters(in: .whitespacesAndNewlines)
            let artUrl = parts[offset + 5].trimmingCharacters(in: .whitespacesAndNewlines)
            let state = parts[offset + 6].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            guard !title.isEmpty else { return nil }

            let pos = max(0.0, parseTimecode(posRaw) ?? 0.0)
            let parsedDur = parseTimecode(durRaw) ?? 0.0
            let duration: Double
            if parsedDur < 0 {
                duration = pos + abs(parsedDur)
            } else {
                duration = parsedDur
            }

            return PlaybackSnapshot(
                title: title,
                artist: artist,
                album: album,
                position: pos,
                duration: duration,
                artworkURLOrPath: artUrl,
                isPlaying: state == "playing",
                source: .webMusic(service: service, browser: browser),
                isJSBridgeAvailable: true
            )
        } else if mode == "FALLBACK" {
            let service: WebMusicService
            let tabTitle: String
            if parts.count >= 3, let matchedService = WebMusicService(rawValue: parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
                service = matchedService
                tabTitle = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            } else if parts.count >= 2 {
                service = .spotifyWeb
                tabTitle = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                return nil
            }

            let sourceKind = PlaybackSourceKind.webMusic(service: service, browser: browser)
            if let parsed = parseWebTabTitle(tabTitle, service: service) {
                let sameTrack = (previousSnapshot?.title == parsed.title && previousSnapshot?.artist == parsed.artist)
                return PlaybackSnapshot(
                    title: parsed.title,
                    artist: parsed.artist,
                    album: sameTrack ? (previousSnapshot?.album ?? "") : "",
                    position: sameTrack ? (previousSnapshot?.position ?? 0.0) : 0.0,
                    duration: sameTrack ? (previousSnapshot?.duration ?? 0.0) : 0.0,
                    artworkURLOrPath: sameTrack ? (previousSnapshot?.artworkURLOrPath ?? "") : "",
                    isPlaying: true,
                    source: sourceKind,
                    isJSBridgeAvailable: false
                )
            } else if let prev = previousSnapshot, prev.source == sourceKind, !prev.title.isEmpty {
                return PlaybackSnapshot(
                    title: prev.title,
                    artist: prev.artist,
                    album: prev.album,
                    position: prev.position,
                    duration: prev.duration,
                    artworkURLOrPath: prev.artworkURLOrPath,
                    isPlaying: false,
                    source: sourceKind,
                    isJSBridgeAvailable: false
                )
            }
        }
        return nil
    }

    nonisolated static func resolvePreferredSnapshot(
        candidates: [PlaybackSnapshot],
        lastActiveSource: PlaybackSourceKind?
    ) -> PlaybackSnapshot? {
        let valid = candidates.filter { !$0.title.isEmpty }
        guard !valid.isEmpty else { return nil }

        // Rank by explicit source priority, never by the order candidates were collected.
        let ranked = valid.sorted { $0.source.priority < $1.source.priority }

        // 1. Any actively playing source wins in priority order
        if let playingCandidate = ranked.first(where: { $0.isPlaying }) {
            return playingCandidate
        }

        // 2. When all sources are paused, retain the most recently active source
        if let lastSource = lastActiveSource,
           let stickyCandidate = ranked.first(where: { $0.source == lastSource }) {
            return stickyCandidate
        }

        // 3. Fallback to the highest-priority valid candidate
        return ranked.first
    }

    // MARK: - AppleScript Builders (Multi-Service Web Bridge)

    nonisolated static let webMusicDOMProbeJS: String =
        "(function(){try{" +
        "var host=location.hostname||'';" +
        "var ms=navigator.mediaSession&&navigator.mediaSession.metadata;" +
        "var art='';" +
        "if(ms&&ms.artwork&&ms.artwork.length>0){art=ms.artwork[ms.artwork.length-1].src||'';}" +
        "if(host.indexOf('music.youtube.com')!==-1){" +
        "var tEl=document.querySelector('.title.ytmusic-player-bar');" +
        "var byEl=document.querySelector('.byline.ytmusic-player-bar');" +
        "var title=(ms&&ms.title?ms.title:'')||(tEl&&tEl.textContent?tEl.textContent.trim():'');" +
        "var artist=(ms&&ms.artist?ms.artist:'');" +
        "var album=(ms&&ms.album?ms.album:'');" +
        "if(!artist&&byEl&&byEl.textContent){var bp=byEl.textContent.split('•');artist=(bp[0]||'').trim();if(!album&&bp.length>1){album=(bp[1]||'').trim();}}" +
        "if(!art){var yImg=document.querySelector('.image.ytmusic-player-bar');if(yImg&&yImg.src){art=yImg.src;}}" +
        "var v=document.querySelector('video');" +
        "var pos=v&&!isNaN(v.currentTime)?String(v.currentTime):'0';" +
        "var dur=v&&!isNaN(v.duration)&&isFinite(v.duration)?String(v.duration):'0';" +
        "var playing=v?(!v.paused&&!v.ended&&v.currentTime>0):(navigator.mediaSession&&navigator.mediaSession.playbackState==='playing');" +
        "return 'DOM|||ytmusic|||'+title+'|||'+artist+'|||'+album+'|||'+pos+'|||'+dur+'|||'+art+'|||'+(playing?'playing':'paused');" +
        "}" +
        "if(host.indexOf('music.apple.com')!==-1){" +
        "var mk=(typeof MusicKit!=='undefined'&&MusicKit.getInstance)?MusicKit.getInstance():null;" +
        "var aud=document.querySelector('audio');" +
        "var pEl=document.querySelector('.lcd-meta__primary,[class*=lcd-meta__primary]');" +
        "var sEl=document.querySelector('.lcd-meta__secondary,[class*=lcd-meta__secondary]');" +
        "var title=(ms&&ms.title?ms.title:'')||(pEl&&pEl.textContent?pEl.textContent.trim():'');" +
        "var artist=(ms&&ms.artist?ms.artist:'')||(sEl&&sEl.textContent?sEl.textContent.split('—')[0].trim():'');" +
        "var album=(ms&&ms.album?ms.album:'');" +
        "var pos='0';var dur='0';" +
        "if(mk&&typeof mk.currentPlaybackTime==='number'){pos=String(mk.currentPlaybackTime);dur=String(mk.currentPlaybackDuration||0);}" +
        "else if(aud&&!isNaN(aud.currentTime)){pos=String(aud.currentTime);dur=String(aud.duration||0);}" +
        "var playing=(mk&&mk.isPlaying===true)||(aud&&!aud.paused)||(navigator.mediaSession&&navigator.mediaSession.playbackState==='playing');" +
        "return 'DOM|||applemusic|||'+title+'|||'+artist+'|||'+album+'|||'+pos+'|||'+dur+'|||'+art+'|||'+(playing?'playing':'paused');" +
        "}" +
        "var tEl=document.querySelector('[data-testid=context-item-info-title]');" +
        "var aEl=document.querySelector('[data-testid=context-item-info-subtitles]');" +
        "var title=(tEl&&tEl.textContent?tEl.textContent.trim():'')||(ms&&ms.title?ms.title:'');" +
        "var artist=(aEl&&aEl.textContent?aEl.textContent.trim():'')||(ms&&ms.artist?ms.artist:'');" +
        "var album=(ms&&ms.album?ms.album:'');" +
        "if(!art){var img=document.querySelector('[data-testid=cover-art-image]');if(img&&img.src){art=img.src;}}" +
        "var posEl=document.querySelector('[data-testid=playback-position]');" +
        "var durEl=document.querySelector('[data-testid=playback-duration]');" +
        "var pos=posEl&&posEl.textContent?posEl.textContent.trim():'0:00';" +
        "var dur=durEl&&durEl.textContent?durEl.textContent.trim():'0:00';" +
        "var btn=document.querySelector('[data-testid=control-button-playpause]');" +
        "var lbl=btn?(btn.getAttribute('aria-label')||''):'';" +
        "var isPlaying=false;" +
        "if(lbl.toLowerCase()==='pause'){isPlaying=true;}" +
        "else if(lbl.toLowerCase()==='play'){isPlaying=false;}" +
        "else if(navigator.mediaSession&&navigator.mediaSession.playbackState==='playing'){isPlaying=true;}" +
        "else if(document.title.indexOf('•')!==-1){isPlaying=true;}" +
        "if(!title&&document.title.indexOf('•')!==-1){" +
        "var parts=document.title.split('•');" +
        "title=parts[0].trim();" +
        "artist=parts.slice(1).join('•').replace(/- Spotify.*$/i,'').trim();" +
        "}" +
        "var pState=isPlaying?'playing':'paused';" +
        "return 'DOM|||spotify|||'+title+'|||'+artist+'|||'+album+'|||'+pos+'|||'+dur+'|||'+art+'|||'+pState;" +
        "}catch(e){return 'FALLBACK|||spotify|||'+document.title;}})()"

    nonisolated static func buildBrowserProbeScript(for browser: SpotifyWebBrowser) -> String {
        let titleProperty = browser.isSafari ? "name of t" : "title of t"
        let jsCall = browser.isSafari
            ? "do JavaScript \"\(webMusicDOMProbeJS)\" in t"
            : "execute t javascript \"\(webMusicDOMProbeJS)\""

        return """
        set matchedLines to ""
        with timeout of 8 seconds
            tell application "\(browser.applicationName)"
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            set tabUrl to URL of t
                            set svcId to ""
                            if tabUrl contains "open.spotify.com" then
                                set svcId to "spotify"
                            else if tabUrl contains "music.youtube.com" then
                                set svcId to "ytmusic"
                            else if tabUrl contains "music.apple.com" then
                                set svcId to "applemusic"
                            end if
                            if svcId is not "" then
                                set tabTitle to \(titleProperty)
                                set lineOut to ""
                                try
                                    set domRes to \(jsCall)
                                    if domRes is not missing value and domRes is not "" then
                                        set lineOut to domRes
                                    end if
                                end try
                                if lineOut is "" then
                                    set lineOut to "FALLBACK|||" & svcId & "|||" & tabTitle
                                end if
                                if matchedLines is "" then
                                    set matchedLines to lineOut
                                else
                                    set matchedLines to matchedLines & "\\n" & lineOut
                                end if
                            end if
                        end try
                    end repeat
                end repeat
            end tell
        end timeout
        return matchedLines
        """
    }

    nonisolated static func buildBrowserActionScript(
        for browser: SpotifyWebBrowser,
        service: WebMusicService,
        jsExpression: String
    ) -> String {
        let jsCall = browser.isSafari
            ? "do JavaScript \"\(jsExpression)\" in t"
            : "execute t javascript \"\(jsExpression)\""

        return """
        tell application "\(browser.applicationName)"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if (URL of t) contains "\(service.domainSubstring)" then
                            \(jsCall)
                            return "ok"
                        end if
                    end try
                end repeat
            end repeat
        end tell
        return ""
        """
    }

    /// Reads the browser-detection toggle without relying on `SettingsManager.shared` having
    /// registered its defaults first. `bool(forKey:)` returns `false` for an absent key, so a
    /// plain read can disagree with the documented default depending on singleton init order.
    nonisolated static func isWebMusicDetectionEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard let stored = defaults.object(forKey: SettingsKey.detectSpotifyWebInBrowsers) as? Bool else {
            return SettingsDefaults.detectSpotifyWebInBrowsers
        }
        return stored
    }

    /// The service a probe line belongs to, read from its `DOM|||<svc>|||` / `FALLBACK|||<svc>|||`
    /// prefix. Needed before parsing so each service gets its own previous snapshot.
    nonisolated static func serviceTag(inProbeLine line: String) -> WebMusicService? {
        let parts = line.components(separatedBy: "|||")
        guard parts.count >= 2 else { return nil }
        let raw = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        if let service = WebMusicService(rawValue: raw) { return service }
        // Legacy single-service lines carried no tag.
        return parts[0].hasPrefix("DOM") || parts[0].hasPrefix("FALLBACK") ? .spotifyWeb : nil
    }

    // MARK: - Fetching Playback Details

    /// Probe the players. `targets` limits the probe to the ones the policy
    /// asked for; nil means everything that is running.
    func fetchPlaybackDetails(targets: Set<NowPlayingProbeTarget>? = nil) {
        guard !RuntimeEnvironment.isRunningTests else { return }
        guard !isSimulated else { return }
        guard fetchGate.begin() else {
            // A probe is already in flight; it re-arms when its answer lands.
            return
        }
        let lastSource = self.activeSource
        let previousWebSnapshots = self.lastBrowserSnapshots
        let running = self.runningTargets
        let wanted = targets.map { $0.intersection(running) } ?? running

        // Serial: a slow probe (a browser blocked on a modal dialog) cannot overlap the next one.
        probeQueue.async { [weak self] in
            guard let self else { return }
            defer { self.fetchGate.finish() }
            let isSpotifyRunning = wanted.contains(.spotifyDesktop)
            let isMusicRunning = wanted.contains(.appleMusic)
            let runningBrowsers: [SpotifyWebBrowser] = wanted.compactMap(\.browser)

            guard isSpotifyRunning || isMusicRunning || !runningBrowsers.isEmpty else {
                Task { @MainActor [weak self] in self?.resetToIdle() }
                return
            }

            var candidates: [PlaybackSnapshot] = []
            var updatedWebSnapshots = previousWebSnapshots

            // 1. Desktop Spotify
            if isSpotifyRunning {
                PerfCounters.shared?.bumpAppleScript(target: "spotify")
                let spotifyScript = """
                tell application "Spotify"
                    set trackName to name of current track
                    set trackArtist to artist of current track
                    set trackAlbum to album of current track
                    set trackPos to player position
                    set trackDur to (duration of current track) / 1000
                    try
                        set artUrl to artwork url of current track
                    on error
                        set artUrl to ""
                    end try
                    set pState to player state as string
                    return trackName & "|||" & trackArtist & "|||" & trackAlbum & "|||" & trackPos & "|||" & trackDur & "|||" & artUrl & "|||" & pState
                end tell
                """
                if let rawOutput = Self.runAppleScript(spotifyScript),
                   let snapshot = Self.parseDesktopOutput(rawOutput, source: .spotifyDesktop) {
                    candidates.append(snapshot)
                }
            }

            // 2. Apple Music Desktop
            if isMusicRunning {
                PerfCounters.shared?.bumpAppleScript(target: "music")
                let musicScript = """
                tell application "Music"
                    set trackName to name of current track
                    set trackArtist to artist of current track
                    set trackAlbum to album of current track
                    set trackPos to player position
                    set trackDur to duration of current track
                    set pState to player state as string
                    try
                        if exists (artwork 1 of current track) then
                            set theData to data of artwork 1 of current track
                            set theFile to (open for access POSIX file "/tmp/codeisland_music_art.png" with write permission)
                            set eof theFile to 0
                            write theData to theFile
                            close access theFile
                        end if
                    on error
                        try
                            close access file "/tmp/codeisland_music_art.png"
                        end try
                    end try
                    return trackName & "|||" & trackArtist & "|||" & trackAlbum & "|||" & trackPos & "|||" & trackDur & "|||/tmp/codeisland_music_art.png|||" & pState
                end tell
                """
                if let rawOutput = Self.runAppleScript(musicScript),
                   let snapshot = Self.parseDesktopOutput(rawOutput, source: .appleMusic) {
                    candidates.append(Self.artworkPerTrack(snapshot))
                }
            }

            // 3. Running Web Browsers (open.spotify.com, music.youtube.com, music.apple.com)
            for browser in runningBrowsers {
                PerfCounters.shared?.bumpAppleScript(target: "\(browser)")
                let probeScript = Self.buildBrowserProbeScript(for: browser)
                if let rawOutput = Self.runAppleScript(probeScript) {
                    let lines = rawOutput.components(separatedBy: .newlines)
                    for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                        let service = Self.serviceTag(inProbeLine: line) ?? .spotifyWeb
                        let sourceKind = PlaybackSourceKind.webMusic(service: service, browser: browser)
                        if let snapshot = Self.parseBrowserScriptOutput(
                            line,
                            browser: browser,
                            previousSnapshot: previousWebSnapshots[sourceKind]
                        ) {
                            updatedWebSnapshots[sourceKind] = snapshot
                            candidates.append(snapshot)
                        }
                    }
                }
            }

            guard let chosen = Self.resolvePreferredSnapshot(candidates: candidates, lastActiveSource: lastSource) else {
                Task { @MainActor [weak self] in self?.resetToIdle() }
                return
            }

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.lastBrowserSnapshots = updatedWebSnapshots
                self.applySnapshot(chosen)
            }
        }
    }

    nonisolated private static func parseDesktopOutput(_ rawOutput: String, source: PlaybackSourceKind) -> PlaybackSnapshot? {
        guard !rawOutput.isEmpty else { return nil }
        let parts = rawOutput.components(separatedBy: "|||")
        guard parts.count >= 7 else { return nil }

        let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let artist = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let posStr = parts[3].replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        let durStr = parts[4].replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        let artPathOrUrl = parts[5].trimmingCharacters(in: .whitespacesAndNewlines)
        let state = parts[6].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var pos = Double(posStr) ?? 0
        let dur = Double(durStr) ?? 0
        let playing = (state == "playing")

        // Spotify macOS IPC lag compensation:
        // Spotify's AppleScript IPC position lags behind CoreAudio output.
        // Calibrate by adding +1.65s so scrubber and lyrics match what the ear hears in real-time.
        if source == .spotifyDesktop && pos > 0 && playing {
            pos += 1.65
        }
        if dur > 0 {
            pos = min(dur, pos)
        }

        return PlaybackSnapshot(
            title: title,
            artist: artist,
            album: album,
            position: pos,
            duration: dur,
            artworkURLOrPath: artPathOrUrl,
            isPlaying: playing,
            source: source,
            isJSBridgeAvailable: true
        )
    }

    func applySnapshot(_ chosen: PlaybackSnapshot) {
        guard !isSimulated else { return }
        log.debug(
            "apply \(chosen.source.displayBadge, privacy: .public) playing=\(chosen.isPlaying) pos=\(chosen.position) dur=\(chosen.duration) js=\(chosen.isJSBridgeAvailable)"
        )
        let trackChanged = (self.title != chosen.title || self.artist != chosen.artist) && !chosen.title.isEmpty

        let badge = chosen.source.displayBadge
        self.activeSource = chosen.source
        self.player = badge

        if case .webMusic(_, let browser) = chosen.source, !chosen.isJSBridgeAvailable {
            if !self.isBrowserJSHintVisible { self.isBrowserJSHintVisible = true }
            if self.browserJSHintText != browser.jsPermissionHint { self.browserJSHintText = browser.jsPermissionHint }
        } else {
            if self.isBrowserJSHintVisible { self.isBrowserJSHintVisible = false }
            if !self.browserJSHintText.isEmpty { self.browserJSHintText = "" }
        }

        if self.title != chosen.title { self.title = chosen.title }
        if self.artist != chosen.artist { self.artist = chosen.artist }
        if self.album != chosen.album { self.album = chosen.album }

        if chosen.duration > 0, self.trackDuration != chosen.duration {
            self.trackDuration = chosen.duration
        }

        if trackChanged {
            // A title-only snapshot knows the track but not the transport, so
            // its position must not start interpolating.
            self.setAnchor(
                position: chosen.isJSBridgeAvailable ? max(0.0, chosen.position) : 0,
                playing: chosen.isPlaying && chosen.isJSBridgeAvailable
            )
            self.currentLyricIndex = 0
            self.lyrics = []
            if chosen.isPlaying {
                self.triggerToast()
            }
            self.fetchLyrics(title: chosen.title, artist: chosen.artist)
        } else if chosen.isJSBridgeAvailable && chosen.position >= 0 {
            if abs(self.playerPosition - chosen.position) > 0.75 || self.playerPosition == 0 {
                self.setAnchor(position: chosen.position, playing: chosen.isPlaying && chosen.isJSBridgeAvailable)
                self.updateCurrentLyricIndex()
            }
        }

        if self.trackDuration > 0 && self.playerPosition > self.trackDuration {
            self.setAnchor(position: 0, playing: isPlaying)
            self.updateCurrentLyricIndex()
        }

        if self.isPlaying != chosen.isPlaying || trackChanged {
            self.lastPlaybackChangeAt = Date()
        }
        if self.isPlaying != chosen.isPlaying { self.isPlaying = chosen.isPlaying }
        // Only a probe that could observe transport state may drive the interpolation timer.
        // A title-only (Tier 2) snapshot knows the track but not the position, so advancing
        // from 0 would report progress that was never observed.
        if chosen.isPlaying && chosen.isJSBridgeAvailable {
            self.startProgressTimer()
        } else {
            self.stopProgressTimer()
        }

        self.updateCurrentLyricIndex()
        self.scheduleNextLyricWake()
        self.armProbeTimer()

        // Load artwork if changed
        if self.artworkURL != chosen.artworkURLOrPath {
            self.artworkURL = chosen.artworkURLOrPath
            self.loadArtwork(from: chosen.artworkURLOrPath)
        }

        // Fetch lyrics if not loaded
        if self.lyrics.isEmpty && !chosen.title.isEmpty {
            self.fetchLyrics(title: chosen.title, artist: chosen.artist)
        }
    }

    /// Preview / benchmark only (`--preview music`): plays a fixed track with
    /// synced lyrics and stops asking any player, so no AppleScript runs and no
    /// lyrics are fetched. The progress timer and lyric index run as for a real
    /// track.
    func startSimulatedPlayback(title: String, artist: String, album: String, duration: Double, lrc: String, artwork: NSImage?) {
        isSimulated = true
        probeTimer?.invalidate()
        probeTimer = nil
        activeSource = .spotifyDesktop
        player = PlaybackSourceKind.spotifyDesktop.displayBadge
        isBrowserJSHintVisible = false
        browserJSHintText = ""
        self.title = title
        self.artist = artist
        self.album = album
        trackDuration = duration
        setAnchor(position: 0, playing: false)
        lyrics = Self.parseLRC(lrc)
        currentLyricIndex = lyrics.first?.id ?? 0
        lyricsLoading = false
        artworkURL = ""
        artworkImage = artwork
        isPlaying = true
        triggerToast()
        startProgressTimer()
    }

    /// Clears everything the HUD reads. Called when no source is playing any more so the island
    /// does not keep showing a frozen track (and a position clamped at duration) forever.
    func resetToIdle() {
        // A probe started before simulated playback must not clear it.
        guard !isSimulated else { return }
        guard activeSource != nil || isPlaying || !title.isEmpty else { return }

        stopProgressTimer()
        toastDismissTimer?.invalidate()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            showToast = false
        }

        isPlaying = false
        title = ""
        artist = ""
        album = ""
        player = ""
        artworkURL = ""
        artworkImage = nil
        setAnchor(position: 0, playing: false)
        albumPalette = .fallback
        trackDuration = 0
        lyrics = []
        currentLyricIndex = 0
        lyricsLoading = false
        armProbeTimer()
        lastFetchedLyricsKey = ""
        activeSource = nil
        isBrowserJSHintVisible = false
        browserJSHintText = ""
        lastBrowserSnapshots = [:]
    }

    /// Music writes its cover to one fixed path, so a changed cover and an
    /// unchanged one look identical to the loader and the HUD kept the first
    /// track's art. Copy it to a path that names the track instead.
    nonisolated static func artworkPerTrack(_ snapshot: PlaybackSnapshot) -> PlaybackSnapshot {
        let source = snapshot.artworkURLOrPath
        guard !source.isEmpty, !source.hasPrefix("http"),
              FileManager.default.fileExists(atPath: source) else { return snapshot }
        let key = "\(snapshot.title)|\(snapshot.artist)"
        var hasher = Hasher()
        hasher.combine(key)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("codeisland-artwork-\(UInt(bitPattern: hasher.finalize())).png")
        if !FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.copyItem(atPath: source, toPath: destination.path)
        }
        return PlaybackSnapshot(
            title: snapshot.title, artist: snapshot.artist, album: snapshot.album,
            position: snapshot.position, duration: snapshot.duration,
            artworkURLOrPath: destination.path, isPlaying: snapshot.isPlaying,
            source: snapshot.source, isJSBridgeAvailable: snapshot.isJSBridgeAvailable
        )
    }

    /// How long until the next line starts, from the current position. nil
    /// when the last line is already showing.
    nonisolated static func nextLyricDelay(lyrics: [LyricLine], position: Double) -> TimeInterval? {
        guard let next = lyrics.first(where: { $0.timestamp > position }) else { return nil }
        return max(0.05, next.timestamp - position)
    }

    /// Artwork is downsampled before it is held: a 3000 px cover in a 17 pt
    /// square is tens of megabytes of the footprint for nothing.
    nonisolated static let artworkMaxPixelSize: CGFloat = 256

    /// Load the cover for `pathOrUrl`. A load that is superseded by a new
    /// track is dropped instead of landing on the next track's cover.
    private func loadArtwork(from pathOrUrl: String) {
        artworkToken &+= 1
        let token = artworkToken
        guard !pathOrUrl.isEmpty else {
            self.artworkImage = nil
            return
        }

        if pathOrUrl.hasPrefix("http") {
            guard let url = URL(string: pathOrUrl) else { return }
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let img = Self.downsampledArtwork(data) else { return }
                Task { @MainActor in
                    guard let self, self.artworkToken == token else { return }
                    self.artworkImage = img
                }
            }.resume()
        } else if let img = Self.downsampledArtwork(atPath: pathOrUrl) {
            self.artworkImage = img
        }
    }

    private func loadArtworkFile(url: URL) -> NSImage? { Self.downsampledArtwork(atPath: url.path) }

    nonisolated static func downsampledArtwork(atPath path: String) -> NSImage? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return downsampledArtwork(data)
    }

    nonisolated static func downsampledArtwork(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: artworkMaxPixelSize,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(data: data)
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private func updateAlbumPalette(from image: NSImage?) {
        guard let image else {
            self.albumPalette = .fallback
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let palette = AlbumColorExtractor.extractPalette(from: image)
            Task { @MainActor in
                self?.albumPalette = palette
            }
        }
    }

    // MARK: - Lyrics Engine

    func fetchLyrics(title: String, artist: String) {
        guard !RuntimeEnvironment.isRunningTests else { return }
        let sanitized = Self.sanitizeForLyricsSearch(title: title, artist: artist)
        let key = "\(sanitized.title):::\(sanitized.artist)"
        guard key != lastFetchedLyricsKey && !sanitized.title.isEmpty else { return }
        lastFetchedLyricsKey = key
        lyricsLoading = true

        guard let encodedTitle = sanitized.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedArtist = sanitized.artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            lyricsLoading = false
            return
        }

        var primaryUrlString = "https://lrclib.net/api/get?track_name=\(encodedTitle)&artist_name=\(encodedArtist)"
        let shouldIncludeDuration = trackDuration > 0
        if shouldIncludeDuration {
            primaryUrlString += "&duration=\(Int(trackDuration))"
        }

        guard let primaryUrl = URL(string: primaryUrlString) else {
            lyricsLoading = false
            return
        }

        let fallbackUrl = URL(string: "https://lrclib.net/api/get?track_name=\(encodedTitle)&artist_name=\(encodedArtist)")
        requestLyricsURL(url: primaryUrl, fallbackUrl: shouldIncludeDuration ? fallbackUrl : nil)
    }

    private func requestLyricsURL(url: URL, fallbackUrl: URL?) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                if let fallback = fallbackUrl {
                    Task { @MainActor [weak self] in
                        self?.requestLyricsURL(url: fallback, fallbackUrl: nil)
                    }
                } else {
                    Task { @MainActor in self?.lyricsLoading = false }
                }
                return
            }

            var parsed: [LyricLine] = []
            if let synced = json["syncedLyrics"] as? String, !synced.isEmpty {
                parsed = Self.parseLRC(synced)
            } else if let plain = json["plainLyrics"] as? String, !plain.isEmpty {
                let rawLines = plain.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                parsed = rawLines.enumerated().map { LyricLine(id: $0.offset, timestamp: Double($0.offset) * 4.0, text: $0.element) }
            }

            if parsed.isEmpty, let fallback = fallbackUrl {
                Task { @MainActor [weak self] in
                    self?.requestLyricsURL(url: fallback, fallbackUrl: nil)
                }
                return
            }

            Task { @MainActor in
                self?.lyricsLoading = false
                self?.lyrics = parsed
                if let self = self {
                    if self.trackDuration <= 0, let lastTs = parsed.last?.timestamp, lastTs > 0 {
                        self.trackDuration = lastTs + 5.0
                    }
                    self.updateCurrentLyricIndex()
                }
            }
        }.resume()
    }

    nonisolated private static func parseLRC(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let rawLines = lrc.components(separatedBy: .newlines)
        var idCounter = 0
        for line in rawLines {
            guard line.hasPrefix("["), let closingBracket = line.firstIndex(of: "]") else { continue }
            let timePart = String(line[line.index(after: line.startIndex)..<closingBracket])
            let textPart = String(line[line.index(after: closingBracket)...]).trimmingCharacters(in: .whitespaces)
            let timeParts = timePart.components(separatedBy: ":")
            if timeParts.count == 2,
               let min = Double(timeParts[0]),
               let sec = Double(timeParts[1]) {
                let total = min * 60 + sec
                if !textPart.isEmpty {
                    lines.append(LyricLine(id: idCounter, timestamp: total, text: textPart))
                    idCounter += 1
                }
            }
        }
        return lines
    }

    // MARK: - Playback Controls & Focus

    func activateCurrentPlayer() {
        guard !RuntimeEnvironment.isRunningTests else { return }
        switch activeSource {
        case .appleMusic:
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first?.activate()
        case .spotifyDesktop, .none:
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first?.activate()
        case .webMusic(let service, let browser):
            NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleIdentifier).first?.activate()
            let domain = service.domainSubstring
            let focusScript: String
            if browser.isSafari {
                focusScript = """
                tell application "\(browser.applicationName)"
                    activate
                    repeat with w in windows
                        repeat with t in tabs of w
                            try
                                if (URL of t) contains "\(domain)" then
                                    set current tab of w to t
                                    set index of w to 1
                                    return
                                end if
                            end try
                        end repeat
                    end repeat
                end tell
                """
            } else {
                focusScript = """
                tell application "\(browser.applicationName)"
                    activate
                    repeat with w in windows
                        set tabIdx to 1
                        repeat with t in tabs of w
                            try
                                if (URL of t) contains "\(domain)" then
                                    set active tab index of w to tabIdx
                                    set index of w to 1
                                    return
                                end if
                            end try
                            set tabIdx to tabIdx + 1
                        end repeat
                    end repeat
                end tell
                """
            }
            DispatchQueue.global(qos: .userInitiated).async {
                _ = Self.runAppleScript(focusScript)
            }
        }
    }

    func togglePlayPause() {
        if case .webMusic(let service, let browser) = activeSource {
            let js: String
            switch service {
            case .spotifyWeb:
                js = "(function(){var b=document.querySelector('[data-testid=control-button-playpause]');if(b){b.click();}})()"
            case .youtubeMusic:
                js = "(function(){var b=document.querySelector('#play-pause-button');if(b){b.click();}else{var v=document.querySelector('video');if(v){v.paused?v.play():v.pause();}}})()"
            case .appleMusicWeb:
                js = "(function(){var mk=(typeof MusicKit!=='undefined'&&MusicKit.getInstance)?MusicKit.getInstance():null;if(mk){mk.isPlaying?mk.pause():mk.play();}else{var b=document.querySelector('.playback-play__pause,.playback-play__play,[aria-label=Pause],[aria-label=Play]');if(b){b.click();}}})()"
            }
            let script = Self.buildBrowserActionScript(for: browser, service: service, jsExpression: js)
            DispatchQueue.global(qos: .userInitiated).async {
                _ = Self.runAppleScript(script)
            }
        } else {
            let app = (activeSource == .appleMusic || player == "Music") ? "Music" : "Spotify"
            let script = "tell application \"\(app)\" to playpause"
            _ = Self.runAppleScript(script)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.fetchPlaybackDetails()
        }
    }

    func nextTrack() {
        if case .webMusic(let service, let browser) = activeSource {
            let js: String
            switch service {
            case .spotifyWeb:
                js = "(function(){var b=document.querySelector('[data-testid=control-button-skip-forward]');if(b){b.click();}})()"
            case .youtubeMusic:
                js = "(function(){var b=document.querySelector('.next-button');if(b){b.click();}})()"
            case .appleMusicWeb:
                js = "(function(){var mk=(typeof MusicKit!=='undefined'&&MusicKit.getInstance)?MusicKit.getInstance():null;if(mk&&mk.skipToNextItem){mk.skipToNextItem();}else{var b=document.querySelector('[aria-label=Next]');if(b){b.click();}}})()"
            }
            let script = Self.buildBrowserActionScript(for: browser, service: service, jsExpression: js)
            DispatchQueue.global(qos: .userInitiated).async {
                _ = Self.runAppleScript(script)
            }
        } else {
            let app = (activeSource == .appleMusic || player == "Music") ? "Music" : "Spotify"
            let script = "tell application \"\(app)\" to next track"
            _ = Self.runAppleScript(script)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.fetchPlaybackDetails()
            self?.triggerToast()
        }
    }

    func previousTrack() {
        if case .webMusic(let service, let browser) = activeSource {
            let js: String
            switch service {
            case .spotifyWeb:
                js = "(function(){var b=document.querySelector('[data-testid=control-button-skip-back]');if(b){b.click();}})()"
            case .youtubeMusic:
                js = "(function(){var b=document.querySelector('.previous-button');if(b){b.click();}})()"
            case .appleMusicWeb:
                js = "(function(){var mk=(typeof MusicKit!=='undefined'&&MusicKit.getInstance)?MusicKit.getInstance():null;if(mk&&mk.skipToPreviousItem){mk.skipToPreviousItem();}else{var b=document.querySelector('[aria-label=Previous]');if(b){b.click();}}})()"
            }
            let script = Self.buildBrowserActionScript(for: browser, service: service, jsExpression: js)
            DispatchQueue.global(qos: .userInitiated).async {
                _ = Self.runAppleScript(script)
            }
        } else {
            let app = (activeSource == .appleMusic || player == "Music") ? "Music" : "Spotify"
            let script = "tell application \"\(app)\" to previous track"
            _ = Self.runAppleScript(script)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.fetchPlaybackDetails()
            self?.triggerToast()
        }
    }

    func seek(to position: Double) {
        if case .webMusic(let service, let browser) = activeSource {
            guard trackDuration > 0 else { return }
            // A title-only probe cannot seek; moving the scrubber anyway makes it jump back on
            // the next poll.
            guard !isBrowserJSHintVisible else { return }
            let fraction = min(1.0, max(0.0, position / trackDuration))
            let js: String
            switch service {
            case .spotifyWeb:
                js = String(
                    format: "(function(){var bar=document.querySelector('[data-testid=playback-progressbar]')||document.querySelector('[data-testid=progress-bar]');if(bar){var r=bar.getBoundingClientRect();var x=r.left+r.width*%.6f;var y=r.top+r.height/2;['mousedown','mouseup','click'].forEach(function(ev){bar.dispatchEvent(new MouseEvent(ev,{bubbles:true,cancelable:true,view:window,clientX:x,clientY:y}));});}})()",
                    fraction
                )
            case .youtubeMusic:
                js = String(
                    format: "(function(){var v=document.querySelector('video');if(v){v.currentTime=%.2f;}})()",
                    position
                )
            case .appleMusicWeb:
                js = String(
                    format: "(function(){var mk=(typeof MusicKit!=='undefined'&&MusicKit.getInstance)?MusicKit.getInstance():null;if(mk&&mk.seekToTime){mk.seekToTime(%.2f);}else{var a=document.querySelector('audio');if(a){a.currentTime=%.2f;}}})()",
                    position, position
                )
            }
            let script = Self.buildBrowserActionScript(for: browser, service: service, jsExpression: js)
            DispatchQueue.global(qos: .userInitiated).async {
                _ = Self.runAppleScript(script)
            }
            self.setAnchor(position: position, playing: isPlaying)
            updateCurrentLyricIndex()
        } else {
            let app = (activeSource == .appleMusic || player == "Music") ? "Music" : "Spotify"
            let script = "tell application \"\(app)\" to set player position to \(position)"
            DispatchQueue.global(qos: .userInitiated).async {
                _ = Self.runAppleScript(script)
            }
            self.setAnchor(position: position, playing: isPlaying)
            updateCurrentLyricIndex()
        }
    }

    nonisolated private static func runAppleScript(_ script: String) -> String? {
        guard !RuntimeEnvironment.isRunningTests else { return nil }
        guard let appleScript = compiledAppleScript(script) else { return nil }
        var error: NSDictionary?
        // One instance is shared between probes, so executions are serialized:
        // NSAppleScript is not reentrant.
        appleScriptExecutionLock.lock()
        let result = appleScript.executeAndReturnError(&error)
        appleScriptExecutionLock.unlock()
        if error == nil {
            return result.stringValue
        }
        // Debug level on purpose: a denied Automation grant fails on every poll, so an
        // error-level line here would flood the log. Read it with
        // `log show --debug --predicate 'subsystem == "com.codeisland"'`.
        let number = error?[NSAppleScript.errorNumber] as? Int ?? 0
        let message = error?[NSAppleScript.errorMessage] as? String ?? "unknown"
        log.debug("AppleScript failed (\(number, privacy: .public)): \(message, privacy: .public)")
        return nil
    }

    /// Compiling is the expensive half of a probe and the source is the same
    /// string on every poll, so each source is compiled once and reused.
    /// Seek scripts embed a position, so the cache is capped rather than unbounded.
    nonisolated private static func compiledAppleScript(_ script: String) -> NSAppleScript? {
        appleScriptCacheLock.lock()
        defer { appleScriptCacheLock.unlock() }
        if let cached = appleScriptCache[script] { return cached }
        guard let compiled = NSAppleScript(source: script) else { return nil }
        if appleScriptCache.count >= 64 { appleScriptCache.removeAll() }
        appleScriptCache[script] = compiled
        return compiled
    }

    nonisolated(unsafe) private static var appleScriptCache: [String: NSAppleScript] = [:]
    nonisolated private static let appleScriptCacheLock = NSLock()
    nonisolated private static let appleScriptExecutionLock = NSLock()
}
