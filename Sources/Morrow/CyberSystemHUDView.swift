import SwiftUI
import AppKit
import MorrowCore

// MARK: - MagSafe Charging Dynamic Island Banner

public struct MagSafeChargingBanner: View {
    let batteryLevel: Int
    var displayMode: IslandDisplayMode = .notch
    var onDismiss: (() -> Void)? = nil
    @AppStorage(SettingsKey.islandUITheme) private var islandUITheme = SettingsDefaults.islandUITheme
    @State private var pulseRing = false
    @State private var pixelPulse = false

    private var isPixel: Bool {
        islandUITheme == IslandUITheme.pixel.rawValue
    }

    public init(batteryLevel: Int, displayMode: IslandDisplayMode = .notch, onDismiss: (() -> Void)? = nil) {
        self.batteryLevel = batteryLevel
        self.displayMode = displayMode
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
            if displayMode == .dynamicIsland {
                dynamicIslandFlushBanner
            } else if isPixel {
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

    /// Flush full-pill MagSafe toast endorsed in Round 2 (@agungdunggio): zero nested gray card border.
    private var dynamicIslandFlushBanner: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(chargingGreen.opacity(0.20))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .strokeBorder(chargingGreen.opacity(0.45), lineWidth: 1)
                    )

                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 0.29, green: 0.87, blue: 0.50))
                    .scaleEffect(pulseRing ? 1.08 : 0.96)
            }

            Text("MagSafe Charging")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text("\(batteryLevel)%")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 0.29, green: 0.87, blue: 0.50))
        }
        .padding(.leading, 8)
        .padding(.trailing, 15)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture {
            if let onDismiss {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                onDismiss()
            }
        }
        .help("MagSafe Charging — Click to dismiss")
    }

    // MARK: - 1. Pixel Retro 16-Bit Cyber Cartridge Banner (Impeccable Lineless)

    private var pixelChargingBanner: some View {
        HStack(spacing: 8) {
            // Recessed Energy Core Slot
            ZStack {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(chargingGreen)
                    .shadow(color: chargingGreen.opacity(0.85), radius: 3)
                    .scaleEffect(pixelPulse ? 1.1 : 0.95)
            }
            .frame(width: 22, height: 22)
            .pixel16Bevel(raised: false, cornerRadius: 3.5, fillColor: Pixel16Palette.slot)

            Text("MAGSAFE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white)
                .lineLimit(1)

            Spacer(minLength: 8)

            // Percentage & 5-Segment Discrete Solid Charge Meter
            HStack(spacing: 5) {
                Text("\(batteryLevel)%")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.white)

                // 5-Segment discrete solid charge bar
                HStack(spacing: 1.5) {
                    ForEach(0..<5, id: \.self) { idx in
                        let isFilled = batteryLevel >= (idx * 20 + 10)
                        Rectangle()
                            .fill(isFilled ? chargingGreen : Color.white.opacity(0.12))
                            .frame(width: 3, height: 7)
                    }
                }
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .pixel16Bevel(raised: false, cornerRadius: 2, fillColor: Pixel16Palette.slot)
            }

            if let onDismiss = onDismiss {
                Button(action: {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    onDismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .pixel16Bevel(raised: false, cornerRadius: 6, fillColor: Pixel16Palette.chassis)
        .padding(.horizontal, 6)
        .padding(.bottom, 3)
    }

    // MARK: - 2. Modern Clean Dynamic Island Fluid Glass Banner

    private var modernChargingBanner: some View {
        HStack(spacing: 8) {
            // Glowing MagSafe Energy Puck
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1.8)
                    .frame(width: 22, height: 22)

                Circle()
                    .trim(from: 0.0, to: max(0.08, CGFloat(batteryLevel) / 100.0))
                    .stroke(chargingGreen, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .frame(width: 22, height: 22)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: chargingGreen.opacity(0.4), radius: 2)

                Image(systemName: "bolt.fill")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(chargingGreen)
                    .scaleEffect(pulseRing ? 1.1 : 0.95)
            }

            Text("MagSafe")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Text("\(batteryLevel)%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                // Mini hardware battery indicator
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                        .frame(width: 16, height: 8)

                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(chargingGreen)
                        .frame(width: max(2, 12 * CGFloat(batteryLevel) / 100.0), height: 4.8)
                        .padding(.leading, 1.6)
                }
            }

            if let onDismiss = onDismiss {
                Button(action: {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    onDismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
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
