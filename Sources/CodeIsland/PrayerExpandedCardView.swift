import SwiftUI
import CodeIslandCore

/// Fully redesigned living diorama clock, interactive prayer schedule, Qibla compass,
/// and adhan reminder dashboard with seamless switching between Pixel Retro (8-Bit) and Modern Clean themes.
public struct PrayerExpandedCardView: View {
    @ObservedObject public var manager: PrayerTimeManager

    @AppStorage(SettingsKey.islandUITheme) private var islandUITheme = SettingsDefaults.islandUITheme
    @State private var hoveredPrayer: String? = nil
    @State private var hoveredToolbarItem: String? = nil
    @State private var isPlayingAdhanPreview = false
    @State private var adhanTask: Task<Void, Never>? = nil

    private var isPixel: Bool {
        islandUITheme == IslandUITheme.pixel.rawValue
    }

    public init(manager: PrayerTimeManager) {
        self.manager = manager
    }

    public var body: some View {
        Group {
            if isPixel {
                pixelDashboard
            } else {
                modernDashboard
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
    }

    // MARK: - ==========================================
    // MARK: 1. PIXEL RETRO (8-BIT) THEME DASHBOARD
    // MARK: - ==========================================

    private var pixelDashboard: some View {
        let upcoming = manager.upcomingPrayer
        let schedule = manager.todaySchedule
        let phase = manager.currentPhase

        return VStack(spacing: 12) {
            // Header Bar: Pixel Retro Title & Controls
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(red: 0.12, green: 0.84, blue: 0.38))
                    Text("JADWAL SHOLAT // PRAYER DIORAMA")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.95))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Rectangle()
                        .fill(Color(red: 0.12, green: 0.84, blue: 0.38).opacity(0.12))
                        .overlay(Rectangle().stroke(Color(red: 0.12, green: 0.84, blue: 0.38).opacity(0.4), lineWidth: 0.8))
                )

                Spacer()

