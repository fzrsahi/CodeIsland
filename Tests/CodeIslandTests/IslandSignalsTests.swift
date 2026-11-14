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
        signals.setMusic(isPlaying: true, showToast: false, hasTitle: true, hasLyrics: false, title: "A", artist: "B")
        let count = notificationCount { _ = signals.isPlaying }

        // Same values again: no notification.
        signals.setMusic(isPlaying: true, showToast: false, hasTitle: true, hasLyrics: false, title: "A", artist: "B")
        await Task.yield()
        XCTAssertEqual(count(), 0, "an unchanged write must not invalidate an observer")

        // A real change does notify.
        signals.setMusic(isPlaying: false, showToast: false, hasTitle: true, hasLyrics: false, title: "A", artist: "B")
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

    // MARK: - Quiet-hours clock

    /// A UTC calendar, so the expectations below are absolute instants.
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func boundary(_ iso: String, start: Int, end: Int) -> Date? {
        let formatter = ISO8601DateFormatter()
        guard let now = formatter.date(from: iso) else { return nil }
        return IslandSignalsSync.nextQuietHoursBoundary(
            now: now, calendar: utc, start: start, end: end
        )
    }

    func testWindowThatWrapsTheDayArmsForItsStart() {
        // 22:00–07:00, asked at noon: the next flip is tonight at 22:00.
        let next = boundary("2026-01-15T12:00:00Z", start: 22 * 60, end: 7 * 60)
        XCTAssertEqual(next, ISO8601DateFormatter().date(from: "2026-01-15T22:00:00Z"))
    }

    func testWindowThatWrapsTheDayArmsForItsEndAfterMidnight() {
        // Asked at 23:00, inside the window: the next flip is 07:00 tomorrow.
        let next = boundary("2026-01-15T23:00:00Z", start: 22 * 60, end: 7 * 60)
        XCTAssertEqual(next, ISO8601DateFormatter().date(from: "2026-01-16T07:00:00Z"))
    }

    func testWindowInsideOneDayArmsForItsEnd() {
        // 09:00–17:00, asked at noon.
        let next = boundary("2026-01-15T12:00:00Z", start: 9 * 60, end: 17 * 60)
        XCTAssertEqual(next, ISO8601DateFormatter().date(from: "2026-01-15T17:00:00Z"))
    }

    func testAnEmptyWindowNeverArms() {
        XCTAssertNil(boundary("2026-01-15T12:00:00Z", start: 9 * 60, end: 9 * 60))
    }

    func testMusicFieldsMoveIndependently() {
        let signals = IslandSignals()
        signals.setMusic(isPlaying: true, showToast: false, hasTitle: false, hasLyrics: false, title: "", artist: "")
        XCTAssertTrue(signals.isPlaying)
        signals.setMusic(isPlaying: true, showToast: true, hasTitle: true, hasLyrics: true, title: "A", artist: "B")
        XCTAssertTrue(signals.showToast)
        XCTAssertTrue(signals.hasTitle)
        XCTAssertTrue(signals.hasLyrics)
        XCTAssertTrue(signals.isPlaying)
    }
}
