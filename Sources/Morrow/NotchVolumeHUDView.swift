import SwiftUI
import AppKit

struct NotchVolumeHUDView: View {
    @ObservedObject var volumeManager: SystemVolumeManager = .shared
    @AppStorage(SettingsKey.musicHUDProgressColor) private var musicHUDProgressColor = SettingsDefaults.musicHUDProgressColor
    @AppStorage(SettingsKey.islandUITheme) private var islandUITheme = SettingsDefaults.islandUITheme

    private var isPixel: Bool {
        islandUITheme == IslandUITheme.pixel.rawValue
    }

    private var activeProgressColor: Color {
        (MusicProgressColor(rawValue: musicHUDProgressColor) ?? .theme).color
    }

    private var activeProgressGradient: LinearGradient {
        (MusicProgressColor(rawValue: musicHUDProgressColor) ?? .theme).gradient
    }

    private var speakerIconName: String {
        if volumeManager.isMuted {
            return "speaker.slash.fill"
        }
        switch volumeManager.volume {
        case ...0.001:
            return "speaker.fill"
        case ..<0.33:
            return "speaker.wave.1.fill"
        case ..<0.66:
            return "speaker.wave.2.fill"
        default:
            return "speaker.wave.3.fill"
        }
    }

    private var speakerIconColor: Color {
        if volumeManager.isMuted {
            return Color(red: 1.0, green: 0.28, blue: 0.38)
        }
        switch volumeManager.volume {
        case ...0.001:
            return Color.white.opacity(0.5)
        default:
            return activeProgressColor
        }
    }

    private var percentageText: String {
        if volumeManager.isMuted {
            return "MUTE"
        } else {
            return String(format: "%d%%", Int(round(volumeManager.volume * 100)))
        }
    }

    var body: some View {
        Button(action: { volumeManager.toggleMute() }) {
            Group {
                if isPixel {
                    pixelVolumeHUD
                } else {
                    modernVolumeHUD
                }
            }
        }
        .buttonStyle(.plain)
        .help("Click to toggle mute")
    }

    // MARK: - 1. Pixel Retro 16-Bit Hi-Fi Meter HUD (Lineless)

    private var pixelVolumeHUD: some View {
        let totalBlocks = 12
        let filledBlocks = volumeManager.isMuted ? 0 : max(0, min(totalBlocks, Int(round(Double(volumeManager.volume) * Double(totalBlocks)))))

        return HStack(spacing: 8) {
            // Recessed Speaker Icon Slot
            ZStack {
                Image(systemName: speakerIconName)
                    .font(.system(size: 9.5, weight: .black))
                    .foregroundStyle(speakerIconColor)
            }
            .frame(width: 20, height: 20)
            .pixel16Bevel(raised: false, cornerRadius: 3.5, fillColor: Pixel16Palette.slot)

            // 12-Segment Discrete Solid Hi-Fi LED Meter (Lineless)
            HStack(spacing: 2) {
                ForEach(0..<totalBlocks, id: \.self) { idx in
                    let isFilled = idx < filledBlocks
                    let blockColor: Color = {
                        if idx >= 10 {
                            return Pixel16Palette.red // High volume peak
                        } else if idx >= 8 {
                            return Pixel16Palette.amber // Mid-high warning
                        } else {
                            return activeProgressColor // Safe active range
                        }
                    }()

                    Rectangle()
                        .fill(isFilled ? blockColor : Color.white.opacity(0.12))
                        .frame(width: 5, height: 9.5)
                }
            }
            .padding(.horizontal, 4.5)
            .padding(.vertical, 3)
            .pixel16Bevel(raised: false, cornerRadius: 3, fillColor: Pixel16Palette.slot)

            // Monospace Readout
            Text(percentageText)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(volumeManager.isMuted ? Pixel16Palette.red : Pixel16Palette.textWhite)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .pixel16Bevel(raised: false, cornerRadius: 6, fillColor: Pixel16Palette.surface)
        .shadow(color: Color.black.opacity(0.5), radius: 4, y: 2)
    }

    // MARK: - 2. Modern Clean Dynamic Island Fluid Volume HUD

    private var modernVolumeHUD: some View {
        HStack(spacing: 8) {
            // Dynamic speaker icon
            Image(systemName: speakerIconName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(speakerIconColor)
                .frame(width: 14)

            // Theme-aligned volume progress bar
            GeometryReader { geo in
                let totalWidth = geo.size.width
                let fillWidth = volumeManager.isMuted ? 0 : totalWidth * CGFloat(volumeManager.volume)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 4.5)

                    Capsule()
                        .fill(activeProgressGradient)
                        .frame(width: max(0, min(totalWidth, fillWidth)), height: 4.5)
                        .shadow(color: activeProgressColor.opacity(0.5), radius: 2)
                }
            }
            .frame(width: 95, height: 4.5)

            // Volume percentage readout
            Text(percentageText)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(white: 0.08).opacity(0.94))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.45), radius: 6, y: 3)
        )
    }
}
