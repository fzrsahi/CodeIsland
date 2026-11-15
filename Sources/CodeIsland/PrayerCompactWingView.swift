import SwiftUI
import CodeIslandCore

/// The frameless compact pill right-wing component displaying the living diorama clock,
/// solar progress strip, and smart prayer countdown.
/// Completely horizontal, single-line guaranteed, supporting authentic 16-Bit Pixel Retro and Modern Clean themes.
public struct PrayerCompactWingView: View {
    @ObservedObject var manager = PrayerTimeManager.shared
    var isHovered: Bool = false
    var onExpand: (() -> Void)? = nil

    @AppStorage(SettingsKey.islandUITheme) private var islandUITheme = SettingsDefaults.islandUITheme
    @State private var localHover: Bool = false

    private var isPixel: Bool {
        islandUITheme == IslandUITheme.pixel.rawValue
    }

    private var effectiveHover: Bool {
        isHovered || localHover
    }

    public init(isHovered: Bool = false, onExpand: (() -> Void)? = nil) {
        self.isHovered = isHovered
        self.onExpand = onExpand
    }

    public var body: some View {
        Group {
            if isPixel {
                pixelContent
            } else {
                modernContent
            }
        }
        .contentShape(Rectangle())
        .onHover { localHover = $0 }
        .onTapGesture {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            onExpand?()
        }
        .help(helpTooltip)
    }

    // MARK: - 1. Pixel Retro (16-Bit Cyber) Mini Widget

    @ViewBuilder
    private var pixelContent: some View {
        let diffMins = manager.minutesUntilNextPrayer
        let isUrgent = diffMins <= 15
        let accentColor = isUrgent ? Pixel16Palette.amber : Pixel16Palette.cyan

        HStack(alignment: .center, spacing: 4.5) {
            // 16-bit Phase Icon with subtle glow
            Image(systemName: manager.currentPhase.systemImage)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(accentColor)
                .shadow(color: accentColor.opacity(effectiveHover ? 0.75 : 0.35), radius: 2)

            if let next = manager.upcomingPrayer {
                // Single line: e.g. [MAGHRIB -12M] or [MAGHRIB NOW]
                let prayerName = next.prayer.displayName.uppercased()
                let timeTag = diffMins <= 0 ? "NOW" : "-\(diffMins)M"
                let fullLabel = "\(prayerName) \(timeTag)"

                PixelText(
                    text: fullLabel,
                    color: accentColor,
                    pixelSize: 1.05
                )

                if effectiveHover {
                    PixelText(
                        text: "▸",
                        color: accentColor,
                        pixelSize: 1.0
                    )
                }
            } else {
                // Standby clock in pixel
                TimelineView(.periodic(from: .now, by: 10.0)) { _ in
                    PixelText(
                        text: manager.currentTimeString,
                        color: Pixel16Palette.textWhite,
                        pixelSize: 1.05
                    )
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(accentColor.opacity(effectiveHover ? 0.16 : 0.08))
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - 2. Modern Clean (Glass Pill) Mini Widget

    @ViewBuilder
    private var modernContent: some View {
        let diffMins = manager.minutesUntilNextPrayer
        let isUrgent = diffMins <= 15
        let accentColor = isUrgent ? Color(red: 1.0, green: 0.72, blue: 0.20) : manager.currentPhase.accentColor

        HStack(alignment: .center, spacing: 5) {
            Image(systemName: manager.currentPhase.systemImage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(accentColor)

            if let next = manager.upcomingPrayer {
                HStack(spacing: 3) {
                    Text(next.prayer.displayName)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(1)

                    Text(diffMins <= 0 ? "NOW" : "-\(diffMins)m")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundStyle(accentColor)
                        .lineLimit(1)
                }
            } else {
                Text(manager.currentTimeString)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 6.5)
        .padding(.vertical, 2.5)
        .background(
            Capsule()
                .fill(Color.white.opacity(effectiveHover ? 0.12 : 0.06))
                .overlay(Capsule().strokeBorder(accentColor.opacity(effectiveHover ? 0.45 : 0.18), lineWidth: 0.5))
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    private var helpTooltip: String {
        if let next = manager.upcomingPrayer {
            let diff = manager.minutesUntilNextPrayer
            let status = diff <= 0 ? "Time for \(next.prayer.displayName)" : "\(diff)m until \(next.prayer.displayName)"
            return "\(status) (Click to expand Prayer tab)"
        }
        return "Prayer Times & Living Diorama (Click to expand)"
    }
}
