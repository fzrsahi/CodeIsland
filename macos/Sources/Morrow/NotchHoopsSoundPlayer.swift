import AppKit
import MorrowCore

/// Lean, zero-asset 8-bit arcade SFX synthesizer for Notch Hoops.
/// Generates tiny in-memory PCM WAV buffers lazily on first play (~20 KB total)
/// and plays them through `NSSound` with zero background audio engine overhead.
@MainActor
final class NotchHoopsSoundPlayer {
    static let shared = NotchHoopsSoundPlayer()

    private var cache: [NotchHoopsEngine.SoundEvent: Data] = [:]

    private init() {}

    func play(_ event: NotchHoopsEngine.SoundEvent) {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: SettingsKey.notchHoopsSoundEnabled) as? Bool
            ?? SettingsDefaults.notchHoopsSoundEnabled
        guard enabled else { return }

        let volumePercent = defaults.object(forKey: SettingsKey.soundVolume) as? Int
            ?? SettingsDefaults.soundVolume
        let amplitude = SoundVolumeCurve.amplitude(forPercent: volumePercent)
        guard amplitude > 0 else { return }

        let wav = wavData(for: event)
        guard let sound = NSSound(data: wav) else { return }
        sound.volume = amplitude
        sound.play()
    }

    func wavData(for event: NotchHoopsEngine.SoundEvent) -> Data {
        if let cached = cache[event] { return cached }
        let data = Self.synthesizeWAV(for: event)
        cache[event] = data
        return data
    }

    private static func synthesizeWAV(for event: NotchHoopsEngine.SoundEvent) -> Data {
        switch event {
        case .launch:
            return buildSweepWAV(duration: 0.065, startHz: 260, endHz: 620, gain: 0.45, square: false)
        case .rimOrBackboard:
            return buildSweepWAV(duration: 0.055, startHz: 220, endHz: 110, gain: 0.55, square: true)
        case .bounce:
            return buildSweepWAV(duration: 0.045, startHz: 150, endHz: 72, gain: 0.48, square: false)
        case .score(isSwish: true):
            return buildNotesWAV(notes: [(523.25, 0.055), (659.25, 0.055), (783.99, 0.09)], gain: 0.65)
        case .score(isSwish: false):
            return buildNotesWAV(notes: [(493.88, 0.06), (659.25, 0.085)], gain: 0.60)
        case .miss:
            return buildSweepWAV(duration: 0.11, startHz: 210, endHz: 120, gain: 0.42, square: true)
        case .gameOver:
            return buildNotesWAV(notes: [(392.0, 0.075), (329.63, 0.075), (261.63, 0.12)], gain: 0.55)
        }
    }

    private static func buildSweepWAV(duration: Double, startHz: Double, endHz: Double, gain: Double, square: Bool) -> Data {
        let sampleRate = 22_050
        let count = max(1, Int(Double(sampleRate) * duration))
        var samples = [UInt8](repeating: 128, count: count)
        var phase = 0.0
        for i in 0..<count {
            let t = Double(i) / Double(count)
            let freq = startHz + (endHz - startHz) * t
            phase += 2.0 * .pi * freq / Double(sampleRate)
            let raw = square ? (sin(phase) >= 0 ? 1.0 : -1.0) : sin(phase)
            let env = 1.0 - t
            let val = 128.0 + raw * env * gain * 110.0
            samples[i] = UInt8(clamping: Int(val.rounded()))
        }
        return wrapPCM8Mono(samples: samples, sampleRate: sampleRate)
    }

    private static func buildNotesWAV(notes: [(hz: Double, duration: Double)], gain: Double) -> Data {
        let sampleRate = 22_050
        var samples: [UInt8] = []
        samples.reserveCapacity(Int(Double(sampleRate) * notes.reduce(0) { $0 + $1.duration }))
        for (hz, duration) in notes {
            let count = max(1, Int(Double(sampleRate) * duration))
            for i in 0..<count {
                let t = Double(i) / Double(count)
                let wave = sin(2.0 * .pi * hz * Double(i) / Double(sampleRate)) >= 0 ? 1.0 : -1.0
                let env = t < 0.1 ? (t / 0.1) : (1.0 - (t - 0.1) / 0.9)
                let val = 128.0 + wave * max(0, env) * gain * 105.0
                samples.append(UInt8(clamping: Int(val.rounded())))
            }
        }
        return wrapPCM8Mono(samples: samples, sampleRate: sampleRate)
    }

    private static func wrapPCM8Mono(samples: [UInt8], sampleRate: Int) -> Data {
        let dataSize = UInt32(samples.count)
        let chunkSize = 36 + dataSize
        var data = Data(capacity: 44 + samples.count)
        data.append(contentsOf: "RIFF".utf8)
        appendLE(chunkSize, to: &data)
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        appendLE(UInt32(16), to: &data)          // PCM subchunk size
        appendLE(UInt16(1), to: &data)           // PCM format
        appendLE(UInt16(1), to: &data)           // Mono
        appendLE(UInt32(sampleRate), to: &data)  // Sample rate
        appendLE(UInt32(sampleRate), to: &data)  // Byte rate (1 byte/sample)
        appendLE(UInt16(1), to: &data)           // Block align
        appendLE(UInt16(8), to: &data)           // Bits per sample
        data.append(contentsOf: "data".utf8)
        appendLE(dataSize, to: &data)
        data.append(contentsOf: samples)
        return data
    }

    private static func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }
}
