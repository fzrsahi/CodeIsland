import AppKit
import QuartzCore
import SwiftUI

// MARK: - Kurva keyframe varian B (murni, ter-test)
//
// Rumus yang sama dengan prototype `prototype/ca-music-visuals` (varian B):
// rumus SwiftUI hari ini dengan frekuensi dibulatkan agar loop 6 dtk mulus
// (8,0→8,378 · 12,5/13,0→12,566 · 4,2/4,5→4,189 rad/s: 8, 12, dan 4 siklus
// penuh per 6 dtk). Disampel 25 fps menjadi keyframe Core Animation, jadi
// render server yang menggerakkan visual, bukan SwiftUI per frame.

enum CAMusicCurves {
    /// Satu periode loop untuk spectrum (6 dtk, varian B).
    static let period: Double = 6
    /// Keyframe per detik.
    static let fps: Double = 25

    /// Tinggi kapsul Modern, sudah clamp 0,25…1.
    static func modernLevel(at t: Double, bar i: Int) -> Double {
        let f = Double(i)
        let v = 0.55 + sin(8.378 * t + f * 2.2) * 0.42
            + cos(12.566 * t + f * 1.7) * 0.28 + sin(4.189 * t + f * 0.9) * 0.15
        return min(1, max(0.25, v))
    }

    /// Level Retro, sudah clamp 0,15…1.
    static func retroLevel(at t: Double, bar i: Int) -> Double {
        let f = Double(i)
        let v = 0.45 + sin(8.378 * t + f * 1.5) * 0.4
            + cos(12.566 * t + f * 2.2) * 0.3 + sin(4.189 * t) * 0.15
        return min(1, max(0.15, v))
    }

    /// Jumlah segmen Retro yang menyala (0…4) untuk satu level.
    static func retroActiveSegments(level n: Double) -> Int { Int((n * 4).rounded()) }

    /// Sampel `f` sebanyak `fps` per detik selama `duration`, termasuk kedua
    /// ujung (loop mulus: sampel terakhir == awal periode berikutnya).
    static func samples<T>(duration: Double, _ f: (Double) -> T) -> [T] {
        let n = Int(duration * fps)
        return (0...n).map { f(Double($0) / fps) }
    }

    /// Tinggi still frame Modern saat kelas tidak aktif: 0,25.
    static let modernStillLevel: Double = 0.25
    /// Tinggi kapsul minimum, sama seperti versi SwiftUI.
    static let modernMinHeight: CGFloat = 2.5
}

// MARK: - Layer-hosting view
//
// Sublayer hanya dibangun ulang saat konfigurasi berubah (tema, jumlah bar,
// kelas aktif): `updateNSView` membandingkan `configKey` dan tidak menyentuh
// layer bila sama.

final class CAMusicLayerHostView: NSView {
    var configKey = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func rebuild(size: CGSize, _ build: (CALayer) -> Void) {
        guard let root = layer else { return }
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        root.bounds = CGRect(origin: .zero, size: size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        build(root)
        CATransaction.commit()
    }

    override var intrinsicContentSize: NSSize { layer?.bounds.size ?? .zero }
}

private func infiniteCAKeyframes(keyPath: String, values: [Any], duration: Double,
                                 discrete: Bool) -> CAKeyframeAnimation {
    let a = CAKeyframeAnimation(keyPath: keyPath)
    a.values = values
    a.duration = duration
    a.repeatCount = .infinity
    a.calculationMode = discrete ? .discrete : .linear
    a.isRemovedOnCompletion = false
    return a
}

/// Kunci konfigurasi yang stabil untuk satu warna (komponen sRGB).
private func caColorKey(_ c: Color) -> String {
    let ns = NSColor(c).usingColorSpace(.sRGB) ?? NSColor(c)
    return String(format: "%.3f,%.3f,%.3f,%.3f",
                  ns.redComponent, ns.greenComponent, ns.blueComponent, ns.alphaComponent)
}

private func caResolvedCGColor(_ c: Color) -> CGColor {
    let ns = NSColor(c).usingColorSpace(.sRGB) ?? NSColor(c)
    return ns.cgColor
}

// MARK: - Spectrum Modern (kapsul halus)

/// Pengganti CA untuk `ModernAudioSpectrumView` saat kelas Music aktif:
/// tinggi tiap kapsul dianimasikan keyframe 25 fps loop 6 dtk di render
/// server. Ukuran yang dilaporkan ke layout sama persis dengan HStack
/// SwiftUI yang digantikannya.
struct CAModernSpectrumView: NSViewRepresentable {
    var barCount: Int
    var barWidth: CGFloat
    var maxHeight: CGFloat
    var color: Color
    /// False saat kelas tidak aktif atau Reduce Motion: animasi dilepas,
    /// setiap kapsul diam di 0,25.
    var animating: Bool

