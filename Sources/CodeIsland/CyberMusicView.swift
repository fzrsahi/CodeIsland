import SwiftUI
import CodeIslandCore
import AppKit

// MARK: - Retro Spectrum Dynamic Palette (Color Theme as Base, Harmonious Gradient on Top)

struct RetroSpectrumPalette: Equatable, Sendable {
    var base: Color
    var mid: Color
    var peak: Color

    @MainActor
    static func forThemeKey(_ key: String) -> RetroSpectrumPalette {
        let syncAlbum = UserDefaults.standard.bool(forKey: SettingsKey.syncThemeWithAlbumArt)
        if (syncAlbum || key == MusicProgressColor.album.rawValue) && NowPlayingManager.shared.isPlaying && NowPlayingManager.shared.artworkImage != nil {
            return NowPlayingManager.shared.albumPalette.spectrum
        }
        let pc = MusicProgressColor(rawValue: key) ?? .theme
        return forProgressColor(pc)
    }

    @MainActor
    static func forProgressColor(_ pc: MusicProgressColor) -> RetroSpectrumPalette {
        switch pc {
        case .album:
            if NowPlayingManager.shared.isPlaying && NowPlayingManager.shared.artworkImage != nil {
                return NowPlayingManager.shared.albumPalette.spectrum
            }
            return forProgressColor(.cyan)
        case .pink:
            // Base = Neon Pink/Merah, Mid = Warm Sunset Orange, Peak = Electric Yellow
            return RetroSpectrumPalette(
                base: Color(red: 1.0, green: 0.16, blue: 0.53),
                mid: Color(red: 1.0, green: 0.58, blue: 0.12),
                peak: Color(red: 1.0, green: 0.88, blue: 0.20)
            )
        case .amber:
            // Base = Sunset Amber, Mid = Neon Coral, Peak = Hot Magenta
            return RetroSpectrumPalette(
                base: Color(red: 1.0, green: 0.72, blue: 0.20),
                mid: Color(red: 1.0, green: 0.38, blue: 0.28),
                peak: Color(red: 1.0, green: 0.16, blue: 0.53)
            )
        case .green:
            // Base = Matrix Green, Mid = Neon Lime, Peak = Electric Cyan
            return RetroSpectrumPalette(
                base: Color(red: 0.12, green: 0.84, blue: 0.38),
                mid: Color(red: 0.76, green: 0.94, blue: 0.16),
                peak: Color(red: 0.0, green: 0.96, blue: 0.83)
            )
        case .white:
            // Base = Pure White, Mid = Ice Aqua, Peak = Electric Cyan
            return RetroSpectrumPalette(
                base: .white,
                mid: Color(red: 0.55, green: 0.92, blue: 1.0),
                peak: Color(red: 0.0, green: 0.96, blue: 0.83)
            )
        case .cyan, .theme:
            // Base = Electric Cyan, Mid = Deep Aqua, Peak = Ice White
            return RetroSpectrumPalette(
                base: Color(red: 0.0, green: 0.96, blue: 0.83),
                mid: Color(red: 0.0, green: 0.82, blue: 0.88),
                peak: Color(red: 0.70, green: 0.96, blue: 1.0)
            )
        }
    }
}

// MARK: - Guaranteed 60fps Dancing Audio Spectrum (TimelineView)

struct CyberAudioSpectrumView: View {
    var barCount: Int = 4
    var isPlaying: Bool = true
    var barWidth: CGFloat = 2.6
    var segmentHeight: CGFloat = 1.8
    var segmentSpacing: CGFloat = 1.0
    var palette: RetroSpectrumPalette? = nil
    var accentColor: Color? = nil
    @Environment(\.animationGates) private var animationGates

    private var activePalette: RetroSpectrumPalette {
        if let palette { return palette }
        if let accent = accentColor {
            return RetroSpectrumPalette(
                base: accent,
                mid: Color(red: 0.96, green: 0.62, blue: 0.04),
                peak: Color(red: 1.0, green: 0.88, blue: 0.20)
            )
        }
        return RetroSpectrumPalette.forProgressColor(.cyan)
    }

    private func segmentColor(level: Int, isActive: Bool) -> Color {
        guard isActive else {
            return Color(red: 0.12, green: 0.14, blue: 0.18)
        }
        let pal = activePalette
        switch level {
        case 0, 1:
            return pal.base // Base mengikuti Color Theme yang dipilih di bawah
        case 2:
            return pal.mid  // Transisi gradient harmonis di tengah
        default:
            return pal.peak // Ujung puncak visualizer di atas
        }
    }

    /// Fixed size the CA replacement reports to layout — identical to the
    /// SwiftUI HStack it replaces, so the measured wing width never changes.
    private var caSize: CGSize {
        CARetroSpectrumView.fixedSize(barCount: barCount, barWidth: barWidth,
                                      segmentHeight: segmentHeight, segmentSpacing: segmentSpacing)
    }

    var body: some View {
        // Gated on the Music class (one decision from ticket 03): while a
        // track plays, the render server drives the segments — no SwiftUI
        // redraw per frame. The still frame (gate off, Reduce Motion, paused)
        // stays SwiftUI and holds the bottom segment lit, exactly as before.
        if animationGates.allows(.music) && isPlaying {
            CARetroSpectrumView(
                barCount: barCount,
                barWidth: barWidth,
                segmentHeight: segmentHeight,
                segmentSpacing: segmentSpacing,
                palette: activePalette,
                animating: true
            )
            .frame(width: caSize.width, height: caSize.height)
        } else {
            bars(time: nil)
        }
    }

    /// `time == nil` renders the still frame: one segment lit, no motion.
    @ViewBuilder
    private func bars(time: TimeInterval?) -> some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<barCount, id: \.self) { barIndex in
                let normalized: Double = {
                    guard isPlaying else { return 0.2 }
                    guard let time else { return 0.15 }
                    let factor = Double(barIndex)
                    let b1 = sin(time * 8.0 + factor * 1.5) * 0.4
                    let b2 = cos(time * 13.0 + factor * 2.2) * 0.3
                    let b3 = sin(time * 4.5) * 0.15
                    return max(0.15, min(1.0, 0.45 + b1 + b2 + b3))
                }()
                let activeCount = isPlaying ? Int((normalized * 4.0).rounded()) : 1

                VStack(spacing: segmentSpacing) {
                    ForEach((0..<4).reversed(), id: \.self) { step in
                        Rectangle()
                            .fill(segmentColor(level: step, isActive: step < activeCount))
                            .frame(width: barWidth, height: segmentHeight)
                    }
                }
            }
        }
    }
}

// MARK: - Retro Disco Equalizer Visualizer

struct CyberDiscoVisualizer: View {
    var isPlaying: Bool = true
    var barCount: Int = 6
    var maxHeight: CGFloat = 18
    var palette: RetroSpectrumPalette? = nil
    var accentColor: Color? = nil
    @Environment(\.animationGates) private var animationGates

    private var activePalette: RetroSpectrumPalette {
        if let palette { return palette }
        if let accent = accentColor {
            return RetroSpectrumPalette(
                base: accent,
                mid: Color(red: 0.96, green: 0.62, blue: 0.04),
                peak: Color(red: 1.0, green: 0.88, blue: 0.20)
            )
        }
        return RetroSpectrumPalette.forProgressColor(.cyan)
    }

    var body: some View {
        if animationGates.allows(.music) {
            TimelineView(.animation(minimumInterval: 0.04)) { timeline in
                bars(time: timeline.date.timeIntervalSinceReferenceDate)
            }
        } else {
            bars(time: nil)
        }
    }

    /// `time == nil` renders the still frame: every bar at rest.
    @ViewBuilder
    private func bars(time: TimeInterval?) -> some View {
        let pal = activePalette
        HStack(alignment: .bottom, spacing: 2.0) {
            ForEach(0..<barCount, id: \.self) { i in
                let factor = Double(i) * 0.9
                let wave = isPlaying && time != nil
                    ? max(0.12, min(1.0, 0.5 + sin(time! * 7.0 + factor) * 0.35 + cos(time! * 12.0 + factor * 1.7) * 0.25))
                    : 0.15
                let barH = max(3, maxHeight * CGFloat(wave))

                    VStack(spacing: 1.2) {
                        Rectangle()
                            .fill(pal.peak)
                            .frame(width: 2.5, height: 1.5)
                            .opacity(isPlaying && wave > 0.6 ? 1 : 0.2)

                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        pal.base, // Base bawah: warna Color Theme
                                        pal.mid,  // Tengah: gradien harmonis
                                        pal.peak  // Atas: peak tip
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 2.5, height: barH)
                    }
                }
            }
        .frame(height: maxHeight + 4, alignment: .bottom)
    }
}

// MARK: - Modern Clean Audio Spectrum (Smooth Dynamic Island Style)

struct ModernAudioSpectrumView: View {
    var barCount: Int = 3
    var isPlaying: Bool = true
    var barWidth: CGFloat = 1.8
    var maxHeight: CGFloat = 9.0
    var color: Color = Color(red: 1.0, green: 0.65, blue: 0.45)
    @Environment(\.animationGates) private var animationGates

    /// Fixed size the CA replacement reports to layout — identical to the
    /// SwiftUI HStack it replaces, so the measured wing width never changes.
    private var caSize: CGSize {
        CAModernSpectrumView.fixedSize(barCount: barCount, barWidth: barWidth, maxHeight: maxHeight)
    }

    var body: some View {
        // Gated on the Music class (one decision from ticket 03): while a
        // track plays, the render server drives the capsule heights — no
        // SwiftUI redraw per frame. The still frame stays SwiftUI.
        if animationGates.allows(.music) && isPlaying {
            CAModernSpectrumView(
                barCount: barCount,
                barWidth: barWidth,
                maxHeight: maxHeight,
                color: color,
                animating: true
            )
            .frame(width: caSize.width, height: caSize.height)
        } else {
            // Still frame: every capsule at its rest height.
            bars(time: nil)
        }
    }

    @ViewBuilder
    private func bars(time: TimeInterval?) -> some View {
        HStack(alignment: .center, spacing: 1.6) {
            ForEach(0..<barCount, id: \.self) { barIndex in
                let normalized: CGFloat = {
                    guard isPlaying else { return 0.25 }
                    guard let time else { return 0.25 }
                    let factor = Double(barIndex)
                    let b1 = sin(time * 8.0 + factor * 2.2) * 0.42
                    let b2 = cos(time * 12.5 + factor * 1.7) * 0.28
                    let b3 = sin(time * 4.2 + factor * 0.9) * 0.15
                    return max(0.25, min(1.0, CGFloat(0.55 + b1 + b2 + b3)))
                }()

                Capsule()
                    .fill(color)
                    .frame(width: barWidth, height: max(2.5, maxHeight * normalized))
            }
        }
        .frame(height: maxHeight, alignment: .center)
    }
}

// MARK: - Modern Marquee Scrolling Text for Compact Wing

private struct ModernMarqueeTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ModernMarqueeText: View {
    let text: String
    var font: Font = .system(size: 9.5, weight: .bold, design: .rounded)
    var color: Color = .white
    var maxWidth: CGFloat? = nil
    var centerShortText: Bool = false
    @Environment(\.animationGates) private var animationGates
    @State private var textWidth: CGFloat = 0
    @State private var startDate = Date()

