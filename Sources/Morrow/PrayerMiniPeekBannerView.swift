import SwiftUI
import MorrowCore

/// Minimalist, Impeccable Mini Peek Notification Banner for Prayer times.
/// Seamless notch-integrated 3-line Dynamic Island design with Modern Clean & Pixel 32-bit parity.
public struct PrayerMiniPeekBannerView: View {
    @ObservedObject var manager: PrayerTimeManager
    var displayMode: IslandDisplayMode = .notch
    var onOpenFull: () -> Void

    @ObservedObject private var nowPlaying = NowPlayingManager.shared
    @AppStorage(SettingsKey.islandUITheme) private var islandUITheme = SettingsDefaults.islandUITheme
    @AppStorage(SettingsKey.musicHUDProgressColor) private var musicHUDProgressColor = SettingsDefaults.musicHUDProgressColor
    @AppStorage(SettingsKey.syncThemeWithAlbumArt) private var syncThemeWithAlbumArt = SettingsDefaults.syncThemeWithAlbumArt
    @State private var isHovered = false

    private var isPixel: Bool {
        islandUITheme == IslandUITheme.pixel.rawValue
    }

    private var pixelAccent: Color {
        _ = syncThemeWithAlbumArt
        _ = nowPlaying.albumPalette
        return AppColorTheme.readableOnDark(
            AppColorTheme.accent(for: musicHUDProgressColor, isModern: false)
        )
    }

    public init(manager: PrayerTimeManager, displayMode: IslandDisplayMode = .notch, onOpenFull: @escaping () -> Void) {
        self.manager = manager
        self.displayMode = displayMode
        self.onOpenFull = onOpenFull
    }

    private var prayerName: String {
        if let next = manager.upcomingPrayer {
            return next.prayer.displayName
        }
        let lower = manager.miniPeekBannerTitle.lowercased()
        for prayer in PrayerType.allCases {
            if lower.contains(prayer.rawValue) {
                return prayer.displayName
            }
        }
        return "Maghrib"
    }

    private var statusBadge: String {
        let diff = manager.minutesUntilNextPrayer
        if diff <= 0 {
            return isPixel ? "NOW" : "now"
        }
        return isPixel ? "-\(diff)M" : "-\(diff)m"
    }

    private var prayerTimeString: String {
        if let next = manager.upcomingPrayer {
            return manager.formattedPrayerTime(next.date)
        }
        return manager.currentTimeString
    }

    private var subtitleLine: String {
        let sub = manager.miniPeekBannerSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sub.isEmpty {
            return sub
        }
        let diff = manager.minutesUntilNextPrayer
        if diff <= 0 {
            return "Prayer time at \(prayerTimeString)"
        }
        return "Adhan at \(prayerTimeString) · \(manager.currentPhase.displayName)"
    }

    private var titleLine: String {
        let diff = manager.minutesUntilNextPrayer
        if diff > 0 {
            return "\(prayerName) in \(diff) min"
        }
        return prayerName
    }

    public var body: some View {
        Button(action: {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            onOpenFull()
        }) {
            Group {
                if isPixel {
                    pixelBanner
                } else {
                    modernBanner
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    // MARK: - 1. Pixel 32-Bit Clean 3-Line Banner (No Brackets, PixelText, Adaptive Color)

    private var pixelBanner: some View {
        HStack(spacing: 14) {
            ZStack {
                PixelIcon(glyph: .prayer, color: pixelAccent, pixelSize: 2.3)
            }
            .frame(width: 44, height: 44)
            .pixel16Bevel(raised: false, cornerRadius: 6, fillColor: Pixel16Palette.slot)

            VStack(alignment: .leading, spacing: 3.5) {
                HStack(alignment: .center, spacing: 8) {
                    PixelText(
                        text: "PRAYER · \(manager.cityName.uppercased())",
                        color: Color.white.opacity(0.58),
                        pixelSize: 1.15
                    )

                    Spacer(minLength: 8)

                    PixelText(
                        text: statusBadge,
                        color: pixelAccent,
                        pixelSize: 1.2
                    )
                }

                PixelText(
                    text: titleLine.uppercased(),
                    color: .white,
                    pixelSize: 1.55
                )

                Text(subtitleLine)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .lineLimit(1)
            }

            if isHovered {
                dismissButton
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, displayMode == .dynamicIsland ? 22 : 18)
        .padding(.vertical, displayMode == .dynamicIsland ? 12 : 10)
    }

    // MARK: - 2. Modern Clean Notch-Integrated 3-Line Banner (Ref #2)

    private var modernBanner: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(manager.currentPhase.accentColor)
                    .frame(width: 44, height: 44)

                Image(systemName: manager.currentPhase.systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Prayer · \(manager.cityName)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.56))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(statusBadge)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.52))
                }

                Text(titleLine)
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(subtitleLine)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .lineLimit(1)
            }

            if isHovered {
                dismissButton
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, displayMode == .dynamicIsland ? 22 : 18)
        .padding(.vertical, displayMode == .dynamicIsland ? 12 : 10)
    }

    private var dismissButton: some View {
        Button(action: {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                manager.dismissMiniPeekBanner()
            }
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .help("Dismiss")
    }
}
