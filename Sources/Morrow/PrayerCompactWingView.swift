import SwiftUI
import MorrowCore

/// Frameless compact right-wing prayer countdown respecting strict Idle (41–56pt) and Thinking (118–168pt) budgets.
/// Displays 5 distinct astronomical sun/moon icons (Subuh, Dzuhur, Ashar, Maghrib, Isya) in both 16-bit Pixel and Modern themes.
public struct PrayerCompactWingView: View {
    @ObservedObject var manager = PrayerTimeManager.shared
    var isHovered: Bool = false
    var isWideMode: Bool = false
    var onExpand: (() -> Void)? = nil

    @AppStorage(SettingsKey.islandUITheme) private var islandUITheme = SettingsDefaults.islandUITheme
    @State private var localHover: Bool = false

    private var isPixel: Bool {
        islandUITheme == IslandUITheme.pixel.rawValue
    }

    private var effectiveHover: Bool {
        isHovered || localHover
    }

    public init(isHovered: Bool = false, isWideMode: Bool = false, onExpand: (() -> Void)? = nil) {
        self.isHovered = isHovered
        self.isWideMode = isWideMode
        self.onExpand = onExpand
    }

    private var activePrayer: PrayerType {
        manager.upcomingPrayer?.prayer ?? .maghrib
    }

    private var iconSize: CGFloat {
        if isWideMode { return 20 }
        return isPixel ? 15 : 14
    }

    private func prayerAccentColor(for prayer: PrayerType, isUrgent: Bool) -> Color {
        if isUrgent {
            return isPixel ? Pixel16Palette.amber : Color(red: 1.0, green: 0.72, blue: 0.20)
        }
        switch prayer {
        case .imsak, .subuh, .terbit: return Color(red: 1.0, green: 0.70, blue: 0.42)
        case .dhuha, .dzuhur:         return Color(red: 0.35, green: 0.76, blue: 1.0)
        case .ashar:                  return Color(red: 1.0, green: 0.62, blue: 0.27)
        case .maghrib:                return Color(red: 1.0, green: 0.42, blue: 0.29)
        case .isya:                   return Color(red: 0.60, green: 0.60, blue: 1.0)
        }
    }

    public var body: some View {
        let prayer = activePrayer
        let mins = max(1, manager.minutesUntilNextPrayer)
        let isUrgent = mins <= 15
        let accent = prayerAccentColor(for: prayer, isUrgent: isUrgent)

        Group {
            if isPixel {
                pixelContent(prayer: prayer, mins: mins, accent: accent)
            } else {
                modernContent(prayer: prayer, mins: mins, accent: accent)
            }
        }
        .opacity(effectiveHover ? 1.0 : 0.94)
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(Rectangle())
        .onHover { localHover = $0 }
        .onTapGesture {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            onExpand?()
        }
        .help(helpTooltip)
    }

    // MARK: - 1. Pixel 16-Bit Frameless Content

    @ViewBuilder
    private func pixelContent(prayer: PrayerType, mins: Int, accent: Color) -> some View {
        HStack(alignment: .center, spacing: isWideMode ? 5 : 2.5) {
            PrayerPixelSpriteView(prayer: prayer)
                .frame(width: iconSize, height: iconSize)

            if isWideMode {
                PixelText(
                    text: prayer.displayName.uppercased(),
                    color: Pixel16Palette.textWhite,
                    pixelSize: 1.15
                )
            }

            PixelText(
                text: "-\(mins)M",
                color: accent,
                pixelSize: isWideMode ? 1.15 : 1.0
            )
        }
    }

    // MARK: - 2. Modern Frameless Content

