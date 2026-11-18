import SwiftUI
import MorrowCore

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

    private var pixelAccent: Color {
        _ = syncThemeWithAlbumArt
        _ = nowPlaying.albumPalette
        return AppColorTheme.readableOnDark(
            AppColorTheme.accent(for: musicHUDProgressColor, isModern: false)
        )
    }

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

    /// `HH:mm:ss` in the city's zone at a given instant.
    static func clockText(at date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
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

                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(Self.clockText(at: context.date, timeZone: manager.timeZone))
                                .font(.system(size: 26, weight: .black, design: .monospaced))
                                .foregroundStyle(Color.white)
                                .shadow(color: Color.black.opacity(0.8), radius: 3)
                        }
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
    // MARK: 2. PIXEL 32-BIT - UNIFIED HORIZON ARC
    // MARK: - ==========================================

    private var compactPixelDashboard: some View {
        unifiedHorizonDashboard(isPixelTheme: true)
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

                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(Self.clockText(at: context.date, timeZone: manager.timeZone))
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white)
                                .shadow(color: Color.black.opacity(0.7), radius: 3)
                        }
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
    // MARK: 4. MODERN CLEAN - UNIFIED HORIZON ARC
    // MARK: - ==========================================

    private var compactModernDashboard: some View {
        unifiedHorizonDashboard(isPixelTheme: false)
    }

    @ViewBuilder
    private func unifiedHorizonDashboard(isPixelTheme: Bool) -> some View {
        let upcoming = manager.upcomingPrayer
        let schedule = manager.todaySchedule
        let activeAccent = isPixelTheme ? pixelAccent : Color(red: 0.35, green: 0.78, blue: 0.98)
        let prayers = schedule?.fivePrayers ?? []

        ZStack {
            // Subtle phase-tinted radial ambient glow fading seamlessly into pure notch black
            RadialGradient(
                colors: [
                    activeAccent.opacity(isPixelTheme ? 0.14 : 0.16),
                    activeAccent.opacity(0.03),
                    Color.clear
                ],
                center: UnitPoint(x: 0.5, y: 0.12),
                startRadius: 10,
                endRadius: 240
            )
            .allowsHitTesting(false)

            VStack(spacing: 4) {
                // Subtle top corner context (single focus canvas, no side dock)
                HStack {
                    if isPixelTheme {
                        PixelText(
                            text: "PRAYER · \(manager.cityName.uppercased())",
                            color: Color.white.opacity(0.55),
                            pixelSize: 1.1
                        )
                    } else {
                        Text("Prayer · \(manager.cityName)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.52))
                    }

                    Spacer()

                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        let hm = Self.shortClockText(at: context.date, timeZone: manager.timeZone)
                        if isPixelTheme {
                            PixelText(text: hm, color: Color.white.opacity(0.68), pixelSize: 1.15)
                        } else {
                            Text(hm)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Color.white.opacity(0.58))
                        }
                    }
                }
                .padding(.horizontal, 6)

                // Sun-Arc Canvas + Centered Next Prayer Hero
                ZStack {
                    horizonSunArcCanvas(
                        prayers: prayers,
                        upcoming: upcoming,
                        isPixelTheme: isPixelTheme,
                        activeAccent: activeAccent
                    )
                    .frame(height: 82)

                    if let next = upcoming {
                        let diffMins = manager.minutesUntilNextPrayer
                        let countdown = diffMins <= 0 ? (isPixelTheme ? "NOW" : "Now") : "in \(manager.formattedCountdown)"
                        let heroTitle = "\(next.prayer.displayName) · \(manager.formattedPrayerTime(next.date))"

                        VStack(spacing: 4) {
                            Spacer(minLength: 26)
                            if isPixelTheme {
                                PixelText(text: heroTitle.uppercased(), color: .white, pixelSize: 1.85)
                                PixelText(text: countdown.uppercased(), color: activeAccent, pixelSize: 1.15)
                            } else {
                                Text(heroTitle)
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .shadow(color: Color.black.opacity(0.85), radius: 6, y: 1)

                                Text(countdown)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(activeAccent)
                            }
                        }
                    }
                }

                // Bottom 5-Prayer Baseline
                if !prayers.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(prayers, id: \.prayer) { item in
                            let isNext = item.prayer == upcoming?.prayer
                            let timeText = manager.formattedPrayerTime(item.date)
                            VStack(spacing: 2) {
                                if isPixelTheme {
                                    PixelText(
                                        text: String(item.prayer.displayName.prefix(3)).uppercased(),
                                        color: isNext ? activeAccent : Color.white.opacity(0.50),
                                        pixelSize: 1.1
                                    )
                                    PixelText(
                                        text: timeText,
                                        color: isNext ? .white : Color.white.opacity(0.45),
                                        pixelSize: 1.05
                                    )
                                } else {
                                    Text("\(item.prayer.displayName) \(timeText)")
                                        .font(.system(size: 10.5, weight: isNext ? .bold : .medium, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(isNext ? .white : Color.white.opacity(0.50))
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(height: 150)
    }

    private static func shortClockText(at date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private func horizonSunArcCanvas(
        prayers: [(prayer: PrayerType, date: Date)],
        upcoming: (prayer: PrayerType, date: Date)?,
        isPixelTheme: Bool,
        activeAccent: Color
    ) -> some View {
        let minH = fractionalHour(from: prayers.first?.date) ?? max(4.0, manager.sunriseHour - 1.2)
        let maxH = fractionalHour(from: prayers.last?.date) ?? max(minH + 10.0, manager.sunsetHour + 1.2)
        let span = max(1.0, maxH - minH)
        let prog = max(0.0, min(1.0, (manager.currentFractionalHour - minH) / span))

        return Canvas { ctx, size in
            let padX: CGFloat = 22
            let baseY = size.height - 8
            let peakY: CGFloat = 12
            let usableW = max(1, size.width - padX * 2)

            func pointAt(_ t: Double) -> CGPoint {
                let x = padX + CGFloat(t) * usableW
                let y = baseY - CGFloat(sin(t * .pi)) * (baseY - peakY)
                return CGPoint(x: x, y: y)
            }

            // Horizon baseline
            var baseLine = Path()
            baseLine.move(to: CGPoint(x: 10, y: baseY))
            baseLine.addLine(to: CGPoint(x: size.width - 10, y: baseY))
            ctx.stroke(baseLine, with: .color(Color.white.opacity(isPixelTheme ? 0.16 : 0.12)), lineWidth: 1)

            if isPixelTheme {
                // Continuous 2pt stepped pixel curve (no gaps or sparse blocks)
                let step: CGFloat = 2.0
                var prevGy: CGFloat? = nil
                var x = padX
                while x <= size.width - padX {
                    let t = Double((x - padX) / usableW)
                    let rawY = baseY - CGFloat(sin(t * .pi)) * (baseY - peakY)
                    let gy = (rawY / step).rounded() * step
                    let active = t <= prog
                    let col = active ? activeAccent : Color.white.opacity(0.16)

                    if let prev = prevGy, abs(gy - prev) > step {
                        let dir: CGFloat = gy > prev ? step : -step
                        var yy = prev + dir
                        while (dir > 0 && yy < gy) || (dir < 0 && yy > gy) {
                            ctx.fill(Path(CGRect(x: x, y: yy, width: step, height: step)), with: .color(col))
                            yy += dir
                        }
                    }
                    ctx.fill(Path(CGRect(x: x, y: gy, width: 2.2, height: 2.2)), with: .color(col))
                    prevGy = gy
                    x += step
                }

                // Prayer milestone nodes
                for item in prayers {
                    if let h = fractionalHour(from: item.date) {
                        let t = max(0.0, min(1.0, (h - minH) / span))
                        let p = pointAt(t)
                        let nx = (p.x / 2).rounded() * 2
                        let ny = (p.y / 2).rounded() * 2
                        let isNext = item.prayer == upcoming?.prayer
                        ctx.fill(
                            Path(CGRect(x: nx - 2, y: ny - 2, width: 4.5, height: 4.5)),
                            with: .color(isNext ? activeAccent : Color.white.opacity(0.48))
                        )
                    }
                }

                // 32-bit circular stepped pixel sun sprite
                let sun = pointAt(prog)
                let sx = (sun.x / 2).rounded() * 2
                let sy = (sun.y / 2).rounded() * 2
                ctx.fill(Path(CGRect(x: sx - 5, y: sy - 3, width: 10, height: 6)), with: .color(Color.yellow.opacity(0.22)))
                ctx.fill(Path(CGRect(x: sx - 3, y: sy - 5, width: 6, height: 10)), with: .color(Color.yellow.opacity(0.22)))
                ctx.fill(Path(CGRect(x: sx - 3, y: sy - 1.5, width: 6, height: 3)), with: .color(Color(red: 0.98, green: 0.75, blue: 0.14)))
                ctx.fill(Path(CGRect(x: sx - 1.5, y: sy - 3, width: 3, height: 6)), with: .color(Color(red: 0.98, green: 0.75, blue: 0.14)))
                ctx.fill(Path(CGRect(x: sx - 1.5, y: sy - 1.5, width: 3, height: 3)), with: .color(.white))
            } else {
                // Smooth Modern Bezier-sampled curve
                let segs = 64
                var pastPath = Path()
                var futurePath = Path()
                var startedPast = false
                var startedFuture = false
                for i in 0...segs {
                    let t = Double(i) / Double(segs)
                    let p = pointAt(t)
                    if t <= prog {
                        if !startedPast { pastPath.move(to: p); startedPast = true } else { pastPath.addLine(to: p) }
                    }
                    if t >= prog {
                        if !startedFuture { futurePath.move(to: p); startedFuture = true } else { futurePath.addLine(to: p) }
                    }
                }
                if startedPast {
                    pastPath.addLine(to: pointAt(prog))
                }

                ctx.stroke(futurePath, with: .color(Color.white.opacity(0.16)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                ctx.stroke(
                    pastPath,
                    with: .linearGradient(
                        Gradient(colors: [Color(red: 0.22, green: 0.74, blue: 0.97), Color(red: 0.23, green: 0.51, blue: 0.96)]),
                        startPoint: CGPoint(x: padX, y: baseY),
                        endPoint: CGPoint(x: size.width - padX, y: peakY)
                    ),
                    style: StrokeStyle(lineWidth: 2.8, lineCap: .round)
                )

                for item in prayers {
                    if let h = fractionalHour(from: item.date) {
                        let t = max(0.0, min(1.0, (h - minH) / span))
                        let p = pointAt(t)
                        let isNext = item.prayer == upcoming?.prayer
                        let r: CGFloat = isNext ? 3.5 : 2.3
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                            with: .color(isNext ? .white : Color.white.opacity(0.50))
                        )
                    }
                }

                // Luminous sun orb
                let sun = pointAt(prog)
                let glowRect = CGRect(x: sun.x - 11, y: sun.y - 11, width: 22, height: 22)
                ctx.fill(
                    Path(ellipseIn: glowRect),
                    with: .radialGradient(
                        Gradient(colors: [.white, Color(red: 0.99, green: 0.90, blue: 0.54).opacity(0.85), Color.clear]),
                        center: sun,
                        startRadius: 1,
                        endRadius: 11
                    )
                )
                ctx.fill(Path(ellipseIn: CGRect(x: sun.x - 4, y: sun.y - 4, width: 8, height: 8)), with: .color(.white))
            }
        }
    }

    private func fractionalHour(from date: Date?) -> Double? {
        guard let date else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = manager.timeZone
        let c = cal.dateComponents([.hour, .minute], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60.0
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
