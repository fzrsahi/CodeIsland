import AppKit
import SwiftUI

/// Central gate that decides whether the pixel mascots should keep driving
/// their per-frame `TimelineView` redraws.
///
/// Two things pin a CPU core when this is left unchecked (issue #225):
///  1. The notch panel is hidden / occluded but the mascot Canvas keeps
///     redrawing at ~20fps forever (worst with zero sessions, where the idle
///     mascot animates indefinitely).
///  2. After display sleep/wake the `TimelineView(.periodic(from: .now, by:))`
///     schedules are still anchored to their original reference date, so
///     SwiftUI tries to "catch up" every missed tick in a burst.
///
/// The gate solves both: `animationsActive` is false while the panel is hidden
/// or the machine is asleep (views render a static frame instead of looping),
/// and `epoch` is bumped on wake so the periodic schedules — keyed on the epoch
/// via `.id()` — get torn down and re-anchored to the *new* current time rather
/// than replaying the gap.
/// Which kind of motion a view is about to run. One gate decision per kind,
/// made once in `MascotAnimationGate` and injected into the panel root, so no
/// view decides on its own whether it may keep animating.
enum AnimationKind: String, CaseIterable, Sendable {
    /// The pixel mascot's own frames.
    case mascot
    /// The breath glow behind an idle mascot.
    case ambientIdle
    /// Aura, spectrum wing/capsule/HUD while music plays.
    case music
    /// Glow alert, waiting badge, shimmer/dots while a session thinks.
    case attention
    /// Scrolling titles.
    case marquee
    /// Transitions, springs, banners: never gated, a one-off is not a loop.
    case transient
    /// Previews inside Settings: out of scope, never gated here.
    case settings
}

/// Everything the gate needs to know, as a plain value — which is what makes
/// the decision testable without a window, a screen or a clock.
struct AnimationState: Equatable, Sendable {
    var isVisible = true
    var isAwake = true
    var reduceMotion = false
    var isIdleSettled = false
    var musicPlaying = false
    /// Seconds the island has been waiting for the user (approval or question)
    /// without any interaction since. `waitingQuietAfter` and beyond is quiet.
    var waitingForInteraction: TimeInterval = 0

    /// A waiting island that nobody has touched for this long stops animating
    /// everything but the bell: the user has walked away.
    static let waitingQuietAfter: TimeInterval = 60
}

/// The resolved answer for every kind, injected once at the panel root.
struct AnimationGates: Equatable, Sendable {
    var mascot = true
    var ambientIdle = true
    var music = true
    var attention = true
    var marquee = true
    var transient = true

    func allows(_ kind: AnimationKind) -> Bool {
        switch kind {
        case .mascot: return mascot
        case .ambientIdle: return ambientIdle
        case .music: return music
        case .attention: return attention
        case .marquee: return marquee
        case .transient, .settings: return true
        }
    }

    /// Everything animating — what a view renders outside the panel.
    static let all = AnimationGates()
}

@MainActor
final class MascotAnimationGate: ObservableObject {
    static let shared = MascotAnimationGate()

    /// Bumped whenever the system wakes so periodic schedules re-anchor to "now".
    @Published private(set) var epoch: Int = 0

    /// True while the panel window is on-screen / not occluded.
    @Published private(set) var isPanelVisible: Bool = true

    /// True while the display/system is awake.
    @Published private(set) var isAwake: Bool = true

    /// True when the island is collapsed and every session is idle — i.e. the
    /// mascot is asleep in a ~20pt strip and nothing is happening.
    @Published private(set) var isIdleSettled: Bool = false

    /// True while a player is playing (the Music animation class).
    @Published private(set) var musicPlaying: Bool = false

    /// True while a session waits for the user (approval or question).
    @Published private(set) var isWaitingForUser: Bool = false

    /// True once a waiting island has gone `waitingQuietAfter` without an
    /// interaction; set by a one-shot timer, never by polling.
    @Published private(set) var isWaitingQuiet: Bool = false

    private var waitingSince: Date?
    private var lastInteractionAt: Date?
    private var waitingQuietTimer: Timer?

    /// System Settings › Accessibility › Display › Reduce motion. Read in
    /// `start()`, so a test process (which never starts the gate) keeps
    /// animating whatever the machine running it is set to.
    @Published private(set) var reduceMotion: Bool = false

