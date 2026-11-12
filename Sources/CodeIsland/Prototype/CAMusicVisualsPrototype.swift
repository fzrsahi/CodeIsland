// PROTOTYPE — throwaway, branch prototype/ca-music-visuals only. Never merge.
//
// Ticket "Tampilan spectrum & aura versi Core Animation": three Core Animation
// variants of the collapsed bar's continuously animated visuals (right-wing
// spectrum, lyric-capsule spectrum, beat aura, breath glow, waiting bell),
// next to today's SwiftUI version, switchable from a floating panel.
//
//   0  SwiftUI (today)        TimelineView per frame
//   A  CA additive oscillators two autoreversing animations per bar, smooth
//   B  CA keyframes (formula) today's sin formula, sampled into a seamless 6 s loop
//   C  CA staggered curve     one shared curve, each bar offset and slightly faster/slower
//
// All variants apply ticket 03's decisions so the CPU numbers compare only the
// rendering technique: mascot frozen in its idle pose, no ♪ note.
//
// Run: scripts/prototype-ca-visuals.sh

import AppKit
import CodeIslandCore
import QuartzCore
import SwiftUI

// MARK: - State

@MainActor
final class PrototypeVisuals: ObservableObject {
    static let shared = PrototypeVisuals()

    enum Variant: String, CaseIterable {
        case original = "0", a = "A", b = "B", c = "C"
        var label: String {
            switch self {
            case .original: return "0 · SwiftUI (sekarang)"
            case .a: return "A · CA osilator aditif"
            case .b: return "B · CA keyframe dari rumus"
            case .c: return "C · CA stagger satu kurva"
            }
        }
    }

    enum Scene: String, CaseIterable {
        case music, breath, waiting
        var label: String {
            switch self {
            case .music: return "Musik (aura + spectrum + lirik)"
            case .breath: return "Idle session (breath glow)"
            case .waiting: return "Waiting approval (bell)"
            }
        }
    }

    nonisolated static let enabled = ProcessInfo.processInfo.arguments.contains("--proto-visuals")

    @Published var variant: Variant
    @Published var scene: Scene = .music
    /// Music HUD theme for the prototype only; the user's setting is not written.
    @Published var theme: String = MusicHUDTheme.modernClean.rawValue
    /// Stand-in for "gate off / Reduce Motion": every visual holds its still frame.
    @Published var frozen = false

    weak var appState: AppState?

    var usesCoreAnimation: Bool { Self.enabled && variant != .original }

    private init() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--proto-variant"), i + 1 < args.count,
           let v = Variant(rawValue: args[i + 1]) {
            variant = v
        } else {
            variant = .a
        }
    }

    func start(appState: AppState) {
        guard Self.enabled else { return }
        self.appState = appState
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--proto-theme"), i + 1 < args.count {
            theme = args[i + 1] == "retro" ? MusicHUDTheme.retroCyber.rawValue : MusicHUDTheme.modernClean.rawValue
        }
        if let i = args.firstIndex(of: "--proto-scene"), i + 1 < args.count,
           let s = Scene(rawValue: args[i + 1]), s != .music {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                self.apply(scene: s)
            }
        }
        if !args.contains("--proto-no-panel") {
            PrototypeSwitcherPanel.shared.show()
        }
        PrototypeStats.shared.start()
    }

    func step(_ delta: Int) {
        let all = Variant.allCases
        let i = all.firstIndex(of: variant) ?? 0
        variant = all[(i + delta + all.count) % all.count]
        PrototypeStats.shared.reset()
    }

    func apply(scene: Scene) {
        self.scene = scene
        guard let app = appState else { return }
        let np = NowPlayingManager.shared
        app.sessions.removeValue(forKey: "proto-session")
        switch scene {
        case .music:
            np.isPlaying = true
        case .breath, .waiting:
            np.isPlaying = false
            var s = SessionSnapshot()
            s.source = "claude"
            s.cwd = "/Users/dev/prototype"
            s.status = scene == .waiting ? .waitingApproval : .idle
            if scene == .waiting && ProcessInfo.processInfo.environment["PROTO_NO_TOOL"] == nil {
                s.currentTool = "Bash"
                s.toolDescription = "npm test"
            }
            app.sessions["proto-session"] = s
        }
        app.activeSessionId = app.sessions.isEmpty ? nil : "proto-session"
        app.surface = .collapsed
        app.refreshDerivedState()
        PrototypeStats.shared.reset()
    }
}

