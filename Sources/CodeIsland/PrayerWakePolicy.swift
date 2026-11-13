import Foundation
import CodeIslandCore

/// When the prayer manager next has to wake up.
///
/// It used to wake every second to advance a clock string, a solar progress
/// value and a countdown — all of which change at most once a minute — and to
/// notice a banner or a priority window. The schedule is the same information
/// read the other way round: the next moment anything can change. The manager
/// arms one timer for it, and the seconds only run inside the expanded card
/// that actually shows them.
enum PrayerWakePolicy {
    /// Smart priority: the wing hands itself to the next prayer this long before.
    static let priorityLeadMinutes = 15
    /// …and keeps it this long after the entry.
    static let priorityTrailMinutes = 5

    /// Everything that can make the next tick do something:
    ///
    /// - the next minute boundary (clock, countdown, solar progress);
    /// - the T-N banner lead-in, and the prayer entry itself;
    /// - the start and end of the smart-priority window;
    /// - a day-phase change (the diorama's palette);
    /// - midnight (a new schedule, a new Hijri day).
    ///
    /// Returns nil when prayer times are off: nothing to wake for.
    static func nextWake(
        now: Date,
        schedule: DailyPrayerSchedule?,
        tomorrowSubuh: Date?,
        alertMinutes: Int,
        timeZone: TimeZone,
        isEnabled: Bool = true
    ) -> Date? {
        guard isEnabled else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var candidates: [Date] = []

        // The next whole minute.
        let secondsIntoMinute = now.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
        candidates.append(now.addingTimeInterval(60 - secondsIntoMinute))

        // Midnight: a fresh schedule, and the Hijri date rolls over.
        let startOfToday = calendar.startOfDay(for: now)
        if let midnight = calendar.date(byAdding: .day, value: 1, to: startOfToday) {
            candidates.append(midnight)
        }

        if let schedule {
            if let next = schedule.nextFardhPrayer(at: now, tomorrowSubuh: tomorrowSubuh) {
                candidates.append(next.date)
                candidates.append(next.date.addingTimeInterval(-Double(priorityLeadMinutes) * 60))
                candidates.append(next.date.addingTimeInterval(Double(priorityTrailMinutes) * 60))
                if alertMinutes > 0 {
                    candidates.append(next.date.addingTimeInterval(-Double(alertMinutes) * 60))
                }
            }
            // Day-phase boundaries inside today: fajr, the 11:00 morning line,
            // asr, and maghrib.
            candidates.append(schedule.subuh)
            if let eleven = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: now) {
                candidates.append(eleven)
            }
            candidates.append(schedule.ashar)
            candidates.append(schedule.maghrib)
        }

        return candidates
            .filter { $0 > now }
            .min()
    }
}
