import SwiftUI
import AppKit

// MARK: - MagSafe Charging Dynamic Island Banner

public struct MagSafeChargingBanner: View {
    let batteryLevel: Int
    var onDismiss: (() -> Void)? = nil
    @AppStorage(SettingsKey.islandUITheme) private var islandUITheme = SettingsDefaults.islandUITheme
    @State private var pulseRing = false
    @State private var pixelPulse = false

    private var isPixel: Bool {
        islandUITheme == IslandUITheme.pixel.rawValue
    }

    public init(batteryLevel: Int, onDismiss: (() -> Void)? = nil) {
        self.batteryLevel = batteryLevel
        self.onDismiss = onDismiss
    }

    private var chargingGreen: Color {
        Color(red: 0.19, green: 0.82, blue: 0.35) // Apple MagSafe Emerald (#30D158)
    }

    private var cyberCyan: Color {
        Color(red: 0.0, green: 0.96, blue: 0.83) // Cyberpunk Neon Cyan
    }

    public var body: some View {
        Group {
            if isPixel {
                pixelChargingBanner
            } else {
                modernChargingBanner
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                pulseRing = true
            }
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                pixelPulse = true
            }
        }
    }

    // MARK: - 1. Pixel Retro 16-Bit Cyber Cartridge Banner (Impeccable Lineless)

    private var pixelChargingBanner: some View {
        let filledBlocks = max(1, min(10, Int(ceil(Double(batteryLevel) / 10.0))))

        return HStack(spacing: 10) {
            // Recessed Energy Core Slot
            ZStack {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(chargingGreen)
                    .shadow(color: chargingGreen.opacity(0.85), radius: 3)
                    .scaleEffect(pixelPulse ? 1.15 : 0.95)
            }
            .frame(width: 26, height: 26)
            .pixel16Bevel(raised: false, cornerRadius: 4.5, fillColor: Pixel16Palette.slot)

            // Monospace Dot-Matrix Telemetry
            VStack(alignment: .leading, spacing: 2.5) {
                HStack(spacing: 5) {
                    Text("POWER: AC_CONNECTED")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Pixel16Palette.cyan)

                    Text(batteryLevel >= 100 ? "FULL" : "CHARGING")
                        .font(.system(size: 7.5, weight: .black, design: .monospaced))
                        .foregroundStyle(chargingGreen)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1.5)
                        .pixel16Bevel(raised: false, cornerRadius: 2.5, fillColor: Pixel16Palette.slot)
                }

                Text(batteryLevel >= 100 ? "BATTERY FULL // TRICKLE_MODE" : "FAST_CHARGE // STATUS: OPTIMAL")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Pixel16Palette.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            // 10-Segment Lineless Solid LED Battery Cells & Readout
            VStack(alignment: .trailing, spacing: 3.5) {
                Text("\(batteryLevel)%")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(Pixel16Palette.textWhite)

                // 10-Segment Discrete Solid Blocks (No wireframe outlines)
                HStack(spacing: 2) {
                    ForEach(0..<10, id: \.self) { idx in
                        let isFilled = idx < filledBlocks
                        let isHead = idx == (filledBlocks - 1)
                        Rectangle()
                            .fill(
                                isFilled
                                    ? (isHead && pixelPulse ? Pixel16Palette.cyan : chargingGreen)
                                    : Color.white.opacity(0.12)
                            )
                            .frame(width: 3.5, height: 7)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2.5)
                .pixel16Bevel(raised: false, cornerRadius: 3, fillColor: Pixel16Palette.slot)
            }

            if let onDismiss = onDismiss {
                Button(action: {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    onDismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .frame(width: 16, height: 16)
                        .pixel16Bevel(raised: false, cornerRadius: 3.5, fillColor: Pixel16Palette.slot)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .pixel16Bevel(raised: false, cornerRadius: 8, fillColor: Pixel16Palette.chassis)
        .padding(.horizontal, 8)
        .padding(.bottom, 5)
    }

    // MARK: - 2. Modern Clean Dynamic Island Fluid Glass Banner

    private var modernChargingBanner: some View {
        HStack(spacing: 11) {
            // Glowing MagSafe Energy Puck
            ZStack {
                // Background Track
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 2.6)
                    .frame(width: 26, height: 26)

                // Dynamic Charge Progress Arc
                Circle()
                    .trim(from: 0.0, to: max(0.06, CGFloat(batteryLevel) / 100.0))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                chargingGreen.opacity(0.7),
                                chargingGreen
                            ]),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 2.6, lineCap: .round)
                    )
                    .frame(width: 26, height: 26)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: chargingGreen.opacity(0.45), radius: 3)

                // Center Pulsing Bolt
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(chargingGreen)
                    .scaleEffect(pulseRing ? 1.12 : 0.92)
            }

            // Power Details
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4.5) {
                    Text("MAGSAFE")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .tracking(0.6)

                    Text("•")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.28))

                    Text("CHARGING")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundStyle(chargingGreen)
                        .tracking(0.5)
                }

                Text(batteryLevel >= 100 ? "Battery Fully Charged" : "Fast Power Delivery Connected")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
            }

            Spacer(minLength: 8)

            // Battery Percentage & Hardware Capsule
            HStack(spacing: 5.5) {
                Text("\(batteryLevel)%")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)

                // Mini Hardware Battery Indicator
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.9)
                        .frame(width: 19, height: 9.5)

                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(chargingGreen)
                        .frame(width: max(2, 15 * CGFloat(batteryLevel) / 100.0), height: 5.5)
                        .padding(.leading, 2)
                }
            }

            if let onDismiss = onDismiss {
                Button(action: {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    onDismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.55))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 5)
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
