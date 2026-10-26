import SwiftUI
import AppKit

// MARK: - MagSafe Charging Dynamic Island Banner

public struct MagSafeChargingBanner: View {
    let batteryLevel: Int
    @State private var pulseRing = false

    public init(batteryLevel: Int) {
        self.batteryLevel = batteryLevel
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Glowing MagSafe Energy Ring
            ZStack {
                Circle()
                    .stroke(Color(red: 0.0, green: 0.90, blue: 0.46).opacity(0.3), lineWidth: 3)
                    .frame(width: 22, height: 22)

                Circle()
                    .trim(from: 0.0, to: CGFloat(batteryLevel) / 100.0)
                    .stroke(Color(red: 0.0, green: 0.90, blue: 0.46), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 22, height: 22)
                    .rotationEffect(.degrees(-90))

                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 0.0, green: 0.90, blue: 0.46))
                    .scaleEffect(pulseRing ? 1.15 : 0.9)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseRing = true
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("MAGSAFE CONNECTED")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.0, green: 0.90, blue: 0.46))

                    Text("\(batteryLevel)%")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                }

                Text("Fast Charging Active")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.65))
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: 0.04, green: 0.08, blue: 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(red: 0.0, green: 0.90, blue: 0.46).opacity(0.5), lineWidth: 1)
                )
        )
        .shadow(color: Color(red: 0.0, green: 0.90, blue: 0.46).opacity(0.3), radius: 8, y: 2)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}

// MARK: - Compact Cyber System Telemetry Gauge Bar

public struct CyberSystemGaugeBar: View {
    @ObservedObject private var sys = SystemMonitorManager.shared

    public init() {}

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
    }
}