/// CPU and layout passes, sampled every 2 s. Separate object so its updates
/// only re-render the switcher, not the island.
@MainActor
final class PrototypeStats: ObservableObject {
    static let shared = PrototypeStats()
    @Published var line = "measuring…"

    private var timer: Timer?
    private var lastCPU: Double = 0
    private var lastWall: Double = 0
    private var lastLayouts = 0
    private var cpuWindow: [Double] = []
    private var layoutWindow: [Double] = []

    func start() {
        reset()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in PrototypeStats.shared.sample() }
        }
    }

    func reset() {
        lastCPU = Self.cpuSeconds()
        lastWall = Date().timeIntervalSinceReferenceDate
        lastLayouts = PerfCounters.shared?.count(.hostingLayoutPass) ?? 0
        cpuWindow = []
        layoutWindow = []
        line = "measuring…"
    }

    private func sample() {
        let cpu = Self.cpuSeconds()
        let wall = Date().timeIntervalSinceReferenceDate
        let layouts = PerfCounters.shared?.count(.hostingLayoutPass) ?? 0
        let dt = wall - lastWall
        guard dt > 0 else { return }
        cpuWindow.append(100 * (cpu - lastCPU) / dt)
        layoutWindow.append(Double(layouts - lastLayouts) * 60 / dt)
        if cpuWindow.count > 10 { cpuWindow.removeFirst(); layoutWindow.removeFirst() }
        lastCPU = cpu; lastWall = wall; lastLayouts = layouts
        let c = cpuWindow.reduce(0, +) / Double(cpuWindow.count)
        let l = layoutWindow.reduce(0, +) / Double(layoutWindow.count)
        line = String(format: "CPU %.1f%%  ·  layout %.0f/menit  ·  rata-rata %ds", c, l, cpuWindow.count * 2)
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func s(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return s(usage.ru_utime) + s(usage.ru_stime)
    }
}

// MARK: - Switcher panel

@MainActor
final class PrototypeSwitcherPanel {
    static let shared = PrototypeSwitcherPanel()
    private var panel: NSPanel?
    private var keyMonitor: Any?

    func show() {
        guard panel == nil, let screen = NSScreen.main else { return }
        let size = NSSize(width: 470, height: 128)
        let p = NSPanel(
            contentRect: NSRect(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.minY + 24,
                                width: size.width, height: size.height),
            styleMask: [.titled, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.title = "PROTOTYPE · CA music visuals"
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.contentView = NSHostingView(rootView: PrototypeSwitcherView())
        p.orderFrontRegardless()
        panel = p
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 123: PrototypeVisuals.shared.step(-1); return nil
            case 124: PrototypeVisuals.shared.step(1); return nil
            default: return event
            }
        }
    }
}

