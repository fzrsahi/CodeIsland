import XCTest
@testable import CodeIsland

/// The Workspace gauge is the only reason to sample CPU/RAM/network/battery
/// (idle-perf ticket 10).
@MainActor
final class SystemMonitorSamplingTests: XCTestCase {
    func testSamplingStartsWithTheFirstGaugeAndStopsWithTheLast() {
        let monitor = SystemMonitorManager.shared
        monitor.endSampling()  // leave any other test's registry empty
        XCTAssertFalse(monitor.isSampling)

        monitor.beginSampling()
        XCTAssertTrue(monitor.isSampling, "a gauge that just appeared shows a fresh number")

        monitor.beginSampling()
        XCTAssertTrue(monitor.isSampling, "two gauges still sample once")

        monitor.endSampling()
        XCTAssertTrue(monitor.isSampling, "the last gauge is what stops it")

        monitor.endSampling()
        XCTAssertFalse(monitor.isSampling)
    }

    func testExtraDisappearDoesNotUnderflow() {
        let monitor = SystemMonitorManager.shared
        monitor.endSampling()
        monitor.endSampling()
        XCTAssertFalse(monitor.isSampling)
        monitor.beginSampling()
        XCTAssertTrue(monitor.isSampling)
        monitor.endSampling()
        monitor.endSampling()
        XCTAssertFalse(monitor.isSampling)
    }
}
