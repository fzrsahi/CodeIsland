import XCTest
import CodeIslandCore
@testable import CodeIsland

/// The prayer manager's wake schedule (idle-perf ticket 09). It used to wake
/// every second; the schedule is the same information read the other way round.
final class PrayerWakePolicyTests: XCTestCase {
    private let tz = TimeZone(identifier: "Asia/Jakarta")!

    private func date(_ hour: Int, _ minute: Int, _ second: Int = 0, day: Int = 14) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        return calendar.date(from: DateComponents(
            year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second
        ))!
    }

    private func schedule(subuh: Date, ashar: Date, maghrib: Date) -> DailyPrayerSchedule {
        DailyPrayerSchedule(
            day: YearMonthDay(year: 2026, month: 11, day: 14),
            method: .kemenag,
            imsak: subuh.addingTimeInterval(-10 * 60),
            subuh: subuh,
            terbit: date(5, 45),
            dhuha: date(6, 10),
            dzuhur: date(11, 50),
            ashar: ashar,
            maghrib: maghrib,
            isya: date(19, 10)
        )
    }

    func testTheNextMinuteBoundaryIsTheCommonCase() {
        let now = date(9, 30, 10)
        let wake = PrayerWakePolicy.nextWake(
            now: now, schedule: schedule(subuh: date(4, 40), ashar: date(15, 5), maghrib: date(17, 55)),
            tomorrowSubuh: nil, alertMinutes: 10, timeZone: tz
        )
        XCTAssertEqual(wake, date(9, 31))
    }

    func testAPrayerEntryOutranksTheMinuteBoundary() {
        let entry = date(15, 5)
        let now = date(15, 4, 55)
        let wake = PrayerWakePolicy.nextWake(
            now: now, schedule: schedule(subuh: date(4, 40), ashar: entry, maghrib: date(17, 55)),
            tomorrowSubuh: nil, alertMinutes: 10, timeZone: tz
        )
        XCTAssertEqual(wake, entry)
    }

    func testTheWakeNeverComesAfterTheLeadInBanner() {
        let entry = date(15, 5)
        let leadIn = date(14, 55)
        // The lead-in lands on a minute boundary, so the two reasons coincide.
        let wake = PrayerWakePolicy.nextWake(
            now: date(14, 50), schedule: schedule(subuh: date(4, 40), ashar: entry, maghrib: date(17, 55)),
            tomorrowSubuh: nil, alertMinutes: 10, timeZone: tz
        )
        XCTAssertEqual(wake, date(14, 51))
        XCTAssertLessThanOrEqual(wake!, leadIn)
    }

    func testThePriorityWindowOpensFifteenMinutesBefore() {
        let entry = date(19, 10)
        let now = date(18, 55, 30)
        let wake = PrayerWakePolicy.nextWake(
            now: now, schedule: schedule(subuh: date(4, 40), ashar: date(15, 5), maghrib: date(17, 55)),
            tomorrowSubuh: entry, alertMinutes: 0, timeZone: tz
        )
        XCTAssertEqual(wake, date(18, 56), "the minute boundary is nearer than the entry")
    }

    func testThePriorityWindowClosingIsAWakeReason() {
        let entry = date(15, 5)
        let now = date(15, 6)
        let wake = PrayerWakePolicy.nextWake(
            now: now, schedule: schedule(subuh: date(4, 40), ashar: entry, maghrib: date(17, 55)),
            tomorrowSubuh: nil, alertMinutes: 0, timeZone: tz
        )
        // Entry + 5 minutes is the wing's priority trail.
        let expected = entry.addingTimeInterval(5 * 60)
        XCTAssertLessThanOrEqual(wake!, expected)
    }

    func testMidnightIsAWakeReason() {
        let midnight = date(0, 0, day: 15)
        let now = date(23, 59, 30)
        let wake = PrayerWakePolicy.nextWake(
            now: now, schedule: schedule(subuh: date(4, 40), ashar: date(15, 5), maghrib: date(17, 55)),
            tomorrowSubuh: nil, alertMinutes: 10, timeZone: tz
        )
        XCTAssertEqual(wake, midnight)
    }

    func testAnHourBeforeMidnightWakesOnTheNextMinuteNotMidnight() {
        let now = date(23, 0, 20)
        let wake = PrayerWakePolicy.nextWake(
            now: now, schedule: schedule(subuh: date(4, 40), ashar: date(15, 5), maghrib: date(17, 55)),
            tomorrowSubuh: nil, alertMinutes: 10, timeZone: tz
        )
        XCTAssertEqual(wake, date(23, 1))
    }

    func testDisabledPrayerTimesNeverWake() {
        XCTAssertNil(PrayerWakePolicy.nextWake(
            now: date(9, 0), schedule: nil, tomorrowSubuh: nil,
            alertMinutes: 10, timeZone: tz, isEnabled: false
        ))
    }

    func testWithoutAScheduleTheClockStillTicks() {
        let now = date(9, 0, 15)
        let wake = PrayerWakePolicy.nextWake(
            now: now, schedule: nil, tomorrowSubuh: nil, alertMinutes: 10, timeZone: tz
        )
        XCTAssertEqual(wake, date(9, 1))
    }
}