    var body: some View {
        GeometryReader { geo in
            let containerWidth = maxWidth ?? geo.size.width
            let excess = max(0, textWidth - containerWidth)
            // The Marquee class still needs text wider than its box; a title
            // that fits never scrolls, so no timeline is created for it.
            if animationGates.allows(.marquee) && excess > 0 {
                scrolling(containerWidth: containerWidth, excess: excess, height: geo.size.height)
            } else {
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: containerWidth, height: geo.size.height, alignment: (centerShortText && excess == 0) ? .center : .leading)
                    .clipped()
            }
        }
        .frame(width: maxWidth)
        .onPreferenceChange(ModernMarqueeTextWidthKey.self) { width in
            if abs(self.textWidth - width) > 1 {
                self.textWidth = width
            }
        }
        .onChange(of: text) { _, _ in
            startDate = Date()
            textWidth = 0
        }
    }

    private func scrolling(containerWidth: CGFloat, excess: CGFloat, height: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 0.03)) { timeline in
                let offset: CGFloat = {
                    guard excess > 0 else { return 0 }
                    let scrollDuration = max(2.5, Double(excess) / 22.0)
                    let pauseStart = 1.2
                    let pauseEnd = 1.2
                    let resetDuration = 1.0
                    let totalCycle = pauseStart + scrollDuration + pauseEnd + resetDuration

                    let time = max(0, timeline.date.timeIntervalSince(startDate))
                    let t = time.truncatingRemainder(dividingBy: totalCycle)

                    if t < pauseStart {
                        return 0
                    } else if t < pauseStart + scrollDuration {
                        let progress = (t - pauseStart) / scrollDuration
                        let smooth = (1.0 - cos(progress * .pi)) / 2.0
                        return CGFloat(smooth) * excess
                    } else if t < pauseStart + scrollDuration + pauseEnd {
                        return excess
                    } else {
                        let progress = (t - (pauseStart + scrollDuration + pauseEnd)) / resetDuration
                        let smooth = (1.0 - cos(progress * .pi)) / 2.0
                        return (1.0 - CGFloat(smooth)) * excess
                    }
                }()

                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize()
                    .background(
                        GeometryReader { textGeo in
                            Color.clear.preference(key: ModernMarqueeTextWidthKey.self, value: textGeo.size.width)
                        }
                    )
                    .offset(x: -offset)
                    .frame(width: containerWidth, height: height, alignment: .leading)
                    .clipped()
        }
    }
}

// MARK: - Compact Wing Music View (Ultra-Compact for Small Notch)

struct CyberMusicWingView: View {
    @ObservedObject var nowPlaying: NowPlayingManager
    var isHovered: Bool = false
    var isEnlarged: Bool = false
    var wingWidth: CGFloat = 0
    @AppStorage(SettingsKey.musicHUDTheme) private var musicHUDTheme = SettingsDefaults.musicHUDTheme
    @AppStorage(SettingsKey.islandUITheme) private var islandUITheme = SettingsDefaults.islandUITheme
    @AppStorage(SettingsKey.musicHUDProgressColor) private var musicHUDProgressColor = SettingsDefaults.musicHUDProgressColor
    @AppStorage(SettingsKey.syncThemeWithAlbumArt) private var syncThemeWithAlbumArt = SettingsDefaults.syncThemeWithAlbumArt

    init(nowPlaying: NowPlayingManager, isHovered: Bool = false, isEnlarged: Bool = false, wingWidth: CGFloat = 0) {
        self.nowPlaying = nowPlaying
        self.isHovered = isHovered
        self.isEnlarged = isEnlarged
        self.wingWidth = wingWidth
    }

    private var isModernClean: Bool {
        if islandUITheme == IslandUITheme.modern.rawValue { return true }
        if islandUITheme == IslandUITheme.pixel.rawValue { return false }
        return musicHUDTheme == MusicHUDTheme.modernClean.rawValue
    }

    private var accentColor: Color {
        if (syncThemeWithAlbumArt || musicHUDProgressColor == MusicProgressColor.album.rawValue) && nowPlaying.isPlaying && nowPlaying.artworkImage != nil {
            return nowPlaying.albumPalette.primary
        }
        let pc = MusicProgressColor(rawValue: musicHUDProgressColor) ?? .theme
        switch pc {
        case .album:
            if nowPlaying.isPlaying && nowPlaying.artworkImage != nil {
                return nowPlaying.albumPalette.primary
            }
            return isModernClean ? Color(red: 1.0, green: 0.65, blue: 0.45) : Color(red: 0.0, green: 0.96, blue: 0.83)
        case .theme: return isModernClean ? Color(red: 1.0, green: 0.65, blue: 0.45) : Color(red: 0.0, green: 0.96, blue: 0.83)
        case .white: return .white
        case .cyan: return Color(red: 0.0, green: 0.96, blue: 0.83)
        case .pink: return Color(red: 1.0, green: 0.16, blue: 0.53)
        case .green: return Color(red: 0.12, green: 0.84, blue: 0.38)
        case .amber: return Color(red: 1.0, green: 0.72, blue: 0.20)
        }
    }

    var body: some View {
        let artSize: CGFloat = isEnlarged ? 23 : 17
        let spectrumMaxH: CGFloat = isEnlarged ? 14.0 : 11.0

        if isModernClean {
            // MODERN CLEAN: Langsung album cover, marquee title (saat di-hover), dan visualizer tanpa border
            HStack(alignment: .center, spacing: isEnlarged ? 5 : 4) {
                if let art = nowPlaying.artworkImage {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: artSize, height: artSize)
                        .clipShape(RoundedRectangle(cornerRadius: isEnlarged ? 5 : 4, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: isEnlarged ? 5 : 4, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: artSize, height: artSize)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: isEnlarged ? 10 : 8, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.85))
                        )
                }

                if isHovered && (wingWidth == 0 || wingWidth >= 75) {
                    let titleMaxW = max(36, min(isEnlarged ? 76 : 64, wingWidth > 0 ? (wingWidth - 44) : 64))
                    ModernMarqueeText(
                        text: nowPlaying.title.isEmpty ? "Music" : nowPlaying.title,
                        maxWidth: titleMaxW
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                ModernAudioSpectrumView(
                    barCount: 3,
                    isPlaying: nowPlaying.isPlaying,
                    barWidth: isEnlarged ? 2.4 : 2.0,
                    maxHeight: spectrumMaxH,
                    color: accentColor
                )
            }
            .fixedSize()
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
        } else {
            // RETRO CYBER: Seamless Frameless, Sharp Album Art, Marquee Monospaced Title saat hover, Dancing Spectrum
            HStack(alignment: .center, spacing: isEnlarged ? 5 : 4) {
                // Album Art (crisp rounded corner, no outer bounding pill)
                if let art = nowPlaying.artworkImage {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: artSize, height: artSize)
                        .clipShape(RoundedRectangle(cornerRadius: isEnlarged ? 4.5 : 3.5, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: isEnlarged ? 4.5 : 3.5, style: .continuous)
                        .fill(Color(red: 0.08, green: 0.09, blue: 0.12))
                        .frame(width: artSize, height: artSize)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: isEnlarged ? 10 : 8))
                                .foregroundStyle(accentColor.opacity(0.85))
                        )
                }

                // Title: Marquee scrolling text in retro monospace font (vertically centered, never truncated)
                if isHovered && (wingWidth == 0 || wingWidth >= 75) {
                    let titleMaxW = max(36, min(isEnlarged ? 76 : 64, wingWidth > 0 ? (wingWidth - 44) : 64))
                    ModernMarqueeText(
                        text: nowPlaying.title.isEmpty ? "Music" : nowPlaying.title,
                        font: .system(size: isEnlarged ? 9.5 : 8.5, weight: .bold, design: .monospaced),
                        color: .white,
                        maxWidth: titleMaxW
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                // Equalizer: Pixel dancing spectrum using active theme accent as base
                CyberAudioSpectrumView(
                    barCount: isHovered ? 3 : 4,
                    isPlaying: nowPlaying.isPlaying,
                    barWidth: isEnlarged ? 2.4 : 2.0,
                    segmentHeight: isEnlarged ? 2.0 : 1.6,
                    segmentSpacing: 0.8,
                    palette: RetroSpectrumPalette.forThemeKey(musicHUDProgressColor)
                )
            }
            .fixedSize()
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
        }
    }
}

// MARK: - Mini Peek Banner (Buka Tipis-Tipis saat Ganti Lagu)

struct CyberMusicMiniPeekBanner: View {
    @ObservedObject var nowPlaying: NowPlayingManager
    var onOpenFull: () -> Void
    @AppStorage(SettingsKey.musicHUDTheme) private var musicHUDTheme = SettingsDefaults.musicHUDTheme
    @AppStorage(SettingsKey.islandUITheme) private var islandUITheme = SettingsDefaults.islandUITheme
    @AppStorage(SettingsKey.musicHUDProgressColor) private var musicHUDProgressColor = SettingsDefaults.musicHUDProgressColor
    @AppStorage(SettingsKey.syncThemeWithAlbumArt) private var syncThemeWithAlbumArt = SettingsDefaults.syncThemeWithAlbumArt

    private var isModernClean: Bool {
        if islandUITheme == IslandUITheme.modern.rawValue { return true }
        if islandUITheme == IslandUITheme.pixel.rawValue { return false }
        return musicHUDTheme == MusicHUDTheme.modernClean.rawValue
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
            return isModernClean ? Color(red: 1.0, green: 0.65, blue: 0.45) : Color(red: 0.0, green: 0.96, blue: 0.83)
        case .theme: return isModernClean ? Color(red: 1.0, green: 0.65, blue: 0.45) : Color(red: 0.0, green: 0.96, blue: 0.83)
        case .white: return .white
        case .cyan: return Color(red: 0.0, green: 0.96, blue: 0.83)
        case .pink: return Color(red: 1.0, green: 0.16, blue: 0.53)
        case .green: return Color(red: 0.12, green: 0.84, blue: 0.38)
        case .amber: return Color(red: 1.0, green: 0.72, blue: 0.20)
        }
    }

    var body: some View {
        Button(action: onOpenFull) {
            HStack(spacing: 8) {
                // Animated Cover Art
                if let art = nowPlaying.artworkImage {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: isModernClean ? 6 : 3.5, style: .continuous))
                        .shadow(color: Color.black.opacity(0.4), radius: 3)
                } else {
                    ZStack {
                        if isModernClean {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(white: 0.12))
                                .frame(width: 26, height: 26)
                        } else {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Pixel16Palette.slot)
                                .frame(width: 26, height: 26)
                                .pixel16Bevel(raised: false, fillColor: Pixel16Palette.slot)
                        }

                        Image(systemName: "music.note")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(isModernClean ? accentColor : Color(red: 0.0, green: 0.96, blue: 0.83))
                    }
                }

                // Track Title & Artist
                VStack(alignment: .leading, spacing: 1) {
                    Text(nowPlaying.title.isEmpty ? "No Track" : nowPlaying.title)
                        .font(.system(size: 10, weight: .bold, design: isModernClean ? .rounded : .monospaced))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)

                    Text(nowPlaying.artist.isEmpty ? "Now Playing" : nowPlaying.artist)
                        .font(.system(size: 8.5, design: isModernClean ? .default : .monospaced))
                        .foregroundStyle(isModernClean ? Color(white: 0.65) : Color(red: 0.0, green: 0.96, blue: 0.83).opacity(0.75))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // Dancing Spectrum
                if isModernClean {
                    ModernAudioSpectrumView(barCount: 4, isPlaying: nowPlaying.isPlaying, barWidth: 2.2, maxHeight: 12.0, color: accentColor)
                } else {
                    CyberAudioSpectrumView(barCount: 4, isPlaying: nowPlaying.isPlaying, barWidth: 2.2, segmentHeight: 1.8, segmentSpacing: 1.0, palette: RetroSpectrumPalette.forThemeKey(musicHUDProgressColor))
                }

                // Close button
                Button(action: {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    nowPlaying.dismissToast()
                }) {
                    ZStack {
                        if !isModernClean {
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .fill(Pixel16Palette.surface)
                                .frame(width: 16, height: 16)
                                .pixel16Bevel(raised: true, fillColor: Pixel16Palette.surface)
                        }
                        Image(systemName: "xmark")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.65))
                            .frame(width: 14, height: 14)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                Group {
                    if isModernClean {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(white: 0.10).opacity(0.95))
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Pixel16Palette.chassis)
                            .pixel16Bevel(raised: false, fillColor: Pixel16Palette.chassis)
                    }
                }
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 5)
        }
        .buttonStyle(.plain)
    }
}