                // Test Adhan Button
                Button(action: handleAdhanTest) {
                    HStack(spacing: 4) {
                        Image(systemName: isPlayingAdhanPreview ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 8.5, weight: .bold))
                        Text(isPlayingAdhanPreview ? "PLAYING..." : "TEST ADHAN")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(
                        Rectangle()
                            .fill(isPlayingAdhanPreview ? Color(red: 0.12, green: 0.84, blue: 0.38).opacity(0.3) : Color.white.opacity(0.06))
                            .overlay(Rectangle().stroke(isPlayingAdhanPreview ? Color(red: 0.12, green: 0.84, blue: 0.38) : Color.white.opacity(0.15), lineWidth: 0.8))
                    )
                    .foregroundStyle(isPlayingAdhanPreview ? Color(red: 0.12, green: 0.84, blue: 0.38) : Color.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .help("Dengarkan bunyi pengingat sholat")
            }

            // 1. Pixel Living Diorama Sky Card
            ZStack(alignment: .topLeading) {
                DioramaSkyView(
                    hour: manager.currentFractionalHour,
                    hijriDay: manager.hijriDay,
                    sunriseHour: manager.sunriseHour,
                    sunsetHour: manager.sunsetHour,
                    pixel: true,
                    skyline: true,
                    skylineHeight: 0.15
                )
                .clipShape(Rectangle())
                .overlay(
                    Rectangle()
                        .stroke(Color(red: 0.12, green: 0.84, blue: 0.38).opacity(0.45), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 0) {
                    // Top Row: Phase Badge & Upcoming Countdown
                    HStack(alignment: .center) {
                        HStack(spacing: 5) {
                            Image(systemName: phase.systemImage)
                                .font(.system(size: 10, weight: .bold))
                            Text("WAKTU: \(phase.displayName)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Rectangle()
                                .fill(Color.black.opacity(0.65))
                                .overlay(Rectangle().stroke(Color.white.opacity(0.2), lineWidth: 0.8))
                        )

                        Spacer()

                        if let next = upcoming {
                            HStack(alignment: .center, spacing: 6) {
                                Text("\(next.prayer.displayName.uppercased()) \(manager.formattedPrayerTime(next.date))")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.white)

                                Text("-\(manager.formattedCountdown)")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.black)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        Rectangle()
                                            .fill(Color(red: 0.12, green: 0.84, blue: 0.38))
                                    )
                                    .shadow(color: Color(red: 0.12, green: 0.84, blue: 0.38).opacity(0.6), radius: 4)
                            }
                        }
                    }

                    Spacer(minLength: 4)

                    // Big Retro Digital Clock with live seconds
                    Text(manager.currentSecondsString)
                        .font(.system(size: 38, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .shadow(color: Color.black.opacity(0.85), radius: 4)

                    Spacer(minLength: 6)

                    // Subtitle: Location · Gregorian · Hijri
                    let subtitle = "📍 \(manager.cityName.uppercased()) // \(manager.gregorianDateString.uppercased()) // \(manager.hijriDateString.uppercased())"
                    Text(subtitle)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .frame(height: 142)

            // 2. Five Pixel Prayer Cards (Subuh, Dzuhur, Ashar, Maghrib, Isya)
            if let sched = schedule {
                HStack(spacing: 6) {
                    ForEach(sched.fivePrayers, id: \.prayer.rawValue) { item in
                        let isNext = (item.prayer == upcoming?.prayer)
                        let isPassed = (item.date < Date() && !isNext)
                        let isHovered = (hoveredPrayer == item.prayer.rawValue)

                        VStack(spacing: 5) {
                            // Top Tag: Next or Icon
                            if isNext {
                                Text("NEXT")
                                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.black)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Rectangle().fill(Color(red: 0.12, green: 0.84, blue: 0.38)))
                            } else if isPassed {
                                Text("✓")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Color(red: 0.12, green: 0.84, blue: 0.38).opacity(0.7))
                            } else {
                                Text("·")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.white.opacity(0.35))
                            }

                            Text(item.prayer.displayName.uppercased())
                                .font(.system(size: 9.5, weight: isNext ? .bold : .medium, design: .monospaced))
                                .foregroundStyle(isNext ? Color(red: 0.12, green: 0.84, blue: 0.38) : (isPassed ? Color.white.opacity(0.45) : Color.white.opacity(0.85)))

                            Text(manager.formattedPrayerTime(item.date))
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(isNext ? Color.white : (isPassed ? Color.white.opacity(0.55) : Color.white))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Rectangle()
                                .fill(isNext ? Color(red: 0.12, green: 0.84, blue: 0.38).opacity(0.18) : (isHovered ? Color.white.opacity(0.08) : Color.black.opacity(0.35)))
                        )
                        .overlay(
                            Rectangle()
                                .stroke(isNext ? Color(red: 0.12, green: 0.84, blue: 0.38) : (isHovered ? Color.white.opacity(0.25) : Color.white.opacity(0.10)), lineWidth: isNext ? 1.2 : 0.8)
                        )
                        .shadow(color: isNext ? Color(red: 0.12, green: 0.84, blue: 0.38).opacity(0.35) : Color.clear, radius: 4)
                        .scaleEffect(isHovered ? 1.02 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
                        .contentShape(Rectangle())
                        .onHover { hoveredPrayer = $0 ? item.prayer.rawValue : nil }
                        .onTapGesture {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            handleAdhanTest()
                        }
                        .help("Klik untuk test suara pengingat \(item.prayer.displayName)")
                    }
                }
            }

            // 3. Pixel Utility Toolbar: Qibla Compass + Solar Horizon Progress
            HStack(spacing: 8) {
                // Interactive Qibla Compass Card
                HStack(spacing: 6) {
                    // Rotating Needle
                    ZStack {
                        Circle()
                            .stroke(Color(red: 0.12, green: 0.84, blue: 0.38).opacity(0.4), lineWidth: 1)
                            .frame(width: 22, height: 22)

                        Image(systemName: "location.north.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(red: 0.12, green: 0.84, blue: 0.38))
                            .rotationEffect(.degrees(manager.qiblaDegrees))
                            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: manager.qiblaDegrees)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("KIBLAT // KAABA")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.65))
                        Text("\(Int(manager.qiblaDegrees))° \(manager.qiblaCompassDirection)")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.12, green: 0.84, blue: 0.38))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Rectangle()
                        .fill(Color.white.opacity(0.04))
                        .overlay(Rectangle().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
                )

                Spacer()

