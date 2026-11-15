import SwiftUI
import CodeIslandCore

/// Minimalist, Impeccable Mini Peek Notification Banner for Prayer times.
/// Gently rolls down under the notch when approaching prayer (T <= 10m) or when prayer time arrives.
public struct PrayerMiniPeekBannerView: View {
    @ObservedObject var manager: PrayerTimeManager
    var onOpenFull: () -> Void

    @AppStorage(SettingsKey.islandUITheme) private var islandUITheme = SettingsDefaults.islandUITheme
    @State private var isHovering = false

    private var isPixel: Bool {
        islandUITheme == IslandUITheme.pixel.rawValue
    }

    public init(manager: PrayerTimeManager, onOpenFull: @escaping () -> Void) {
        self.manager = manager
        self.onOpenFull = onOpenFull
    }

    private var prayerDisplayName: String {
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

    private var prayerSubtitle: String {
        if let next = manager.upcomingPrayer {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let timeStr = formatter.string(from: next.date)
            return "\(timeStr) · Waktu Salat"
        }
        if !manager.miniPeekBannerSubtitle.isEmpty {
            return manager.miniPeekBannerSubtitle
        }
        return "Waktu Salat Tiba"
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
        .onHover { isHovering = $0 }
    }

    // MARK: - 1. Pixel Retro Minimalist Banner (Lineless Impeccable)

    private var pixelBanner: some View {
        HStack(spacing: 8) {
            // Recessed Celestial Slot
            ZStack {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))
                    .shadow(color: Color(red: 0.0, green: 0.96, blue: 0.83).opacity(0.85), radius: 3)
            }
            .frame(width: 24, height: 24)
            .pixel16Bevel(raised: false, cornerRadius: 4, fillColor: Pixel16Palette.slot)

            // Minimalist Prayer Name & Subtitle
            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 4.5) {
                    Text(prayerDisplayName.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)

                    Text(statusBadge)
                        .font(.system(size: 7.5, weight: .black, design: .monospaced))
                        .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .pixel16Bevel(raised: false, cornerRadius: 2, fillColor: Pixel16Palette.slot)
                }

                Text(prayerSubtitle.uppercased())
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Pixel16Palette.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            // Minimal dismiss button
            Button(action: {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    manager.dismissMiniPeekBanner()
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5.5)
        .pixel16Bevel(raised: false, cornerRadius: 7, fillColor: Pixel16Palette.chassis)
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
    }

    // MARK: - 2. Modern Clean Minimalist Banner

    private var modernBanner: some View {
        HStack(spacing: 8) {
            // Phase icon capsule
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(manager.currentPhase.accentColor.opacity(0.18))
                    .frame(width: 24, height: 24)
                Image(systemName: manager.currentPhase.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(manager.currentPhase.accentColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4.5) {
                    Text(prayerDisplayName)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(statusBadge)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(manager.currentPhase.accentColor.opacity(0.25))
                        )
                        .foregroundStyle(manager.currentPhase.accentColor)
                }

                Text(prayerSubtitle)
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            // Minimal dismiss button
            Button(action: {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    manager.dismissMiniPeekBanner()
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5.5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
                )
        )
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
    }
}
