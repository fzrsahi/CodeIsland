import SwiftUI
import AppKit
import AudioToolbox
import CodeIslandCore

public enum SoundPack: String, CaseIterable, Identifiable, Sendable {
    case retro8Bit = "retro8Bit"
    case cyberpunk = "cyberpunk"
    case macintosh1984 = "macintosh1984"
    case sciFiHud = "sciFiHud"
    case mechanical = "mechanical"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .retro8Bit: return "8-Bit Arcade (Classic Bleeps)"
        case .cyberpunk: return "Cyberpunk 2077 (Neon Tech)"
        case .macintosh1984: return "Macintosh 1984 (Classic Chimes)"
        case .sciFiHud: return "Sci-Fi HUD (Subtle Telemetry)"
        case .mechanical: return "Mechanical Switch (Clicky Keystrokes)"
        }
    }

    public var description: String {
        switch self {
        case .retro8Bit: return "Authentic 8-bit square wave audio cues for tasks and agent events."
        case .cyberpunk: return "Futuristic synthesizer tones and sharp electronic pings."
        case .macintosh1984: return "Nostalgic retro Mac chimes (Sosumi, Hero, Glass)."
        case .sciFiHud: return "Ultra-clean high-frequency holographic interface blips."
        case .mechanical: return "Tactile mechanical keyboard clicks and switch pops."
        }
    }
}

@MainActor
public final class SoundPackManager: ObservableObject {
    public static let shared = SoundPackManager()

    @AppStorage("activeSoundPack") public var currentPackRaw: String = SoundPack.retro8Bit.rawValue {
        didSet {
            objectWillChange.send()
        }
    }

    public var currentPack: SoundPack {
        SoundPack(rawValue: currentPackRaw) ?? .retro8Bit
    }

    private init() {}

    /// Play an event sound adapted to the current sound pack
    public func play(event: String) {
        guard UserDefaults.standard.bool(forKey: SettingsKey.soundEnabled) else { return }

        switch currentPack {
        case .retro8Bit:
            // Handled by original 8bit WAV files in SoundManager
            SoundManager.shared.handleEvent(event)

        case .cyberpunk:
            playCyberpunkSound(event: event)

        case .macintosh1984:
            playMacintoshSound(event: event)

        case .sciFiHud:
            playSciFiSound(event: event)

        case .mechanical:
            playMechanicalSound(event: event)
        }
    }

    public func preview(pack: SoundPack) {
        let prev = currentPackRaw
        currentPackRaw = pack.rawValue
        play(event: "TaskRoundComplete")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.currentPackRaw = prev
        }
    }

    // MARK: - Specialized Pack Audio Routers

    private func playCyberpunkSound(event: String) {
        switch event {
        case "SessionStart":
            NSSound(named: "Funk")?.play()
        case "TaskRoundComplete", "Stop":
            NSSound(named: "Glass")?.play()
        case "PermissionRequest":
            NSSound(named: "Submarine")?.play()
        default:
            NSSound(named: "Tink")?.play()
        }
    }

    private func playMacintoshSound(event: String) {
        switch event {
        case "SessionStart":
            NSSound(named: "Hero")?.play()
        case "TaskRoundComplete", "Stop":
            NSSound(named: "Sosumi")?.play()
        case "PermissionRequest":
            NSSound(named: "Basso")?.play()
        default:
            NSSound(named: "Pop")?.play()
        }
    }

    private func playSciFiSound(event: String) {
        switch event {
        case "SessionStart":
            NSSound(named: "Morse")?.play()
        case "TaskRoundComplete", "Stop":
            NSSound(named: "Ping")?.play()
        case "PermissionRequest":
            NSSound(named: "Blow")?.play()
        default:
            NSSound(named: "Tink")?.play()
        }
    }

    private func playMechanicalSound(event: String) {
        switch event {
        case "PermissionRequest":
            NSSound(named: "Purr")?.play()
        default:
            NSSound(named: "Pop")?.play()
        }
    }
}
