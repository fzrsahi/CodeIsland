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
                skylineHeight: 0.18
            )
            .clipShape(Rectangle())
            .overlay(
                Rectangle()
                    .stroke(Self.tabGreen.opacity(0.40), lineWidth: 1)
            )

            // Deepening vertical contrast gradient overlay for flawless legibility
            LinearGradient(
                colors: [
                    Color.black.opacity(0.15),
                    Color.black.opacity(0.40),
                    Color.black.opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            // ── Foreground Unified Content ──
            VStack(spacing: 0) {
                // A. Top Floating Header Strip
                HStack(alignment: .center) {
                    // Phase Tag + Date
                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: phase.systemImage)
                                .font(.system(size: 8.5, weight: .bold))
                            Text("PHASE: \(phase.displayName.uppercased())")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Rectangle()
                                .fill(Color.black.opacity(0.70))
                                .overlay(Rectangle().stroke(Color.white.opacity(0.25), lineWidth: 0.8))
                        )

                        Text("\(manager.gregorianDateString.uppercased()) // \(manager.hijriDateString.uppercased())")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineLimit(1)
                    }

                    Spacer()

                    // Location / City Tag
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Self.tabGreen)
                        Text(manager.cityName.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.95))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Rectangle()
                            .fill(Color.black.opacity(0.70))
                            .overlay(Rectangle().stroke(Self.tabGreen.opacity(0.40), lineWidth: 0.8))
                    )
                    .help("Active location for prayer times calculation")
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                Spacer(minLength: 6)

                // B. Hero Spotlight & Minimalist Qibla Dial
                HStack(alignment: .center, spacing: 14) {
                    // Left: Next Prayer Big Spotlight & Live Digital Clock
                    VStack(alignment: .leading, spacing: 3) {
                        if let next = upcoming {
                            let diffMins = manager.minutesUntilNextPrayer
                            Text(diffMins <= 0 ? "PRAYER TIME HAS ARRIVED" : "TIME UNTIL NEXT PRAYER")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.75))

                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(next.prayer.displayName.uppercased()) \(manager.formattedPrayerTime(next.date))")
                                    .font(.system(size: 17, weight: .black, design: .monospaced))
                                    .foregroundStyle(Color.white)

                                Text(diffMins <= 0 ? "[NOW]" : "[-\(manager.formattedCountdown)]")
                                    .font(.system(size: 10, weight: .black, design: .monospaced))
                                    .foregroundStyle(Color.black)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Rectangle().fill(Self.tabGreen))
                                    .shadow(color: Self.tabGreen.opacity(0.6), radius: 4)
                            }
                        }

                        // Digital Seconds Clock
                        Text(manager.currentSecondsString)
                            .font(.system(size: 26, weight: .black, design: .monospaced))
                            .foregroundStyle(Color.white)
                            .shadow(color: Color.black.opacity(0.8), radius: 3)
                    }

                    Spacer()

                    // Right: Sleek Pixel Qibla Compass Dial (Seamless, no double boxes)
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .stroke(Self.tabGreen.opacity(0.50), lineWidth: 1)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.black.opacity(0.65)))

                            // Cardinal Markers
                            VStack {
                                Text("N")
                                    .font(.system(size: 6, weight: .black, design: .monospaced))
                                    .foregroundStyle(Color.white)
                                Spacer()
                                Text("S")
                                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.white.opacity(0.4))
                            }
                            .frame(height: 40)

                            HStack {
                                Text("W")
                                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.white.opacity(0.4))
                                Spacer()
                                Text("E")
                                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.white.opacity(0.4))
                            }
                            .frame(width: 40)

                            // Kaaba needle
                            ZStack {
                                VStack(spacing: 0) {
                                    Image(systemName: "triangle.fill")
                                        .font(.system(size: 6, weight: .bold))
                                        .foregroundStyle(Self.tabGreen)
                                    Rectangle()
                                        .fill(Self.tabGreen)
                                        .frame(width: 1.2, height: 13)
                                    Spacer()
                                }
                                .frame(height: 36)
                                .rotationEffect(.degrees(deg))
                                .animation(.spring(response: 0.45, dampingFraction: 0.75), value: deg)

                                Circle()
                                    .fill(Self.tabGreen)
                                    .frame(width: 4, height: 4)
                            }

                            // Kaaba Icon
                            Text("🕋")
                                .font(.system(size: 7))
                                .offset(x: 15 * sin(deg * .pi / 180.0), y: -15 * cos(deg * .pi / 180.0))
                        }
                        .frame(width: 46, height: 46)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("QIBLA")
                                .font(.system(size: 7, weight: .black, design: .monospaced))
                                .foregroundStyle(Self.tabGreen)

                            Text("\(Int(deg))° \(dirShort)")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundStyle(Color.white)

                            Text(dirFull)
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.75))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        Rectangle()
                            .fill(Color.black.opacity(0.65))
                            .overlay(Rectangle().stroke(Self.tabGreen.opacity(0.35), lineWidth: 0.8))
                    )
                    .help("Qibla Direction: \(Int(deg))° clockwise from North towards the Kaaba in Mecca")
                }
                .padding(.horizontal, 14)

                Spacer(minLength: 8)

                // C. Seamless Integrated Prayer Timeline Ribbon (NO BOXES / KOTAK-KOTAK)
                if let sched = schedule {
                    seamlessPrayerTimeline(sched: sched, isPixelTheme: true)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                }
            }
        }
        .frame(height: 242)
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
                skylineHeight: 0.18
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )

            // Deepening vertical contrast gradient overlay
            LinearGradient(
                colors: [
                    Color.black.opacity(0.10),
                    Color.black.opacity(0.35),
                    Color.black.opacity(0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            // ── Foreground Unified Content ──
            VStack(spacing: 0) {
                // A. Top Floating Header Strip
                HStack(alignment: .center) {
                    // Phase Tag + Date
                    HStack(spacing: 8) {
                        HStack(spacing: 4.5) {
                            Image(systemName: phase.systemImage)
                                .font(.system(size: 9, weight: .bold))
                            Text(phase.displayName)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.50))
                                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.6))
                        )

                        Text("\(manager.gregorianDateString) · \(manager.hijriDateString)")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.88))
                            .lineLimit(1)
                    }

                    Spacer()

                    // Location / City Tag
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(Self.tabGreen)
                        Text(manager.cityName)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.95))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.50))
                            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.6))
                    )
                    .help("Active location for prayer times calculation")
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                Spacer(minLength: 6)

                // B. Hero Spotlight & Minimalist Modern Qibla Dial
                HStack(alignment: .center, spacing: 16) {
                    // Left: Next Prayer Big Spotlight & Live Digital Clock
                    VStack(alignment: .leading, spacing: 3) {
                        if let next = upcoming {
                            let diffMins = manager.minutesUntilNextPrayer
                            Text(diffMins <= 0 ? "Prayer Time Has Arrived" : "Time Until Next Prayer")
                                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.75))

                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(next.prayer.displayName) \(manager.formattedPrayerTime(next.date))")
                                    .font(.system(size: 19, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.white)

                                Text(diffMins <= 0 ? "Now" : "-\(manager.formattedCountdown)")
                                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Self.tabGreen.opacity(0.90)))
                                    .shadow(color: Self.tabGreen.opacity(0.4), radius: 5, y: 1)
                            }
                        }

                        // Digital Seconds Clock
                        Text(manager.currentSecondsString)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .shadow(color: Color.black.opacity(0.6), radius: 3)
                    }

                    Spacer()

                    // Right: Minimal Modern Qibla Compass Dial
                    HStack(spacing: 9) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.45))
                                .frame(width: 48, height: 48)
                                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.8))

                            // Cardinal Ticks
                            VStack {
                                Text("N")
                                    .font(.system(size: 6.5, weight: .black, design: .rounded))
                                    .foregroundStyle(Color.white)
                                Spacer()
                                Text("S")
                                    .font(.system(size: 6.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.4))
                            }
                            .frame(height: 42)

                            HStack {
                                Text("W")
                                    .font(.system(size: 6.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.4))
                                Spacer()
                                Text("E")
                                    .font(.system(size: 6.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.4))
                            }
                            .frame(width: 42)

                            // Needle towards Kaaba
                            ZStack {
                                VStack(spacing: 0) {
                                    Image(systemName: "location.north.fill")
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundStyle(Self.tabGreen)
                                        .shadow(color: Self.tabGreen.opacity(0.6), radius: 2)
                                    Rectangle()
                                        .fill(Self.tabGreen)
                                        .frame(width: 1.2, height: 14)
                                    Spacer()
                                }
                                .frame(height: 38)
                                .rotationEffect(.degrees(deg))
                                .animation(.spring(response: 0.45, dampingFraction: 0.75), value: deg)

                                Circle()
                                    .fill(Self.tabGreen)
                                    .frame(width: 4, height: 4)
                            }

                            // Kaaba marker
                            Text("🕋")
                                .font(.system(size: 7))
                                .offset(x: 16 * sin(deg * .pi / 180.0), y: -16 * cos(deg * .pi / 180.0))
                        }
                        .frame(width: 50, height: 50)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Qibla Direction")
                                .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(Self.tabGreen)

                            Text("\(Int(deg))° \(dirShort)")
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white)

                            Text(dirFull)
                                .font(.system(size: 7.5, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.80))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.45))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
                            )
                    )
                    .help("Qibla Direction: \(Int(deg))° clockwise from North towards the Kaaba in Mecca")
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 8)

                // C. Seamless Integrated Prayer Timeline Ribbon (NO BOXES / KOTAK-KOTAK)
                if let sched = schedule {
                    seamlessPrayerTimeline(sched: sched, isPixelTheme: false)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                }
            }
        }
        .frame(height: 242)
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
                .offset(y: -13)

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
                        .offset(y: geo.size.height / 2 - 13)
                }
                .frame(height: 4)
            }

            // 5 Prayer Stations (FAJR, DHUHR, ASR, MAGHRIB, ISHA)
            HStack(spacing: 4) {
                ForEach(Array(prayers.enumerated()), id: \.element.prayer.rawValue) { index, item in
                    let isNext = (item.prayer == upcoming?.prayer)
                    let isPassed = (item.date < Date() && !isNext)
                    let isHovered = (hoveredPrayer == item.prayer.rawValue)

                    VStack(spacing: 3) {
                        // 1. Station Node Beacon on Rail
                        ZStack {
                            if isNext {
                                Circle()
                                    .fill(Self.tabGreen)
                                    .frame(width: 13, height: 13)
                                    .shadow(color: Self.tabGreen.opacity(0.8), radius: 5)

                                Circle()
                                    .fill(Color.black)
                                    .frame(width: 5, height: 5)
                            } else if isPassed {
                                Circle()
                                    .fill(Self.tabGreen.opacity(0.35))
                                    .frame(width: 10, height: 10)

                                Image(systemName: "checkmark")
                                    .font(.system(size: 5.5, weight: .black))
                                    .foregroundStyle(Self.tabGreen)
                            } else {
                                Circle()
                                    .fill(Color.white.opacity(0.25))
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .frame(height: 15)

                        // 2. Status Label Tag
                        if isNext {
                            Text("NEXT")
                                .font(.system(size: 6.5, weight: .black, design: isPixelTheme ? .monospaced : .rounded))
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
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
                                .font(.system(size: 6.5, weight: .semibold, design: isPixelTheme ? .monospaced : .rounded))
                                .foregroundStyle(Color.white.opacity(0.35))
                        } else {
                            Text("UPCOMING")
                                .font(.system(size: 6.5, weight: .semibold, design: isPixelTheme ? .monospaced : .rounded))
                                .foregroundStyle(Color.white.opacity(0.40))
                        }

                        // 3. Prayer Name (Bold, Crisp)
                        Text(item.prayer.displayName.uppercased())
                            .font(.system(size: 9.5, weight: isNext ? .black : .bold, design: isPixelTheme ? .monospaced : .rounded))
                            .foregroundStyle(isNext ? Color.white : (isPassed ? Color.white.opacity(0.45) : Color.white.opacity(0.85)))

                        // 4. Formatted Time
                        Text(manager.formattedPrayerTime(item.date))
                            .font(.system(size: 12.5, weight: isNext ? .black : .bold, design: isPixelTheme ? .monospaced : .rounded))
                            .foregroundStyle(isNext ? Self.tabGreen : (isPassed ? Color.white.opacity(0.50) : Color.white))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        // Seamless glowing backdrop without boxed borders
                        Group {
                            if isHovered {
                                RoundedRectangle(cornerRadius: 8)
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
        .padding(.vertical, 4)
    }
}