extension FloatingLyricTextColor {
    @MainActor
    var color: Color {
        switch self {
        case .album:
            if NowPlayingManager.shared.isPlaying && NowPlayingManager.shared.artworkImage != nil {
                return NowPlayingManager.shared.albumPalette.primary
            }
            return Color.white
        case .white: return Color.white
        case .cyan: return Color(red: 0.0, green: 0.96, blue: 0.83)
        case .pink: return Color(red: 1.0, green: 0.16, blue: 0.53)
        case .green: return Color(red: 0.0, green: 0.90, blue: 0.46)
        case .amber: return Color(red: 1.0, green: 0.62, blue: 0.0)
        }
    }
}

// MARK: - Sub-Notch Floating Synced Lyric Bar Helpers

/// Dual rotating tape spools with spokes & connecting tape for Teenage Engineering TP-7 preset
private struct TeenageTapeReelView: View {
    let isPlaying: Bool
    let color: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.04)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let angle = isPlaying ? (t * 140.0).truncatingRemainder(dividingBy: 360.0) : 0.0

            HStack(spacing: 3) {
                singleSpool(angle: angle)
                Rectangle()
                    .fill(color.opacity(0.4))
                    .frame(width: 4, height: 1)
                singleSpool(angle: angle)
            }
        }
    }

    private func singleSpool(angle: Double) -> some View {
        ZStack {
            Circle()
                .strokeBorder(color.opacity(0.85), lineWidth: 1.0)
                .frame(width: 12, height: 12)
            Circle()
                .fill(Color.black.opacity(0.9))
                .frame(width: 9, height: 9)
            ForEach(0..<3, id: \.self) { i in
                Rectangle()
                    .fill(color.opacity(0.9))
                    .frame(width: 1.0, height: 8)
                    .rotationEffect(.degrees(Double(i) * 60.0))
            }
            Circle()
                .fill(Color.white.opacity(0.95))
                .frame(width: 2.5, height: 2.5)
        }
        .rotationEffect(.degrees(angle))
    }
}

/// Rotating micro vinyl record with concentric grooves & metallic tonearm for Vinyl Groove preset
private struct MicroVinylRecordView: View {
    let isPlaying: Bool
    let accentColor: Color

    var body: some View {
        HStack(spacing: 2) {
            TimelineView(.periodic(from: .now, by: 0.04)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let angle = isPlaying ? (t * 90.0).truncatingRemainder(dividingBy: 360.0) : 0.0

                ZStack {
                    Circle()
                        .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
                        .frame(width: 15, height: 15)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6)
                        .frame(width: 12, height: 12)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
                        .frame(width: 9, height: 9)
                    Circle()
                        .fill(accentColor)
                        .frame(width: 5.5, height: 5.5)
                    Circle()
                        .fill(Color.black)
                        .frame(width: 1.5, height: 1.5)
                }
                .rotationEffect(.degrees(angle))
                .shadow(color: Color.black.opacity(0.6), radius: 2)
            }

            Path { p in
                p.move(to: CGPoint(x: 0, y: 1))
                p.addLine(to: CGPoint(x: 3.5, y: 6))
                p.addLine(to: CGPoint(x: 2.5, y: 10))
            }
            .stroke(Color.white.opacity(0.65), style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))
            .frame(width: 4, height: 12)
            .offset(y: isPlaying ? 0 : -2)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isPlaying)
        }
    }
}

/// Dynamic silk oscilloscope wave for Apple Music Fluid Shimmer preset
private struct FluidSilkWaveView: View {
    let isPlaying: Bool
    let color: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.04)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                var path = Path()
                let midY = size.height / 2
                let width = size.width

                path.move(to: CGPoint(x: 0, y: midY))
                for x in stride(from: 0, through: width, by: 1.5) {
                    let progress = x / width
                    let envelope = sin(progress * .pi)
                    let amp = isPlaying ? (size.height * 0.42 * envelope) : 0.8
                    let y = midY + sin((x / 5.0) + (t * 4.0)) * amp
                    path.addLine(to: CGPoint(x: x, y: y))
                }

                ctx.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [color.opacity(0.3), color, color.opacity(0.3)]),
                        startPoint: CGPoint(x: 0, y: midY),
                        endPoint: CGPoint(x: width, y: midY)
                    ),
                    lineWidth: 1.5
                )
            }
        }
        .frame(width: 18, height: 10)
    }
}

// MARK: - Interactive Floating Lyric Icon View

struct InteractiveFloatingLyricIconView: View {
    let style: FloatingLyricIconStyle
    @ObservedObject var nowPlaying: NowPlayingManager
    let accentColor: Color
    var onAction: () -> Void = {}

    @State private var isHovered = false
    @State private var spinAngle: Double = 0

    var body: some View {
        if style == .none {
            EmptyView()
        } else {
            Button(action: {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                onAction()
            }) {
                iconBody
                    .scaleEffect(isHovered ? 1.18 : 1.0)
                    .shadow(color: isHovered ? accentColor.opacity(0.85) : Color.black.opacity(0.6), radius: isHovered ? 4 : 2)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    isHovered = hovering
                }
            }
            .help(nowPlaying.isPlaying ? "Click to Pause" : "Click to Play")
        }
    }

    @ViewBuilder
    private var iconBody: some View {
        switch style {
        case .spinningVinyl:
            // Realistic micro vinyl record (16x16) with concentric grooves and rotating animation
            ZStack {
                Circle()
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.09))
                    .frame(width: 15, height: 15)

                // Grooves
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
                    .frame(width: 11, height: 11)

                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    .frame(width: 7, height: 7)

                // Center Label / Spindle
                Circle()
                    .fill(accentColor)
                    .frame(width: 4.5, height: 4.5)

                Circle()
                    .fill(Color.black)
                    .frame(width: 1.5, height: 1.5)
            }
            .rotationEffect(.degrees(spinAngle))
            .onAppear {
                if nowPlaying.isPlaying {
                    withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                        spinAngle = 360
                    }
                }
            }
            .onChange(of: nowPlaying.isPlaying) { _, isPlaying in
                if isPlaying {
                    withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                        spinAngle += 360
                    }
                }
            }

        case .albumTurntable:
            // Miniature circular album art turntable disc
            ZStack {
                if let art = nowPlaying.artworkImage {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 15, height: 15)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(accentColor.opacity(0.6), lineWidth: 0.75))
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accentColor, Color(red: 0.1, green: 0.1, blue: 0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 15, height: 15)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white)
                        )
                }

                // Center spindle hole
                Circle()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: 2.5, height: 2.5)
            }
            .rotationEffect(.degrees(spinAngle))
            .onAppear {
                if nowPlaying.isPlaying {
                    withAnimation(.linear(duration: 5.0).repeatForever(autoreverses: false)) {
                        spinAngle = 360
                    }
                }
            }
            .onChange(of: nowPlaying.isPlaying) { _, isPlaying in
                if isPlaying {
                    withAnimation(.linear(duration: 5.0).repeatForever(autoreverses: false)) {
                        spinAngle += 360
                    }
                }
            }

        case .dancingWave:
            // Harmonic audio spectrum node: 3 bouncing live bars
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(0..<3) { i in
                    TimelineView(.animation(minimumInterval: 0.08)) { timeline in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        let h: CGFloat = nowPlaying.isPlaying
                            ? max(3.5, 12.0 * CGFloat(abs(sin(time * 3.5 + Double(i) * 1.2))))
                            : 3.5
                        RoundedRectangle(cornerRadius: 1)
                            .fill(accentColor)
                            .frame(width: 2.2, height: h)
                    }
                }
            }
            .frame(width: 13, height: 13, alignment: .bottom)

        case .pulsingNote:
            // Neon glowing musical note with subtle pulse
            TimelineView(.animation(minimumInterval: 0.1)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let pulse = nowPlaying.isPlaying ? 0.8 + 0.2 * sin(time * 4.0) : 0.85
                let bounce = nowPlaying.isPlaying ? -1.0 * sin(time * 3.0) : 0.0

                Image(systemName: "music.note")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(accentColor)
                    .shadow(color: accentColor.opacity(pulse), radius: 4)
                    .offset(y: bounce)
                    .frame(width: 12)
            }

        case .retroCassette:
            // Miniature cassette tape spool with dual rotating teeth
            ZStack {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
                    .frame(width: 17, height: 11)
                    .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(accentColor.opacity(0.6), lineWidth: 0.6))

                HStack(spacing: 3) {
                    Circle()
                        .stroke(Color.white.opacity(0.85), lineWidth: 0.8)
                        .frame(width: 4, height: 4)
                        .rotationEffect(.degrees(spinAngle))

                    Circle()
                        .stroke(Color.white.opacity(0.85), lineWidth: 0.8)
                        .frame(width: 4, height: 4)
                        .rotationEffect(.degrees(spinAngle))
                }
            }
            .frame(width: 17, height: 11)
            .onAppear {
                if nowPlaying.isPlaying {
                    withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                        spinAngle = 360
                    }
                }
            }
            .onChange(of: nowPlaying.isPlaying) { _, isPlaying in
                if isPlaying {
                    withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                        spinAngle += 360
                    }
                }
            }

        case .studioMic:
            // Live studio mic with status glow
            ZStack {
                Image(systemName: "mic.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(accentColor)

                Circle()
                    .stroke(accentColor.opacity(nowPlaying.isPlaying ? 0.85 : 0.2), lineWidth: 0.8)
                    .frame(width: 13, height: 13)
            }
            .frame(width: 13, height: 13)

        case .hapticBubble:
            // Tactile lyric bubble with internal pulsing soundwave dots
            ZStack {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(accentColor)
            }
            .frame(width: 12)

        case .none:
            EmptyView()
        }
    }
}

// MARK: - Integrated Notch Chin Lyric View (Unified contiguous chin under physical notch)

struct IntegratedNotchChinLyricView: View {
    @ObservedObject var nowPlaying: NowPlayingManager
    let width: CGFloat
    var onOpenFull: () -> Void = {}
    @AppStorage(SettingsKey.floatingLyricFontSize) private var floatingLyricFontSize = SettingsDefaults.floatingLyricFontSize
    @AppStorage(SettingsKey.floatingLyricFontDesign) private var floatingLyricFontDesign = SettingsDefaults.floatingLyricFontDesign
    @AppStorage(SettingsKey.floatingLyricIconStyle) private var floatingLyricIconStyle = SettingsDefaults.floatingLyricIconStyle
    @AppStorage(SettingsKey.floatingLyricTextColor) private var floatingLyricTextColor = SettingsDefaults.floatingLyricTextColor
    @AppStorage(SettingsKey.syncThemeWithAlbumArt) private var syncThemeWithAlbumArt = SettingsDefaults.syncThemeWithAlbumArt
    @AppStorage(SettingsKey.musicHUDProgressColor) private var musicHUDProgressColor = SettingsDefaults.musicHUDProgressColor
    @AppStorage(SettingsKey.islandUITheme) private var islandUITheme = SettingsDefaults.islandUITheme
    @State private var isHovered = false

