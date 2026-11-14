import Combine
import Foundation

/// The one place that copies manager state into `IslandSignals`.
///
/// The panel root and both wings used to observe the five singletons directly,
/// so a track position, a CPU sample or a workspace refresh re-rendered the
/// whole bar. They read `IslandSignals` now; this object feeds it, and every
/// write goes through a setter that does nothing when the value has not moved.
///
/// It also owns the quiet-hours clock: the moon used to be recomputed on every
/// render, which meant reading `UserDefaults` and the calendar per frame. One
/// timer, armed for the next boundary, replaces that.
@MainActor
final class IslandSignalsSync {
    static let shared = IslandSignalsSync()

    private let signals: IslandSignals
    private var cancellables: Set<AnyCancellable> = []
    private var quietHoursTimer: Timer?
    private var started = false

    init(signals: IslandSignals = .shared) {
        self.signals = signals
    }

    func start() {
        guard !started else { return }
        started = true
        let nowPlaying = NowPlayingManager.shared
        let workspace = WorkspaceMonitorManager.shared
        let system = SystemMonitorManager.shared
        let prayer = PrayerTimeManager.shared
        let volume = SystemVolumeManager.shared

        // Music: any of these moving recomputes the handful of values the bar
        // shows. The setters drop writes that would not change anything.
        for publisher in [
            nowPlaying.$isPlaying.map { _ in () }.eraseToAnyPublisher(),
            nowPlaying.$showToast.map { _ in () }.eraseToAnyPublisher(),
            nowPlaying.$title.map { _ in () }.eraseToAnyPublisher(),
            nowPlaying.$artist.map { _ in () }.eraseToAnyPublisher(),
            nowPlaying.$lyrics.map { _ in () }.eraseToAnyPublisher(),
            nowPlaying.$lyricsLoading.map { _ in () }.eraseToAnyPublisher(),
        ] {
            publisher
                .sink { [weak self] in self?.publishMusic() }
                .store(in: &cancellables)
        }

        workspace.$isExpandedDetail
            .sink { [weak self] expanded in self?.signals.setDetailExpanded(expanded) }
            .store(in: &cancellables)

        for publisher in [
            system.$showChargingBanner.map { _ in () }.eraseToAnyPublisher(),
            system.$metrics.map { _ in () }.eraseToAnyPublisher(),
        ] {
            publisher
                .sink { [weak self] in
                    self?.signals.setChargingBanner(
                        visible: system.showChargingBanner,
                        batteryLevel: system.metrics.batteryLevel
                    )
                }
                .store(in: &cancellables)
        }

        prayer.$showMiniPeekBanner
            .sink { [weak self] visible in self?.signals.setMiniPeekBanner(visible) }
            .store(in: &cancellables)

        // Smart priority depends on the clock, not only on the schedule: the
        // prayer manager already wakes at the window's edges, so recompute
        // whenever its state moves.
        for publisher in [
            prayer.$upcomingPrayer.map { _ in () }.eraseToAnyPublisher(),
            prayer.$minutesUntilNextPrayer.map { _ in () }.eraseToAnyPublisher(),
        ] {
            publisher
                .sink { [weak self] in
                    let minutes = prayer.minutesUntilNextPrayer
                    self?.signals.setPrayerPrioritized(minutes <= 15 && minutes >= -5)
                }
                .store(in: &cancellables)
        }

        volume.$isHUDVisible
            .sink { [weak self] visible in self?.signals.setVolumeHUDVisible(visible) }
            .store(in: &cancellables)

        refreshQuietHours()
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshQuietHours() }
        }
    }

    private func publishMusic() {
        let nowPlaying = NowPlayingManager.shared
        signals.setMusic(
            isPlaying: nowPlaying.isPlaying,
            showToast: nowPlaying.showToast,
            hasTitle: !nowPlaying.title.isEmpty,
            hasLyrics: !nowPlaying.lyrics.isEmpty || nowPlaying.lyricsLoading,
            title: nowPlaying.title,
            artist: nowPlaying.artist
        )
    }

    // MARK: - Quiet hours

    /// Recompute "are we inside quiet hours" and arm one timer for the next
    /// moment the answer can change.
    func refreshQuietHours(now: Date = Date(), calendar: Calendar = .current) {
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: SettingsKey.soundEnabled)
            && defaults.bool(forKey: SettingsKey.quietHoursEnabled)
        let start = defaults.integer(forKey: SettingsKey.quietHoursStart)
        let end = defaults.integer(forKey: SettingsKey.quietHoursEnd)

        let components = calendar.dateComponents([.hour, .minute], from: now)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let quiet = enabled && SoundManager.isInQuietHours(minutesSinceMidnight: minutes, start: start, end: end)
        signals.setInQuietHours(quiet)

        quietHoursTimer?.invalidate()
        quietHoursTimer = nil
        guard enabled else { return }
        guard let boundary = Self.nextQuietHoursBoundary(
            now: now, calendar: calendar, start: start, end: end
        ) else { return }
        let delay = max(0.5, boundary.timeIntervalSince(now))
        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.quietHoursTimer = nil
                self?.refreshQuietHours()
            }
        }
        timer.tolerance = min(30, delay * 0.1)
        quietHoursTimer = timer
    }

    /// The next minute the quiet-hours answer can flip: the window's start, its
    /// end, or midnight (a window that wraps the day flips at both).
    nonisolated static func nextQuietHoursBoundary(
        now: Date, calendar: Calendar, start: Int, end: Int
    ) -> Date? {
        guard start != end else { return nil }
        let startOfDay = calendar.startOfDay(for: now)
        var candidates: [Date] = []
        for dayOffset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfDay) else { continue }
            for minutes in [start, end] {
                guard let moment = calendar.date(byAdding: .minute, value: minutes, to: day) else { continue }
                if moment > now { candidates.append(moment) }
            }
        }
        // Midnight only flips the answer when a window edge sits on it.
        if start == 0 || end == 0,
           let midnight = calendar.date(byAdding: .day, value: 1, to: startOfDay), midnight > now {
            candidates.append(midnight)
        }
        return candidates.min()
    }
}
