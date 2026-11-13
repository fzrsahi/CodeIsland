import XCTest
@testable import CodeIsland

@MainActor
final class MascotAnimationGateTests: XCTestCase {
    func testShouldAnimateOnlyWhenVisibleAndAwake() {
        XCTAssertTrue(MascotAnimationGate.shouldAnimate(isVisible: true, isAwake: true))
        XCTAssertFalse(MascotAnimationGate.shouldAnimate(isVisible: false, isAwake: true))
        XCTAssertFalse(MascotAnimationGate.shouldAnimate(isVisible: true, isAwake: false))
        XCTAssertFalse(MascotAnimationGate.shouldAnimate(isVisible: false, isAwake: false))
    }

    func testHidingPanelStopsAnimationsWithoutBumpingEpoch() {
        let gate = MascotAnimationGate.shared
        gate.setPanelVisible(true)
        let baseEpoch = gate.epoch

        gate.setPanelVisible(false)
        XCTAssertFalse(gate.animationsActive)
        // Hiding must not re-anchor — only re-showing/waking does.
        XCTAssertEqual(gate.epoch, baseEpoch)
    }

    func testReShowingPanelBumpsEpochToReAnchorSchedules() {
        let gate = MascotAnimationGate.shared
        gate.setPanelVisible(false)
        let hiddenEpoch = gate.epoch

        gate.setPanelVisible(true)
        XCTAssertTrue(gate.animationsActive)
        XCTAssertEqual(gate.epoch, hiddenEpoch + 1)
    }

    func testRepeatedSameVisibilityIsIdempotent() {
        let gate = MascotAnimationGate.shared
        gate.setPanelVisible(true)
        let epoch = gate.epoch
        gate.setPanelVisible(true)
        XCTAssertEqual(gate.epoch, epoch)
    }

    /// #299 — a live TimelineView keeps SwiftUI's update machinery on a display
    /// link and re-runs the panel's whole layout pass every cycle, which is the
    /// bulk of the idle CPU baseline. A collapsed island with nothing running
    /// holds a static frame instead.
    func testSettledIslandStopsAnimationsEvenWhileVisibleAndAwake() {
        XCTAssertFalse(
            MascotAnimationGate.shouldAnimate(isVisible: true, isAwake: true, isIdleSettled: true)
        )
        XCTAssertTrue(
            MascotAnimationGate.shouldAnimate(isVisible: true, isAwake: true, isIdleSettled: false)
        )
    }

    func testLeavingTheSettledStateReAnchorsSchedules() {
        let gate = MascotAnimationGate.shared
        gate.setPanelVisible(true)
        gate.setIdleSettled(true)
        XCTAssertFalse(gate.animationsActive)
        let settledEpoch = gate.epoch

        gate.setIdleSettled(false)
        XCTAssertTrue(gate.animationsActive)
        XCTAssertEqual(
            gate.epoch,
            settledEpoch + 1,
            "resuming must re-anchor, or SwiftUI replays every tick missed while settled"
        )
    }

    func testReduceMotionHoldsTheMascotsStill() {
        XCTAssertFalse(MascotAnimationGate.shouldAnimate(isVisible: true, isAwake: true, reduceMotion: true))
        let gate = MascotAnimationGate.shared
        gate.setPanelVisible(true)
        gate.setIdleSettled(false)
        defer { gate.setReduceMotion(false) }
        gate.setReduceMotion(true)
        XCTAssertFalse(gate.animationsActive)
        let stillEpoch = gate.epoch
        gate.setReduceMotion(false)
        XCTAssertTrue(gate.animationsActive)
        XCTAssertEqual(gate.epoch, stillEpoch + 1, "resuming must re-anchor the schedules")
    }

    func testSettlingDoesNotReAnchor() {
        let gate = MascotAnimationGate.shared
        gate.setIdleSettled(false)
        let epoch = gate.epoch
        gate.setIdleSettled(true)
        XCTAssertEqual(gate.epoch, epoch)
        gate.setIdleSettled(false)
    }
}

// MARK: - Animation classes (idle-perf ticket 03)

@MainActor
final class AnimationClassGateTests: XCTestCase {
    private func state(
        visible: Bool = true,
        awake: Bool = true,
        reduceMotion: Bool = false,
        settled: Bool = false,
        music: Bool = false,
        waiting: TimeInterval = 0
    ) -> AnimationState {
        AnimationState(
            isVisible: visible, isAwake: awake, reduceMotion: reduceMotion,
            isIdleSettled: settled, musicPlaying: music, waitingForInteraction: waiting
        )
    }

    func testMascotSleepsWhenTheIslandIsSettled() {
        XCTAssertTrue(MascotAnimationGate.shouldAnimate(.mascot, state: state()))
        XCTAssertFalse(MascotAnimationGate.shouldAnimate(.mascot, state: state(settled: true)))
    }