    private var activeTextColor: Color {
        if (syncThemeWithAlbumArt || floatingLyricTextColor == "album" || musicHUDProgressColor == "album") && nowPlaying.isPlaying && nowPlaying.artworkImage != nil {
            return nowPlaying.albumPalette.primary
        }
        return FloatingLyricTextColor(rawValue: floatingLyricTextColor)?.color ?? .white
    }

    private var activeFontDesign: Font.Design {
        switch FloatingLyricFontDesign(rawValue: floatingLyricFontDesign) ?? .rounded {
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        case .system: return .default
        case .serif: return .serif
        case .pixel: return .monospaced
        }
    }

    private var activeIconStyle: FloatingLyricIconStyle {
        FloatingLyricIconStyle(rawValue: floatingLyricIconStyle) ?? .spinningVinyl
    }

    private var displayText: String {
        let lyric = nowPlaying.currentLyricText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !lyric.isEmpty { return lyric }
        if nowPlaying.lyricsLoading { return "♫ Loading lyrics..." }
        if nowPlaying.currentLyricIndex > 0 { return "♪ Instrumental Interlude ♪" }
        if !nowPlaying.title.isEmpty {
            let artist = nowPlaying.artist.isEmpty ? "" : " • \(nowPlaying.artist)"
            return "♪ \(nowPlaying.title)\(artist)"
        }
        return "♪ Music Playing..."
    }

    var body: some View {
        Button(action: {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            onOpenFull()
        }) {
            HStack(spacing: 6) {
                InteractiveFloatingLyricIconView(
                    style: activeIconStyle,
                    nowPlaying: nowPlaying,
                    accentColor: activeTextColor,
                    onAction: { nowPlaying.togglePlayPause() }
                )

                Text(displayText)
                    .font(.system(size: CGFloat(floatingLyricFontSize), weight: .semibold, design: activeFontDesign))
                    .foregroundStyle(activeTextColor)
                    .shadow(color: Color.black.opacity(0.85), radius: 2.5, y: 1)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .id("\(displayText)-\(floatingLyricFontDesign)-\(floatingLyricFontSize)")
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 3)),
                        removal: .opacity.combined(with: .offset(y: -3))
                    ))

                CyberAudioSpectrumView(
                    barCount: 3,
                    isPlaying: nowPlaying.isPlaying,
                    barWidth: 1.6,
                    segmentHeight: 1.4,
                    segmentSpacing: 0.6,
                    palette: RetroSpectrumPalette.forThemeKey(musicHUDProgressColor)
                )
                .frame(width: 12)
            }
            .padding(.horizontal, 10)
            .frame(width: max(100, width), height: 24)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("♫ Live Synced Lyrics (Click to open Music HUD)")
    }
}

// MARK: - Sub-Notch Floating Synced Lyric Bar (Mini Dynamic Island for Lyrics)

struct SubNotchFloatingLyricCapsuleView: View {
    @ObservedObject var nowPlaying: NowPlayingManager
    var onOpenFull: () -> Void

    @AppStorage(SettingsKey.floatingLyricPreset) private var floatingLyricPreset = SettingsDefaults.floatingLyricPreset
    @AppStorage(SettingsKey.floatingLyricFontSize) private var floatingLyricFontSize = SettingsDefaults.floatingLyricFontSize
    @AppStorage(SettingsKey.floatingLyricFontDesign) private var floatingLyricFontDesign = SettingsDefaults.floatingLyricFontDesign
    @AppStorage(SettingsKey.floatingLyricIconStyle) private var floatingLyricIconStyle = SettingsDefaults.floatingLyricIconStyle
    @AppStorage(SettingsKey.floatingLyricTextColor) private var floatingLyricTextColor = SettingsDefaults.floatingLyricTextColor
    @AppStorage(SettingsKey.musicHUDProgressColor) private var musicHUDProgressColor = SettingsDefaults.musicHUDProgressColor
    @AppStorage(SettingsKey.syncThemeWithAlbumArt) private var syncThemeWithAlbumArt = SettingsDefaults.syncThemeWithAlbumArt
    @AppStorage(SettingsKey.islandUITheme) private var islandUITheme = SettingsDefaults.islandUITheme
    @State private var isHovered = false
    @State private var capsuleWidth: CGFloat = 180

    private var isPixel: Bool {
        islandUITheme == IslandUITheme.pixel.rawValue
    }

    private var activePreset: FloatingLyricPreset {
        FloatingLyricPreset(rawValue: floatingLyricPreset) ?? .pureText
    }

    private var activeIconStyle: FloatingLyricIconStyle {
        FloatingLyricIconStyle(rawValue: floatingLyricIconStyle) ?? .spinningVinyl
    }

    private var activeTextColor: Color {
        if (syncThemeWithAlbumArt || floatingLyricTextColor == "album" || musicHUDProgressColor == "album") && nowPlaying.isPlaying && nowPlaying.artworkImage != nil {
            return nowPlaying.albumPalette.primary
        }
        return FloatingLyricTextColor(rawValue: floatingLyricTextColor)?.color ?? .white
    }

    private var activeFontDesign: Font.Design {
        if activePreset == .retroPixel { return .monospaced }
        if activePreset == .vinylGroove && floatingLyricFontDesign == FloatingLyricFontDesign.rounded.rawValue {
            return .serif
        }
        switch FloatingLyricFontDesign(rawValue: floatingLyricFontDesign) ?? .rounded {
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        case .system: return .default
        case .serif: return .serif
        case .pixel: return .monospaced
        }
    }

    private var activeNSFont: NSFont {
        let baseSize = CGFloat(floatingLyricFontSize)
        let size = (activePreset == .retroPixel || floatingLyricFontDesign == FloatingLyricFontDesign.pixel.rawValue) ? max(baseSize * 1.25, 12.5) : baseSize
        if activePreset == .vinylGroove && floatingLyricFontDesign == FloatingLyricFontDesign.rounded.rawValue {
            if let desc = NSFont.systemFont(ofSize: size, weight: .bold).fontDescriptor.withDesign(.serif) {
                return NSFont(descriptor: desc, size: size) ?? NSFont.boldSystemFont(ofSize: size)
            }
            return NSFont.boldSystemFont(ofSize: size)
        }
        switch FloatingLyricFontDesign(rawValue: floatingLyricFontDesign) ?? .rounded {
        case .rounded:
            if let desc = NSFont.systemFont(ofSize: size, weight: .bold).fontDescriptor.withDesign(.rounded) {
                return NSFont(descriptor: desc, size: size) ?? NSFont.boldSystemFont(ofSize: size)
            }
            return NSFont.boldSystemFont(ofSize: size)
        case .monospaced, .pixel:
            return NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        case .system:
            return NSFont.boldSystemFont(ofSize: size)
        case .serif:
            if let desc = NSFont.systemFont(ofSize: size, weight: .bold).fontDescriptor.withDesign(.serif) {
                return NSFont(descriptor: desc, size: size) ?? NSFont.boldSystemFont(ofSize: size)
            }
            return NSFont.boldSystemFont(ofSize: size)
        }
    }

    private var isRealLyric: Bool {
        !nowPlaying.currentLyricText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var activeDisplayText: String {
        let lyric = nowPlaying.currentLyricText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !lyric.isEmpty {
            return lyric
        }
        if nowPlaying.lyricsLoading {
            return "♫ Loading lyrics..."
        }
        if nowPlaying.currentLyricIndex > 0 {
            return "♪ Instrumental Interlude ♪"
        }
        if !nowPlaying.title.isEmpty {
            let artist = nowPlaying.artist.isEmpty ? "" : " • \(nowPlaying.artist)"
            return "♪ Intro: \(nowPlaying.title)\(artist)"
        }
        return "♪ Music Playing..."
    }

    private var iconName: String {
        if isRealLyric {
            return "quote.bubble.fill"
        }
        if nowPlaying.lyricsLoading {
            return "arrow.triangle.2.circlepath"
        }
        return "music.note"
    }

    /// Computes pixel-perfect dynamic capsule width based on text length and active layout preset:
    /// Auto-expands smoothly with spring physics for long lyrics, contracts for short lines.
    private func calculateTargetWidth(for text: String, preset: FloatingLyricPreset) -> CGFloat {
        let font = activeNSFont
        let chromeWidth: CGFloat
        let minWidth: CGFloat

        switch preset {
        case .pureText:
            chromeWidth = activeIconStyle == .none ? 36 : 52
            minWidth = activeIconStyle == .none ? 44 : 64
        case .capsule:
            chromeWidth = activeIconStyle == .none ? 48 : 64
            minWidth = activeIconStyle == .none ? 56 : 74
        case .frostedGlass:
            chromeWidth = activeIconStyle == .none ? 44 : 60
            minWidth = activeIconStyle == .none ? 54 : 70
        case .neonHud:
            chromeWidth = activeIconStyle == .none ? 56 : 72
            minWidth = activeIconStyle == .none ? 64 : 80
        case .seamlessGlass:
            chromeWidth = 40
            minWidth = 50
        case .retroPixel:
            chromeWidth = activeIconStyle == .none ? 46 : 60
            minWidth = activeIconStyle == .none ? 56 : 72
        case .liquidAurora:
            chromeWidth = activeIconStyle == .none ? 48 : 62
            minWidth = activeIconStyle == .none ? 56 : 72
        case .minimalBraun:
            chromeWidth = activeIconStyle == .none ? 50 : 64
            minWidth = activeIconStyle == .none ? 60 : 76
        case .tapeReel:
            chromeWidth = 60
            minWidth = 76
        case .vinylGroove:
            chromeWidth = 60
            minWidth = 76
        case .fluidKaraoke:
            chromeWidth = activeIconStyle == .none ? 50 : 64
            minWidth = activeIconStyle == .none ? 60 : 76
        case .connectedChin:
            chromeWidth = 50
            minWidth = 60
        }

        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let target = ceil(textWidth + chromeWidth)
        return min(max(minWidth, target), 680)
    }

    @ViewBuilder
    private var presetContent: some View {
        switch activePreset {
        case .pureText:
            // Preset 1: Minimalist floating subtitle (No solid background)
            // Crisp pure-white text with layered drop shadow highlight & interactive lead icon snugly beside lyrics
            HStack(spacing: 8) {
                InteractiveFloatingLyricIconView(
                    style: activeIconStyle,
                    nowPlaying: nowPlaying,
                    accentColor: activeTextColor,
                    onAction: { nowPlaying.togglePlayPause() }
                )

                ZStack {
                    Text(activeDisplayText)
                        .font(.system(size: CGFloat(floatingLyricFontSize), weight: .bold, design: activeFontDesign))
                        .foregroundStyle(activeTextColor)
                        // Layered text highlight shadow for crystal-clear readability against any wallpaper
                        .shadow(color: Color.black.opacity(0.95), radius: 3, x: 0, y: 1.2)
                        .shadow(color: Color.black.opacity(0.80), radius: 6, x: 0, y: 2.5)
                        .shadow(color: activeTextColor.opacity(isHovered ? 0.70 : 0.30), radius: 4, x: 0, y: 0)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .id("\(activeDisplayText)-\(floatingLyricFontDesign)-\(floatingLyricFontSize)")
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 4)),
                            removal: .opacity.combined(with: .offset(y: -4))
                        ))
                }
                .fixedSize(horizontal: true, vertical: false)

