import SwiftUI

// Glyph identifier for pixel-art icons
public enum PixelIconGlyph: String, CaseIterable, Sendable {
    case agents
    case workspace
    case music
    case prayer
    case calendar
    case email
    case refresh
    case checkmark
    case arrowUpRight
}

// Crisp Canvas-based vector pixel icon renderer
public struct PixelIcon: View {
    let glyph: PixelIconGlyph
    let color: Color
    var pixelSize: CGFloat = 1.6

    // Dimensions and binary bitmap matrices
    private var spec: (w: Int, h: Int, data: [UInt8]) {
        switch glyph {
        case .agents:
            return (9, 9, [
                0,1,0,1,0,1,0,1,0,
                1,1,1,1,1,1,1,1,1,
                0,1,0,0,0,0,0,1,0,
                1,1,0,1,1,1,0,1,1,
                0,1,0,1,0,1,0,1,0,
                1,1,0,1,1,1,0,1,1,
                0,1,0,0,0,0,0,1,0,
                1,1,1,1,1,1,1,1,1,
                0,1,0,1,0,1,0,1,0
            ])
        case .workspace:
            return (9, 9, [
                1,1,1,1,0,0,0,0,0,
                1,0,0,0,1,1,1,1,1,
                1,0,1,1,1,1,1,0,1,
                1,1,1,1,1,1,1,1,1,
                1,0,0,0,0,0,0,0,1,
                1,0,1,1,0,1,1,0,1,
                1,0,0,0,0,0,0,0,1,
                1,1,1,1,1,1,1,1,1,
                0,1,1,1,1,1,1,1,0
            ])
        case .music:
            return (9, 9, [
                0,0,1,1,1,1,1,1,0,
                0,0,1,1,1,1,1,1,0,
                0,0,1,0,0,0,0,1,0,
                0,0,1,0,0,0,0,1,0,
                0,0,1,0,0,0,0,1,0,
                0,1,1,1,0,0,1,1,1,
                1,1,1,1,0,1,1,1,1,
                1,1,1,0,0,1,1,1,0,
                0,1,0,0,0,0,1,0,0
            ])
        case .prayer:
            return (9, 9, [
                0,0,1,1,1,0,0,0,1,
                0,1,1,0,0,1,0,1,1,
                1,1,0,0,0,0,0,0,1,
                1,1,0,0,0,0,0,0,0,
                1,1,0,0,0,0,0,0,0,
                1,1,0,0,0,0,0,0,0,
                0,1,1,0,0,1,0,0,0,
                0,0,1,1,1,0,0,0,0,
                0,0,0,0,0,0,0,0,0
            ])
        case .calendar:
            return (9, 9, [
                0,1,0,0,1,0,0,1,0,
                1,1,1,1,1,1,1,1,1,
                1,1,1,1,1,1,1,1,1,
                1,0,0,0,0,0,0,0,1,
                1,0,1,0,1,0,1,0,1,
                1,0,0,0,0,0,0,0,1,
                1,0,1,0,1,0,1,0,1,
                1,0,0,0,0,0,0,0,1,
                1,1,1,1,1,1,1,1,1
            ])
        case .email:
            return (9, 9, [
                0,0,0,0,0,0,0,0,0,
                1,1,1,1,1,1,1,1,1,
                1,1,0,0,0,0,0,1,1,
                1,0,1,0,0,0,1,0,1,
                1,0,0,1,0,1,0,0,1,
                1,0,0,0,1,0,0,0,1,
                1,0,0,0,0,0,0,0,1,
                1,1,1,1,1,1,1,1,1,
                0,0,0,0,0,0,0,0,0
            ])
        case .refresh:
            return (9, 9, [
                0,0,1,1,1,1,0,0,0,
                0,1,0,0,0,0,1,0,0,
                1,0,0,0,0,0,1,1,1,
                1,0,0,0,0,0,0,1,0,
                0,0,0,0,0,0,0,0,0,
                0,1,0,0,0,0,0,0,1,
                1,1,1,0,0,0,0,0,1,
                0,0,1,0,0,0,0,1,0,
                0,0,0,1,1,1,1,0,0
            ])
        case .checkmark:
            return (9, 9, [
                0,0,0,0,0,0,0,0,1,
                0,0,0,0,0,0,0,1,1,
                0,0,0,0,0,0,1,1,0,
                1,0,0,0,0,1,1,0,0,
                1,1,0,0,1,1,0,0,0,
                0,1,1,1,1,0,0,0,0,
                0,0,1,1,0,0,0,0,0,
                0,0,0,0,0,0,0,0,0,
                0,0,0,0,0,0,0,0,0
            ])
        case .arrowUpRight:
            return (9, 9, [
                0,0,0,0,1,1,1,1,1,
                0,0,0,0,0,0,1,1,1,
                0,0,0,0,0,1,0,1,1,
                0,0,0,0,1,0,0,0,1,
                0,0,0,1,0,0,0,0,0,
                0,0,1,0,0,0,0,0,0,
                0,1,0,0,0,0,0,0,0,
                1,0,0,0,0,0,0,0,0,
                0,0,0,0,0,0,0,0,0
            ])
        }
    }

