import SwiftUI
import AppKit

public enum ThemePreset: String, CaseIterable, Identifiable, Sendable {
    case neonTokyo = "neonTokyo"
    case matrixTerminal = "matrixTerminal"
    case amber1984 = "amber1984"
    case midnightSynth = "midnightSynth"
    case monochromePro = "monochromePro"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .neonTokyo: return "Neon Tokyo (Hot Pink & Electric Cyan)"
        case .matrixTerminal: return "Matrix Terminal (Phosphor Green)"
        case .amber1984: return "Amber 1984 (Retro Monochrome CRT)"
        case .midnightSynth: return "Midnight Synth (Deep Violet & Ice Blue)"
        case .monochromePro: return "Monochrome Pro (Clean White / Slate)"
        }
    }

    public var shortTag: String {
        switch self {
        case .neonTokyo: return "TOKYO"
        case .matrixTerminal: return "MATRIX"
        case .amber1984: return "AMBER"
        case .midnightSynth: return "SYNTH"
        case .monochromePro: return "MONO"
        }
    }

    public var primaryAccent: Color {
        switch self {
        case .neonTokyo: return Color(red: 0.0, green: 0.96, blue: 0.83)        // Electric Cyan #00F5D4
        case .matrixTerminal: return Color(red: 0.0, green: 0.90, blue: 0.46)   // Matrix Green #00E676
        case .amber1984: return Color(red: 1.0, green: 0.69, blue: 0.0)         // Amber #FFB000
        case .midnightSynth: return Color(red: 0.69, green: 0.15, blue: 1.0)     // Violet #B026FF
        case .monochromePro: return Color.white                                  // Crisp White
        }
    }

    public var secondaryAccent: Color {
        switch self {
        case .neonTokyo: return Color(red: 1.0, green: 0.16, blue: 0.53)        // Cyber Pink #FF2987
        case .matrixTerminal: return Color(red: 0.2, green: 1.0, blue: 0.6)     // Light Mint
        case .amber1984: return Color(red: 1.0, green: 0.45, blue: 0.0)         // Dark Amber #FF7300
        case .midnightSynth: return Color(red: 0.0, green: 0.82, blue: 1.0)     // Ice Blue #00D2FF
        case .monochromePro: return Color(white: 0.75)                           // Silver Slate
        }
    }

    public var cardBorderColor: Color {
        switch self {
        case .neonTokyo: return Color(red: 0.0, green: 0.96, blue: 0.83).opacity(0.35)
        case .matrixTerminal: return Color(red: 0.0, green: 0.90, blue: 0.46).opacity(0.35)
        case .amber1984: return Color(red: 1.0, green: 0.69, blue: 0.0).opacity(0.35)
        case .midnightSynth: return Color(red: 0.69, green: 0.15, blue: 1.0).opacity(0.35)
        case .monochromePro: return Color.white.opacity(0.25)
        }
    }

    public var glowColor: Color {
        switch self {
        case .neonTokyo: return Color(red: 0.0, green: 0.96, blue: 0.83).opacity(0.6)
        case .matrixTerminal: return Color(red: 0.0, green: 0.90, blue: 0.46).opacity(0.6)
        case .amber1984: return Color(red: 1.0, green: 0.69, blue: 0.0).opacity(0.6)
        case .midnightSynth: return Color(red: 0.69, green: 0.15, blue: 1.0).opacity(0.6)
        case .monochromePro: return Color.white.opacity(0.4)
        }
    }
}

@MainActor
public final class ThemeManager: ObservableObject {
    public static let shared = ThemeManager()

    @AppStorage("themePreset") public var currentPresetRaw: String = ThemePreset.neonTokyo.rawValue {
        didSet {
            objectWillChange.send()
        }
    }

    public var current: ThemePreset {
        ThemePreset(rawValue: currentPresetRaw) ?? .neonTokyo
    }

    private init() {}
}
