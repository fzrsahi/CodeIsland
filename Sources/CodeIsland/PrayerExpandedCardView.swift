import SwiftUI
import CodeIslandCore

/// Fully redesigned living diorama clock, interactive prayer schedule ribbon, and functional Qibla compass dashboard.
/// Features authentic 8-bit stepped pixel art and modern clean themes with strict anti-slop visual craft.
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
            // Header Bar: Indonesian Pixel Title & Active City Badge
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Self.tabGreen)
                    PixelText(
                        text: "JADWAL SALAT & ARAH KIBLAT",
                        color: Self.tabGreen,
                        pixelSize: 1.15
                    )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Rectangle()
                        .fill(Self.tabGreen.opacity(0.12))
                        .overlay(Rectangle().stroke(Self.tabGreen.opacity(0.4), lineWidth: 0.8))
                )

                Spacer()

                // Location / City Tag
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Self.tabGreen)
                    Text(manager.cityName.uppercased())
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.9))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .overlay(Rectangle().stroke(Color.white.opacity(0.15), lineWidth: 0.8))
                )
                .help("Lokasi aktif untuk perhitungan jadwal salat dan koordinat arah kiblat")
            }

            // 1. Pixel Living Diorama Hero Spotlight Card (~154pt)
            ZStack(alignment: .topLeading) {
                // Authentic 8-bit dithered sky & stepped mosque canvas
                DioramaSkyView(
                    hour: manager.currentFractionalHour,
                    hijriDay: manager.hijriDay,
                    sunriseHour: manager.sunriseHour,
                    sunsetHour: manager.sunsetHour,
                    pixel: true,
                    skyline: true,
                    skylineHeight: 0.16
                )
                .clipShape(Rectangle())
                .overlay(
                    Rectangle()
                        .stroke(Self.tabGreen.opacity(0.45), lineWidth: 1)
                )

                // Hero Content Overlay: Spotlight (Left) + Functional Qibla Compass (Right)
                HStack(alignment: .top, spacing: 14) {
                    // Left Hero Column: Active Status, Next Prayer, Big Countdown, and Clock
                    VStack(alignment: .leading, spacing: 3) {
                        // Phase Tag
                        HStack(spacing: 5) {
                            Image(systemName: phase.systemImage)
                                .font(.system(size: 9.5, weight: .bold))
                            Text("FASE: \(phase.displayName.uppercased())")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Rectangle()
                                .fill(Color.black.opacity(0.75))
                                .overlay(Rectangle().stroke(Color.white.opacity(0.2), lineWidth: 0.8))
                        )

                        Spacer(minLength: 2)

                        // Next Prayer Big Announcement & Indonesian Countdown
                        if let next = upcoming {
                            let diffMins = manager.minutesUntilNextPrayer
                            VStack(alignment: .leading, spacing: 2) {
                                Text(diffMins <= 0 ? "WAKTU SALAT TELAH TIBA" : "MENUJU SALAT BERIKUTNYA")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.white.opacity(0.75))

                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(next.prayer.displayName.uppercased()) \(manager.formattedPrayerTime(next.date))")
                                        .font(.system(size: 16, weight: .black, design: .monospaced))
                                        .foregroundStyle(Color.white)

                                    Text(diffMins <= 0 ? "[SEKARANG]" : "[-\(manager.formattedCountdown)]")
                                        .font(.system(size: 10.5, weight: .black, design: .monospaced))
                                        .foregroundStyle(Color.black)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2.5)
                                        .background(
                                            Rectangle()
                                                .fill(Self.tabGreen)
                                        )
                                        .shadow(color: Self.tabGreen.opacity(0.6), radius: 4)
                                }
                            }
                        }

                        // Big Retro Seconds Clock
                        Text(manager.currentSecondsString)
                            .font(.system(size: 28, weight: .black, design: .monospaced))
                            .foregroundStyle(Color.white)
                            .shadow(color: Color.black.opacity(0.9), radius: 3)

                        Spacer(minLength: 2)

                        // Date in Indonesian
                        Text("📅 \(manager.gregorianDateString.uppercased()) // \(manager.hijriDateString.uppercased())")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.90))
                            .lineLimit(1)
                    }

                    Spacer()

                    // Right Hero Column: Authentic Functional Qibla Compass Card
                    qiblaCompassPixelCard
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(height: 154)

            // 2. Horizontal Stepped Prayer Ribbon (Timeline Stepper)
            if let sched = schedule {
                prayerTimelineRibbon(sched: sched, isPixelTheme: true)
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
            // Header Bar: Indonesian Modern Title & Location Pill
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Self.tabGreen)
                    Text("Jadwal Salat & Arah Kiblat")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                }

                Spacer()

                // Location Tag
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Self.tabGreen)
                    Text(manager.cityName)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.9))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.6))
                )
                .help("Lokasi aktif perhitungan waktu salat")
            }

            // 1. Modern Living Diorama Hero Spotlight Card (~154pt)
            ZStack(alignment: .topLeading) {
                // Smooth gradient & silhouette sky canvas
                DioramaSkyView(
                    hour: manager.currentFractionalHour,
                    hijriDay: manager.hijriDay,
                    sunriseHour: manager.sunriseHour,
                    sunsetHour: manager.sunsetHour,
                    pixel: false,
                    skyline: true,
                    skylineHeight: 0.16
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

                HStack(alignment: .top, spacing: 14) {
                    // Left Hero Column: Next Prayer Spotlight & Indonesian Countdown
                    VStack(alignment: .leading, spacing: 3) {
                        // Phase Capsule
                        HStack(spacing: 5) {
                            Image(systemName: phase.systemImage)
                                .font(.system(size: 10, weight: .bold))
                            Text(phase.displayName)
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.55))
                                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.6))
                        )

                        Spacer(minLength: 2)

                        if let next = upcoming {
                            let diffMins = manager.minutesUntilNextPrayer
                            VStack(alignment: .leading, spacing: 2) {
                                Text(diffMins <= 0 ? "Waktu Salat Telah Tiba" : "Menuju Waktu Salat")
                                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.75))

                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(next.prayer.displayName) \(manager.formattedPrayerTime(next.date))")
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color.white)

                                    Text(diffMins <= 0 ? "Sekarang" : "-\(manager.formattedCountdown)")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3.5)
                                        .background(
                                            Capsule()
                                                .fill(Self.tabGreen.opacity(0.85))
                                        )
                                        .shadow(color: Self.tabGreen.opacity(0.4), radius: 5, y: 1)
                                }
                            }
                        }

                        // Big Digital Clock
                        Text(manager.currentSecondsString)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .shadow(color: Color.black.opacity(0.6), radius: 3)

                        Spacer(minLength: 2)

                        // Indonesian Date
                        Text("\(manager.gregorianDateString) · \(manager.hijriDateString)")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.92))
                            .lineLimit(1)
                    }

                    Spacer()

                    // Right Hero Column: Modern Functional Qibla Compass Card
                    qiblaCompassModernCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .frame(height: 154)

            // 2. Horizontal Stepped Prayer Ribbon (Timeline Stepper)
            if let sched = schedule {
                prayerTimelineRibbon(sched: sched, isPixelTheme: false)
            }
        }
    }

    // MARK: - ==========================================
    // MARK: 3. FUNCTIONAL QIBLA COMPASS CARDS
    // MARK: - ==========================================

    /// Functional Pixel Retro Qibla Compass Card
    private var qiblaCompassPixelCard: some View {
        let deg = manager.qiblaDegrees
        let dirShort = manager.qiblaCompassDirection
        let dirFull = manager.qiblaCompassDirectionFull

        return VStack(spacing: 6) {
            Text("ARAH KIBLAT")
                .font(.system(size: 7.5, weight: .black, design: .monospaced))
                .foregroundStyle(Self.tabGreen)

            // Functional Rotating Compass Dial
            ZStack {
                // Dial Border
                Circle()
                    .stroke(Self.tabGreen.opacity(0.45), lineWidth: 1)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.black.opacity(0.65)))

                // Cardinal Points (U = Utara/North, T = Timur/East, S = Selatan/South, B = Barat/West)
                VStack {
                    Text("U")
                        .font(.system(size: 6.5, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.white)
                    Spacer()
                    Text("S")
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .frame(height: 48)

                HStack {
                    Text("B")
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.45))
                    Spacer()
                    Text("T")
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .frame(width: 48)

                // Dynamic Kaaba Bearing Needle
                ZStack {
                    // Needle line pointing to Kaaba angle
                    VStack(spacing: 0) {
                        // Arrowhead pointing towards Kaaba bearing
                        Image(systemName: "triangle.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Self.tabGreen)

                        Rectangle()
                            .fill(Self.tabGreen)
                            .frame(width: 1.5, height: 16)

                        Spacer()
                    }
                    .frame(height: 44)
                    .rotationEffect(.degrees(deg))
                    .animation(.spring(response: 0.45, dampingFraction: 0.75), value: deg)

                    // Center pivot point
                    Circle()
                        .fill(Self.tabGreen)
                        .frame(width: 5, height: 5)
                        .overlay(Circle().stroke(Color.black, lineWidth: 1))
                }

                // Kaaba Icon badge
                Text("🕋")
                    .font(.system(size: 8))
                    .offset(x: 18 * sin(deg * .pi / 180.0), y: -18 * cos(deg * .pi / 180.0))
            }
            .frame(width: 54, height: 54)

            // Degree Readout & Direction
            VStack(spacing: 1) {
                Text("\(Int(deg))° \(dirShort)")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(Self.tabGreen)

                Text(dirFull)
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .lineLimit(1)

                Text("Arahkan dari Utara")
                    .font(.system(size: 6.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(Color.black.opacity(0.70))
                .overlay(Rectangle().stroke(Self.tabGreen.opacity(0.4), lineWidth: 0.8))
        )
        .help("Arah Kiblat: \(Int(deg))° searah jarum jam dari arah Utara menuju Ka'bah di Mekkah (21.42° U, 39.83° T)")
    }

    /// Functional Modern Clean Qibla Compass Card
    private var qiblaCompassModernCard: some View {
        let deg = manager.qiblaDegrees
        let dirShort = manager.qiblaCompassDirection
        let dirFull = manager.qiblaCompassDirectionFull

        return VStack(spacing: 6) {
            Text("Arah Kiblat")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Self.tabGreen)

            // Modern Rotating Compass Dial
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: 56, height: 56)
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.8))

                // Cardinal Ticks: U, T, S, B
                VStack {
                    Text("U")
                        .font(.system(size: 7, weight: .black, design: .rounded))
                        .foregroundStyle(Color.white)
                    Spacer()
                    Text("S")
                        .font(.system(size: 7, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .frame(height: 50)

                HStack {
                    Text("B")
                        .font(.system(size: 7, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.4))
                    Spacer()
                    Text("T")
                        .font(.system(size: 7, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .frame(width: 50)

                // Dynamic Needle towards Kaaba
                ZStack {
                    VStack(spacing: 0) {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Self.tabGreen)
                            .shadow(color: Self.tabGreen.opacity(0.6), radius: 3)
                        Rectangle()
                            .fill(Self.tabGreen)
                            .frame(width: 1.5, height: 16)
                        Spacer()
                    }
                    .frame(height: 46)
                    .rotationEffect(.degrees(deg))
                    .animation(.spring(response: 0.45, dampingFraction: 0.75), value: deg)

                    Circle()
                        .fill(Self.tabGreen)
                        .frame(width: 5, height: 5)
                }

                // Kaaba marker
                Text("🕋")
                    .font(.system(size: 8))
                    .offset(x: 20 * sin(deg * .pi / 180.0), y: -20 * cos(deg * .pi / 180.0))
            }
            .frame(width: 58, height: 58)

            // Degree & Direction Text
            VStack(spacing: 1) {
                Text("\(Int(deg))° \(dirShort)")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Self.tabGreen)

                Text(dirFull)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)

                Text("Arahkan dari Utara")
                    .font(.system(size: 7, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.50))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
                )
        )
        .help("Arah Kiblat: \(Int(deg))° searah jarum jam dari arah Utara menuju Ka'bah di Mekkah")
    }

    // MARK: - ==========================================
    // MARK: 4. HORIZONTAL STEPPED PRAYER RIBBON
    // MARK: - ==========================================

    /// Elegant continuous horizontal timeline stepper connecting all 5 prayer times.
    /// Replaces the old grid of 5 detached square cards.
    @ViewBuilder
    private func prayerTimelineRibbon(sched: DailyPrayerSchedule, isPixelTheme: Bool) -> some View {
        let upcoming = manager.upcomingPrayer
        let prayers = sched.fivePrayers
        let nextIndex = prayers.firstIndex { $0.prayer == upcoming?.prayer } ?? -1

        VStack(alignment: .leading, spacing: 6) {
            // Section Title
            HStack(spacing: 5) {
                Text("LINIMASA SALAT HARI INI")
                    .font(.system(size: 8, weight: .bold, design: isPixelTheme ? .monospaced : .rounded))
                    .foregroundStyle(Color.white.opacity(0.65))

                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
            }

            // Horizontal Ribbon Stepper Track
            ZStack(alignment: .leading) {
                // Background Track Line
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: isPixelTheme ? 2 : 2.5)
                    .padding(.horizontal, 32)
                    .offset(y: -14)

                // Passed Progress Line
                if nextIndex > 0 {
                    GeometryReader { geo in
                        let totalSteps = CGFloat(prayers.count - 1)
                        let activeRatio = CGFloat(nextIndex) / totalSteps
                        let trackWidth = geo.size.width - 64
                        Rectangle()
                            .fill(Self.tabGreen)
                            .frame(width: max(0, trackWidth * activeRatio), height: isPixelTheme ? 2 : 2.5)
                            .padding(.leading, 32)
                            .offset(y: geo.size.height / 2 - 14)
                    }
                    .frame(height: 4)
                }

                // 5 Prayer Nodes in Horizontal Stepper
                HStack(spacing: 6) {
                    ForEach(Array(prayers.enumerated()), id: \.element.prayer.rawValue) { index, item in
                        let isNext = (item.prayer == upcoming?.prayer)
                        let isPassed = (item.date < Date() && !isNext)
                        let isHovered = (hoveredPrayer == item.prayer.rawValue)

                        VStack(spacing: 4) {
                            // Status Node Circle / Tag on Timeline
                            ZStack {
                                if isNext {
                                    Circle()
                                        .fill(Self.tabGreen)
                                        .frame(width: 14, height: 14)
                                        .shadow(color: Self.tabGreen.opacity(0.8), radius: 4)

                                    Circle()
                                        .fill(Color.black)
                                        .frame(width: 6, height: 6)
                                } else if isPassed {
                                    Circle()
                                        .fill(Self.tabGreen.opacity(0.35))
                                        .frame(width: 12, height: 12)

                                    Image(systemName: "checkmark")
                                        .font(.system(size: 6.5, weight: .black))
                                        .foregroundStyle(Self.tabGreen)
                                } else {
                                    Circle()
                                        .fill(Color.white.opacity(0.20))
                                        .frame(width: 10, height: 10)
                                }
                            }
                            .frame(height: 16)

                            // Node Card Details (Name + Time + Badge)
                            VStack(spacing: 2) {
                                // Status Pill
                                if isNext {
                                    Text("BERIKUTNYA")
                                        .font(.system(size: 6.5, weight: .black, design: isPixelTheme ? .monospaced : .rounded))
                                        .foregroundStyle(Color.black)
                                        .padding(.horizontal, 4)
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
                                    Text("SELESAI")
                                        .font(.system(size: 6.5, weight: .bold, design: isPixelTheme ? .monospaced : .rounded))
                                        .foregroundStyle(Color.white.opacity(0.40))
                                } else {
                                    Text("AKAN DATANG")
                                        .font(.system(size: 6.5, weight: .semibold, design: isPixelTheme ? .monospaced : .rounded))
                                        .foregroundStyle(Color.white.opacity(0.45))
                                }

                                // Prayer Name in Indonesian
                                Text(item.prayer.displayName.uppercased())
                                    .font(.system(size: 9.5, weight: isNext ? .black : .bold, design: isPixelTheme ? .monospaced : .rounded))
                                    .foregroundStyle(isNext ? Color.white : (isPassed ? Color.white.opacity(0.45) : Color.white.opacity(0.85)))

                                // Formatted Time
                                Text(manager.formattedPrayerTime(item.date))
                                    .font(.system(size: 13, weight: isNext ? .black : .bold, design: isPixelTheme ? .monospaced : .rounded))
                                    .foregroundStyle(isNext ? Self.tabGreen : (isPassed ? Color.white.opacity(0.55) : Color.white))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 4)
                            .background(ribbonCardBackground(isNext: isNext, isHovered: isHovered, isPixelTheme: isPixelTheme))
                            .shadow(color: isNext ? Self.tabGreen.opacity(0.35) : Color.clear, radius: 5)
                            .scaleEffect(isHovered ? 1.02 : 1.0)
                            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
                        }
                        .contentShape(Rectangle())
                        .onHover { hoveredPrayer = $0 ? item.prayer.rawValue : nil }
                        .help("Waktu salat \(item.prayer.displayName): \(manager.formattedPrayerTime(item.date))")
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func ribbonCardBackground(isNext: Bool, isHovered: Bool, isPixelTheme: Bool) -> some View {
        if isPixelTheme {
            let fillColor = isNext ? Self.tabGreen.opacity(0.18) : (isHovered ? Color.white.opacity(0.08) : Color.black.opacity(0.35))
            let strokeColor = isNext ? Self.tabGreen : (isHovered ? Color.white.opacity(0.25) : Color.white.opacity(0.08))
            Rectangle()
                .fill(fillColor)
                .overlay(
                    Rectangle()
                        .stroke(strokeColor, lineWidth: isNext ? 1.2 : 0.8)
                )
        } else {
            let fillColor = isNext ? Self.tabGreen.opacity(0.15) : (isHovered ? Color.white.opacity(0.10) : Color.white.opacity(0.05))
            let strokeColor = isNext ? Self.tabGreen.opacity(0.8) : (isHovered ? Color.white.opacity(0.25) : Color.white.opacity(0.08))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(fillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(strokeColor, lineWidth: isNext ? 1.2 : 0.6)
                )
        }
    }
}