    func testMascotRunsWhileMusicPlays() {
        XCTAssertTrue(MascotAnimationGate.shouldAnimate(.mascot, state: state(music: true)))
    }

    func testAmbientGlowFollowsTheSettledState() {
        XCTAssertTrue(MascotAnimationGate.shouldAnimate(.ambientIdle, state: state()))
        XCTAssertFalse(MascotAnimationGate.shouldAnimate(.ambientIdle, state: state(settled: true)))
    }

    func testMusicOnlyMovesWhileSomethingPlays() {
        XCTAssertFalse(MascotAnimationGate.shouldAnimate(.music, state: state()))
        XCTAssertTrue(MascotAnimationGate.shouldAnimate(.music, state: state(music: true)))
    }

    func testAttentionRunsUntilTheIslandHasBeenLeftAloneForAMinute() {
        XCTAssertTrue(MascotAnimationGate.shouldAnimate(.attention, state: state(waiting: 0)))
        XCTAssertTrue(MascotAnimationGate.shouldAnimate(.attention, state: state(waiting: 59)))
        XCTAssertFalse(MascotAnimationGate.shouldAnimate(.attention, state: state(waiting: 60)))
        XCTAssertFalse(MascotAnimationGate.shouldAnimate(.attention, state: state(waiting: 600)))
    }

    func testMascotStopsAfterAMinuteOfWaiting() {
        XCTAssertTrue(MascotAnimationGate.shouldAnimate(.mascot, state: state(waiting: 59)))
        XCTAssertFalse(MascotAnimationGate.shouldAnimate(.mascot, state: state(waiting: 60)))
    }

    func testReduceMotionStopsEveryLoop() {
        for kind in [AnimationKind.mascot, .ambientIdle, .music, .attention, .marquee] {
            XCTAssertFalse(
                MascotAnimationGate.shouldAnimate(kind, state: state(reduceMotion: true, music: true)),
                "\(kind) must hold still under Reduce Motion"
            )
        }
    }

    func testHiddenOrAsleepStopsEveryLoop() {
        for kind in [AnimationKind.mascot, .ambientIdle, .music, .attention, .marquee] {
            XCTAssertFalse(MascotAnimationGate.shouldAnimate(kind, state: state(visible: false, music: true)))
            XCTAssertFalse(MascotAnimationGate.shouldAnimate(kind, state: state(awake: false, music: true)))
        }
    }

    func testTransitionsAndSettingsPreviewsAreNeverGated() {
        let dark = state(visible: false, awake: false, reduceMotion: true, settled: true, waiting: 600)
        XCTAssertTrue(MascotAnimationGate.shouldAnimate(.transient, state: dark))
        XCTAssertTrue(MascotAnimationGate.shouldAnimate(.settings, state: dark))
    }

    func testMarqueeNeedsTheGateButNotAHoverToDecide() {
        // Hover and overflow are the view's own conditions; the gate only says
        // the class may move at all.
        XCTAssertTrue(MascotAnimationGate.shouldAnimate(.marquee, state: state(settled: true)))
        XCTAssertFalse(MascotAnimationGate.shouldAnimate(.marquee, state: state(reduceMotion: true)))
    }

    func testGatesResolveEveryClassFromOneState() {
        let gates = AnimationGates(
            mascot: false, ambientIdle: false, music: true, attention: false, marquee: false, transient: true
        )
        XCTAssertFalse(gates.allows(.mascot))
        XCTAssertTrue(gates.allows(.music))
        XCTAssertTrue(gates.allows(.transient))
        XCTAssertTrue(AnimationGates.all.allows(.mascot))
    }

    func testWaitingGoesQuietOnItsOwnAndWakesOnInteraction() {
        let gate = MascotAnimationGate.shared
        gate.setPanelVisible(true)
        gate.setMusicPlaying(false)
        defer { gate.setWaitingForUser(false) }

        gate.setWaitingForUser(true)
        XCTAssertFalse(gate.isWaitingQuiet, "a fresh wait is not quiet yet")
        XCTAssertTrue(gate.gates.mascot)

        // Interaction restarts the quiet clock instead of ending the wait.
        gate.noteInteraction()
        XCTAssertTrue(gate.isWaitingForUser)
        XCTAssertFalse(gate.isWaitingQuiet)
        XCTAssertTrue(gate.gates.attention)
    }

    func testLeavingTheWaitingStateClearsQuiet() {
        let gate = MascotAnimationGate.shared
        gate.setWaitingForUser(true)
        gate.setWaitingForUser(false)
        XCTAssertFalse(gate.isWaitingQuiet)
        XCTAssertTrue(gate.gates.mascot)
    }
}