                CyberAudioSpectrumView(
                    barCount: 3,
                    isPlaying: nowPlaying.isPlaying,
                    barWidth: 1.8,
                    segmentHeight: 1.4,
                    segmentSpacing: 0.6,
                    palette: RetroSpectrumPalette.forThemeKey(musicHUDProgressColor)
                )
                .shadow(color: Color.black.opacity(0.8), radius: 2)
                .frame(width: 14)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

        case .capsule:
            // Preset 2: Original cyber capsule: solid black Dynamic Island pill with neon gradient border
            HStack(spacing: 8) {
                InteractiveFloatingLyricIconView(
                    style: activeIconStyle,
                    nowPlaying: nowPlaying,
                    accentColor: activeTextColor,
                    onAction: { nowPlaying.togglePlayPause() }
                )

                ZStack {
                    Text(activeDisplayText)
                        .font(.system(size: CGFloat(floatingLyricFontSize), weight: .bold, design: activeFontDesign))
                        .foregroundStyle(isRealLyric ? activeTextColor : activeTextColor.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .id("\(activeDisplayText)-\(floatingLyricFontDesign)-\(floatingLyricFontSize)")
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 5)),
                            removal: .opacity.combined(with: .offset(y: -5))
                        ))
                }
                .fixedSize(horizontal: true, vertical: false)

                CyberAudioSpectrumView(
                    barCount: 3,
                    isPlaying: nowPlaying.isPlaying,
                    barWidth: 1.8,
                    segmentHeight: 1.4,
                    segmentSpacing: 0.6,
                    palette: RetroSpectrumPalette.forThemeKey(musicHUDProgressColor)
                )
                .frame(width: 14)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 5)

        case .frostedGlass:
            // Preset 3: Apple-style translucent frosted blur pill with hairline border
            HStack(spacing: 8) {
                InteractiveFloatingLyricIconView(
                    style: activeIconStyle,
                    nowPlaying: nowPlaying,
                    accentColor: activeTextColor,
                    onAction: { nowPlaying.togglePlayPause() }
                )

                ZStack {
                    Text(activeDisplayText)
                        .font(.system(size: CGFloat(floatingLyricFontSize), weight: .semibold, design: activeFontDesign))
                        .foregroundStyle(activeTextColor)
                        .shadow(color: Color.black.opacity(0.5), radius: 2, x: 0, y: 1)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .id("\(activeDisplayText)-\(floatingLyricFontDesign)-\(floatingLyricFontSize)")
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 4)),
                            removal: .opacity.combined(with: .offset(y: -4))
                        ))
                }
                .fixedSize(horizontal: true, vertical: false)

                CyberAudioSpectrumView(
                    barCount: 3,
                    isPlaying: nowPlaying.isPlaying,
                    barWidth: 1.8,
                    segmentHeight: 1.4,
                    segmentSpacing: 0.6,
                    palette: RetroSpectrumPalette.forThemeKey(musicHUDProgressColor)
                )
                .frame(width: 14)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

        case .neonHud:
            // Preset 4: Cyberpunk HUD with technical bracket telemetry styling
            HStack(spacing: 7) {
                Text("[")
                    .font(.system(size: CGFloat(floatingLyricFontSize), weight: .black, design: .monospaced))
                    .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83).opacity(0.9))

                InteractiveFloatingLyricIconView(
                    style: activeIconStyle,
                    nowPlaying: nowPlaying,
                    accentColor: Color(red: 0.0, green: 0.96, blue: 0.83),
                    onAction: { nowPlaying.togglePlayPause() }
                )

                ZStack {
                    Text(activeDisplayText)
                        .font(.system(size: CGFloat(floatingLyricFontSize), weight: .bold, design: activeFontDesign))
                        .foregroundStyle(activeTextColor)
                        .shadow(color: activeTextColor.opacity(0.4), radius: 3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .id("\(activeDisplayText)-\(floatingLyricFontDesign)-\(floatingLyricFontSize)")
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 4)),
                            removal: .opacity.combined(with: .offset(y: -4))
                        ))
                }
                .fixedSize(horizontal: true, vertical: false)

                CyberAudioSpectrumView(
                    barCount: 3,
                    isPlaying: nowPlaying.isPlaying,
                    barWidth: 1.8,
                    segmentHeight: 1.4,
                    segmentSpacing: 0.6,
                    palette: RetroSpectrumPalette.forThemeKey(musicHUDProgressColor)
                )
                .frame(width: 14)

                Text("]")
                    .font(.system(size: CGFloat(floatingLyricFontSize), weight: .black, design: .monospaced))
                    .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83).opacity(0.9))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4.5)

        case .seamlessGlass:
            // Preset 5: Seamless Glass — borderless translucent frosted glass with pure text focus and iPad Spotify vertical roll-up
            HStack(spacing: 0) {
                ZStack {
                    Text(activeDisplayText)
                        .font(.system(size: CGFloat(floatingLyricFontSize), weight: .semibold, design: activeFontDesign))
                        .foregroundStyle(activeTextColor)
                        .shadow(color: Color.black.opacity(0.55), radius: 2.5, x: 0, y: 1)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.center)
                        .id("floating-seamless-\(nowPlaying.currentLyricIndex)")
                        .transition(.asymmetric(
                            insertion: .offset(y: 20).combined(with: .opacity),
                            removal: .offset(y: -20).combined(with: .opacity)
                        ))
                }
                .frame(maxWidth: .infinity)
                .clipped()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4.5)

        case .retroPixel:
            // Preset 6: 8-Bit Retro Arcade — stepped pixel typography & live pixel audio spectrum
            let lyricFontSize: CGFloat = max(CGFloat(floatingLyricFontSize) * 1.25, 12.5)
            HStack(spacing: 7) {
                InteractiveFloatingLyricIconView(
                    style: activeIconStyle,
                    nowPlaying: nowPlaying,
                    accentColor: (MusicProgressColor(rawValue: musicHUDProgressColor) ?? .theme).color,
                    onAction: { nowPlaying.togglePlayPause() }
                )

                ZStack {
                    Text(activeDisplayText)
                        .font(.system(size: lyricFontSize, weight: .bold, design: .monospaced))
                        .foregroundStyle(activeTextColor)
                        .shadow(color: activeTextColor.opacity(0.4), radius: 3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .id("\(activeDisplayText)-\(floatingLyricFontDesign)-\(floatingLyricFontSize)")
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 4)),
                            removal: .opacity.combined(with: .offset(y: -4))
                        ))
                }
                .fixedSize(horizontal: true, vertical: false)

                CyberAudioSpectrumView(
                    barCount: 3,
                    isPlaying: nowPlaying.isPlaying,
                    barWidth: 2.0,
                    segmentHeight: 1.6,
                    segmentSpacing: 0.7,
                    palette: RetroSpectrumPalette.forThemeKey(musicHUDProgressColor)
                )
                .frame(width: 16)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 4.5)

        case .liquidAurora:
            // Preset 7: Liquid Aurora — translucent pill with flowing multi-color ambient glow behind lyrics
            HStack(spacing: 7) {
                InteractiveFloatingLyricIconView(
                    style: activeIconStyle,
                    nowPlaying: nowPlaying,
                    accentColor: Color(red: 0.0, green: 0.96, blue: 0.83),
                    onAction: { nowPlaying.togglePlayPause() }
                )

                ZStack {
                    Text(activeDisplayText)
                        .font(.system(size: CGFloat(floatingLyricFontSize), weight: .bold, design: activeFontDesign))
                        .foregroundStyle(Color.white)
                        .shadow(color: Color.black.opacity(0.85), radius: 2.5, y: 1.2)
                        .shadow(color: Color(red: 0.0, green: 0.96, blue: 0.83).opacity(0.4), radius: 5)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .id("\(activeDisplayText)-\(floatingLyricFontDesign)-\(floatingLyricFontSize)")
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 4)),
                            removal: .opacity.combined(with: .offset(y: -4))
                        ))
                }
                .fixedSize(horizontal: true, vertical: false)

                ModernAudioSpectrumView(
                    barCount: 3,
                    isPlaying: nowPlaying.isPlaying,
                    barWidth: 1.8,
                    maxHeight: 9.0,
                    color: Color(red: 0.0, green: 0.96, blue: 0.83)
                )
                .frame(width: 14)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 4.5)

        case .minimalBraun:
            // Preset 8: Braun Industrial — studio monitor strip with live recording status dot & Swiss typography
            HStack(spacing: 7) {
                HStack(spacing: 3) {
                    Circle()
                        .fill(nowPlaying.isPlaying ? activeTextColor : Color.white.opacity(0.3))
                        .frame(width: 4.5, height: 4.5)
                        .shadow(color: nowPlaying.isPlaying ? activeTextColor.opacity(0.8) : Color.clear, radius: 2)
                    Text("LIVE")
                        .font(.system(size: 6.5, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())

                ZStack {
                    Text(activeDisplayText)
                        .font(.system(size: CGFloat(floatingLyricFontSize), weight: .semibold, design: activeFontDesign))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .id("\(activeDisplayText)-\(floatingLyricFontDesign)-\(floatingLyricFontSize)")
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 3)),
                            removal: .opacity.combined(with: .offset(y: -3))
                        ))
                }
                .fixedSize(horizontal: true, vertical: false)

                ModernAudioSpectrumView(
                    barCount: 3,
                    isPlaying: nowPlaying.isPlaying,
                    barWidth: 1.6,
                    maxHeight: 8.5,
                    color: Color.white.opacity(0.8)
                )
                .frame(width: 12)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 4.5)

        case .tapeReel:
            // Preset 9: Teenage Engineering TP-7 Tape Reel
            // Dual spinning tape spools, phosphor amber VFD glow (#FFAE19), hardware 3-dot peak LED VU meter
            let reelAmber = Color(red: 1.0, green: 0.68, blue: 0.10)
            HStack(spacing: 7) {
                TeenageTapeReelView(isPlaying: nowPlaying.isPlaying, color: reelAmber)

                ZStack {
                    Text(activeDisplayText)
                        .font(.system(size: CGFloat(floatingLyricFontSize), weight: .bold, design: .monospaced))
                        .foregroundStyle(reelAmber)
                        .shadow(color: reelAmber.opacity(0.85), radius: 3)
                        .shadow(color: Color.black.opacity(0.9), radius: 2, y: 1)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .id("\(activeDisplayText)-\(floatingLyricFontDesign)-\(floatingLyricFontSize)")
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 4)),
                            removal: .opacity.combined(with: .offset(y: -4))
                        ))
                }
                .fixedSize(horizontal: true, vertical: false)

                // 3-dot LED hardware peak meter
                HStack(spacing: 2.5) {
                    Circle()
                        .fill(nowPlaying.isPlaying ? Color(red: 0.20, green: 0.88, blue: 0.65) : Color.white.opacity(0.2))
                        .frame(width: 3.5, height: 3.5)
                    Circle()
                        .fill(nowPlaying.isPlaying ? reelAmber : Color.white.opacity(0.2))
                        .frame(width: 3.5, height: 3.5)
                    Circle()
                        .fill(nowPlaying.isPlaying ? Color(red: 1.0, green: 0.20, blue: 0.20) : Color.white.opacity(0.2))
                        .frame(width: 3.5, height: 3.5)
                }
                .frame(width: 16)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 4.5)

        case .vinylGroove:
            // Preset 10: Vinyl Groove Scribe & Tonearm
            // Micro rotating 12-inch vinyl disc, metallic tonearm, SIDE A badge, elegant serif typography
            HStack(spacing: 7) {
                MicroVinylRecordView(isPlaying: nowPlaying.isPlaying, accentColor: activeTextColor)

                Text("SIDE A")
                    .font(.system(size: 6.5, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.horizontal, 3.5)
                    .padding(.vertical, 1.5)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 2.5))

                ZStack {
                    Text(activeDisplayText)
                        .font(.system(size: CGFloat(floatingLyricFontSize), weight: .semibold, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .italic()
                        .shadow(color: Color.black.opacity(0.75), radius: 2.5, y: 1.2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .id("\(activeDisplayText)-\(floatingLyricFontDesign)-\(floatingLyricFontSize)")
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 3)),
                            removal: .opacity.combined(with: .offset(y: -3))
                        ))
                }
                .fixedSize(horizontal: true, vertical: false)

                ModernAudioSpectrumView(
                    barCount: 3,
                    isPlaying: nowPlaying.isPlaying,
                    barWidth: 1.5,
                    maxHeight: 8.5,
                    color: Color.white.opacity(0.85)
                )
                .frame(width: 12)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 4.5)

        case .fluidKaraoke:
            // Preset 11: Apple Music Spatial Fluid Wave
            // Liquid chromatic iridescent sweep across words, live silk sine wave spectrum
            let waveColor = (MusicProgressColor(rawValue: musicHUDProgressColor) ?? .theme).color
            HStack(spacing: 7) {
                InteractiveFloatingLyricIconView(
                    style: activeIconStyle,
                    nowPlaying: nowPlaying,
                    accentColor: waveColor,
                    onAction: { nowPlaying.togglePlayPause() }
                )

                ZStack {
                    Text(activeDisplayText)
                        .font(.system(size: CGFloat(floatingLyricFontSize), weight: .bold, design: activeFontDesign))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color.white,
                                    Color(red: 0.95, green: 0.95, blue: 1.0),
                                    waveColor.opacity(0.95)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: Color.black.opacity(0.8), radius: 3, y: 1.5)
                        .shadow(color: waveColor.opacity(0.4), radius: 6)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .id("\(activeDisplayText)-\(floatingLyricFontDesign)-\(floatingLyricFontSize)")
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 4)),
                            removal: .opacity.combined(with: .offset(y: -4))
                        ))
                }
                .fixedSize(horizontal: true, vertical: false)

                FluidSilkWaveView(isPlaying: nowPlaying.isPlaying, color: waveColor)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 4.5)

        case .connectedChin:
            // Unified chin is integrated directly into the notch bar silhouette
            EmptyView()
        }
    }

    @ViewBuilder
    private var presetBackground: some View {
        switch activePreset {
        case .pureText:
            // Feather-soft ambient blur shadow for 100% legibility without visible container box
            Capsule()
                .fill(Color.black.opacity(isHovered ? 0.28 : 0.08))
                .blur(radius: isHovered ? 8 : 4)
                .background(Capsule().fill(Color.clear))

        case .capsule:
            // Solid black pill with neon gradient border
            Capsule()
                .fill(Color.black.opacity(0.96))
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.0, green: 0.96, blue: 0.83).opacity(isHovered ? 0.95 : 0.50),
                                    Color(red: 1.0, green: 0.16, blue: 0.53).opacity(isHovered ? 0.90 : 0.35)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1.0
                        )
                )
                .shadow(color: Color.black.opacity(0.92), radius: 8, x: 0, y: 4)
                .shadow(color: Color(red: 0.0, green: 0.96, blue: 0.83).opacity(isHovered ? 0.35 : 0.12), radius: 6, x: 0, y: 1)

        case .frostedGlass:
            // Apple-style translucent pill with hairline light border
            Capsule()
                .fill(Color.black.opacity(0.55))
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.38 : 0.22),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                )
                .shadow(color: Color.black.opacity(0.65), radius: 6, x: 0, y: 3)

        case .neonHud:
            // Cyberpunk HUD dark slate with neon teal border & glow
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: 0.04, green: 0.05, blue: 0.07).opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            Color(red: 0.0, green: 0.96, blue: 0.83).opacity(isHovered ? 0.85 : 0.45),
                            lineWidth: 0.75
                        )
                )
                .shadow(color: Color.black.opacity(0.9), radius: 6, x: 0, y: 3)
                .shadow(color: Color(red: 0.0, green: 0.96, blue: 0.83).opacity(isHovered ? 0.30 : 0.10), radius: 4, x: 0, y: 0)

        case .seamlessGlass:
            // Borderless translucent frosted blur pill (no stroke, pure subtle opacity)
            Capsule()
                .fill(Color.black.opacity(isHovered ? 0.45 : 0.32))
                .shadow(color: Color.black.opacity(0.40), radius: 6, x: 0, y: 2)

        case .retroPixel:
            // 8-bit stepped pixel box with theme color hairline stroke
            Rectangle()
                .fill(Color(red: 0.04, green: 0.05, blue: 0.07).opacity(0.95))
                .overlay(
                    Rectangle()
                        .stroke(
                            (MusicProgressColor(rawValue: musicHUDProgressColor) ?? .theme).color.opacity(isHovered ? 0.95 : 0.60),
                            lineWidth: 1.0
                        )
                )
                .shadow(color: Color.black.opacity(0.90), radius: 6, y: 3)

        case .liquidAurora:
            // Translucent glass capsule with animated liquid aurora glow
            TimelineView(.animation(minimumInterval: 0.04)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let shift = CGFloat(sin(t * 1.5) * 15.0)
                Capsule()
                    .fill(Color.black.opacity(0.75))
                    .overlay(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.0, green: 0.96, blue: 0.83).opacity(0.20),
                                        Color(red: 1.0, green: 0.16, blue: 0.53).opacity(0.18),
                                        Color(red: 0.58, green: 0.20, blue: 1.0).opacity(0.22)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .offset(x: shift)
                            .blur(radius: 6)
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isHovered ? 0.50 : 0.30),
                                        Color(red: 0.0, green: 0.96, blue: 0.83).opacity(isHovered ? 0.40 : 0.15)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(color: Color.black.opacity(0.85), radius: 8, y: 3)
            }

        case .minimalBraun:
            // Studio monitor matte graphite capsule with subtle specular edge
            Capsule()
                .fill(Color(red: 0.07, green: 0.08, blue: 0.09).opacity(0.96))
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.28 : 0.16),
                                    Color.white.opacity(0.04)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                )
                .shadow(color: Color.black.opacity(0.8), radius: 6, y: 2.5)

        case .tapeReel:
            // Chiseled matte charcoal aluminum chassis with amber phosphor rim
            let reelAmber = Color(red: 1.0, green: 0.68, blue: 0.10)
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(
                            reelAmber.opacity(isHovered ? 0.85 : 0.45),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: Color.black.opacity(0.9), radius: 7, y: 3)
                .shadow(color: reelAmber.opacity(isHovered ? 0.35 : 0.12), radius: 5)

        case .vinylGroove:
            // Vintage acoustic warm charcoal capsule with brass hairline
            Capsule()
                .fill(Color(red: 0.06, green: 0.06, blue: 0.08).opacity(0.96))
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.85, green: 0.72, blue: 0.50).opacity(isHovered ? 0.65 : 0.35),
                                    Color(red: 0.40, green: 0.35, blue: 0.25).opacity(0.20)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                )
                .shadow(color: Color.black.opacity(0.85), radius: 6, y: 3)

        case .fluidKaraoke:
            // VisionOS refractive specular glass capsule with soft chromatic fringe
            Capsule()
                .fill(Color.black.opacity(0.68))
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.55 : 0.32),
                                    Color(red: 0.0, green: 0.96, blue: 0.83).opacity(isHovered ? 0.45 : 0.20),
                                    Color(red: 1.0, green: 0.16, blue: 0.53).opacity(isHovered ? 0.35 : 0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.85
                        )
                )
                .shadow(color: Color.black.opacity(0.85), radius: 8, y: 3)

        case .connectedChin:
            EmptyView()
        }
    }

    var body: some View {
        Button(action: {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            onOpenFull()
        }) {
            presetContent
                .frame(width: capsuleWidth, height: 26)
                .background(presetBackground)
                .scaleEffect(isHovered ? 1.02 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            capsuleWidth = calculateTargetWidth(for: activeDisplayText, preset: activePreset)
        }
        .onChange(of: activeDisplayText) { _, newText in
            let target = calculateTargetWidth(for: newText, preset: activePreset)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
                capsuleWidth = target
            }
        }
        .onChange(of: floatingLyricPreset) { _, _ in
            let target = calculateTargetWidth(for: activeDisplayText, preset: activePreset)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
                capsuleWidth = target
            }
        }
        .onChange(of: floatingLyricFontSize) { _, _ in
            let target = calculateTargetWidth(for: activeDisplayText, preset: activePreset)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
                capsuleWidth = target
            }
        }
        .onChange(of: floatingLyricFontDesign) { _, _ in
            let target = calculateTargetWidth(for: activeDisplayText, preset: activePreset)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
                capsuleWidth = target
            }
        }
        .onChange(of: floatingLyricIconStyle) { _, _ in
            let target = calculateTargetWidth(for: activeDisplayText, preset: activePreset)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
                capsuleWidth = target
            }
        }
        .help("♫ Live Synced Lyrics [Style: \(activePreset.title)] (Click to open Music HUD)")
    }
}

