import SwiftUI
import CodeIslandCore

/// Unified living diorama prayer card with an integrated seamless timeline and functional Qibla compass.
/// Eliminates harsh outer bounding boxes in favor of a cohesive, minimalist, and cinematic panoramic dashboard.
/// Fully supports both Compact (120pt) and Panoramic (242pt) display modes, configurable in Settings.
public struct PrayerExpandedCardView: View {
    @ObservedObject public var manager: PrayerTimeManager

    @AppStorage(SettingsKey.islandUITheme) private var islandUITheme = SettingsDefaults.islandUITheme
    @AppStorage(SettingsKey.prayerCardDisplayMode) private var prayerCardDisplayMode = SettingsDefaults.prayerCardDisplayMode
    @State private var hoveredPrayer: String? = nil
    @State private var hoveredCompass = false

    private var isPixel: Bool {
        islandUITheme == IslandUITheme.pixel.rawValue
    }

    private var isPanoramic: Bool {
        prayerCardDisplayMode == PrayerCardDisplayMode.panoramic.rawValue
    }

    @AppStorage(SettingsKey.musicHUDProgressColor) private var musicHUDProgressColor = SettingsDefaults.musicHUDProgressColor
    @AppStorage(SettingsKey.syncThemeWithAlbumArt) private var syncThemeWithAlbumArt = SettingsDefaults.syncThemeWithAlbumArt
    @ObservedObject private var nowPlaying = NowPlayingManager.shared

    private var accentColor: Color {
        if (syncThemeWithAlbumArt || musicHUDProgressColor == "album") && nowPlaying.isPlaying && nowPlaying.artworkImage != nil {
            return nowPlaying.albumPalette.primary
        }
        let pc = MusicProgressColor(rawValue: musicHUDProgressColor) ?? .theme
        switch pc {
        case .album:
            if nowPlaying.isPlaying && nowPlaying.artworkImage != nil {
                return nowPlaying.albumPalette.primary
            }
            return isPixel ? Color(red: 0.0, green: 0.96, blue: 0.83) : .white
        case .theme, .cyan: return isPixel ? Color(red: 0.0, green: 0.96, blue: 0.83) : .white
        case .white: return .white
        case .pink: return Color(red: 1.0, green: 0.16, blue: 0.53)
        case .green: return Color(red: 0.12, green: 0.84, blue: 0.38)
        case .amber: return Color(red: 1.0, green: 0.72, blue: 0.20)
        }
    }

    public init(manager: PrayerTimeManager) {
        self.manager = manager
    }