    /// Whether mascot per-frame animations should run right now.
    var animationsActive: Bool {
        Self.shouldAnimate(isVisible: isPanelVisible, isAwake: isAwake, isIdleSettled: isIdleSettled,
                           reduceMotion: reduceMotion)
    }

    /// The current state, as the pure decision sees it.
    var state: AnimationState {
        AnimationState(
            isVisible: isPanelVisible,
            isAwake: isAwake,
            reduceMotion: reduceMotion,
            isIdleSettled: isIdleSettled,
            musicPlaying: musicPlaying,
            waitingForInteraction: isWaitingQuiet ? AnimationState.waitingQuietAfter : 0
        )
    }

    /// The resolved answer for every animation class.
    var gates: AnimationGates {
        let state = self.state
        return AnimationGates(
            mascot: Self.shouldAnimate(.mascot, state: state),
            ambientIdle: Self.shouldAnimate(.ambientIdle, state: state),
            music: Self.shouldAnimate(.music, state: state),
            attention: Self.shouldAnimate(.attention, state: state),
            marquee: Self.shouldAnimate(.marquee, state: state)
        )
    }

    private var observers: [NSObjectProtocol] = []

    private init() {}

    /// Pure decision used by `animationsActive` and unit tests. Animations only
    /// run while the panel is visible *and* the machine is awake — there is no
    /// point burning frames behind a hidden panel or during sleep.
    ///
    /// The third condition is the expensive one. A live `TimelineView` does not
    /// merely run its own schedule: it keeps SwiftUI's update machinery on a
    /// display link, and every cycle re-runs the whole panel's layout pass. That
    /// measured at ~7.6% CPU forever on an idle Mac, against ~2% with no live
    /// timeline — and *slowing* the schedule barely helped (4 fps still cost
    /// ~6.2%), because the cost is per display cycle, not per mascot frame.
    /// So when the island is collapsed and nothing is running, the mascot holds
    /// a static sleeping frame instead. Any state change — a session waking, the
    /// panel expanding on hover — re-enables it immediately. (#299)
    ///
    /// With Reduce Motion on, the mascots hold their status pose instead of
    /// looping forever next to whatever the user is reading.
    static func shouldAnimate(isVisible: Bool, isAwake: Bool, isIdleSettled: Bool = false,
                              reduceMotion: Bool = false) -> Bool {
        shouldAnimate(.mascot, state: AnimationState(
            isVisible: isVisible, isAwake: isAwake, reduceMotion: reduceMotion, isIdleSettled: isIdleSettled
        ))
    }

    /// The one decision every animation class goes through.
    ///
    /// Hidden and asleep silence everything — there is nobody to see the
    /// motion. Reduce Motion silences the loops but not one-off transitions.
    /// The mascot additionally sleeps in a settled island and after a waiting
    /// island has been left alone; music only moves while something plays.
    static func shouldAnimate(_ kind: AnimationKind, state: AnimationState) -> Bool {
        switch kind {
        case .transient, .settings:
            // A transition or spring is a one-off, not a loop; Settings
            // previews are out of scope for this gate.
            return true
        default:
            break
        }
        guard state.isVisible, state.isAwake, !state.reduceMotion else { return false }
        switch kind {
        case .mascot:
            return !state.isIdleSettled && state.waitingForInteraction < AnimationState.waitingQuietAfter
        case .ambientIdle:
            return !state.isIdleSettled
        case .music:
            return state.musicPlaying
        case .attention:
            return state.waitingForInteraction < AnimationState.waitingQuietAfter
        case .marquee:
            // The view still requires a hover and text wider than its box.
            return true
        case .transient, .settings:
            return true
        }
    }