    public var body: some View {
        let (w, h, data) = spec
        let px = pixelSize
        let totalW = CGFloat(w) * px
        let totalH = CGFloat(h) * px

        Canvas { ctx, _ in
            for row in 0..<h {
                for col in 0..<w {
                    if data[row * w + col] == 1 {
                        let rect = CGRect(
                            x: CGFloat(col) * px,
                            y: CGFloat(row) * px,
                            width: px,
                            height: px
                        )
                        ctx.fill(Path(rect), with: .color(color))
                    }
                }
            }
        }
        .frame(width: totalW, height: totalH)
    }
}

// MARK: - Pixel Circle Shape (Stepped 8-Bit Discrete Contour)

/// An authentic 8-bit stepped pixel circle shape.
/// Replaces continuous Bezier curves with discrete orthogonal staircase pixel steps.
public struct PixelCircleShape: Shape {
    public var step: CGFloat = 2.0

    public init(step: CGFloat = 2.0) {
        self.step = step
    }

    public func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let s = min(step, min(w, h) / 6.0)
        let s2 = s * 2.0

        var path = Path()
        // Top edge
        path.move(to: CGPoint(x: s2, y: 0))
        path.addLine(to: CGPoint(x: w - s2, y: 0))

        // Top-right corner steps
        path.addLine(to: CGPoint(x: w - s2, y: s))
        path.addLine(to: CGPoint(x: w - s, y: s))
        path.addLine(to: CGPoint(x: w - s, y: s2))
        path.addLine(to: CGPoint(x: w, y: s2))

        // Right edge
        path.addLine(to: CGPoint(x: w, y: h - s2))

        // Bottom-right corner steps
        path.addLine(to: CGPoint(x: w - s, y: h - s2))
        path.addLine(to: CGPoint(x: w - s, y: h - s))
        path.addLine(to: CGPoint(x: w - s2, y: h - s))
        path.addLine(to: CGPoint(x: w - s2, y: h))

        // Bottom edge
        path.addLine(to: CGPoint(x: s2, y: h))

        // Bottom-left corner steps
        path.addLine(to: CGPoint(x: s2, y: h - s))
        path.addLine(to: CGPoint(x: s, y: h - s))
        path.addLine(to: CGPoint(x: s, y: h - s2))
        path.addLine(to: CGPoint(x: 0, y: h - s2))

        // Left edge
        path.addLine(to: CGPoint(x: 0, y: s2))

        // Top-left corner steps
        path.addLine(to: CGPoint(x: s, y: s2))
        path.addLine(to: CGPoint(x: s, y: s))
        path.addLine(to: CGPoint(x: s2, y: s))
        path.addLine(to: CGPoint(x: s2, y: 0))

        path.closeSubpath()
        return path
    }
}
