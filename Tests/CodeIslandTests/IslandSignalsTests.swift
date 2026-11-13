import XCTest
import Observation
@testable import CodeIsland

/// The panel root's short list of visible values (idle-perf ticket 06).
@MainActor
final class IslandSignalsTests: XCTestCase {
    /// Counts how many times an observation of `body` is invalidated.
    private func notificationCount(_ body: @escaping () -> Void) -> () -> Int {
        var count = 0
        var armed = true
        func arm() {
            armed = true
            withObservationTracking {
                body()
            } onChange: {
                count += 1
                guard armed else { return }
                armed = false
                Task { @MainActor in arm() }
            }
        }
        arm()
        return { count }
    }

    func testWritingTheSameValueDoesNotNotify() async {
        let signals = IslandSignals()
        signals.setMusic(isPlaying: true, showToast: false, hasTitle: true, hasLyrics: false)
        let count = notificationCount { _ = signals.isPlaying }

        // Same values again: no notification.
        signals.setMusic(isPlaying: true, showToast: false, hasTitle: true, hasLyrics: false)
        await Task.yield()
        XCTAssertEqual(count(), 0, "an unchanged write must not invalidate an observer")

        // A real change does notify.
        signals.setMusic(isPlaying: false, showToast: false, hasTitle: true, hasLyrics: false)
        await Task.yield()
        XCTAssertEqual(count(), 1)
    }

    func testEachSetterIsNoOpWhenUnchanged() async {
        let signals = IslandSignals()
        signals.setTooltip("agents")
        signals.setDetailExpanded(true)
        signals.setChargingBanner(visible: true, batteryLevel: 80)
        signals.setMiniPeekBanner(true)
        signals.setVolumeHUDVisible(true)
        signals.setPrayerPrioritized(true)
        signals.setInQuietHours(true)

        let count = notificationCount {
            _ = signals.tooltipText
            _ = signals.isDetailExpanded
            _ = signals.showChargingBanner
            _ = signals.batteryLevel
            _ = signals.showMiniPeekBanner
            _ = signals.isVolumeHUDVisible
            _ = signals.isPrayerPrioritized
            _ = signals.inQuietHours
        }

        signals.setTooltip("agents")
        signals.setDetailExpanded(true)
        signals.setChargingBanner(visible: true, batteryLevel: 80)
        signals.setMiniPeekBanner(true)
        signals.setVolumeHUDVisible(true)
        signals.setPrayerPrioritized(true)
        signals.setInQuietHours(true)
        await Task.yield()
        XCTAssertEqual(count(), 0)
    }

    func testTheBatteryLevelAloneCanChange() async {
        let signals = IslandSignals()
        signals.setChargingBanner(visible: true, batteryLevel: 80)
        let count = notificationCount { _ = signals.batteryLevel }
        signals.setChargingBanner(visible: true, batteryLevel: 79)
        await Task.yield()
        XCTAssertEqual(count(), 1)
        XCTAssertEqual(signals.batteryLevel, 79)
    }

    func testMusicFieldsMoveIndependently() {
        let signals = IslandSignals()
        signals.setMusic(isPlaying: true, showToast: false, hasTitle: false, hasLyrics: false)
        XCTAssertTrue(signals.isPlaying)
        signals.setMusic(isPlaying: true, showToast: true, hasTitle: true, hasLyrics: true)
        XCTAssertTrue(signals.showToast)
        XCTAssertTrue(signals.hasTitle)
        XCTAssertTrue(signals.hasLyrics)
        XCTAssertTrue(signals.isPlaying)
    }
}
