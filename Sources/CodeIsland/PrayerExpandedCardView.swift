import SwiftUI
import CodeIslandCore

/// Unified living diorama prayer card with an integrated seamless timeline and functional Qibla compass.
/// Eliminates segmented boxy cards in favor of a cohesive, minimalist, and cinematic panoramic dashboard.
/// Fully supports authentic 8-bit retro pixel and modern clean aesthetics with 100% English wording.
public struct PrayerExpandedCardView: View {
    @ObservedObject public var manager: PrayerTimeManager

    @AppStorage(SettingsKey.islandUITheme) private var islandUITheme = SettingsDefaults.islandUITheme
    @State private var hoveredPrayer: String? = nil
    @State private var hoveredCompass = false

    private var isPixel: Bool {
        islandUITheme == IslandUITheme.pixel.rawValue
    }

    private static let tabGreen = Color(red: 0.12, green: 0.84, blue: 0.38)

    public init(manager: PrayerTimeManager) {
        self.manager = manager
    }

    public var body: some View {
        Group {
            if isPixel {
                unifiedPixelDashboard
            } else {
                unifiedModernDashboard
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
    }

    // MARK: - ==========================================
    // MARK: 1. UNIFIED PIXEL RETRO (8-BIT) DASHBOARD
    // MARK: - ==========================================

    private var unifiedPixelDashboard: some View {
        let upcoming = manager.upcomingPrayer
        let schedule = manager.todaySchedule
        let phase = manager.currentPhase
        let deg = manager.qiblaDegrees
        let dirShort = manager.qiblaCompassDirection
        let dirFull = manager.qiblaCompassDirectionFull

        return ZStack(alignment: .topLeading) {
            // ── Background: Authentic 8-bit Stepped Pixel Sky & Mosque Skyline ──
            DioramaSkyView(
                hour: manager.currentFractionalHour,
                hijriDay: manager.hijriDay,
                sunriseHour: manager.sunriseHour,
                sunsetHour: manager.sunsetHour,
                pixel: true,
                skyline: true,
                skylineHeight: 0.28
            )
            .clipShape(Rectangle())
            .overlay(
                Rectangle()
                    .stroke(Self.tabGreen.opacity(0.40), lineWidth: 1)
            )

            // Deepening vertical contrast gradient overlay for flawless legibility
            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.48),
                    Color.black.opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            // ── Foreground Unified Content ──
            VStack(spacing: 6) {
                // A. Top Floating Header & Info Row (Compact, Single Horizontal Bar)
                HStack(alignment: .center, spacing: 7) {
                    // Phase Tag
                    HStack(spacing: 4) {
                        Image(systemName: phase.systemImage)
                            .font(.system(size: 8, weight: .bold))
                        Text(phase.displayName.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(
                        Rectangle()
                            .fill(Color.black.opacity(0.70))
                            .overlay(Rectangle().stroke(Color.white.opacity(0.20), lineWidth: 0.8))
                    )

                    // Date & City
                    Text("\(manager.gregorianDateString.uppercased()) // \(manager.cityName.uppercased())")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    // Next Prayer Spotlight Badge
                    if let next = upcoming {
                        let diffMins = manager.minutesUntilNextPrayer
                        HStack(spacing: 4) {
                            Text(next.prayer.displayName.uppercased())
                                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                .foregroundStyle(Color.white)

                            Text(manager.formattedPrayerTime(next.date))
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Self.tabGreen)

                            Text(diffMins <= 0 ? "[NOW]" : "[-\(manager.formattedCountdown)]")
                                .font(.system(size: 7.5, weight: .black, design: .monospaced))
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(Rectangle().fill(Self.tabGreen))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            Rectangle()
                                .fill(Color.black.opacity(0.70))
                                .overlay(Rectangle().stroke(Self.tabGreen.opacity(0.35), lineWidth: 0.8))
                        )
                    }

                    // Compact Pixel Qibla Dial
                    HStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .stroke(Self.tabGreen.opacity(0.40), lineWidth: 0.8)
                                .frame(width: 17, height: 17)
                                .background(Circle().fill(Color.black.opacity(0.65)))

                            // Needle
                            VStack(spacing: 0) {
                                Image(systemName: "triangle.fill")
                                    .font(.system(size: 4, weight: .bold))
                                    .foregroundStyle(Self.tabGreen)
                                Rectangle()
                                    .fill(Self.tabGreen)
                                    .frame(width: 1.0, height: 5.5)
                                Spacer()
                            }
                            .frame(height: 14)
                            .rotationEffect(.degrees(deg))
                        }
                        .frame(width: 17, height: 17)

                        Text("QIBLA: \(Int(deg))° \(dirShort)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.90))

                        Text("🕋")
                            .font(.system(size: 7))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(
                        Rectangle()
                            .fill(Color.black.opacity(0.70))
                            .overlay(Rectangle().stroke(Self.tabGreen.opacity(0.35), lineWidth: 0.8))
                    )
                    .help("Qibla Direction: \(Int(deg))° \(dirFull) towards Kaaba")
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)

                Spacer(minLength: 2)

                // B. Seamless Integrated Prayer Timeline Ribbon
                if let sched = schedule {
                    seamlessPrayerTimeline(sched: sched, isPixelTheme: true)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 6)
                }
            }
        }
        .frame(height: 120)
    }

    // MARK: - ==========================================
    // MARK: 2. UNIFIED MODERN CLEAN DASHBOARD
    // MARK: - ==========================================

    private var unifiedModernDashboard: some View {
        let upcoming = manager.upcomingPrayer
        let schedule = manager.todaySchedule
        let phase = manager.currentPhase
        let deg = manager.qiblaDegrees
        let dirShort = manager.qiblaCompassDirection
        let dirFull = manager.qiblaCompassDirectionFull

        return ZStack(alignment: .topLeading) {
            // ── Background: Smooth Atmospheric Diorama Sky & Silhouette Skyline ──
            DioramaSkyView(
                hour: manager.currentFractionalHour,
                hijriDay: manager.hijriDay,
                sunriseHour: manager.sunriseHour,
                sunsetHour: manager.sunsetHour,
                pixel: false,
                skyline: true,
                skylineHeight: 0.28
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
            )

            // Deepening vertical contrast gradient overlay
            LinearGradient(
                colors: [
                    Color.black.opacity(0.12),
                    Color.black.opacity(0.42),
                    Color.black.opacity(0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            // ── Foreground Unified Content ──
            VStack(spacing: 6) {
                // A. Top Floating Header & Info Row (Compact, Single Horizontal Bar)
                HStack(alignment: .center, spacing: 8) {
                    // Phase Tag
                    HStack(spacing: 4) {
                        Image(systemName: phase.systemImage)
                            .font(.system(size: 8.5, weight: .bold))
                        Text(phase.displayName)
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.50))
                            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.6))
                    )

                    // Date & City
                    Text("\(manager.gregorianDateString) · \(manager.cityName)")
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    // Next Prayer Spotlight Badge
                    if let next = upcoming {
                        let diffMins = manager.minutesUntilNextPrayer
                        HStack(spacing: 4.5) {
                            Text(next.prayer.displayName)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white)

                            Text(manager.formattedPrayerTime(next.date))
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(Self.tabGreen)

                            Text(diffMins <= 0 ? "Now" : "-\(manager.formattedCountdown)")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Self.tabGreen.opacity(0.90)))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.50))
                                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.6))
                        )
                    }

                    // Compact Modern Qibla Dial
                    HStack(spacing: 4.5) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.45))
                                .frame(width: 18, height: 18)
                                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.6))

                            // Needle towards Kaaba
                            VStack(spacing: 0) {
                                Image(systemName: "location.north.fill")
                                    .font(.system(size: 4.5, weight: .bold))
                                    .foregroundStyle(Self.tabGreen)
                                Rectangle()
                                    .fill(Self.tabGreen)
                                    .frame(width: 1.0, height: 6)
                                Spacer()
                            }
                            .frame(height: 15)
                            .rotationEffect(.degrees(deg))
                        }
                        .frame(width: 18, height: 18)

                        Text("Qibla \(Int(deg))° \(dirShort)")
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.95))

                        Text("🕋")
                            .font(.system(size: 7.5))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.50))
                            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.6))
                    )
                    .help("Qibla Direction: \(Int(deg))° \(dirFull) towards Kaaba in Mecca")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer(minLength: 2)

                // B. Seamless Integrated Prayer Timeline Ribbon
                if let sched = schedule {
                    seamlessPrayerTimeline(sched: sched, isPixelTheme: false)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }
            }
        }
        .frame(height: 120)
    }

    // MARK: - ==========================================
    // MARK: 3. SEAMLESS TIMELINE RIBBON (NO BOXES / KOTAK-KOTAK)
    // MARK: - ==========================================

    /// Elegant borderless horizontal timeline stepper with glowing beacon dots.
    /// Perfectly integrates across the lower portion of the unified panoramic canvas.
    @ViewBuilder
    private func seamlessPrayerTimeline(sched: DailyPrayerSchedule, isPixelTheme: Bool) -> some View {
        let upcoming = manager.upcomingPrayer
        let prayers = sched.fivePrayers
        let nextIndex = prayers.firstIndex { $0.prayer == upcoming?.prayer } ?? -1

        ZStack(alignment: .leading) {
            // Background Track Rail
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: isPixelTheme ? 1.5 : 2)
                .padding(.horizontal, 28)
                .offset(y: -9)

            // Passed Progress Glow Rail
            if nextIndex > 0 {
                GeometryReader { geo in
                    let totalSteps = CGFloat(prayers.count - 1)
                    let activeRatio = CGFloat(nextIndex) / totalSteps
                    let trackWidth = geo.size.width - 56
                    Rectangle()
                        .fill(Self.tabGreen.opacity(0.85))
                        .frame(width: max(0, trackWidth * activeRatio), height: isPixelTheme ? 1.5 : 2)
                        .padding(.leading, 28)
                        .offset(y: geo.size.height / 2 - 9)
                }
                .frame(height: 4)
            }

            // 5 Prayer Stations (FAJR, DHUHR, ASR, MAGHRIB, ISHA)
            HStack(spacing: 4) {
                ForEach(Array(prayers.enumerated()), id: \.element.prayer.rawValue) { index, item in
                    let isNext = (item.prayer == upcoming?.prayer)
                    let isPassed = (item.date < Date() && !isNext)
                    let isHovered = (hoveredPrayer == item.prayer.rawValue)

                    VStack(spacing: 2) {
                        // 1. Station Node Beacon on Rail
                        ZStack {
                            if isNext {
                                Circle()
                                    .fill(Self.tabGreen)
                                    .frame(width: 10, height: 10)
                                    .shadow(color: Self.tabGreen.opacity(0.8), radius: 4)

                                Circle()
                                    .fill(Color.black)
                                    .frame(width: 4, height: 4)
                            } else if isPassed {
                                Circle()
                                    .fill(Self.tabGreen.opacity(0.35))
                                    .frame(width: 8, height: 8)

                                Image(systemName: "checkmark")
                                    .font(.system(size: 4.5, weight: .black))
                                    .foregroundStyle(Self.tabGreen)
                            } else {
                                Circle()
                                    .fill(Color.white.opacity(0.25))
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .frame(height: 12)

                        // 2. Status Label Tag
                        if isNext {
                            Text("NEXT")
                                .font(.system(size: 6, weight: .black, design: isPixelTheme ? .monospaced : .rounded))
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 0.5)
                                .background(
                                    Group {
                                        if isPixelTheme {
                                            Rectangle().fill(Self.tabGreen)
                                        } else {
                                            Capsule().fill(Self.tabGreen)
                                        }
                                    }
                                )
                        } else if isPassed {
                            Text("PASSED")
                                .font(.system(size: 6, weight: .semibold, design: isPixelTheme ? .monospaced : .rounded))
                                .foregroundStyle(Color.white.opacity(0.35))
                        } else {
                            Text("UPCOMING")
                                .font(.system(size: 6, weight: .semibold, design: isPixelTheme ? .monospaced : .rounded))
                                .foregroundStyle(Color.white.opacity(0.40))
                        }

                        // 3. Prayer Name (Bold, Crisp)
                        Text(item.prayer.displayName.uppercased())
                            .font(.system(size: 8.5, weight: isNext ? .black : .bold, design: isPixelTheme ? .monospaced : .rounded))
                            .foregroundStyle(isNext ? Color.white : (isPassed ? Color.white.opacity(0.45) : Color.white.opacity(0.85)))

                        // 4. Formatted Time
                        Text(manager.formattedPrayerTime(item.date))
                            .font(.system(size: 11, weight: isNext ? .black : .bold, design: isPixelTheme ? .monospaced : .rounded))
                            .foregroundStyle(isNext ? Self.tabGreen : (isPassed ? Color.white.opacity(0.50) : Color.white))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                    .background(
                        Group {
                            if isHovered {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.08))
                            } else {
                                Color.clear
                            }
                        }
                    )
                    .contentShape(Rectangle())
                    .onHover { hoveredPrayer = $0 ? item.prayer.rawValue : nil }
                    .help("Prayer time for \(item.prayer.displayName): \(manager.formattedPrayerTime(item.date))")
                }
            }
        }
        .padding(.vertical, 2)
    }
}
