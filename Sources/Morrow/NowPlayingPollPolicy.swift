import Foundation

/// A player or browser Now Playing can ask. The set doubles as the "is it
/// running" answer, so a probe never scripts an app that is not there.
enum NowPlayingProbeTarget: String, CaseIterable, Hashable, Sendable {
    case spotifyDesktop
    case appleMusic
    case safari
    case brave
    case chrome
    case arc
    case edge

    var isBrowser: Bool {
        switch self {
        case .spotifyDesktop, .appleMusic: return false
        case .safari, .brave, .chrome, .arc, .edge: return true
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .spotifyDesktop: return "com.spotify.client"
        case .appleMusic: return "com.apple.Music"
        case .safari: return SpotifyWebBrowser.safari.bundleIdentifier
        case .brave: return SpotifyWebBrowser.brave.bundleIdentifier
        case .chrome: return SpotifyWebBrowser.chrome.bundleIdentifier
        case .arc: return SpotifyWebBrowser.arc.bundleIdentifier
        case .edge: return SpotifyWebBrowser.edge.bundleIdentifier
        }
    }

    var browser: SpotifyWebBrowser? {
        switch self {
        case .safari: return .safari
        case .brave: return .brave
        case .chrome: return .chrome
        case .arc: return .arc
        case .edge: return .edge
        case .spotifyDesktop, .appleMusic: return nil
        }
    }

    static func target(for bundleIdentifier: String) -> NowPlayingProbeTarget? {
        allCases.first { $0.bundleIdentifier == bundleIdentifier }
    }
}

/// Everything the probe schedule depends on, as a plain value.
struct NowPlayingPollState: Equatable, Sendable {
    var runningTargets: Set<NowPlayingProbeTarget> = []
    var isPlaying = false
    var isPaused = false
    var activeTarget: NowPlayingProbeTarget?
    var lastTarget: NowPlayingProbeTarget?
    var isExpanded = false
    var isDisplayAsleep = false
    var isScreenLocked = false
    var isSessionActive = true
    /// Seconds since the last play/pause/seek/track change.
    var secondsSinceLastChange: TimeInterval = 0
}

/// When to probe next, and whom. `nil` means "stop": nothing is running, or
/// nobody is at the Mac to see the answer.
struct NowPlayingProbePlan: Equatable, Sendable {
    var interval: TimeInterval
    var targets: Set<NowPlayingProbeTarget>
}

/// The one decision behind Now Playing's polling.
///
/// Every probe is an Apple Event to another app, so the schedule is explicit:
/// a playing track is checked often enough to notice a pause, an idle browser
/// rarely enough to cost almost nothing, and a sleeping, locked or inactive
/// session not at all — the next probe happens when the Mac comes back.
enum NowPlayingPollPolicy {
    /// A playing track: notice pause/seek quickly.
    static let playingInterval: TimeInterval = 5
    static let playingExpandedInterval: TimeInterval = 2
    /// Paused: nothing moves, so a slow check is enough.
    static let pausedInterval: TimeInterval = 10
    /// Nothing playing, a browser is open: it may start a track at any moment.
    static let browserInterval: TimeInterval = 15
    static let browserExpandedInterval: TimeInterval = 3
    /// Nothing playing, only desktop players: they announce themselves through
    /// their own notifications, so this is only a safety net.
    static let desktopSafetyInterval: TimeInterval = 30
    /// After this long paused with no change, the paused track is treated as
    /// gone and the idle rules take over.
    static let pausedIdleAfter: TimeInterval = 10 * 60

    static func nextProbe(_ state: NowPlayingPollState) -> NowPlayingProbePlan? {
        // Nobody is there to see it, and a probe would only wake the Mac.
        guard state.isSessionActive, !state.isDisplayAsleep, !state.isScreenLocked else { return nil }

        // A claim about a player that has since quit is stale: fall through to
        // the idle rules rather than probing nothing forever.
        if state.isPlaying,
           let target = state.activeTarget ?? state.lastTarget,
           state.runningTargets.contains(target) {
            return NowPlayingProbePlan(
                interval: state.isExpanded ? playingExpandedInterval : playingInterval,
                targets: [target]
            )
        }

        if state.isPaused,
           state.secondsSinceLastChange < pausedIdleAfter,
           let target = state.lastTarget ?? state.activeTarget,
           state.runningTargets.contains(target) {
            return NowPlayingProbePlan(interval: pausedInterval, targets: [target])
        }

        let browsers = state.runningTargets.filter(\.isBrowser)
        if !browsers.isEmpty {
            return NowPlayingProbePlan(
                interval: state.isExpanded ? browserExpandedInterval : browserInterval,
                targets: browsers
            )
        }

        let desktops = state.runningTargets.subtracting(browsers)
        if !desktops.isEmpty {
            return NowPlayingProbePlan(interval: desktopSafetyInterval, targets: desktops)
        }

        return nil
    }
}