    /// Spacing HStack versi SwiftUI yang digantikan.
    private static let spacing: CGFloat = 1.6

    static func fixedSize(barCount: Int, barWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        CGSize(width: CGFloat(barCount) * barWidth + CGFloat(max(0, barCount - 1)) * spacing,
               height: maxHeight)
    }

    private var size: CGSize {
        Self.fixedSize(barCount: barCount, barWidth: barWidth, maxHeight: maxHeight)
    }

    func makeNSView(context: Context) -> CAMusicLayerHostView { CAMusicLayerHostView() }

    func updateNSView(_ view: CAMusicLayerHostView, context: Context) {
        let key = "\(barCount)|\(barWidth)|\(maxHeight)|\(caColorKey(color))|\(animating)"
        guard view.configKey != key else { return }
        view.configKey = key
        view.rebuild(size: size) { build(into: $0) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CAMusicLayerHostView,
                      context: Context) -> CGSize? { size }

    private func height(_ n: Double) -> CGFloat {
        max(CAMusicCurves.modernMinHeight, maxHeight * CGFloat(n))
    }

    private func build(into root: CALayer) {
        let cg = caResolvedCGColor(color)
        for i in 0..<barCount {
            let bar = CALayer()
            bar.backgroundColor = cg
            bar.cornerRadius = barWidth / 2
            bar.position = CGPoint(x: CGFloat(i) * (barWidth + Self.spacing) + barWidth / 2,
                                   y: maxHeight / 2)
            if animating {
                bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: height(0.5))
                let values: [CGFloat] = CAMusicCurves.samples(duration: CAMusicCurves.period) {
                    height(CAMusicCurves.modernLevel(at: $0, bar: i))
                }
                bar.add(infiniteCAKeyframes(keyPath: "bounds.size.height", values: values,
                                            duration: CAMusicCurves.period, discrete: false), forKey: "k")
            } else {
                bar.bounds = CGRect(x: 0, y: 0, width: barWidth,
                                    height: height(CAMusicCurves.modernStillLevel))
            }
            root.addSublayer(bar)
        }
    }
}

// MARK: - Spectrum Retro (segmen diskrit 4 tingkat)

/// Pengganti CA untuk `CyberAudioSpectrumView` saat kelas Music aktif:
/// tiap segmen beralih antara warna lit dan unlit dalam step diskrit
/// (4 tingkat, sama seperti versi SwiftUI). Palet dan warna unlit sama
/// dengan sekarang. Ukuran yang dilaporkan ke layout sama persis.
struct CARetroSpectrumView: NSViewRepresentable {
    var barCount: Int
    var barWidth: CGFloat
    var segmentHeight: CGFloat
    var segmentSpacing: CGFloat
    var palette: RetroSpectrumPalette
    /// False saat kelas tidak aktif atau Reduce Motion: animasi dilepas,
    /// hanya segmen bawah yang menyala.
    var animating: Bool

    /// Spacing HStack versi SwiftUI yang digantikan.
    private static let spacing: CGFloat = 1.5

    static func fixedSize(barCount: Int, barWidth: CGFloat,
                          segmentHeight: CGFloat, segmentSpacing: CGFloat) -> CGSize {
        CGSize(width: CGFloat(barCount) * barWidth + CGFloat(max(0, barCount - 1)) * spacing,
               height: 4 * segmentHeight + 3 * segmentSpacing)
    }

    private var size: CGSize {
        Self.fixedSize(barCount: barCount, barWidth: barWidth,
                       segmentHeight: segmentHeight, segmentSpacing: segmentSpacing)
    }

    /// Warna unlit, sama dengan versi SwiftUI.
    private static let unlit = Color(red: 0.12, green: 0.14, blue: 0.18)

    func makeNSView(context: Context) -> CAMusicLayerHostView { CAMusicLayerHostView() }