    @ViewBuilder
    private func modernContent(prayer: PrayerType, mins: Int, accent: Color) -> some View {
        HStack(alignment: .center, spacing: isWideMode ? 5 : 2) {
            PrayerModernGlyphView(prayer: prayer)
                .frame(width: iconSize, height: iconSize)

            if isWideMode {
                Text(prayer.displayName)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
            }

            Text("-\(mins)m")
                .font(.system(size: isWideMode ? 10 : 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent)
                .lineLimit(1)
        }
    }

    private var helpTooltip: String {
        if let next = manager.upcomingPrayer {
            let diff = max(1, manager.minutesUntilNextPrayer)
            return "\(diff)m until \(next.prayer.displayName) (Click to expand Prayer tab)"
        }
        return "Prayer Times & Living Diorama (Click to expand)"
    }
}

// MARK: - 16×16 Multi-Color Pixel Sprites (Integer Grid, Zero Blur)

private struct PrayerPixelSpriteView: View {
    let prayer: PrayerType

    private static let palette: [Character: Color] = [
        "W": Color(red: 1.00, green: 0.97, blue: 0.84), // bright core
        "Y": Color(red: 1.00, green: 0.83, blue: 0.28), // warm sun yellow
        "O": Color(red: 1.00, green: 0.55, blue: 0.20), // sunset orange
        "R": Color(red: 0.91, green: 0.29, blue: 0.24), // deep horizon red
        "P": Color(red: 0.49, green: 0.32, blue: 0.58), // twilight purple
        "B": Color(red: 0.31, green: 0.66, blue: 1.00), // dawn reflection
        "M": Color(red: 0.96, green: 0.96, blue: 1.00), // moon highlight
        "L": Color(red: 0.72, green: 0.75, blue: 1.00), // moon midtone
        "D": Color(red: 0.44, green: 0.47, blue: 0.79), // moon shadow
        "S": Color(red: 1.00, green: 0.90, blue: 0.50), // star gold
    ]

    private var rows: [String] {
        switch prayer {
        case .imsak, .subuh, .terbit:
            return [
                "................",
                ".......YY.......",
                ".....Y....Y.....",
                "................",
                "......WWWW......",
                ".....WYYYYW.....",
                "....YYOOOOYY....",
                "..OOOOOOOOOOOO..",
                ".RRRRRRRRRRRRRR.",
                "...PPPPPPPPPP...",
                "................",
                "......BBBB......",
                "................",
                "................",
                "................",
                "................",
            ]
        case .dhuha, .dzuhur:
            return [
                ".......YY.......",
                ".......YY.......",
                "..Y..........Y..",
                "...Y..WWWW..Y...",
                ".....WYYYYW.....",
                "....WYYYYYYW....",
                "..Y.YYWWWWYY.Y..",
                "YY..YYWWWWYY..YY",
                "....YYYYYYYY....",
                "....OYYYYYYO....",
                "...Y..OOOO..Y...",
                "..Y..........Y..",
                ".......OO.......",
                ".......OO.......",
                "................",
                "................",
            ]
        case .ashar:
            return [
                "................",
                ".......YY.......",
                "...Y........Y...",
                "......WWWW......",
                ".....WYYYYW.....",
                "..Y..YYYYYY..Y..",
                ".....OYYYYO.....",
                "......OOOO......",
                "................",
                "..PPPPPPPPPPPP..",
                ".OOOOOOOOOOOOOO.",
                "....RRRRRRRR....",
                "................",
                "................",
                "................",
                "................",
            ]
        case .maghrib:
            return [
                "................",
                "................",
                "......OOOO......",
                "....OOYYYYOO....",
                "...OYYWWWWYYO...",
                "...YYWWWWWWYY...",
                "..ROOOOOOOOOOR..",
                ".RRRRRRRRRRRRRR.",
                "...PPPPPPPPPP...",
                "......RRRR......",
                ".......RR.......",
                "................",
                "................",
                "................",
                "................",
                "................",
            ]
        case .isya:
            return [
                "................",
                ".......MM.......",
                ".....MMLL.......",
                "....MLLD....S...",
                "...MLDD....SSS..",
                "...MLD......S...",
                "...MLD..........",
                "...MLDD.........",
                "....MLLD.....S..",
                ".....MMLL.......",
                ".......MM.......",
                "................",
                "................",
                "................",
                "................",
                "................",
            ]
        }
    }

