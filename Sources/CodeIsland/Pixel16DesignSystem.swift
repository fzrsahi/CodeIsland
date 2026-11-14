import SwiftUI
import Combine

// MARK: - 16-Bit Retro Cyber Design System
// Inspired by 16-bit arcade hardware (SNES, Sega Genesis, Neo-Geo, Capcom CPS-2,
// Amiga, and Teenage Engineering modern cyberdecks).
// Features crisp micro-bevels, tactile cartridge slots, stepped LED meters, and high-contrast obsidian chassis.

public enum Pixel16Palette {
    /// Deep obsidian cyberdeck chassis base
    public static let chassis = Color(red: 0.05, green: 0.07, blue: 0.10)
    /// Surface layer for cards and decks
    public static let surface = Color(red: 0.08, green: 0.11, blue: 0.15)
    /// Raised surface for interactive 16-bit buttons and tabs
    public static let surfaceRaised = Color(red: 0.12, green: 0.16, blue: 0.22)
    /// Recessed cartridge bay slot
    public static let slot = Color(red: 0.03, green: 0.04, blue: 0.06)

    /// 1px 16-bit light bevel (top/left)
    public static let bevelHighlight = Color.white.opacity(0.15)
    /// 1px 16-bit shadow bevel (bottom/right)
    public static let bevelShadow = Color.black.opacity(0.70)

    /// Phosphor Laser Cyan (Default 16-bit Primary Hero Accent)
    public static let cyan = Color(red: 0.0, green: 0.96, blue: 0.83)
    /// Phosphor Amber (Warnings, Prompts, Attention)
    public static let amber = Color(red: 1.0, green: 0.72, blue: 0.20)
    /// Phosphor Coral / Red (Destructive, Errors, Deny)
    public static let red = Color(red: 0.95, green: 0.35, blue: 0.35)
    /// High-contrast 16-bit text white
    public static let textWhite = Color(red: 0.95, green: 0.97, blue: 1.0)
    /// Muted secondary 16-bit text
    public static let textMuted = Color(red: 0.60, green: 0.68, blue: 0.78)
    /// Dim tertiary text
    public static let textDim = Color(red: 0.38, green: 0.44, blue: 0.52)
}

// MARK: - 16-Bit Lineless Surface Modifier (Seamless, Pure Depth, Zero Stroke Lines)

public struct Pixel16Bevel: ViewModifier {
    public var raised: Bool = true
    public var cornerRadius: CGFloat = 3
    public var fillColor: Color = Pixel16Palette.surface

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fillColor)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

public extension View {
    func pixel16Bevel(raised: Bool = true, cornerRadius: CGFloat = 3, fillColor: Color = Pixel16Palette.surface) -> some View {
        modifier(Pixel16Bevel(raised: raised, cornerRadius: cornerRadius, fillColor: fillColor))
    }
}

// MARK: - 16-Bit Stepped LED Progress Meter

public struct Pixel16Gauge: View {
    public var totalSegments: Int = 12
    public var filledSegments: Int = 0
    public var isCurrentFlashing: Bool = false
    public var activeColor: Color = Pixel16Palette.cyan
    public var height: CGFloat = 2.5

    public init(totalSegments: Int = 12, filledSegments: Int = 0, isCurrentFlashing: Bool = false, activeColor: Color = Pixel16Palette.cyan, height: CGFloat = 2.5) {
        self.totalSegments = max(1, totalSegments)
        self.filledSegments = max(0, min(filledSegments, totalSegments))
        self.isCurrentFlashing = isCurrentFlashing
        self.activeColor = activeColor
        self.height = height
    }

    public var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<min(totalSegments, 16), id: \.self) { i in
                let isFilled = i < filledSegments
                let isCurrent = isCurrentFlashing && (i == filledSegments)

                Rectangle()
                    .fill(isFilled ? activeColor : (isCurrent ? Pixel16Palette.amber : Color.white.opacity(0.12)))
                    .frame(height: height)
                    .overlay(
                        // 1px micro-highlight on active cells
                        isFilled ? Rectangle().fill(Color.white.opacity(0.35)).frame(height: 0.8) : nil,
                        alignment: .top
                    )
            }
        }
    }
}

// MARK: - 16-Bit Tactile Button

public struct Pixel16Button<Label: View>: View {
    public var action: () -> Void
    public var isAccent: Bool = false
    public var accentColor: Color = Pixel16Palette.cyan
    @ViewBuilder public var label: () -> Label
    @State private var isHovered = false
    @State private var isPressed = false

    public init(
        action: @escaping () -> Void,
        isAccent: Bool = false,
        accentColor: Color = Pixel16Palette.cyan,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.action = action
        self.isAccent = isAccent
        self.accentColor = accentColor
        self.label = label
    }

    public var body: some View {
        Button(action: {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            action()
        }) {
            label()
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(isAccent
                            ? (isHovered ? accentColor.opacity(0.95) : accentColor)
                            : (isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.06)))
                )
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - 16-Bit Lineless Badge

public struct Pixel16Badge: View {
    public let text: String
    public var color: Color = Pixel16Palette.cyan
    public var isFilled: Bool = false

    public init(_ text: String, color: Color = Pixel16Palette.cyan, isFilled: Bool = false) {
        self.text = text
        self.color = color
        self.isFilled = isFilled
    }

    public var body: some View {
        HStack(spacing: 3) {
            PixelText(
                text: text.uppercased(),
                color: isFilled ? Color.black : color,
                pixelSize: 1.05
            )
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2.5)
        .background(
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(isFilled ? color : color.opacity(0.12))
        )
        .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
    }
}

// MARK: - 16-Bit Thinking / Computing Indicator

public struct Pixel16ThinkingDots: View {
    public var color: Color = Pixel16Palette.cyan
    @State private var phase: Int = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    public init(color: Color = Pixel16Palette.cyan) {
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Text("■")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(color.opacity(phase == i ? 1.0 : 0.25))
            }
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}
