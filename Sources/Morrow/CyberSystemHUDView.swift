import SwiftUI
import AppKit
import MorrowCore

// MARK: - MagSafe & Power Charging Dynamic Island Banner

public struct MagSafeChargingBanner: View {
    let batteryLevel: Int
    var displayMode: IslandDisplayMode = .notch
    var powerState: PowerBannerState? = nil
    var onDismiss: (() -> Void)? = nil
    @ObservedObject private var sys = SystemMonitorManager.shared
    @AppStorage(SettingsKey.islandUITheme) private var islandUITheme = SettingsDefaults.islandUITheme
    @State private var pulseRing = false
    @State private var isHovered = false

    private var isPixel: Bool {
        islandUITheme == IslandUITheme.pixel.rawValue
    }

    public init(
        batteryLevel: Int,
        displayMode: IslandDisplayMode = .notch,
        powerState: PowerBannerState? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.batteryLevel = batteryLevel
        self.displayMode = displayMode
        self.powerState = powerState
        self.onDismiss = onDismiss
    }

    private var effectiveState: PowerBannerState {
        powerState ?? sys.activeBannerState
    }

    private var effectiveBattery: Int {
        sys.showChargingBanner ? sys.activeBannerBatteryLevel : batteryLevel
    }

    private var stateColor: Color {
        switch effectiveState {
        case .charging, .fullyCharged:
            return Color(red: 0.19, green: 0.82, blue: 0.35) // Apple Emerald (#30D158)
        case .chargingOnHold:
            return Color(red: 1.0, green: 0.72, blue: 0.20) // Warm Amber
        case .lowBattery:
            return Color(red: 1.0, green: 0.27, blue: 0.23) // Alert Red (#FF453A)
        }
    }

    private var modernIconName: String {
        switch effectiveState {
        case .charging, .lowBattery: return "bolt.fill"
        case .chargingOnHold: return "pause.fill"
        case .fullyCharged: return "checkmark"
        }
    }

    private var pixelGlyph: PixelIconGlyph {
        switch effectiveState {
        case .charging, .lowBattery: return .bolt
        case .chargingOnHold: return .pause
        case .fullyCharged: return .checkmark
        }
    }

    public var body: some View {
        Group {
            if isPixel {
                pixelChargingBanner
            } else {
                modernChargingBanner
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                pulseRing = true
            }
        }
    }

    // MARK: - 1. Pixel 32-Bit Power Banner (Smooth Pixel Ring + Bolt Left, PixelText, % Right)

    private var pixelChargingBanner: some View {
        let pct = max(0.06, min(1.0, Double(effectiveBattery) / 100.0))

        return HStack(spacing: 14) {
            ZStack {
                Canvas { ctx, size in
                    let cx = size.width / 2
                    let cy = size.height / 2
                    let radius: CGFloat = 17.0
                    let steps = 72
                    for i in 0..<steps {
                        let t = Double(i) / Double(steps)
                        let angle = t * Double.pi * 2.0 - Double.pi / 2.0
                        let px = (cx + cos(angle) * radius).rounded()
                        let py = (cy + sin(angle) * radius).rounded()
                        let rect = CGRect(x: px - 1.25, y: py - 1.25, width: 2.5, height: 2.5)
                        if t <= pct {
                            ctx.fill(Path(rect), with: .color(stateColor))
                        } else {
                            ctx.fill(Path(rect), with: .color(Color.white.opacity(0.14)))
                        }
                    }
                }
                .frame(width: 44, height: 44)

                PixelIcon(glyph: pixelGlyph, color: .white, pixelSize: 1.55)
                    .scaleEffect(pulseRing ? 1.06 : 0.96)
            }

            VStack(alignment: .leading, spacing: 4) {
                PixelText(text: effectiveState.title.uppercased(), color: .white, pixelSize: 1.55)
                Text(effectiveState.subtitle)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                PixelText(text: "\(effectiveBattery)%", color: .white, pixelSize: 2.4)

                if let onDismiss, isHovered {
                    dismissButton(onDismiss: onDismiss)
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, displayMode == .dynamicIsland ? 22 : 18)
        .padding(.vertical, displayMode == .dynamicIsland ? 12 : 10)
    }

    // MARK: - 2. Modern Clean Dynamic Island Banner (Ref #3: Ring + Bolt Left, 2-Line Stack, Hero % Right)

    private var modernChargingBanner: some View {
        let pct = max(0.06, min(1.0, CGFloat(effectiveBattery) / 100.0))

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(stateColor.opacity(0.22), lineWidth: 5.0)
                    .frame(width: 42, height: 42)

                Circle()
                    .trim(from: 0.0, to: pct)
                    .stroke(stateColor, style: StrokeStyle(lineWidth: 5.0, lineCap: .round))
                    .frame(width: 42, height: 42)
                    .rotationEffect(.degrees(-90))

                Image(systemName: modernIconName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(pulseRing ? 1.06 : 0.96)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(effectiveState.title)
                    .font(.system(size: 16.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(effectiveState.subtitle)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.56))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Text("\(effectiveBattery)%")
                    .font(.system(size: 25, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                if let onDismiss, isHovered {
                    dismissButton(onDismiss: onDismiss)
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, displayMode == .dynamicIsland ? 22 : 18)
        .padding(.vertical, displayMode == .dynamicIsland ? 12 : 10)
    }

    private func dismissButton(onDismiss: @escaping () -> Void) -> some View {
        Button(action: {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            onDismiss()
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

// MARK: - Compact Cyber System Telemetry Gauge Bar

public struct CyberSystemGaugeBar: View {
    @ObservedObject private var sys = SystemMonitorManager.shared

    public init() {}

    /// Sampling runs only while this gauge is on screen: appearing starts it,
    /// disappearing (the Workspace tab closing) stops it.
    private struct SamplingLifecycle: ViewModifier {
        func body(content: Content) -> some View {
            content
                .onAppear { SystemMonitorManager.shared.beginSampling() }
                .onDisappear { SystemMonitorManager.shared.endSampling() }
        }
    }

    public var body: some View {
        let m = sys.metrics
        HStack(spacing: 8) {
            // CPU
            HStack(spacing: 3) {
                Image(systemName: "cpu")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(m.cpuUsagePercent > 75 ? Color(red: 1.0, green: 0.16, blue: 0.53) : Color(red: 0.0, green: 0.96, blue: 0.83))
                Text(String(format: "%.0f%%", m.cpuUsagePercent))
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white)
            }

            // RAM
            HStack(spacing: 3) {
                Image(systemName: "memorychip")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color(red: 0.0, green: 0.90, blue: 0.46))
                Text(String(format: "%.1fG", m.memoryUsedGB))
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.9))
            }

            // Network Speed
            HStack(spacing: 3) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.6))
                Text(SystemMonitorManager.formatSpeed(m.downloadBytesPerSec))
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))
            }

            // Battery
            HStack(spacing: 2) {
                Image(systemName: m.isCharging ? "battery.100.bolt" : "battery.75")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(m.isCharging ? Color(red: 0.0, green: 0.90, blue: 0.46) : Color.white.opacity(0.8))
                Text("\(m.batteryLevel)%")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(
            RoundedRectangle(cornerRadius: 3.5)
                .fill(Color(white: 0.08))
                .overlay(RoundedRectangle(cornerRadius: 3.5).stroke(Color(white: 0.16), lineWidth: 0.6))
        )
        .modifier(SamplingLifecycle())
    }
}
