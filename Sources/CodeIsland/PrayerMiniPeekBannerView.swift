import SwiftUI
import CodeIslandCore

/// Interactive Mini Peek Toast Banner that gently rolls down from under the notch
/// upon approaching prayer time (T <= 10m) or when prayer time arrives.
/// Supports both Pixel Retro (8-Bit) and Modern Clean themes with direct micro-actions (Open Tab, Snooze 5m, Dismiss).
public struct PrayerMiniPeekBannerView: View {
    @ObservedObject var manager: PrayerTimeManager
    var onOpenFull: () -> Void

    @AppStorage(SettingsKey.islandUITheme) private var islandUITheme = SettingsDefaults.islandUITheme
    @State private var isHovering = false
    @State private var hoveredButton: String? = nil

    private var isPixel: Bool {
        islandUITheme == IslandUITheme.pixel.rawValue
    }

    public init(manager: PrayerTimeManager, onOpenFull: @escaping () -> Void) {
        self.manager = manager
        self.onOpenFull = onOpenFull
    }

    public var body: some View {
        Group {
            if isPixel {
                pixelBanner
            } else {
                modernBanner
            }
        }
        .onHover { isHovering = $0 }
    }

    // MARK: - 1. Pixel Retro (8-Bit) Banner (Lineless Impeccable)

    private var pixelBanner: some View {
        HStack(spacing: 9) {
            // Recessed Crescent / Moon Slot
            ZStack {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))
                    .shadow(color: Color(red: 0.0, green: 0.96, blue: 0.83).opacity(0.8), radius: 3)
            }
            .frame(width: 26, height: 26)
            .pixel16Bevel(raised: false, cornerRadius: 4.5, fillColor: Pixel16Palette.slot)

            // Text Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(manager.miniPeekBannerTitle.uppercased())
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)

                    if manager.upcomingPrayer != nil {
                        let diffMins = manager.minutesUntilNextPrayer
                        Text(diffMins <= 0 ? "NOW" : "-\(diffMins)M")
                            .font(.system(size: 7.5, weight: .black, design: .monospaced))
                            .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1.5)
                            .pixel16Bevel(raised: false, cornerRadius: 2.5, fillColor: Pixel16Palette.slot)
                    }
                }

                Text(manager.miniPeekBannerSubtitle.uppercased())
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Pixel16Palette.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Interactive Actions Strip (Lineless Tactile Buttons)
            HStack(spacing: 4.5) {
                // Open Tab Button
                Button(action: {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    onOpenFull()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 8, weight: .bold))
                        Text("OPEN")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3.5)
                    .pixel16Bevel(raised: true, cornerRadius: 3.5, fillColor: hoveredButton == "open" ? Pixel16Palette.surfaceRaised : Pixel16Palette.slot)
                    .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))
                }
                .buttonStyle(.plain)
                .onHover { if $0 { hoveredButton = "open" } else if hoveredButton == "open" { hoveredButton = nil } }
                .help("Open Prayer Tab")

                // Snooze 5m Button
                Button(action: {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    manager.snoozeMiniPeekBanner(minutes: 5)
                }) {
                    Text("+5M")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3.5)
                        .pixel16Bevel(raised: true, cornerRadius: 3.5, fillColor: hoveredButton == "snooze" ? Pixel16Palette.surfaceRaised : Pixel16Palette.slot)
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .onHover { if $0 { hoveredButton = "snooze" } else if hoveredButton == "snooze" { hoveredButton = nil } }
                .help("Snooze reminder 5 minutes")

                // Dismiss Button
                Button(action: {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        manager.dismissMiniPeekBanner()
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(Color.white.opacity(hoveredButton == "dismiss" ? 1.0 : 0.45))
                        .frame(width: 16, height: 16)
                        .pixel16Bevel(raised: false, cornerRadius: 3.5, fillColor: hoveredButton == "dismiss" ? Pixel16Palette.surfaceRaised : Color.clear)
                }
                .buttonStyle(.plain)
                .onHover { if $0 { hoveredButton = "dismiss" } else if hoveredButton == "dismiss" { hoveredButton = nil } }
                .help("Dismiss reminder")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .pixel16Bevel(raised: false, cornerRadius: 8, fillColor: Pixel16Palette.chassis)
        .padding(.horizontal, 8)
        .padding(.bottom, 5)
    }

    // MARK: - 2. Modern Clean Banner

    private var modernBanner: some View {
        HStack(spacing: 8) {
            // Phase / Prayer Icon Capsule
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(manager.currentPhase.accentColor.opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: manager.currentPhase.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(manager.currentPhase.accentColor)
            }

            // Announcement text
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(manager.miniPeekBannerTitle)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if manager.upcomingPrayer != nil {
                        let diffMins = manager.minutesUntilNextPrayer
                        Text(diffMins <= 0 ? "NOW" : "-\(diffMins)m")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule()
                                    .fill(manager.currentPhase.accentColor.opacity(0.25))
                            )
                            .foregroundStyle(manager.currentPhase.accentColor)
                    }
                }

                Text(manager.miniPeekBannerSubtitle)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Modern Interactive Action Strip
            HStack(spacing: 4) {
                // Open Tab Button
                Button(action: {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    onOpenFull()
                }) {
                    Text("Open")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule()
                                .fill(manager.currentPhase.accentColor.opacity(hoveredButton == "open" ? 0.45 : 0.25))
                                .overlay(Capsule().stroke(manager.currentPhase.accentColor.opacity(0.6), lineWidth: 0.6))
                        )
                }
                .buttonStyle(.plain)
                .onHover { if $0 { hoveredButton = "open" } else if hoveredButton == "open" { hoveredButton = nil } }

                // Snooze 5m Button
                Button(action: {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    manager.snoozeMiniPeekBanner(minutes: 5)
                }) {
                    Text("+5m")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(hoveredButton == "snooze" ? 0.16 : 0.08))
                                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)
                .onHover { if $0 { hoveredButton = "snooze" } else if hoveredButton == "snooze" { hoveredButton = nil } }
                .help("Snooze 5 minutes")

                // Dismiss Button
                Button(action: {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        manager.dismissMiniPeekBanner()
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Color.white.opacity(hoveredButton == "dismiss" ? 0.9 : 0.45))
                        .frame(width: 16, height: 16)
                        .background(
                            Circle()
                                .fill(hoveredButton == "dismiss" ? Color.white.opacity(0.15) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { if $0 { hoveredButton = "dismiss" } else if hoveredButton == "dismiss" { hoveredButton = nil } }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 5)
    }
}
