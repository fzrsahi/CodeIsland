import XCTest
@testable import CodeIsland

/// The Now Playing probe schedule (idle-perf ticket 07). Every row of the
/// spec's interval table is a case here.
@MainActor
final class NowPlayingPollPolicyTests: XCTestCase {
    private func state(
        running: Set<NowPlayingProbeTarget> = [.brave],
        playing: Bool = false,
        paused: Bool = false,
        active: NowPlayingProbeTarget? = nil,
        last: NowPlayingProbeTarget? = nil,
        expanded: Bool = false,
        asleep: Bool = false,
        locked: Bool = false,
        sessionActive: Bool = true,
        sinceChange: TimeInterval = 0
    ) -> NowPlayingPollState {
        NowPlayingPollState(
            runningTargets: running, isPlaying: playing, isPaused: paused,
            activeTarget: active, lastTarget: last, isExpanded: expanded,
            isDisplayAsleep: asleep, isScreenLocked: locked,
            isSessionActive: sessionActive, secondsSinceLastChange: sinceChange
        )
    }

    func testAnIdleBrowserIsProbedEveryFifteenSeconds() {
        let plan = NowPlayingPollPolicy.nextProbe(state(running: [.brave]))
        XCTAssertEqual(plan?.interval, 15)
        XCTAssertEqual(plan?.targets, [.brave])
    }

    func testAnExpandedIdleBrowserIsProbedEveryThreeSeconds() {
        let plan = NowPlayingPollPolicy.nextProbe(state(running: [.brave, .safari], expanded: true))
        XCTAssertEqual(plan?.interval, 3)
        XCTAssertEqual(plan?.targets, [.brave, .safari])
    }

    func testDesktopPlayersOnlyGetASafetyProbe() {
        let plan = NowPlayingPollPolicy.nextProbe(state(running: [.spotifyDesktop, .appleMusic]))
        XCTAssertEqual(plan?.interval, 30)
        XCTAssertEqual(plan?.targets, [.spotifyDesktop, .appleMusic])
    }

    func testPlayingProbesTheActiveSourceEveryFiveSeconds() {
        let plan = NowPlayingPollPolicy.nextProbe(state(
            running: [.brave, .safari], playing: true, active: .brave, last: .brave
        ))
        XCTAssertEqual(plan?.interval, 5)
        XCTAssertEqual(plan?.targets, [.brave], "a playing track is the only thing worth asking")
    }

    func testExpandedPlayingProbesEveryTwoSeconds() {
        let plan = NowPlayingPollPolicy.nextProbe(state(
            running: [.spotifyDesktop], playing: true, active: .spotifyDesktop, expanded: true
        ))
        XCTAssertEqual(plan?.interval, 2)
    }

    func testPausedProbesTheLastSourceEveryTenSeconds() {
        let plan = NowPlayingPollPolicy.nextProbe(state(
            running: [.brave, .safari], paused: true, last: .safari, sinceChange: 120
        ))
        XCTAssertEqual(plan?.interval, 10)
        XCTAssertEqual(plan?.targets, [.safari])
    }

    func testAPauseOlderThanTenMinutesFallsBackToTheIdleRules() {
        let plan = NowPlayingPollPolicy.nextProbe(state(
            running: [.brave], paused: true, last: .brave,
            sinceChange: NowPlayingPollPolicy.pausedIdleAfter
        ))
        XCTAssertEqual(plan?.interval, 15, "a track paused ten minutes ago is not being watched")
        XCTAssertEqual(plan?.targets, [.brave])
    }

    func testSleepingLockedOrInactiveProbesNothing() {
        XCTAssertNil(NowPlayingPollPolicy.nextProbe(state(asleep: true)))
        XCTAssertNil(NowPlayingPollPolicy.nextProbe(state(locked: true)))
        XCTAssertNil(NowPlayingPollPolicy.nextProbe(state(sessionActive: false)))
    }

    func testNothingRunningProbesNothing() {
        XCTAssertNil(NowPlayingPollPolicy.nextProbe(state(running: [])))
    }

    func testAPlayingTrackOnAQuitPlayerFallsThroughToTheIdleRules() {
        let plan = NowPlayingPollPolicy.nextProbe(state(
            running: [.brave], playing: true, active: .spotifyDesktop, last: .spotifyDesktop
        ))
        XCTAssertEqual(plan?.interval, 15)
        XCTAssertEqual(plan?.targets, [.brave])
    }

    func testEveryBrowserMapsToItsBundleIdentifier() {
        for browser in SpotifyWebBrowser.allCases {
            XCTAssertEqual(
                NowPlayingProbeTarget.target(for: browser.bundleIdentifier)?.browser,
                browser
            )
        }
        XCTAssertEqual(NowPlayingProbeTarget.target(for: "com.spotify.client"), .spotifyDesktop)
        XCTAssertNil(NowPlayingProbeTarget.target(for: "com.example.nothing"))
    }
}