// Backward compatibility aliases
typealias SubNotchIntegratedLyricChinView = SubNotchFloatingLyricCapsuleView
typealias SubNotchLyricCapsuleView = SubNotchFloatingLyricCapsuleView

// MARK: - Full Solid Lyric Line View (Immediate 100% line display, no staggered word popup)

struct KaraokeLyricLineView: View {
    let text: String
    let isCurrent: Bool
    let currentFraction: Double // 0.0 ... 1.0 (kept for backwards signature compatibility)
    let primaryColor: Color
    var fontSize: CGFloat = 10.0

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: isCurrent ? .bold : .medium, design: .rounded))
            .foregroundStyle(isCurrent ? Color.white : Color.white.opacity(0.40))
            .shadow(color: isCurrent ? primaryColor.opacity(0.65) : Color.clear, radius: isCurrent ? 3.5 : 0)
    }
}

// MARK: - Redesigned High-Taste Compact Music HUD View with Synced Lyrics

struct CyberMusicHUDView: View {
    @ObservedObject var nowPlaying: NowPlayingManager
    var appState: AppState
    @AppStorage(SettingsKey.musicHUDTheme) private var musicHUDTheme = SettingsDefaults.musicHUDTheme
    @AppStorage(SettingsKey.islandUITheme) private var islandUITheme = SettingsDefaults.islandUITheme

    init(nowPlaying: NowPlayingManager, appState: AppState) {
        self.nowPlaying = nowPlaying
        self.appState = appState
    }

    private var isRetroTheme: Bool {
        if islandUITheme == IslandUITheme.pixel.rawValue { return true }
        if islandUITheme == IslandUITheme.modern.rawValue { return false }
        return musicHUDTheme == MusicHUDTheme.retroCyber.rawValue
    }