    public var body: some View {
        Group {
            if isPixel {
                if isPanoramic {
                    panoramicPixelDashboard
                } else {
                    compactPixelDashboard
                }
            } else {
                if isPanoramic {
                    panoramicModernDashboard
                } else {
                    compactModernDashboard
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
    }

    // MARK: - ==========================================
    // MARK: 1. PIXEL RETRO - PANORAMIC (242pt)
    // MARK: - ==========================================

    private var panoramicPixelDashboard: some View {
        let upcoming = manager.upcomingPrayer
        let schedule = manager.todaySchedule
        let phase = manager.currentPhase
        let deg = manager.qiblaDegrees
        let dirShort = manager.qiblaCompassDirection

        return ZStack(alignment: .topLeading) {
            // Background: Living 8-bit Stepped Pixel Sky & Mosque Architecture
            DioramaSkyView(
                hour: manager.currentFractionalHour,
                hijriDay: manager.hijriDay,
                sunriseHour: manager.sunriseHour,
                sunsetHour: manager.sunsetHour,
                pixel: true,
                skyline: true,
                skylineHeight: 0.18
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Contrast Gradient Overlay for flawless legibility
            LinearGradient(
                colors: [
                    Color.black.opacity(0.15),
                    Color.black.opacity(0.40),
                    Color.black.opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .allowsHitTesting(false)

            // Foreground Unified Content
            VStack(spacing: 0) {
                // A. Top Floating Header Strip
                HStack(alignment: .center) {
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
                        .pixel16Bevel(raised: false, cornerRadius: 3.5, fillColor: Pixel16Palette.slot.opacity(0.70))

                        Text("\(manager.gregorianDateString.uppercased()) // \(manager.hijriDateString.uppercased())")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineLimit(1)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(accentColor)
                        Text(manager.cityName.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.95))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .pixel16Bevel(raised: false, cornerRadius: 3.5, fillColor: Pixel16Palette.slot.opacity(0.70))
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                Spacer(minLength: 6)

                // B. Hero Spotlight & Qibla Compass
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        if let next = upcoming {
                            let diffMins = manager.minutesUntilNextPrayer
                            HStack(spacing: 6) {
                                Text(next.prayer.displayName.uppercased())
                                    .font(.system(size: 14, weight: .black, design: .monospaced))
                                    .foregroundStyle(Color.white)

                                Text(manager.formattedPrayerTime(next.date))
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundStyle(accentColor)

                                Text(diffMins <= 0 ? "[NOW]" : "[-\(manager.formattedCountdown)]")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Pixel16Palette.textMuted)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .pixel16Bevel(raised: false, cornerRadius: 3, fillColor: Pixel16Palette.slot.opacity(0.70))
                            }
                        }

                        Text(manager.currentSecondsString)
                            .font(.system(size: 26, weight: .black, design: .monospaced))
                            .foregroundStyle(Color.white)
                            .shadow(color: Color.black.opacity(0.8), radius: 3)
                    }

                    Spacer()

                    // Right: Seamless Pixel Qibla Compass Dial
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.50))
                                .frame(width: 44, height: 44)

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

                            ZStack {
                                VStack(spacing: 0) {
                                    Image(systemName: "triangle.fill")
                                        .font(.system(size: 6, weight: .bold))
                                        .foregroundStyle(accentColor)
                                    Rectangle()
                                        .fill(accentColor)
                                        .frame(width: 1.2, height: 13)
                                    Spacer()
                                }
                                .frame(height: 36)
                                .rotationEffect(.degrees(deg))

                                Circle()
                                    .fill(accentColor)
                                    .frame(width: 4, height: 4)
                            }

                            Text("🕋")
                                .font(.system(size: 7))
                                .offset(x: 15 * sin(deg * .pi / 180.0), y: -15 * cos(deg * .pi / 180.0))
                        }
                        .frame(width: 46, height: 46)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("QIBLA")
                                .font(.system(size: 7, weight: .black, design: .monospaced))
                                .foregroundStyle(accentColor)

                            Text("\(Int(deg))° \(dirShort)")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundStyle(Color.white)

                            Text(manager.qiblaCompassDirectionFull.uppercased())
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.55))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .pixel16Bevel(
                        raised: false,
                        cornerRadius: 4,
                        fillColor: Pixel16Palette.slot.opacity(0.70)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

                Spacer(minLength: 4)

                // C. Timeline Ribbon
                if let sched = schedule {
                    timelineRibbon(sched: sched, isPixelTheme: true)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                }
            }
        }
        .frame(height: 242)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - ==========================================
    // MARK: 2. PIXEL RETRO - COMPACT RIBBON (120pt)
    // MARK: - ==========================================

    private var compactPixelDashboard: some View {
        let upcoming = manager.upcomingPrayer
        let schedule = manager.todaySchedule
        let phase = manager.currentPhase
        let deg = manager.qiblaDegrees
        let dirShort = manager.qiblaCompassDirection
        let dirFull = manager.qiblaCompassDirectionFull

        return ZStack(alignment: .topLeading) {
            // Background: Living 8-bit Stepped Pixel Sky & Mosque Skyline
            DioramaSkyView(
                hour: manager.currentFractionalHour,
                hijriDay: manager.hijriDay,
                sunriseHour: manager.sunriseHour,
                sunsetHour: manager.sunsetHour,
                pixel: true,
                skyline: true,
                skylineHeight: 0.28
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.48),
                    Color.black.opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .allowsHitTesting(false)

            // Foreground Content
            VStack(spacing: 6) {
                // Top Floating Header & Info Row
                HStack(alignment: .center, spacing: 7) {
                    HStack(spacing: 4) {
                        Image(systemName: phase.systemImage)
                            .font(.system(size: 8, weight: .bold))
                        Text(phase.displayName.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .pixel16Bevel(
                        raised: false,
                        cornerRadius: 3.5,
                        fillColor: Pixel16Palette.slot.opacity(0.70)
                    )

                    Text("\(manager.gregorianDateString.uppercased()) // \(manager.cityName.uppercased())")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    // Next Prayer Spotlight Badge (Seamless 16-Bit Telemetry - Zero Ugly Nested Stroke Boxes)
                    if let next = upcoming {
                        let diffMins = manager.minutesUntilNextPrayer
                        HStack(spacing: 5) {
                            Text(next.prayer.displayName.uppercased())
                                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                .foregroundStyle(Pixel16Palette.textWhite)

                            Text(manager.formattedPrayerTime(next.date))
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(accentColor)

                            Text(diffMins <= 0 ? "[NOW]" : "[-\(manager.formattedCountdown)]")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Pixel16Palette.textMuted)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .pixel16Bevel(
                            raised: false,
                            cornerRadius: 3.5,
                            fillColor: Pixel16Palette.slot.opacity(0.70)
                        )
                    }

                    // Compact Pixel Qibla Dial (Seamless 16-Bit Recessed Inset)
                    HStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(Pixel16Palette.slot.opacity(0.80))
                                .frame(width: 17, height: 17)

                            VStack(spacing: 0) {
                                Image(systemName: "triangle.fill")
                                    .font(.system(size: 4, weight: .bold))
                                    .foregroundStyle(accentColor)
                                Rectangle()
                                    .fill(accentColor)
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
                    .pixel16Bevel(
                        raised: false,
                        cornerRadius: 3.5,
                        fillColor: Pixel16Palette.slot.opacity(0.70)
                    )
                    .help("Qibla Direction: \(Int(deg))° \(dirFull) towards Kaaba")
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)

                Spacer(minLength: 2)

                // Timeline Ribbon
                if let sched = schedule {
                    timelineRibbon(sched: sched, isPixelTheme: true)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)
                }
            }
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - ==========================================
    // MARK: 3. MODERN CLEAN - PANORAMIC (242pt)
    // MARK: - ==========================================

    private var panoramicModernDashboard: some View {
        let upcoming = manager.upcomingPrayer
        let schedule = manager.todaySchedule
        let phase = manager.currentPhase
        let deg = manager.qiblaDegrees
        let dirShort = manager.qiblaCompassDirection

        return ZStack(alignment: .topLeading) {
            DioramaSkyView(
                hour: manager.currentFractionalHour,
                hijriDay: manager.hijriDay,
                sunriseHour: manager.sunriseHour,
                sunsetHour: manager.sunsetHour,
                pixel: false,
                skyline: true,
                skylineHeight: 0.18
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            LinearGradient(
                colors: [
                    Color.black.opacity(0.12),
                    Color.black.opacity(0.35),
                    Color.black.opacity(0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Header
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: phase.systemImage)
                                .font(.system(size: 9, weight: .semibold))
                            Text(phase.displayName)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Capsule().fill(Color.black.opacity(0.50)))

                        Text("\(manager.gregorianDateString) · \(manager.hijriDateString)")
                            .font(.system(size: 8.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineLimit(1)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(accentColor)
                        Text(manager.cityName)
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.95))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Capsule().fill(Color.black.opacity(0.50)))
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                Spacer(minLength: 6)

                // Hero Spotlight
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        if let next = upcoming {
                            let diffMins = manager.minutesUntilNextPrayer
                            HStack(spacing: 6) {
                                Text(next.prayer.displayName)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.white)

                                Text(manager.formattedPrayerTime(next.date))
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(accentColor)

                                Text(diffMins <= 0 ? "Now" : "-\(manager.formattedCountdown)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(accentColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2.5)
                                    .background(Capsule().fill(accentColor.opacity(0.20)))
                            }
                        }

                        Text(manager.currentSecondsString)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .shadow(color: Color.black.opacity(0.7), radius: 3)
                    }

                    Spacer()

                    // Modern Qibla Dial
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.50))
                                .frame(width: 44, height: 44)

                            VStack(spacing: 0) {
                                Image(systemName: "location.north.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(accentColor)
                                Rectangle()
                                    .fill(accentColor)
                                    .frame(width: 1.2, height: 14)
                                Spacer()
                            }
                            .frame(height: 38)
                            .rotationEffect(.degrees(deg))

                            Circle()
                                .fill(accentColor)
                                .frame(width: 4, height: 4)

                            Text("🕋")
                                .font(.system(size: 7.5))
                                .offset(x: 16 * sin(deg * .pi / 180.0), y: -16 * cos(deg * .pi / 180.0))
                        }
                        .frame(width: 46, height: 46)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Qibla")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(accentColor)

                            Text("\(Int(deg))° \(dirShort)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white)

                            Text(manager.qiblaCompassDirectionFull)
                                .font(.system(size: 7.5, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.50)))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

                Spacer(minLength: 4)

                if let sched = schedule {
                    timelineRibbon(sched: sched, isPixelTheme: false)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                }
            }
        }
        .frame(height: 242)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - ==========================================
    // MARK: 4. MODERN CLEAN - COMPACT RIBBON (120pt)
    // MARK: - ==========================================

    private var compactModernDashboard: some View {
        let upcoming = manager.upcomingPrayer
        let schedule = manager.todaySchedule
        let phase = manager.currentPhase
        let deg = manager.qiblaDegrees
        let dirShort = manager.qiblaCompassDirection
        let dirFull = manager.qiblaCompassDirectionFull

        return ZStack(alignment: .topLeading) {
            DioramaSkyView(
                hour: manager.currentFractionalHour,
                hijriDay: manager.hijriDay,
                sunriseHour: manager.sunriseHour,
                sunsetHour: manager.sunsetHour,
                pixel: false,
                skyline: true,
                skylineHeight: 0.28
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.48),
                    Color.black.opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .allowsHitTesting(false)

            VStack(spacing: 6) {
                // Top Row
                HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: phase.systemImage)
                            .font(.system(size: 8.5, weight: .bold))
                        Text(phase.displayName)
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.50)))

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
                                .foregroundStyle(accentColor)

                            Text(diffMins <= 0 ? "Now" : "-\(manager.formattedCountdown)")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(accentColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(accentColor.opacity(0.20)))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.50)))
                    }

                    // Compact Modern Qibla Dial
                    HStack(spacing: 4.5) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.50))
                                .frame(width: 18, height: 18)

                            VStack(spacing: 0) {
                                Image(systemName: "location.north.fill")
                                    .font(.system(size: 4.5, weight: .bold))
                                    .foregroundStyle(accentColor)
                                Rectangle()
                                    .fill(accentColor)
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
                    .background(Capsule().fill(Color.black.opacity(0.50)))
                    .help("Qibla Direction: \(Int(deg))° \(dirFull) towards Kaaba")
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)

                Spacer(minLength: 2)

                if let sched = schedule {
                    timelineRibbon(sched: sched, isPixelTheme: false)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)
                }
            }
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - ==========================================
    // MARK: 5. SEAMLESS TIMELINE RIBBON
    // MARK: - ==========================================

    @ViewBuilder
    private func timelineRibbon(sched: DailyPrayerSchedule, isPixelTheme: Bool) -> some View {
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
                        .fill(accentColor.opacity(0.85))
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
                                    .fill(accentColor)
                                    .frame(width: 10, height: 10)
                                    .shadow(color: accentColor.opacity(0.8), radius: 4)

                                Circle()
                                    .fill(Color.black)
                                    .frame(width: 4, height: 4)
                            } else if isPassed {
                                Circle()
                                    .fill(accentColor.opacity(0.35))
                                    .frame(width: 8, height: 8)

                                Image(systemName: "checkmark")
                                    .font(.system(size: 4.5, weight: .black))
                                    .foregroundStyle(accentColor)
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
                                            Rectangle().fill(accentColor)
                                        } else {
                                            Capsule().fill(accentColor)
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
                            .foregroundStyle(isNext ? accentColor : (isPassed ? Color.white.opacity(0.50) : Color.white))
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