    /// Begin observing system sleep/wake and the Reduce Motion setting. Idempotent.
    func start() {
        guard observers.isEmpty else { return }
        let wsCenter = NSWorkspace.shared.notificationCenter

        let sleepNames: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
        ]
        let wakeNames: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
        ]

        for name in sleepNames {
            observers.append(wsCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setAwake(false) }
            })
        }
        for name in wakeNames {
            observers.append(wsCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setAwake(true) }
            })
        }

        setReduceMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        observers.append(wsCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.setReduceMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) }
        })
    }

    /// Follow the Reduce Motion setting. Turning it off re-anchors the
    /// schedules like any other resume.
    func setReduceMotion(_ reduce: Bool) {
        guard reduceMotion != reduce else { return }
        reduceMotion = reduce
        if !reduce { epoch &+= 1 }
    }

    /// Report the panel's current on-screen visibility (called from the
    /// window controller whenever it orders the panel in or out).
    func setPanelVisible(_ visible: Bool) {
        guard isPanelVisible != visible else { return }
        isPanelVisible = visible
        // Coming back on-screen behaves like a wake for the render layer:
        // re-anchor so we don't replay frames accumulated while hidden.
        if visible { epoch &+= 1 }
    }

    /// Report whether the island is collapsed with nothing running. Coming back
    /// out of that state re-anchors the schedules, exactly like a wake.
    func setIdleSettled(_ settled: Bool) {
        guard isIdleSettled != settled else { return }
        isIdleSettled = settled
        if !settled { epoch &+= 1 }
    }

    private func setAwake(_ awake: Bool) {
        guard isAwake != awake else { return }
        isAwake = awake
        // On wake, bump the epoch so schedules anchored to the old reference
        // date are discarded instead of catching up every missed periodic tick.
        if awake { epoch &+= 1 }
    }

    /// Report whether a player is playing (the Music animation class).
    func setMusicPlaying(_ playing: Bool) {
        guard musicPlaying != playing else { return }
        musicPlaying = playing
        if playing { epoch &+= 1 }
    }

    /// Report whether any session is waiting for the user. Entering the state
    /// arms one timer for the moment the island counts as left alone.
    func setWaitingForUser(_ waiting: Bool) {
        guard isWaitingForUser != waiting else { return }
        isWaitingForUser = waiting
        if waiting {
            let now = Date()
            waitingSince = now
            lastInteractionAt = now
            scheduleWaitingQuiet()
        } else {
            waitingQuietTimer?.invalidate()
            waitingQuietTimer = nil
            waitingSince = nil
            lastInteractionAt = nil
            setWaitingQuiet(false)
        }
    }

    /// A hover, a new event or a follow-up reminder: the user is back, so the
    /// quiet clock restarts and the animations resume.
    func noteInteraction() {
        guard isWaitingForUser else { return }
        lastInteractionAt = Date()
        setWaitingQuiet(false)
        scheduleWaitingQuiet()
    }

    private func scheduleWaitingQuiet() {
        waitingQuietTimer?.invalidate()
        waitingQuietTimer = nil
        guard isWaitingForUser, let since = waitingSince else { return }
        let anchor = max(since, lastInteractionAt ?? since)
        let remaining = AnimationState.waitingQuietAfter - Date().timeIntervalSince(anchor)
        guard remaining > 0 else {
            setWaitingQuiet(true)
            return
        }
        let timer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.setWaitingQuiet(true) }
        }
        timer.tolerance = min(1, remaining * 0.1)
        waitingQuietTimer = timer
    }

    private func setWaitingQuiet(_ quiet: Bool) {
        guard isWaitingQuiet != quiet else { return }
        isWaitingQuiet = quiet
        // Coming back out of the quiet state re-anchors the schedules, exactly
        // like a wake, so nothing replays the ticks missed while quiet.
        if !quiet { epoch &+= 1 }
    }

    deinit {
        waitingQuietTimer?.invalidate()
        let wsCenter = NSWorkspace.shared.notificationCenter
        for observer in observers {
            wsCenter.removeObserver(observer)
        }
    }
}

// MARK: - Environment plumbing

private struct MascotAnimationsActiveKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

private struct MascotAnimationEpochKey: EnvironmentKey {
    static let defaultValue: Int = 0
}

private struct AnimationGatesKey: EnvironmentKey {
    static let defaultValue: AnimationGates = .all
}

extension EnvironmentValues {
    /// The resolved animation decision for every class, injected once at the
    /// panel root so no view has to consult the gate itself.
    var animationGates: AnimationGates {
        get { self[AnimationGatesKey.self] }
        set { self[AnimationGatesKey.self] = newValue }
    }

    /// Whether the mascot's per-frame redraw loops should run.
    var mascotAnimationsActive: Bool {
        get { self[MascotAnimationsActiveKey.self] }
        set { self[MascotAnimationsActiveKey.self] = newValue }
    }

    /// Identity bumped on wake / re-show so periodic schedules re-anchor.
    var mascotAnimationEpoch: Int {
        get { self[MascotAnimationEpochKey.self] }
        set { self[MascotAnimationEpochKey.self] = newValue }
    }
}
