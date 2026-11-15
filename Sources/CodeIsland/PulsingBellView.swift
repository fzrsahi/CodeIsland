import AppKit
import QuartzCore
import SwiftUI

/// The waiting bell.
///
/// It used to be `Image(...).symbolEffect(.pulse, options: .repeating)`, which
/// runs SwiftUI's animation machinery on every display frame: on a waiting
/// island that alone measured ~59 hosting layout passes per second and ~5% CPU
/// for a bell nobody is looking at. The same pulse is one Core Animation
/// opacity animation here, driven by the render server, so the bell keeps
/// breathing without the panel doing any work. Nothing about its size, colour
/// or rhythm changes.
struct PulsingBellView: NSViewRepresentable {
    var pointSize: CGFloat = 8.5
    var color: NSColor = NSColor(red: 1.0, green: 0.7, blue: 0.28, alpha: 1.0)
    /// False under Reduce Motion: the bell holds still, fully visible.
    var animating: Bool = true

    /// One breath, matching the old `.pulse` cadence closely enough that the
    /// change is invisible.
    private static let period: CFTimeInterval = 1.1

    func makeNSView(context: Context) -> BellHostView {
        let view = BellHostView()
        view.pointSize = pointSize
        view.tint = color
        return view
    }

    func updateNSView(_ view: BellHostView, context: Context) {
        view.pointSize = pointSize
        view.tint = color
        view.setAnimating(animating)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BellHostView, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    final class BellHostView: NSView {
        var pointSize: CGFloat = 8.5 { didSet { rebuildIfNeeded() } }
        var tint: NSColor = .systemYellow { didSet { rebuildIfNeeded() } }

        private let bellLayer = CALayer()
        private var isAnimating = false
        private var builtKey = ""
        private var size: CGSize = CGSize(width: 10, height: 10)

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = CALayer()
            layer?.masksToBounds = false
            bellLayer.contentsGravity = .resizeAspect
            layer?.addSublayer(bellLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        /// A fixed box: the bell never resizes, so it never re-lays-out.
        override var intrinsicContentSize: NSSize { size }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bellLayer.frame = CGRect(origin: .zero, size: size)
            CATransaction.commit()
        }

        func setAnimating(_ animating: Bool) {
            guard animating != isAnimating else { return }
            isAnimating = animating
            bellLayer.removeAnimation(forKey: "pulse")
            guard animating else {
                bellLayer.opacity = 1
                return
            }
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.35
            pulse.duration = PulsingBellView.period / 2
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.isRemovedOnCompletion = false
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bellLayer.add(pulse, forKey: "pulse")
        }

        private func rebuildIfNeeded() {
            let key = "\(pointSize)|\(tint.description)"
            guard key != builtKey else { return }
            builtKey = key
            let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
            guard let symbol = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else { return }
            size = symbol.size
            let tinted = NSImage(size: symbol.size, flipped: false) { rect in
                symbol.draw(in: rect)
                self.tint.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            var rect = CGRect(origin: .zero, size: symbol.size)
            bellLayer.contents = tinted.cgImage(forProposedRect: &rect, context: nil, hints: nil)
            bellLayer.frame = CGRect(origin: .zero, size: size)
            invalidateIntrinsicContentSize()
            let wasAnimating = isAnimating
            isAnimating = false
            setAnimating(wasAnimating)
        }
    }
}
