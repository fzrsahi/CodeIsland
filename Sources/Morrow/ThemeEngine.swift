import AppKit
import SwiftUI

/// Unified Color Theme accessor for CodeIsland
public enum AppColorTheme {
    @MainActor
    public static func accent(for colorKey: String, isModern: Bool = false) -> Color {
        let syncAlbum = UserDefaults.standard.bool(forKey: SettingsKey.syncThemeWithAlbumArt)
        let pc = MusicProgressColor(rawValue: colorKey) ?? .theme
        if (syncAlbum || pc == .album)
            && NowPlayingManager.shared.isPlaying
            && NowPlayingManager.shared.artworkImage != nil {
            return NowPlayingManager.shared.albumPalette.primary
        }

        switch pc {
        case .album:
            return isModern ? .white : Color(red: 0.0, green: 0.96, blue: 0.83)
        case .theme:
            return isModern ? .white : Color(red: 0.0, green: 0.96, blue: 0.83)
        case .white: return .white
        case .cyan: return Color(red: 0.0, green: 0.96, blue: 0.83)
        case .pink: return Color(red: 1.0, green: 0.16, blue: 0.53)
        case .green: return Color(red: 0.12, green: 0.84, blue: 0.38)
        case .amber: return Color(red: 1.0, green: 0.72, blue: 0.20)
        }
    }

    /// Computes WCAG relative luminance (0.0 = black, 1.0 = white) in sRGB space.
    nonisolated public static func relativeLuminance(of color: Color) -> CGFloat {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        func linearize(_ c: CGFloat) -> CGFloat {
            let clamped = min(max(c, 0), 1)
            return clamped <= 0.03928 ? (clamped / 12.92) : pow((clamped + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    /// Returns true when the background color is bright/light-gray enough that white foreground loses legibility.
    nonisolated public static func isLightColor(_ color: Color, threshold: CGFloat = 0.34) -> Bool {
        relativeLuminance(of: color) > threshold
    }

    /// Returns dark charcoal ink on light/white/light-gray accents, and crisp white on dark/saturated accents.
    nonisolated public static func contrastingForeground(on background: Color) -> Color {
        isLightColor(background) ? Color(red: 0.07, green: 0.08, blue: 0.11) : .white
    }

    /// Darkens bright/white/light-gray accents so envelope creases and seals remain sharp on white paper envelopes.
    nonisolated public static func envelopeAccentStroke(for accent: Color) -> Color {
        guard relativeLuminance(of: accent) > 0.50 else { return accent }
        let nsColor = NSColor(accent).usingColorSpace(.sRGB) ?? NSColor(accent)
        var hue: CGFloat = 0
        var sat: CGFloat = 0
        var bri: CGFloat = 0
        var alpha: CGFloat = 1
        nsColor.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)

        if sat < 0.14 {
            return Color(red: 0.22, green: 0.25, blue: 0.31)
        }
        return Color(
            hue: Double(hue),
            saturation: Double(min(1.0, max(sat, 0.45))),
            brightness: Double(min(bri, 0.52))
        )
    }
}
