import SwiftUI
import CodeIslandCore

/// The frameless compact pill right-wing component displaying the living diorama clock,
/// solar progress strip, and smart prayer countdown. Supports Pixel Retro and Modern Clean themes.
public struct PrayerCompactWingView: View {
    @ObservedObject var manager = PrayerTimeManager.shared
    var isHovered: Bool = false
    var onExpand: (() -> Void)? = nil

    @AppStorage(SettingsKey.islandUITheme) private var islandUITheme = SettingsDefaults.islandUITheme

    private var isPixel: Bool {
        islandUITheme == IslandUITheme.pixel.rawValue
    }

    public init(isHovered: Bool = false, onExpand: (() -> Void)? = nil) {
        self.isHovered = isHovered
        self.onExpand = onExpand
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 5) {
            // Phase icon
            Image(systemName: manager.currentPhase.systemImage)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(isPixel ? Color(red: 0.12, green: 0.84, blue: 0.38) : manager.currentPhase.accentColor)

            // Current timestamp
            Text(manager.currentTimeString)
                .font(.system(size: 11, weight: .bold, design: isPixel ? .monospaced : .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .monospacedDigit()

            // Next Prayer Countdown
            if let next = manager.upcomingPrayer {
                let diffMins = manager.minutesUntilNextPrayer
                HStack(spacing: 2) {
                    Text(next.prayer.displayName)
                        .font(.system(size: 8, weight: .semibold, design: isPixel ? .monospaced : .rounded))
                    Text(diffMins <= 0 ? "Now" : "-\(diffMins)m")
                        .font(.system(size: 8, weight: .bold, design: isPixel ? .monospaced : .rounded))
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(
                    Group {
                        if isPixel {
                            Rectangle()
                                .fill(Color(red: 0.12, green: 0.84, blue: 0.38).opacity(diffMins <= 15 ? 0.3 : 0.15))
                        } else {
                            Capsule()
                                .fill(manager.currentPhase.accentColor.opacity(diffMins <= 15 ? 0.25 : 0.12))
                        }
                    }
                )
                .foregroundStyle(isPixel ? Color(red: 0.12, green: 0.84, blue: 0.38) : (diffMins <= 15 ? manager.currentPhase.accentColor : Color.white.opacity(0.8)))
            }

            // Solar Progress Horizon Strip
            ZStack(alignment: .leading) {
                if isPixel {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 30, height: 3)

                    Rectangle()
                        .fill(Color(red: 0.12, green: 0.84, blue: 0.38))
                        .frame(width: max(3, 30 * CGFloat(manager.solarProgress)), height: 3)
                } else {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 32, height: 2.5)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [manager.currentPhase.accentColor.opacity(0.4), manager.currentPhase.accentColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(3, 32 * CGFloat(manager.solarProgress)), height: 2.5)

                    Circle()
                        .fill(manager.currentPhase.accentColor)
                        .frame(width: 4, height: 4)
                        .offset(x: max(0, min(28, 32 * CGFloat(manager.solarProgress) - 2)))
                }
            }
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onExpand?()
        }
    }
}