private struct PrototypeSwitcherView: View {
    @ObservedObject var proto = PrototypeVisuals.shared
    @ObservedObject var stats = PrototypeStats.shared

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button("◀") { proto.step(-1) }
                Text(proto.variant.label)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .frame(width: 290)
                Button("▶") { proto.step(1) }
            }
            HStack(spacing: 8) {
                Picker("", selection: Binding(get: { proto.scene }, set: { proto.apply(scene: $0) })) {
                    ForEach(PrototypeVisuals.Scene.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .frame(width: 220)
                Picker("", selection: $proto.theme) {
                    Text("Modern").tag(MusicHUDTheme.modernClean.rawValue)
                    Text("Retro").tag(MusicHUDTheme.retroCyber.rawValue)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                Toggle("Diam", isOn: $proto.frozen)
            }
            Text(stats.line)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Shared sampling

private enum Curve {
    static let period: Double = 6.0
    static let fps: Double = 25

    /// Today's modern formula with frequencies rounded so 6 s is a whole number
    /// of cycles: 8.0→8.378, 12.5→12.566, 4.2→4.189 rad/s (seamless loop).
    static func modernB(_ t: Double, _ i: Int) -> Double {
        let f = Double(i)
        let v = 0.55 + sin(8.378 * t + f * 2.2) * 0.42 + cos(12.566 * t + f * 1.7) * 0.28 + sin(4.189 * t + f * 0.9) * 0.15
        return min(1, max(0.25, v))
    }

    /// Today's retro formula, same rounding: 8.0→8.378, 13.0→12.566, 4.5→4.189.
    static func retroB(_ t: Double, _ i: Int) -> Double {
        let f = Double(i)
        let v = 0.45 + sin(8.378 * t + f * 1.5) * 0.4 + cos(12.566 * t + f * 2.2) * 0.3 + sin(4.189 * t) * 0.15
        return min(1, max(0.15, v))
    }

    /// Variant C: one hand-drawn curve, each bar offset and slightly faster/slower.
    static let cPoints: [Double] = [0.30, 0.95, 0.50, 0.80, 0.35, 1.00, 0.45, 0.70, 0.30]
    static let cSpeeds: [Double] = [1.0, 0.86, 1.12, 0.94, 1.05]
    static func c(_ t: Double, _ i: Int, floor: Double) -> Double {
        let speed = cSpeeds[i % cSpeeds.count]
        let loop = 1.6 / speed
        let phase = ((t + Double(i) * 0.37).truncatingRemainder(dividingBy: loop)) / loop
        let x = phase * Double(cPoints.count - 1)
        let k = min(Int(x), cPoints.count - 2)
        let frac = x - Double(k)
        let smooth = (1 - cos(frac * .pi)) / 2
        return max(floor, cPoints[k] + (cPoints[k + 1] - cPoints[k]) * smooth)
    }

    /// Loop length for variant C bars: a whole number of each bar's cycles in ~6 s.
    static func cDuration(_ i: Int) -> Double {
        let loop = 1.6 / cSpeeds[i % cSpeeds.count]
        return loop * (6.0 / loop).rounded()
    }

    static func samples(duration: Double, _ f: (Double) -> Double) -> [Double] {
        let n = Int(duration * fps)
        return (0...n).map { f(Double($0) / fps) }
    }
}

private func infiniteKeyframes(_ keyPath: String, _ values: [Any], duration: Double, discrete: Bool) -> CAKeyframeAnimation {
    let a = CAKeyframeAnimation(keyPath: keyPath)
    a.values = values
    a.duration = duration
    a.repeatCount = .infinity
    a.calculationMode = discrete ? .discrete : .linear
    a.isRemovedOnCompletion = false
    return a
}

private func oscillator(_ keyPath: String, amplitude: CGFloat, duration: Double, phase: Double) -> CABasicAnimation {
    let a = CABasicAnimation(keyPath: keyPath)
    a.fromValue = -amplitude
    a.toValue = amplitude
    a.isAdditive = true
    a.duration = duration
    a.autoreverses = true
    a.repeatCount = .infinity
    a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    a.beginTime = CACurrentMediaTime() - phase
    a.isRemovedOnCompletion = false
    return a
}

// MARK: - Spectrum

struct CASpectrumView: NSViewRepresentable {
    enum Style {
        case modern(color: NSColor, maxHeight: CGFloat)
        case retro(palette: RetroSpectrumPalette, segmentHeight: CGFloat, segmentSpacing: CGFloat)
    }

    var variant: PrototypeVisuals.Variant
    var style: Style
    var barCount: Int
    var barWidth: CGFloat
    var barSpacing: CGFloat
    var animating: Bool

    var size: CGSize {
        let w = CGFloat(barCount) * barWidth + CGFloat(max(0, barCount - 1)) * barSpacing
        switch style {
        case .modern(_, let h): return CGSize(width: w, height: h)
        case .retro(_, let sh, let ss): return CGSize(width: w, height: 4 * sh + 3 * ss)
        }
    }

    func makeNSView(context: Context) -> LayerHostView { LayerHostView() }

    func updateNSView(_ view: LayerHostView, context: Context) {
        let key = "\(variant.rawValue)|\(barCount)|\(barWidth)|\(animating)|\(styleKey)"
        guard view.configKey != key else { return }
        view.configKey = key
        view.rebuild(size: size) { root in build(into: root) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LayerHostView, context: Context) -> CGSize? { size }

    private var styleKey: String {
        switch style {
        case .modern(let c, let h): return "m\(c)\(h)"
        case .retro(let p, let sh, let ss): return "r\(p.base)\(p.mid)\(p.peak)\(sh)\(ss)"
        }
    }

    private func build(into root: CALayer) {
        switch style {
        case .modern(let color, let h): buildModern(root, color: color.cgColor, maxHeight: h)
        case .retro(let p, let sh, let ss): buildRetro(root, palette: p, segmentHeight: sh, segmentSpacing: ss)
        }
    }

    private func buildModern(_ root: CALayer, color: CGColor, maxHeight h: CGFloat) {
        for i in 0..<barCount {
            let bar = CALayer()
            bar.backgroundColor = color
            bar.cornerRadius = barWidth / 2
            bar.position = CGPoint(x: CGFloat(i) * (barWidth + barSpacing) + barWidth / 2, y: h / 2)
            func height(_ n: Double) -> CGFloat { max(2.5, h * CGFloat(n)) }
            guard animating else {
                bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: height(0.25))
                root.addSublayer(bar)
                continue
            }
            switch variant {
            case .a, .original:
                bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: h * 0.6)
                bar.add(oscillator("bounds.size.height", amplitude: h * 0.3,
                                   duration: [0.29, 0.37, 0.33, 0.41, 0.35][i % 5], phase: Double(i) * 0.11), forKey: "o1")
                bar.add(oscillator("bounds.size.height", amplitude: h * 0.12,
                                   duration: [0.53, 0.47, 0.61, 0.57, 0.5][i % 5], phase: Double(i) * 0.23), forKey: "o2")
            case .b:
                bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: height(0.5))
                let values = Curve.samples(duration: Curve.period) { height(Curve.modernB($0, i)) }
                bar.add(infiniteKeyframes("bounds.size.height", values, duration: Curve.period, discrete: false), forKey: "k")
            case .c:
                bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: height(0.5))
                let d = Curve.cDuration(i)
                let values = Curve.samples(duration: d) { height(Curve.c($0, i, floor: 0.25)) }
                bar.add(infiniteKeyframes("bounds.size.height", values, duration: d, discrete: false), forKey: "k")
            }
            root.addSublayer(bar)
        }
    }

    private func buildRetro(_ root: CALayer, palette p: RetroSpectrumPalette, segmentHeight sh: CGFloat, segmentSpacing ss: CGFloat) {
        let unlit = NSColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1).cgColor
        let lit = [p.base, p.base, p.mid, p.peak].map { NSColor($0).cgColor }
        let totalH = 4 * sh + 3 * ss
        for i in 0..<barCount {
            let x = CGFloat(i) * (barWidth + barSpacing)
            func segmentFrame(_ step: Int) -> CGRect {
                CGRect(x: x, y: CGFloat(step) * (sh + ss), width: barWidth, height: sh)
            }
            func activeCount(_ n: Double) -> Int { Int((n * 4).rounded()) }

            if !animating || variant == .a || variant == .original {
                // Unlit segments as the background; in A the lit stack is revealed by a mask.
                for step in 0..<4 {
                    let seg = CALayer()
                    seg.frame = segmentFrame(step)
                    seg.backgroundColor = (!animating && step < 1) ? lit[step] : unlit
                    root.addSublayer(seg)
                }
                guard animating else { continue }
                let litGroup = CALayer()
                litGroup.frame = root.bounds
                for step in 0..<4 {
                    let seg = CALayer()
                    seg.frame = segmentFrame(step)
                    seg.backgroundColor = lit[step]
                    litGroup.addSublayer(seg)
                }
                let mask = CALayer()
                mask.backgroundColor = NSColor.black.cgColor
                mask.anchorPoint = CGPoint(x: 0.5, y: 0)
                mask.bounds = CGRect(x: 0, y: 0, width: barWidth, height: totalH * 0.55)
                mask.position = CGPoint(x: x + barWidth / 2, y: 0)
                mask.add(oscillator("bounds.size.height", amplitude: totalH * 0.3,
                                    duration: [0.29, 0.37, 0.33, 0.41][i % 4], phase: Double(i) * 0.11), forKey: "o1")
                mask.add(oscillator("bounds.size.height", amplitude: totalH * 0.15,
                                    duration: [0.53, 0.47, 0.61, 0.57][i % 4], phase: Double(i) * 0.23), forKey: "o2")
                litGroup.mask = mask
                root.addSublayer(litGroup)
                continue
            }

            // B and C: each segment switches between lit and unlit in discrete steps,
            // exactly the 4-level look of today's view.
            let duration = variant == .b ? Curve.period : Curve.cDuration(i)
            let levels = Curve.samples(duration: duration) { t in
                Double(activeCount(variant == .b ? Curve.retroB(t, i) : Curve.c(t, i, floor: 0.15)))
            }
            for step in 0..<4 {
                let seg = CALayer()
                seg.frame = segmentFrame(step)
                seg.backgroundColor = unlit
                let colors = levels.map { Int($0) > step ? lit[step] : unlit }
                seg.add(infiniteKeyframes("backgroundColor", colors, duration: duration, discrete: true), forKey: "k")
                root.addSublayer(seg)
            }
        }
    }
}