    func updateNSView(_ view: CAMusicLayerHostView, context: Context) {
        let key = [
            "\(barCount)", "\(barWidth)", "\(segmentHeight)", "\(segmentSpacing)",
            "\(animating)", caColorKey(palette.base) + caColorKey(palette.mid) + caColorKey(palette.peak),
        ].joined(separator: "|")
        guard view.configKey != key else { return }
        view.configKey = key
        view.rebuild(size: size) { build(into: $0) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CAMusicLayerHostView,
                      context: Context) -> CGSize? { size }

    private func build(into root: CALayer) {
        let unlitCG = caResolvedCGColor(Self.unlit)
        let lit = [palette.base, palette.base, palette.mid, palette.peak].map(caResolvedCGColor(_:))
        for i in 0..<barCount {
            let x = CGFloat(i) * (barWidth + Self.spacing)
            if !animating {
                for step in 0..<4 {
                    let seg = CALayer()
                    seg.frame = CGRect(x: x, y: CGFloat(step) * (segmentHeight + segmentSpacing),
                                       width: barWidth, height: segmentHeight)
                    seg.backgroundColor = step < 1 ? lit[step] : unlitCG
                    root.addSublayer(seg)
                }
                continue
            }
            let levels = CAMusicCurves.samples(duration: CAMusicCurves.period) {
                Double(CAMusicCurves.retroActiveSegments(level: CAMusicCurves.retroLevel(at: $0, bar: i)))
            }
            for step in 0..<4 {
                let seg = CALayer()
                seg.frame = CGRect(x: x, y: CGFloat(step) * (segmentHeight + segmentSpacing),
                                   width: barWidth, height: segmentHeight)
                seg.backgroundColor = unlitCG
                let colors = levels.map { Int($0) > step ? lit[step] : unlitCG }
                seg.add(infiniteCAKeyframes(keyPath: "backgroundColor", values: colors,
                                            duration: CAMusicCurves.period, discrete: true), forKey: "k")
                root.addSublayer(seg)
            }
        }
    }
}

// MARK: - Aura & breath glow

/// Pengganti CA untuk aura musik dan breath glow di `CompactLeftWing`:
/// gradient radial dengan keyframe `colors` + `endPoint` selama satu periode
/// (aura 2π/3,5 dtk, breath π dtk). Stop warna dan radius sama seperti versi
/// SwiftUI. Saat kelasnya tidak aktif, glow diam di nilai tengah.
struct CAMusicGlowView: NSViewRepresentable {
    enum Kind { case aura, breath }

    var kind: Kind
    var mascotSize: CGFloat
    /// False saat kelasnya tidak aktif atau Reduce Motion: animasi dilepas.
    var animating: Bool

    private var side: CGFloat { kind == .aura ? mascotSize + 8 : mascotSize + 4 }
    /// Periode rumus hari ini: aura sin(3,5t), breath sin(2t).
    var period: Double { kind == .aura ? 2 * .pi / 3.5 : .pi }

    /// Stop warna dan radius akhir pada level `v` (0…1), sama seperti versi SwiftUI.
    func state(_ v: Double) -> (colors: [CGColor], locations: [NSNumber], endPoint: CGPoint) {
        let cyan = NSColor(red: 0.0, green: 0.96, blue: 0.83, alpha: 1)
        let pink = NSColor(red: 1.0, green: 0.16, blue: 0.53, alpha: 1)
        let radius: CGFloat
        let colors: [CGColor]
        switch kind {
        case .aura:
            radius = mascotSize * 0.6 + CGFloat(v * 3)
            colors = [pink.withAlphaComponent(0.24 + v * 0.18).cgColor,
                      cyan.withAlphaComponent(0.12 + v * 0.10).cgColor,
                      NSColor.clear.cgColor]
        case .breath:
            radius = mascotSize * 0.55 + CGFloat(v * 2)
            colors = [cyan.withAlphaComponent(0.18 + v * 0.14).cgColor,
                      cyan.withAlphaComponent(0).cgColor]
        }
        let start = 2 / Double(radius)
        let locations: [NSNumber] = colors.count == 3
            ? [NSNumber(value: start), NSNumber(value: (start + 1) / 2), 1]
            : [NSNumber(value: start), 1]
        let r = radius / side
        return (colors, locations, CGPoint(x: 0.5 + r, y: 0.5 + r))
    }

    func makeNSView(context: Context) -> CAMusicLayerHostView { CAMusicLayerHostView() }

    func updateNSView(_ view: CAMusicLayerHostView, context: Context) {
        let key = "\(kind)|\(mascotSize)|\(animating)"
        guard view.configKey != key else { return }
        view.configKey = key
        let side = self.side
        view.rebuild(size: CGSize(width: side, height: side)) { build(into: $0) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CAMusicLayerHostView,
                      context: Context) -> CGSize? {
        CGSize(width: side, height: side)
    }

    private func build(into root: CALayer) {
        let g = CAGradientLayer()
        g.type = .radial
        g.frame = root.bounds
        g.cornerRadius = side / 2
        g.masksToBounds = true
        g.startPoint = CGPoint(x: 0.5, y: 0.5)
        let mid = state(0.5)
        g.colors = mid.colors
        g.locations = mid.locations
        g.endPoint = mid.endPoint
        root.addSublayer(g)
        guard animating else { return }
        let samples = CAMusicCurves.samples(duration: period) { (sin($0 * 2 * .pi / period) + 1) / 2 }
        let states = samples.map(state(_:))
        g.add(infiniteCAKeyframes(keyPath: "colors", values: states.map { $0.colors },
                                  duration: period, discrete: false), forKey: "colors")
        g.add(infiniteCAKeyframes(keyPath: "endPoint",
                                  values: states.map { NSValue(point: $0.endPoint) },
                                  duration: period, discrete: false), forKey: "end")
    }
}