    var body: some View {
        Group {
            if isRetroTheme {
                RetroCyberMusicHUDContentView(nowPlaying: nowPlaying, appState: appState)
            } else {
                ModernCleanMusicHUDContentView(nowPlaying: nowPlaying, appState: appState)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isRetroTheme)
    }
}

// MARK: - Modern Clean Dynamic Island Music HUD Theme (Apple Music / Spotify Partial Flow)

extension MusicProgressColor {
    @MainActor
    var color: Color {
        switch self {
        case .album:
            if NowPlayingManager.shared.isPlaying && NowPlayingManager.shared.artworkImage != nil {
                return NowPlayingManager.shared.albumPalette.primary
            }
            return Color(red: 0.0, green: 0.96, blue: 0.83)
        case .theme: return Color(red: 1.0, green: 0.65, blue: 0.45)
        case .white: return .white
        case .cyan: return Color(red: 0.0, green: 0.96, blue: 0.83)
        case .pink: return Color(red: 1.0, green: 0.16, blue: 0.53)
        case .green: return Color(red: 0.12, green: 0.84, blue: 0.38)
        case .amber: return Color(red: 1.0, green: 0.72, blue: 0.20)
        }
    }

    @MainActor
    var gradient: LinearGradient {
        switch self {
        case .album:
            if NowPlayingManager.shared.isPlaying && NowPlayingManager.shared.artworkImage != nil {
                return LinearGradient(
                    colors: [NowPlayingManager.shared.albumPalette.primary, NowPlayingManager.shared.albumPalette.secondary],
                    startPoint: .leading, endPoint: .trailing
                )
            }
            return LinearGradient(
                colors: [Color(red: 0.0, green: 0.96, blue: 0.83), Color(red: 0.0, green: 0.75, blue: 0.95)],
                startPoint: .leading, endPoint: .trailing
            )
        case .theme, .amber:
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.68, blue: 0.48), Color(red: 1.0, green: 0.58, blue: 0.38)],
                startPoint: .leading, endPoint: .trailing
            )
        case .white:
            return LinearGradient(
                colors: [Color.white, Color(white: 0.85)],
                startPoint: .leading, endPoint: .trailing
            )
        case .cyan:
            return LinearGradient(
                colors: [Color(red: 0.0, green: 0.96, blue: 0.83), Color(red: 0.0, green: 0.75, blue: 0.95)],
                startPoint: .leading, endPoint: .trailing
            )
        case .pink:
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.25, blue: 0.60), Color(red: 0.95, green: 0.10, blue: 0.45)],
                startPoint: .leading, endPoint: .trailing
            )
        case .green:
            return LinearGradient(
                colors: [Color(red: 0.15, green: 0.88, blue: 0.42), Color(red: 0.08, green: 0.72, blue: 0.30)],
                startPoint: .leading, endPoint: .trailing
            )
        }
    }
}

struct ModernCleanMusicHUDContentView: View {
    @ObservedObject var nowPlaying: NowPlayingManager
    var appState: AppState
    @AppStorage(SettingsKey.musicHUDProgressColor) private var musicHUDProgressColor = SettingsDefaults.musicHUDProgressColor
    @State private var dragPosition: Double?

    private var activeProgressGradient: LinearGradient {
        (MusicProgressColor(rawValue: musicHUDProgressColor) ?? .theme).gradient
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func formatRemainingTime(position: Double, duration: Double) -> String {
        guard duration > 0 else { return "-0:00" }
        let remaining = max(0.0, duration - position)
        let total = Int(remaining)
        let m = total / 60
        let s = total % 60
        return String(format: "-%d:%02d", m, s)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // LEFT BLOCK: Full Image on Left + Info & Controls Stack Beside It (250pt fixed width)
            HStack(alignment: .center, spacing: 12) {
                // 1. FULL ALBUM IMAGE (86x86 squircle - spans full vertical height)
                ZStack {
                    if let art = nowPlaying.artworkImage {
                        Image(nsImage: art)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 86, height: 86)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                            )
                            .shadow(color: Color.black.opacity(0.45), radius: 6, x: 0, y: 3)
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color(white: 0.16), Color(white: 0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 86, height: 86)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 26))
                                    .foregroundColor(Color.white.opacity(0.6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                            )
                    }
                }
                .id(nowPlaying.title + nowPlaying.artist)

                // 2. STACK BESIDE IMAGE (Title di atas, Scrubber di tengah, Tombol aksi di bawah terpusat horizontal)
                VStack(alignment: .leading, spacing: 0) {
                    // Di atas: Title song (Marquee scrolling jika panjang) & Artist
                    VStack(alignment: .leading, spacing: 2) {
                        ModernMarqueeText(
                            text: nowPlaying.title.isEmpty ? "No track" : nowPlaying.title,
                            font: .system(size: 13.5, weight: .bold, design: .rounded),
                            color: .white
                        )
                        .frame(height: 18)
                        .padding(.trailing, 10)
                        .id(nowPlaying.title)

                        Text(nowPlaying.artist.isEmpty ? "Idle" : nowPlaying.artist)
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.trailing, 10)
                    }

                    Spacer(minLength: 2)

                    // Di tengah: Scrubber Bar & Durasi (diberi padding kanan agar tidak mepet border)
                    // The position comes from the anchor; a local timeline at
                    // two ticks a second keeps the bar smooth without the
                    // manager publishing four times a second.
                    TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                    VStack(spacing: 2) {
                        GeometryReader { geo in
                            let totalWidth = geo.size.width
                            let effectivePosition = dragPosition ?? nowPlaying.position(at: timeline.date)
                            let progressFraction: CGFloat = nowPlaying.trackDuration > 0
                                ? min(1.0, max(0.0, CGFloat(effectivePosition / nowPlaying.trackDuration)))
                                : 0.0

                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.18))
                                    .frame(height: 3)

                                Capsule()
                                    .fill(activeProgressGradient)
                                    .frame(width: totalWidth * progressFraction, height: 3)
                            }
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard nowPlaying.trackDuration > 0 else { return }
                                        let fraction = min(1.0, max(0.0, value.location.x / totalWidth))
                                        dragPosition = Double(fraction) * nowPlaying.trackDuration
                                    }
                                    .onEnded { value in
                                        guard nowPlaying.trackDuration > 0 else {
                                            dragPosition = nil
                                            return
                                        }
                                        let fraction = min(1.0, max(0.0, value.location.x / totalWidth))
                                        let targetTime = Double(fraction) * nowPlaying.trackDuration
                                        dragPosition = nil
                                        nowPlaying.seek(to: targetTime)
                                    }
                            )
                        }
                        .frame(height: 3)

                        HStack {
                            let effectivePosition = dragPosition ?? nowPlaying.position(at: timeline.date)
                            Text(formatTime(effectivePosition))
                                .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.48))
                            Spacer()
                            Text(formatRemainingTime(position: effectivePosition, duration: nowPlaying.trackDuration))
                                .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.48))
                        }
                    }
                    .padding(.trailing, 10)
                    }

                    Spacer(minLength: 2)

                    // Di bawah: Tombol aksi (⏮, ▶/⏸, ⏭) & Modern Animated Spectrum
                    HStack(spacing: 14) {
                        Button(action: { nowPlaying.previousTrack() }) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.85))
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button(action: { nowPlaying.togglePlayPause() }) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 26, height: 26)
                                .overlay(
                                    Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color.black)
                                        .offset(x: nowPlaying.isPlaying ? 0 : 0.8)
                                )
                                .shadow(color: Color.white.opacity(0.22), radius: 3, y: 1)
                        }
                        .buttonStyle(.plain)

                        Button(action: { nowPlaying.nextTrack() }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.85))
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        // Modern dynamic dancing audio wave
                        ModernAudioSpectrumView(
                            barCount: 4,
                            isPlaying: nowPlaying.isPlaying,
                            barWidth: 2.2,
                            maxHeight: 12.0,
                            color: (MusicProgressColor(rawValue: musicHUDProgressColor) ?? .theme).color
                        )
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                    }
                    .frame(height: 26)
                }
                .frame(height: 86)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 6)
            }
            .frame(width: 255, alignment: .leading)

            // RIGHT COLUMN: Multi-Line Interactive Synced Lyrics (Seamless, Borderless, Scrollable)
            VStack(alignment: .leading, spacing: 0) {
                if nowPlaying.lyrics.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "music.quarternote.3")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.white.opacity(0.35))
                        Text(nowPlaying.lyricsLoading ? "Fetching lyrics..." : "No lyrics available")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.40))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(nowPlaying.lyrics) { line in
                                    let isCurrent = (line.id == nowPlaying.currentLyricIndex)
                                    ModernCleanLyricRowView(line: line, isCurrent: isCurrent) {
                                        nowPlaying.seek(to: line.timestamp)
                                    }
                                    .id(line.id)
                                }
                            }
                            .padding(.vertical, 22)
                            .padding(.trailing, 8)
                        }
                        .frame(height: 90)
                        .mask(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .black, location: 0.16),
                                    .init(color: .black, location: 0.84),
                                    .init(color: .clear, location: 1.0)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .onAppear {
                            proxy.scrollTo(nowPlaying.currentLyricIndex, anchor: .center)
                        }
                        .onChange(of: nowPlaying.currentLyricIndex) { _, newIndex in
                            withAnimation(.easeInOut(duration: 0.28)) {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.leading, 12)
        }
        .frame(height: 114)
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }
}

// MARK: - Modern Clean Lyric Row (Interactive, Clickable to Seek, Hover Feedback)

struct ModernCleanLyricRowView: View {
    let line: LyricLine
    let isCurrent: Bool
    let onTap: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Text(line.text)
            .font(.system(size: isCurrent ? 14.5 : 11, weight: isCurrent ? .bold : .medium, design: .rounded))
            .foregroundStyle(isCurrent ? Color.white : (isHovered ? Color.white.opacity(0.80) : Color.white.opacity(0.36)))
            .shadow(color: isCurrent ? Color.white.opacity(0.40) : Color.clear, radius: isCurrent ? 6 : 0)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .scaleEffect(isCurrent ? 1.01 : 1.0, anchor: .leading)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.20), value: isHovered)
            .animation(.easeInOut(duration: 0.25), value: isCurrent)
            .onHover { isHovered = $0 }
            .onTapGesture { onTap() }
    }
}

// MARK: - Retro Cyber Pixel Music HUD Theme (Preserved Classic - Seamless Frameless)

struct RetroCyberMusicHUDContentView: View {
    @ObservedObject var nowPlaying: NowPlayingManager
    var appState: AppState
    @AppStorage(SettingsKey.musicHUDProgressColor) private var musicHUDProgressColor = SettingsDefaults.musicHUDProgressColor
    @AppStorage(SettingsKey.syncThemeWithAlbumArt) private var syncThemeWithAlbumArt = SettingsDefaults.syncThemeWithAlbumArt
    @State private var dragPosition: Double?

    init(nowPlaying: NowPlayingManager, appState: AppState) {
        self.nowPlaying = nowPlaying
        self.appState = appState
    }