    var body: some View {
        Canvas { context, size in
            let cellW = size.width / 16.0
            let cellH = size.height / 16.0
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() {
                    guard let color = Self.palette[ch] else { continue }
                    let rect = CGRect(
                        x: CGFloat(x) * cellW,
                        y: CGFloat(y) * cellH,
                        width: ceil(cellW),
                        height: ceil(cellH)
                    )
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }
}

// MARK: - Modern Multi-Tone Astronomical Prayer Icons (1:1 Match with Preview)

private struct PrayerModernGlyphView: View {
    let prayer: PrayerType

    var body: some View {
        Canvas { context, size in
            let sx = size.width / 24.0
            let sy = size.height / 24.0
            let s = min(sx, sy)
            context.scaleBy(x: s, y: s)

            switch prayer {
            case .imsak, .subuh, .terbit:
                // Up triangle
                var arrow = Path()
                arrow.move(to: CGPoint(x: 12, y: 4))
                arrow.addLine(to: CGPoint(x: 14.2, y: 6.5))
                arrow.addLine(to: CGPoint(x: 9.8, y: 6.5))
                arrow.closeSubpath()
                context.fill(arrow, with: .color(Color(red: 1.0, green: 0.82, blue: 0.40)))

                // Half sun rising
                var sun = Path()
                sun.addArc(center: CGPoint(x: 12, y: 15), radius: 5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                sun.closeSubpath()
                context.fill(
                    sun,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 1.0, green: 0.95, blue: 0.69),
                            Color(red: 1.0, green: 0.55, blue: 0.26),
                        ]),
                        startPoint: CGPoint(x: 12, y: 10),
                        endPoint: CGPoint(x: 12, y: 15)
                    )
                )

                // Horizon & twilight bars
                context.fill(
                    Path(roundedRect: CGRect(x: 3, y: 16.5, width: 18, height: 1.6), cornerRadius: 0.8),
                    with: .color(Color(red: 1.0, green: 0.70, blue: 0.42))
                )
                context.fill(
                    Path(roundedRect: CGRect(x: 6, y: 19.5, width: 12, height: 1.2), cornerRadius: 0.6),
                    with: .color(Color(red: 0.49, green: 0.32, blue: 0.58).opacity(0.85))
                )

            case .dhuha, .dzuhur:
                // Full zenith sun
                let circle = Path(ellipseIn: CGRect(x: 7, y: 7, width: 10, height: 10))
                context.fill(
                    circle,
                    with: .radialGradient(
                        Gradient(colors: [
                            .white,
                            Color(red: 1.0, green: 0.88, blue: 0.40),
                            Color(red: 1.0, green: 0.67, blue: 0.0),
                        ]),
                        center: CGPoint(x: 12, y: 12),
                        startRadius: 0,
                        endRadius: 5
                    )
                )

                // 8 rays
                var rays = Path()
                let rayCoords: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                    (12, 3, 12, 5), (12, 19, 12, 21),
                    (3, 12, 5, 12), (19, 12, 21, 12),
                    (5.6, 5.6, 7.1, 7.1), (16.9, 16.9, 18.4, 18.4),
                    (18.4, 5.6, 16.9, 7.1), (7.1, 16.9, 5.6, 18.4),
                ]
                for (x1, y1, x2, y2) in rayCoords {
                    rays.move(to: CGPoint(x: x1, y: y1))
                    rays.addLine(to: CGPoint(x: x2, y: y2))
                }
                context.stroke(
                    rays,
                    with: .color(Color(red: 1.0, green: 0.82, blue: 0.40)),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                )

            case .ashar:
                // Afternoon sun centered above twilight horizon
                let circle = Path(ellipseIn: CGRect(x: 7.7, y: 6.2, width: 8.6, height: 8.6))
                context.fill(
                    circle,
                    with: .radialGradient(
                        Gradient(colors: [
                            Color(red: 1.0, green: 0.94, blue: 0.65),
                            Color(red: 1.0, green: 0.55, blue: 0.14),
                        ]),
                        center: CGPoint(x: 12, y: 10.5),
                        startRadius: 0,
                        endRadius: 4.3
                    )
                )

                var rays = Path()
                let rayCoords: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                    (12, 3.5, 12, 5.0),
                    (5.0, 10.5, 6.4, 10.5),
                    (17.6, 10.5, 19.0, 10.5),
                    (7.1, 5.6, 8.1, 6.6),
                    (15.9, 6.6, 16.9, 5.6),
                ]
                for (x1, y1, x2, y2) in rayCoords {
                    rays.move(to: CGPoint(x: x1, y: y1))
                    rays.addLine(to: CGPoint(x: x2, y: y2))
                }
                context.stroke(
                    rays,
                    with: .color(Color(red: 1.0, green: 0.62, blue: 0.27)),
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                )

