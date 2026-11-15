import SwiftUI
import CodeIslandCore

/// Minimalist, Impeccable Mini Peek Notification Banner for Prayer times.
/// Single-line ultra-clean Dynamic Island design.
public struct PrayerMiniPeekBannerView: View {
    @ObservedObject var manager: PrayerTimeManager
    var onOpenFull: () -> Void

    @AppStorage(SettingsKey.islandUITheme) private var islandUITheme = SettingsDefaults.islandUITheme

    private var isPixel: Bool {
        islandUITheme == IslandUITheme.pixel.rawValue
    }

    public init(manager: PrayerTimeManager, onOpenFull: @escaping () -> Void) {
        self.manager = manager
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
            return "NOW"
        }
        return "-\(diff)M"
    }

    private var prayerTimeString: String {
        if let next = manager.upcomingPrayer {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: next.date)
        }
        return manager.currentTimeString
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
    }

    // MARK: - 1. Pixel Retro Single-Line Minimalist Banner

    private var pixelBanner: some View {
        HStack(spacing: 8) {
            // Recessed Celestial Slot
            ZStack {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))
                    .shadow(color: Color(red: 0.0, green: 0.96, blue: 0.83).opacity(0.85), radius: 3)
            }
            .frame(width: 22, height: 22)
            .pixel16Bevel(raised: false, cornerRadius: 3.5, fillColor: Pixel16Palette.slot)

            // Prayer Name
            Text(prayerName.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white)
                .lineLimit(1)

            Spacer(minLength: 8)

            // Status Badge & Time
            HStack(spacing: 4.5) {
                Text(statusBadge)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .pixel16Bevel(raised: false, cornerRadius: 2, fillColor: Pixel16Palette.slot)

                Text(prayerTimeString)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Pixel16Palette.textMuted)
            }

            // Minimal dismiss button
            Button(action: {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    manager.dismissMiniPeekBanner()
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .pixel16Bevel(raised: false, cornerRadius: 6, fillColor: Pixel16Palette.chassis)
        .padding(.horizontal, 6)
        .padding(.bottom, 3)
    }

    // MARK: - 2. Modern Clean Single-Line Minimalist Banner

    private var modernBanner: some View {
        HStack(spacing: 8) {
            // Phase icon capsule
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(manager.currentPhase.accentColor.opacity(0.18))
                    .frame(width: 22, height: 22)
                Image(systemName: manager.currentPhase.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(manager.currentPhase.accentColor)
            }

            Text(prayerName)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 8)

            HStack(spacing: 4.5) {
                Text(statusBadge)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .padding(.horizontal, 4.5)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule()
                            .fill(manager.currentPhase.accentColor.opacity(0.25))
                    )
                    .foregroundStyle(manager.currentPhase.accentColor)

                Text(prayerTimeString)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
            }

            // Minimal dismiss button
            Button(action: {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    manager.dismissMiniPeekBanner()
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
                )
        )
        .padding(.horizontal, 6)
        .padding(.bottom, 3)
    }
}