                // Solar Horizon Stepped Progress Strip
                HStack(spacing: 6) {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("SOLAR PROGRESS")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.65))
                            Text("\(Int(manager.solarProgress * 100))%")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.12, green: 0.84, blue: 0.38))
                        }

                        // Stepped 8-bit Progress Bar
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 90, height: 6)

                            Rectangle()
                                .fill(Color(red: 0.12, green: 0.84, blue: 0.38))
                                .frame(width: max(4, 90 * CGFloat(manager.solarProgress)), height: 6)
                                .shadow(color: Color(red: 0.12, green: 0.84, blue: 0.38).opacity(0.6), radius: 2)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Rectangle()
                        .fill(Color.white.opacity(0.04))
                        .overlay(Rectangle().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
                )
            }
        }
    }

    // MARK: - ==========================================
    // MARK: 2. MODERN CLEAN THEME DASHBOARD
    // MARK: - ==========================================

    private var modernDashboard: some View {
        let upcoming = manager.upcomingPrayer
        let schedule = manager.todaySchedule
        let phase = manager.currentPhase

        return VStack(spacing: 12) {
            // 1. Living Diorama Canvas Sky Card (~142pt)
            ZStack(alignment: .topLeading) {
                DioramaSkyView(
                    hour: manager.currentFractionalHour,
                    hijriDay: manager.hijriDay,
                    sunriseHour: manager.sunriseHour,
                    sunsetHour: manager.sunsetHour,
                    pixel: false,
                    skyline: true,
                    skylineHeight: 0.14
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 0) {
                    // Top Row: Phase Badge (Left) & Upcoming Prayer Countdown (Right)
                    HStack(alignment: .center) {
                        HStack(spacing: 6) {
                            Image(systemName: phase.systemImage)
                                .font(.system(size: 11, weight: .bold))
                            Text(phase.displayName)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.45))
                                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.8))
                        )

                        Spacer()

                        if let next = upcoming {
                            HStack(alignment: .center, spacing: 8) {
                                Text("\(next.prayer.displayName) \(manager.formattedPrayerTime(next.date))")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)

                                Text("-\(manager.formattedCountdown)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4.5)
                                    .background(
                                        Capsule()
                                            .fill(phase.accentColor.opacity(0.85))
                                    )
                                    .shadow(color: phase.accentColor.opacity(0.5), radius: 5, y: 1)
                            }
                        }
                    }

                    Spacer(minLength: 4)

                    // Big Digital Clock with live seconds
                    Text(manager.currentSecondsString)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: Color.black.opacity(0.6), radius: 3)

                    Spacer(minLength: 6)

                    // Subtitle: City · Day Date · Hijri Date
                    let subtitle = "\(manager.cityName) · \(manager.gregorianDateString) · \(manager.hijriDateString)"
                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .lineLimit(1)
                }
                .shadow(color: Color.black.opacity(0.6), radius: 2)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 12)
            }
            .frame(height: 142)

            // 2. Five Prayer Capsules (Subuh, Dzuhur, Ashar, Maghrib, Isya)
            if let sched = schedule {
                HStack(spacing: 8) {
                    ForEach(sched.fivePrayers, id: \.prayer.rawValue) { item in
                        let isNext = (item.prayer == upcoming?.prayer)
                        let isPassed = (item.date < Date() && !isNext)
                        let isHovered = (hoveredPrayer == item.prayer.rawValue)

                        VStack(spacing: 4) {
                            Text(item.prayer.displayName)
                                .font(.system(size: 11, weight: isNext ? .bold : .medium, design: .rounded))
                                .foregroundStyle(isNext ? Color(red: 0.08, green: 0.09, blue: 0.16) : (isPassed ? Color.white.opacity(0.45) : Color.white.opacity(0.80)))

                            Text(manager.formattedPrayerTime(item.date))
                                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                                .foregroundStyle(isNext ? Color(red: 0.08, green: 0.09, blue: 0.16) : (isPassed ? Color.white.opacity(0.55) : Color.white))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(isNext ? phase.accentColor : (isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.07)))
                        )
                        .overlay(
                            Capsule()
                                .stroke(isNext ? Color.clear : (isHovered ? Color.white.opacity(0.25) : Color.white.opacity(0.06)), lineWidth: 0.8)
                        )
                        .shadow(color: isNext ? phase.accentColor.opacity(0.4) : Color.clear, radius: 6, y: 2)
                        .scaleEffect(isHovered ? 1.02 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
                        .contentShape(Rectangle())
                        .onHover { hoveredPrayer = $0 ? item.prayer.rawValue : nil }
                        .onTapGesture {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            handleAdhanTest()
                        }
                        .help("Klik untuk test audio pengingat \(item.prayer.displayName)")
                    }
                }
            }

            // 3. Modern Toolbar: Qibla Compass + Adhan Test Button
            HStack(spacing: 8) {
                // Qibla Compass Capsule
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(phase.accentColor.opacity(0.18))
                            .frame(width: 24, height: 24)

                        Image(systemName: "location.north.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(phase.accentColor)
                            .rotationEffect(.degrees(manager.qiblaDegrees))
                            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: manager.qiblaDegrees)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Arah Kiblat")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.65))
                        Text("\(Int(manager.qiblaDegrees))° \(manager.qiblaCompassDirection) Kaaba")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.6))
                )

                Spacer()

                // Test Adhan Pill
                Button(action: handleAdhanTest) {
                    HStack(spacing: 5) {
                        Image(systemName: isPlayingAdhanPreview ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(isPlayingAdhanPreview ? "Memutar Audio..." : "Test Pengingat")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6.5)
                    .background(
                        Capsule()
                            .fill(isPlayingAdhanPreview ? phase.accentColor.opacity(0.3) : Color.white.opacity(0.06))
                            .overlay(Capsule().stroke(isPlayingAdhanPreview ? phase.accentColor : Color.white.opacity(0.10), lineWidth: 0.6))
                    )
                    .foregroundStyle(isPlayingAdhanPreview ? phase.accentColor : Color.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                .help("Dengarkan bunyi pengingat sholat")
            }
        }
    }

    // MARK: - Helpers

    private func handleAdhanTest() {
        guard !isPlayingAdhanPreview else { return }
        isPlayingAdhanPreview = true
        manager.playAdhanPreview()

        adhanTask?.cancel()
        adhanTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            isPlayingAdhanPreview = false
        }
    }
}