    private var activeProgressColor: Color {
        if (syncThemeWithAlbumArt || musicHUDProgressColor == "album") && nowPlaying.isPlaying && nowPlaying.artworkImage != nil {
            return nowPlaying.albumPalette.primary
        }
        let pc = MusicProgressColor(rawValue: musicHUDProgressColor) ?? .theme
        switch pc {
        case .album:
            if nowPlaying.isPlaying && nowPlaying.artworkImage != nil {
                return nowPlaying.albumPalette.primary
            }
            return Color(red: 0.0, green: 0.96, blue: 0.83)
        case .theme: return Color(red: 0.0, green: 0.96, blue: 0.83) // Iconic Cyber Cyan by default
        case .white: return .white
        case .cyan: return Color(red: 0.0, green: 0.96, blue: 0.83)
        case .pink: return Color(red: 1.0, green: 0.16, blue: 0.53)
        case .green: return Color(red: 0.12, green: 0.84, blue: 0.38)
        case .amber: return Color(red: 1.0, green: 0.72, blue: 0.20)
        }
    }

    private var activeProgressGradient: LinearGradient {
        if (syncThemeWithAlbumArt || musicHUDProgressColor == "album") && nowPlaying.isPlaying && nowPlaying.artworkImage != nil {
            return LinearGradient(
                colors: [nowPlaying.albumPalette.primary, nowPlaying.albumPalette.secondary],
                startPoint: .leading, endPoint: .trailing
            )
        }
        let pc = MusicProgressColor(rawValue: musicHUDProgressColor) ?? .theme
        switch pc {
        case .album:
            if nowPlaying.isPlaying && nowPlaying.artworkImage != nil {
                return LinearGradient(
                    colors: [nowPlaying.albumPalette.primary, nowPlaying.albumPalette.secondary],
                    startPoint: .leading, endPoint: .trailing
                )
            }
            return LinearGradient(
                colors: [Color(red: 0.0, green: 0.96, blue: 0.83), Color(red: 0.0, green: 0.75, blue: 0.95)],
                startPoint: .leading, endPoint: .trailing
            )
        case .theme:
            return LinearGradient(
                colors: [Color(red: 0.0, green: 0.96, blue: 0.83), Color(red: 0.0, green: 0.75, blue: 0.95)],
                startPoint: .leading, endPoint: .trailing
            )
        default:
            return pc.gradient
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // LEFT COLUMN: Retro 8-Bit Audio Deck
            VStack(alignment: .leading, spacing: 5) {
                // Deck Header: Title & Player source badge (clean, uncrowded)
                HStack(spacing: 6) {
                    PixelText(text: "AUDIO DECK", color: activeProgressColor, pixelSize: 1.1)
                    Spacer()
                    HStack(spacing: 3.5) {
                        Circle()
                            .fill(activeProgressColor)
                            .frame(width: 3.5, height: 3.5)
                            .opacity(nowPlaying.isPlaying ? 1.0 : 0.4)
                        Text(nowPlaying.player.isEmpty ? "SPOTIFY" : nowPlaying.player.uppercased())
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .pixel16Bevel(raised: false, cornerRadius: 2.5, fillColor: Pixel16Palette.slot)
                }

                // Track & Album Info (Clean, open layout)
                Button(action: { nowPlaying.activateCurrentPlayer() }) {
                    HStack(spacing: 8) {
                        // 16-Bit Recessed Cartridge Album Bay (44x44)
                        ZStack {
                            if let art = nowPlaying.artworkImage {
                                Image(nsImage: art)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 44, height: 44)
                                    .clipped()
                            } else {
                                Rectangle()
                                    .fill(Pixel16Palette.slot)
                                    .frame(width: 44, height: 44)
                                    .overlay(Image(systemName: "music.note").font(.system(size: 14)).foregroundColor(activeProgressColor))
                            }
                        }
                        .pixel16Bevel(raised: false, cornerRadius: 3.5, fillColor: Pixel16Palette.slot)
                        .id(nowPlaying.title + nowPlaying.artist)

                        // Title & Artist
                        VStack(alignment: .leading, spacing: 2) {
                            ModernMarqueeText(
                                text: nowPlaying.title.isEmpty ? "NO AUDIO" : nowPlaying.title,
                                font: .system(size: 11, weight: .bold, design: .monospaced),
                                color: .white
                            )
                            .frame(height: 15)
                            .id(nowPlaying.title)

                            Text(nowPlaying.artist.isEmpty ? "IDLE" : nowPlaying.artist)
                                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.60))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(nowPlaying.isBrowserJSHintVisible ? nowPlaying.browserJSHintText : "Click to focus active music player")

                // Segmented 8-Bit Pixel Scrubber
                TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                let totalSegments = 18
                let effectivePosition = dragPosition ?? nowPlaying.position(at: timeline.date)
                let progressFraction = nowPlaying.trackDuration > 0
                    ? min(1.0, max(0.0, effectivePosition / nowPlaying.trackDuration))
                    : 0.0
                let activeSegments = Int(progressFraction * Double(totalSegments))

                VStack(spacing: 2.5) {
                    GeometryReader { geo in
                        let segW = max(2.5, (geo.size.width - CGFloat(totalSegments - 1) * 2) / CGFloat(totalSegments))
                        HStack(spacing: 2) {
                            ForEach(0..<totalSegments, id: \.self) { idx in
                                Rectangle()
                                    .fill(idx < activeSegments ? activeProgressColor : (idx == activeSegments ? Color.white : Color.white.opacity(0.12)))
                                    .frame(width: segW, height: 4.5)
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard nowPlaying.trackDuration > 0 else { return }
                                    let fraction = min(1.0, max(0.0, Double(value.location.x / geo.size.width)))
                                    dragPosition = fraction * nowPlaying.trackDuration
                                }
                                .onEnded { value in
                                    guard nowPlaying.trackDuration > 0 else {
                                        dragPosition = nil
                                        return
                                    }
                                    let fraction = min(1.0, max(0.0, Double(value.location.x / geo.size.width)))
                                    let target = fraction * nowPlaying.trackDuration
                                    dragPosition = nil
                                    nowPlaying.seek(to: target)
                                }
                        )
                    }
                    .frame(height: 5)

                    HStack {
                        Text(formatTime(effectivePosition))
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(activeProgressColor.opacity(0.85))
                        Spacer()
                        Text("//")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.25))
                        Spacer()
                        Text(formatTime(nowPlaying.trackDuration))
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.50))
                    }
                }
                }

                // Transport Controls + STEREO EQUALIZER INTEGRATED SIDE-BY-SIDE
                HStack(spacing: 8) {
                    // Tactile 16-Bit Cyberdeck Transport Buttons
                    HStack(spacing: 4) {
                        Button(action: { nowPlaying.previousTrack() }) {
                            Text("◀◀")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.90))
                                .frame(width: 25, height: 18)
                                .pixel16Bevel(raised: true, cornerRadius: 2.5, fillColor: Pixel16Palette.surfaceRaised)
                        }
                        .buttonStyle(.plain)

                        Button(action: { nowPlaying.togglePlayPause() }) {
                            Text(nowPlaying.isPlaying ? "❚❚" : "▶")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(activeProgressColor)
                                .frame(width: 29, height: 18)
                                .pixel16Bevel(raised: true, cornerRadius: 2.5, fillColor: activeProgressColor.opacity(0.22))
                        }
                        .buttonStyle(.plain)

                        Button(action: { nowPlaying.nextTrack() }) {
                            Text("▶▶")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.90))
                                .frame(width: 25, height: 18)
                                .pixel16Bevel(raised: true, cornerRadius: 2.5, fillColor: Pixel16Palette.surfaceRaised)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // THE 16-BIT EQUALIZER - Integrated in recessed bay beside controls
                    HStack(spacing: 2) {
                        CyberDiscoVisualizer(
                            isPlaying: nowPlaying.isPlaying,
                            barCount: 8,
                            maxHeight: 14,
                            palette: RetroSpectrumPalette.forThemeKey(musicHUDProgressColor)
                        )
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .pixel16Bevel(raised: false, cornerRadius: 2.5, fillColor: Pixel16Palette.slot)
                }
            }
            .frame(width: 255, alignment: .leading)

            // RIGHT COLUMN: Retro CRT Lyrics (Seamless, Borderless, Floating Stream)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    PixelText(text: "LYRICS", color: activeProgressColor, pixelSize: 1.1)
                    Spacer()
                    if nowPlaying.lyricsLoading {
                        Text("LOADING...")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(activeProgressColor.opacity(0.7))
                    } else if !nowPlaying.lyrics.isEmpty {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(activeProgressColor)
                                .frame(width: 3.5, height: 3.5)
                            Text("SYNCED")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundStyle(activeProgressColor)
                        }
                    }
                }

                // Borderless, Floating Synced Lyrics Stream
                if nowPlaying.lyrics.isEmpty {
                    VStack(spacing: 4) {
                        Spacer()
                        Text(nowPlaying.lyricsLoading ? "[ SCANNING MATRIX... ]" : "[ NO LYRIC FEED ]")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.40))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(nowPlaying.lyrics) { line in
                                    let isCurrent = (line.id == nowPlaying.currentLyricIndex)
                                    HStack(alignment: .top, spacing: 5) {
                                        Text(isCurrent ? "▶" : " ")
                                            .font(.system(size: 10, weight: .black, design: .monospaced))
                                            .foregroundStyle(activeProgressColor)
                                        Text(line.text)
                                            .font(.system(size: isCurrent ? 11.5 : 9.5, weight: isCurrent ? .bold : .medium, design: .monospaced))
                                            .foregroundStyle(isCurrent ? activeProgressColor : Color.white.opacity(0.42))
                                            .shadow(color: isCurrent ? activeProgressColor.opacity(0.65) : Color.clear, radius: 5)
                                            .lineLimit(2)
                                    }
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1.5)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        nowPlaying.seek(to: line.timestamp)
                                    }
                                    .id(line.id)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .frame(height: 84)
                        .mask(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .black, location: 0.18),
                                    .init(color: .black, location: 0.82),
                                    .init(color: .clear, location: 1.0)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .onAppear {
                            proxy.scrollTo(nowPlaying.currentLyricIndex, anchor: .center)
                        }
                        .onChange(of: nowPlaying.currentLyricIndex) { _, newIndex in
                            withAnimation(.easeInOut(duration: 0.22)) {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
        }
        .frame(height: 114)
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }
}

// MARK: - Machined Token Usage Badge (Kept for Agent View)

struct MachinedTokenBadge: View {
    var appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    private var tokenSnapshot: ClaudeUsageTotals? {
        appState.claudeUsage?.today
    }

    private var totalTokens: Int {
        guard let s = tokenSnapshot else { return 0 }
        return s.inputTokens + s.outputTokens + s.cacheCreationTokens + s.cacheReadTokens
    }

    private var tokenLabel: String {
        if totalTokens > 0 {
            return ClaudeUsageScanner.formatTokens(totalTokens)
        }
        let totalToolCalls = appState.sessions.values.reduce(0) { $0 + $1.totalToolCallCount }
        if totalToolCalls > 0 {
            return "\(totalToolCalls) ops"
        }
        return "0k"
    }

    var body: some View {
        HStack(spacing: 3) {
            Text("⚡")
                .font(.system(size: 8))
                .foregroundColor(Color(red: 0.0, green: 0.96, blue: 0.83))
            Text(tokenLabel)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(red: 0.92, green: 0.94, blue: 0.98))
            Text("TOK")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(Color(white: 0.45))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: 0.07, green: 0.08, blue: 0.11))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(red: 0.16, green: 0.19, blue: 0.25), lineWidth: 0.75)
                )
        )
    }
}

// MARK: - Compatibility Aliases
typealias CyberMusicNotificationBanner = CyberMusicMiniPeekBanner