                context.fill(
                    Path(roundedRect: CGRect(x: 3, y: 17.5, width: 18, height: 1.6), cornerRadius: 0.8),
                    with: .color(Color(red: 0.49, green: 0.32, blue: 0.58))
                )
                context.fill(
                    Path(roundedRect: CGRect(x: 6, y: 20.0, width: 12, height: 1.2), cornerRadius: 0.6),
                    with: .color(Color(red: 1.0, green: 0.55, blue: 0.14))
                )

            case .maghrib:
                // Sunset half sun
                var sun = Path()
                sun.addArc(center: CGPoint(x: 12, y: 14.5), radius: 5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                sun.closeSubpath()
                context.fill(
                    sun,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 1.0, green: 0.70, blue: 0.28),
                            Color(red: 1.0, green: 0.30, blue: 0.30),
                        ]),
                        startPoint: CGPoint(x: 12, y: 9.5),
                        endPoint: CGPoint(x: 12, y: 14.5)
                    )
                )

                // Horizon bar
                context.fill(
                    Path(roundedRect: CGRect(x: 3, y: 15.5, width: 18, height: 1.6), cornerRadius: 0.8),
                    with: .color(Color(red: 1.0, green: 0.42, blue: 0.29))
                )

                // Down triangle
                var arrow = Path()
                arrow.move(to: CGPoint(x: 12, y: 20.5))
                arrow.addLine(to: CGPoint(x: 9.8, y: 18.3))
                arrow.addLine(to: CGPoint(x: 14.2, y: 18.3))
                arrow.closeSubpath()
                context.fill(arrow, with: .color(Color(red: 1.0, green: 0.42, blue: 0.29)))

            case .isya:
                // Crescent moon via even-odd mask
                var crescent = Path()
                crescent.addEllipse(in: CGRect(x: 4.2, y: 4.2, width: 15.6, height: 15.6))
                var cutout = Path()
                cutout.addEllipse(in: CGRect(x: 9.5, y: 3.0, width: 13.0, height: 13.0))
                let moonPath = crescent.subtracting(cutout)
                context.fill(
                    moonPath,
                    with: .linearGradient(
                        Gradient(colors: [
                            .white,
                            Color(red: 0.78, green: 0.78, blue: 1.0),
                            Color(red: 0.49, green: 0.49, blue: 0.90),
                        ]),
                        startPoint: CGPoint(x: 5, y: 5),
                        endPoint: CGPoint(x: 18, y: 19)
                    )
                )

                // Two stars
                context.fill(
                    Path(ellipseIn: CGRect(x: 16.6, y: 5.4, width: 2.4, height: 2.4)),
                    with: .color(Color(red: 1.0, green: 0.90, blue: 0.50))
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: 19.0, y: 9.4, width: 1.6, height: 1.6)),
                    with: .color(Color(red: 0.78, green: 0.78, blue: 1.0))
                )
            }
        }
    }
}