/// Layer-hosting NSView; sublayers are rebuilt only when the configuration changes.
final class LayerHostView: NSView {
    var configKey = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { fatalError() }

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
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Aura & breath glow

struct CAGlowView: NSViewRepresentable {
    enum Kind { case aura, breath }

    var kind: Kind
    var variant: PrototypeVisuals.Variant
    var mascotSize: CGFloat
    var animating: Bool

    private var side: CGFloat { kind == .aura ? mascotSize + 8 : mascotSize + 4 }
    /// Period of today's sin: aura sin(3.5t), breath sin(2t).
    private var period: Double { kind == .aura ? 2 * .pi / 3.5 : .pi }

    func makeNSView(context: Context) -> LayerHostView { LayerHostView() }

    func updateNSView(_ view: LayerHostView, context: Context) {
        let key = "\(kind)|\(variant.rawValue)|\(mascotSize)|\(animating)"
        guard view.configKey != key else { return }
        view.configKey = key
        view.rebuild(size: CGSize(width: side, height: side)) { root in build(into: root) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LayerHostView, context: Context) -> CGSize? {
        CGSize(width: side, height: side)
    }

    /// Gradient stops and end radius at beat/breath level `v` (0...1), as today.
    private func state(_ v: Double) -> (colors: [CGColor], locations: [NSNumber], endPoint: CGPoint) {
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
        let start = Double(2 / radius)
        let locations: [NSNumber] = colors.count == 3
            ? [NSNumber(value: start), NSNumber(value: (start + 1) / 2), 1]
            : [NSNumber(value: start), 1]
        let r = radius / side
        return (colors, locations, CGPoint(x: 0.5 + r, y: 0.5 + r))
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

        switch variant {
        case .a, .original:
            // Brightest stops, then breathe layer opacity and radius together.
            let top = state(1), low = state(0)
            g.colors = top.colors
            g.endPoint = top.endPoint
            let minOpacity: Double = kind == .aura ? 0.24 / 0.42 : 0.18 / 0.32
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = minOpacity
            fade.toValue = 1
            let grow = CABasicAnimation(keyPath: "endPoint")
            grow.fromValue = NSValue(point: low.endPoint)
            grow.toValue = NSValue(point: top.endPoint)
            let group = CAAnimationGroup()
            group.animations = [fade, grow]
            group.duration = period / 2
            group.autoreverses = true
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            group.isRemovedOnCompletion = false
            g.add(group, forKey: "breathe")
        case .b:
            // Exactly today's per-frame values, sampled into one period.
            let samples = Curve.samples(duration: period) { (sin($0 * 2 * .pi / period) + 1) / 2 }
            let states = samples.map(state)
            let colors = infiniteKeyframes("colors", states.map { $0.colors }, duration: period, discrete: false)
            let ends = infiniteKeyframes("endPoint", states.map { NSValue(point: $0.endPoint) }, duration: period, discrete: false)
            g.add(colors, forKey: "colors")
            g.add(ends, forKey: "end")
        case .c:
            // Static glow: no animation at all, the cheapest option.
            break
        }
    }
}

// MARK: - Waiting bell

struct CABellView: NSViewRepresentable {
    var animating: Bool

    func makeNSView(context: Context) -> NSImageView {
        let config = NSImage.SymbolConfiguration(pointSize: 8.5, weight: .bold)
        let image = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        let view = NSImageView(image: image ?? NSImage())
        view.contentTintColor = NSColor(red: 1.0, green: 0.7, blue: 0.28, alpha: 1)
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        guard let layer = view.layer else { return }
        let running = layer.animation(forKey: "pulse") != nil
        guard running != animating else { return }
        if animating {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1
            a.toValue = 0.35
            a.duration = 0.75
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.isRemovedOnCompletion = false
            layer.add(a, forKey: "pulse")
        } else {
            layer.removeAnimation(forKey: "pulse")
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}
