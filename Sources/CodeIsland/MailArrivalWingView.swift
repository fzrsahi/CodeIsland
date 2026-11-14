import SwiftUI
import CodeIslandCore

// MARK: - Roller Coaster & Direct Swoop Geometry Helper

public struct RollerCoasterGeometry {
    // Generates cubic Bézier spline segments:
    // Starts at x = 4 (center notch, right beside camera)
    // Travels to the right into the mailbox:
    // 1. isCompact == true (Notch Tidur / Idle, width ~62): Direct, snappy curved swoop into mailbox (entryX = 37)
    // 2. isCompact == false (Agent Aktif / Jalan, width = 118): 360° loop-de-loop (apex y = 9.5, never cut off by top bezel, entryX = 93)

    public static func controlPoints(for width: CGFloat, isCompact: Bool) -> [(p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint)] {
        let entryX = max(width - 25, isCompact ? 35 : 78)
        let entryY: CGFloat = 14.0

        if isCompact {
            // Direct curved swoop from center (x = 4) into mailbox (x = entryX)
            let seg = (
                p0: CGPoint(x: 4, y: 14.0),
                p1: CGPoint(x: 16, y: 17.5),
                p2: CGPoint(x: entryX - 10, y: 12.0),
                p3: CGPoint(x: entryX, y: entryY)
            )
            return [seg]
        }

        // Active Agent Mode (width = 118):
        // Envelope starts at x = 4 (center notch, right beside camera)
        // Curves up to loop apex at loopX ~ 47, y = 9.5
        // Loops clockwise down to y = 20.0
        // Exits loop at x = 62, y = 14.0
        // Glides straight into mailbox door at (entryX, 14.0)
        let loopX = min(max(entryX * 0.50, 44), 52)

        let seg0 = (
            p0: CGPoint(x: 4, y: 14.0),
            p1: CGPoint(x: loopX - 24, y: 14.0),
            p2: CGPoint(x: loopX - 12, y: 9.5),
            p3: CGPoint(x: loopX, y: 9.5)
        )
        let seg1 = (
            p0: CGPoint(x: loopX, y: 9.5),
            p1: CGPoint(x: loopX + 14, y: 9.5),
            p2: CGPoint(x: loopX + 16, y: 17.0),
            p3: CGPoint(x: loopX + 8, y: 20.0)
        )
        let seg2 = (
            p0: CGPoint(x: loopX + 8, y: 20.0),
            p1: CGPoint(x: loopX + 1, y: 21.0),
            p2: CGPoint(x: loopX + 2, y: 14.0),
            p3: CGPoint(x: loopX + 15, y: 14.0)
        )
        let seg3 = (
            p0: CGPoint(x: loopX + 15, y: 14.0),
            p1: CGPoint(x: loopX + 28, y: 14.0),
            p2: CGPoint(x: entryX - 8, y: entryY),
            p3: CGPoint(x: entryX, y: entryY)
        )
        return [seg0, seg1, seg2, seg3]
    }

    public static func buildPath(for width: CGFloat, isCompact: Bool) -> Path {
        let segments = controlPoints(for: width, isCompact: isCompact)
        var path = Path()
        guard let first = segments.first else { return path }
        path.move(to: first.p0)
        for seg in segments {
            path.addCurve(to: seg.p3, control1: seg.p1, control2: seg.p2)
        }
        return path
    }

    public static func sample(at progress: CGFloat, for width: CGFloat, isCompact: Bool) -> (point: CGPoint, angle: Double) {
        let clamped = min(max(progress, 0.0), 1.0)
        let segments = controlPoints(for: width, isCompact: isCompact)
        let count = CGFloat(segments.count)

        let scaled = clamped * count
        var segIndex = Int(scaled)
        if segIndex >= segments.count { segIndex = segments.count - 1 }
        let u = scaled - CGFloat(segIndex)

        let seg = segments[segIndex]
        let p0 = seg.p0
        let p1 = seg.p1
        let p2 = seg.p2
        let p3 = seg.p3

        let om = 1.0 - u
        let om2 = om * om
        let om3 = om2 * om
        let u2 = u * u
        let u3 = u2 * u

        // Position on cubic Bézier
        let x = om3 * p0.x + 3 * om2 * u * p1.x + 3 * om * u2 * p2.x + u3 * p3.x
        let y = om3 * p0.y + 3 * om2 * u * p1.y + 3 * om * u2 * p2.y + u3 * p3.y

        // First derivative (tangent direction)
        let dx = 3 * om2 * (p1.x - p0.x) + 6 * om * u * (p2.x - p1.x) + 3 * u2 * (p3.x - p2.x)
        let dy = 3 * om2 * (p1.y - p0.y) + 6 * om * u * (p2.y - p1.y) + 3 * u2 * (p3.y - p2.y)

        let angle = atan2(dy, dx) * 180.0 / .pi
        return (CGPoint(x: x, y: y), angle)
    }
}

// MARK: - Synchronized Realtime Trail Shape

private struct RollerCoasterTrailPath: Shape {
    var progress: CGFloat
    var width: CGFloat
    var isCompact: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let fullPath = RollerCoasterGeometry.buildPath(for: width > 0 ? width : rect.width, isCompact: isCompact)
        return fullPath.trimmedPath(from: 0, to: min(max(progress, 0.0), 1.0))
    }
}

// MARK: - Main Mail Arrival Right Wing View

public struct MailArrivalWingView: View {
    let isRetro: Bool
    let accentColor: Color
    let isCompact: Bool
    var onTap: (() -> Void)? = nil

    @ObservedObject private var mailManager = MailManager.shared

    public init(
        isRetro: Bool = false,
        accentColor: Color = Color(red: 0.96, green: 0.25, blue: 0.37),
        isCompact: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.isRetro = isRetro
        self.accentColor = accentColor
        self.isCompact = isCompact
        self.onTap = onTap
    }

    private func smoothProgress(_ t: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0.0), 1.0)
        return clamped * clamped * (3.0 - 2.0 * clamped)
    }

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            TimelineView(.animation) { timeline in
                let elapsed = max(0.0, timeline.date.timeIntervalSince(mailManager.arrivalAnimStartTime))
                let duration: Double = isCompact ? 0.85 : 1.25
                let rawProgress = min(max(CGFloat(elapsed / duration), 0.0), 1.0)
                let progress = smoothProgress(rawProgress)

                let flagUp = progress >= 0.88
                let mailboxRecoil = progress >= 0.88 && progress < 0.98
                let showBadge = progress >= 0.92

                ZStack(alignment: .trailing) {
                    // 1. Dynamic Real-time Trailing Wake
                    let trailOpacity: Double = {
                        if progress < 0.02 { return 0.0 }
                        if progress > 0.88 {
                            return max(0.0, 1.0 - Double((progress - 0.88) / 0.12))
                        }
                        return 0.95
                    }()

                    if isRetro {
                        // Dotted Pixel Trail
                        RollerCoasterTrailPath(progress: progress, width: w, isCompact: isCompact)
                            .stroke(
                                accentColor,
                                style: StrokeStyle(lineWidth: 1.2, dash: [2.0, 2.0])
                            )
                            .opacity(trailOpacity)
                    } else {
                        // Luminous Gradient Vapor Trail
                        RollerCoasterTrailPath(progress: progress, width: w, isCompact: isCompact)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.cyan.opacity(0.35),
                                        accentColor.opacity(0.85),
                                        Color.white.opacity(0.95)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 1.3, lineCap: .round)
                            )
                            .shadow(color: accentColor.opacity(0.45), radius: 1.5)
                            .opacity(trailOpacity)
                    }

                    // 2. Flying Envelope (Sampled along exact same spline, 100% visible from start at x=4)
                    let sample = RollerCoasterGeometry.sample(at: progress, for: w, isCompact: isCompact)
                    let letterScale: CGFloat = {
                        if progress >= 0.88 {
                            return max(0.2, 1.0 - (progress - 0.88) / 0.12 * 0.8)
                        }
                        return 1.0
                    }()
                    let letterOpacity: Double = {
                        if progress >= 0.94 {
                            return max(0.0, 1.0 - Double((progress - 0.94) / 0.06))
                        }
                        return 1.0
                    }()

                    Group {
                        if isRetro {
                            PixelMiniEnvelopeView(accentColor: accentColor)
                        } else {
                            ModernMiniEnvelopeView(accentColor: accentColor)
                        }
                    }
                    .scaleEffect(letterScale)
                    .rotationEffect(.degrees(sample.angle))
                    .position(sample.point)
                    .opacity(letterOpacity)

                    // 3. Mailbox Anchor at far right (Pinned with 6pt safe corner clearance, perfectly inside notch 32pt height)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)

                        ZStack(alignment: .topTrailing) {
                            if isRetro {
                                RetroPixelCurbMailboxView(
                                    flagUp: flagUp,
                                    recoil: mailboxRecoil,
                                    accentColor: accentColor
                                )
                            } else {
                                ModernCleanCurbMailboxView(
                                    flagUp: flagUp,
                                    recoil: mailboxRecoil,
                                    accentColor: accentColor
                                )
                            }

                            // Clean +1 badge popping cleanly above mailbox dome
                            if showBadge {
                                Text("+1")
                                    .font(.system(size: 6.8, weight: .heavy, design: isRetro ? .monospaced : .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 2.8)
                                    .padding(.vertical, 0.8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 2.8)
                                            .fill(accentColor)
                                            .shadow(color: accentColor.opacity(0.45), radius: 1.2)
                                    )
                                    .offset(x: -1, y: -4.5)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .frame(width: 19, height: 16.5)
                        .padding(.trailing, 6)
                    }
                    .frame(width: w, height: h, alignment: .trailing)
                }
                .frame(width: w, height: h, alignment: .trailing)
            }
        }
        .frame(height: 32)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }
}

// MARK: - Modern Crisp Mini Envelope

private struct ModernMiniEnvelopeView: View {
    let accentColor: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.white)
                .frame(width: 12.5, height: 8.5)
                .shadow(color: Color.black.opacity(0.35), radius: 1.0)

            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 6.25, y: 4.6))
                path.addLine(to: CGPoint(x: 12.5, y: 0))
            }
            .stroke(accentColor, lineWidth: 0.9)
            .frame(width: 12.5, height: 8.5)
        }
    }
}

// MARK: - Authentic 8-Bit Pixel Mini Envelope (Shaded)

private struct PixelMiniEnvelopeView: View {
    let accentColor: Color

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.white)
                .frame(width: 12.5, height: 8.5)

            VStack {
                Spacer()
                Rectangle()
                    .fill(Color(red: 0.80, green: 0.83, blue: 0.88))
                    .frame(width: 12.5, height: 1)
            }
            .frame(width: 12.5, height: 8.5)

            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 6.25, y: 4.4))
                path.addLine(to: CGPoint(x: 12.5, y: 0))
            }
            .stroke(accentColor, style: StrokeStyle(lineWidth: 1.1, lineCap: .square))
            .frame(width: 12.5, height: 8.5)

            Rectangle()
                .fill(Color(red: 0.94, green: 0.25, blue: 0.37))
                .frame(width: 3.0, height: 1.8)
                .offset(y: 1.0)
        }
    }
}

// MARK: - Modern Clean Suburban Curb Mailbox (19x16.5, Warm Wood Post & Crisp Metallic Dome)

private struct ModernCleanCurbMailboxView: View {
    let flagUp: Bool
    let recoil: Bool
    let accentColor: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // 1. Warm Timber Post (Height 6, safely inside notch)
            HStack(spacing: 0) {
                Rectangle().fill(Color(red: 0.68, green: 0.32, blue: 0.05)).frame(width: 0.8, height: 6)
                Rectangle().fill(Color(red: 0.45, green: 0.20, blue: 0.05)).frame(width: 1.1, height: 6)
            }
            .offset(x: 8.5, y: 0)

            // 2. Mailbox Body
            ZStack(alignment: .trailing) {
                // Curved suburban dome with silver top highlight & deep slate shadow
                Path { path in
                    path.move(to: CGPoint(x: 1, y: 3.5))
                    path.addQuadCurve(to: CGPoint(x: 16, y: 3.5), control: CGPoint(x: 8.5, y: 0.5))
                    path.addLine(to: CGPoint(x: 16, y: 10))
                    path.addLine(to: CGPoint(x: 1, y: 10))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.45, green: 0.52, blue: 0.62),
                            Color(red: 0.22, green: 0.27, blue: 0.35),
                            Color(red: 0.12, green: 0.16, blue: 0.22)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Path { path in
                        path.move(to: CGPoint(x: 1, y: 3.5))
                        path.addQuadCurve(to: CGPoint(x: 16, y: 3.5), control: CGPoint(x: 8.5, y: 0.5))
                        path.addLine(to: CGPoint(x: 16, y: 10))
                        path.addLine(to: CGPoint(x: 1, y: 10))
                        path.closeSubpath()
                    }
                    .stroke(Color.white.opacity(0.85), lineWidth: 0.8)
                )

                // Entrance cavity on left
                Path { path in
                    path.move(to: CGPoint(x: 1, y: 3.5))
                    path.addQuadCurve(to: CGPoint(x: 5, y: 3.5), control: CGPoint(x: 3, y: 1.3))
                    path.addLine(to: CGPoint(x: 5, y: 10))
                    path.addLine(to: CGPoint(x: 1, y: 10))
                    path.closeSubpath()
                }
                .fill(Color(red: 0.02, green: 0.04, blue: 0.08))
                .overlay(
                    Path { path in
                        path.move(to: CGPoint(x: 1, y: 3.5))
                        path.addQuadCurve(to: CGPoint(x: 5, y: 3.5), control: CGPoint(x: 3, y: 1.3))
                        path.addLine(to: CGPoint(x: 5, y: 10))
                        path.addLine(to: CGPoint(x: 1, y: 10))
                        path.closeSubpath()
                    }
                    .stroke(accentColor, lineWidth: 0.8)
                )

                // Red Flip-up Flag with yellow brass bolt
                ZStack(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Rectangle().fill(Color(red: 0.98, green: 0.32, blue: 0.32)).frame(width: 3.0, height: 1.8)
                        Rectangle().fill(Color(red: 0.90, green: 0.20, blue: 0.20)).frame(width: 1.2, height: 3.0)
                    }

                    Circle()
                        .fill(Color(red: 0.99, green: 0.88, blue: 0.28))
                        .frame(width: 1.8, height: 1.8)
                        .offset(x: -0.2, y: 3.5)
                }
                .rotationEffect(.degrees(flagUp ? -72 : 0), anchor: .bottomLeading)
                .offset(x: 2.5, y: -2.5)
            }
            .frame(width: 17, height: 10.5)
            .offset(y: -5.5)
            .scaleEffect(recoil ? 1.12 : 1.0, anchor: .center)
        }
        .frame(width: 19, height: 16.5)
    }
}

// MARK: - Authentic 8-Bit Pixel Art Curb Mailbox (19x16.5, Solid Shading, Volume & Depth)

private struct RetroPixelCurbMailboxView: View {
    let flagUp: Bool
    let recoil: Bool
    let accentColor: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // 1. Shaded 3-Tone Wooden Timber Post (Height 6, safely inside notch)
            HStack(spacing: 0) {
                Rectangle().fill(Color(red: 0.71, green: 0.33, blue: 0.04)).frame(width: 0.8, height: 6)
                Rectangle().fill(Color(red: 0.47, green: 0.21, blue: 0.06)).frame(width: 1.1, height: 6)
                Rectangle().fill(Color(red: 0.27, green: 0.10, blue: 0.01)).frame(width: 0.7, height: 6)
            }
            .offset(x: 8.2, y: 0)

            // 2. Stepped Curved Dome with Solid Pixel Shading & Volume
            ZStack(alignment: .trailing) {
                VStack(spacing: 0) {
                    // Top dome highlights (light silver reflection)
                    Rectangle().fill(Color(red: 0.95, green: 0.96, blue: 0.98)).frame(width: 11, height: 1)
                    Rectangle().fill(Color(red: 0.80, green: 0.84, blue: 0.88)).frame(width: 14, height: 1)

                    // Upper body midtone
                    Rectangle().fill(Color(red: 0.39, green: 0.45, blue: 0.55)).frame(width: 16.5, height: 2.2)

                    // Lower body & shadow depth
                    Rectangle().fill(Color(red: 0.20, green: 0.25, blue: 0.33)).frame(width: 16.5, height: 2.4)
                    Rectangle().fill(Color(red: 0.12, green: 0.16, blue: 0.23)).frame(width: 16.5, height: 1.5)
                    Rectangle().fill(Color(red: 0.06, green: 0.09, blue: 0.16)).frame(width: 14, height: 1.2)
                }
                .overlay(alignment: .leading) {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(accentColor)
                            .frame(width: 1.0, height: 6.0)
                        Rectangle()
                            .fill(Color(red: 0.01, green: 0.02, blue: 0.09))
                            .frame(width: 3.8, height: 6.0)
                    }
                    .offset(x: 1, y: 1.0)
                }

                // 3. Pixel Red Flag with Brass Pivot Pin
                ZStack(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Rectangle().fill(Color(red: 0.97, green: 0.44, blue: 0.44)).frame(width: 3.0, height: 1.8)
                        Rectangle().fill(Color(red: 0.88, green: 0.18, blue: 0.18)).frame(width: 1.2, height: 3.0)
                    }

                    Rectangle()
                        .fill(Color(red: 0.99, green: 0.88, blue: 0.28))
                        .frame(width: 1.8, height: 1.8)
                        .offset(x: -0.3, y: 3.5)
                }
                .rotationEffect(.degrees(flagUp ? -72 : 0), anchor: .bottomLeading)
                .offset(x: 2.5, y: -2.5)
            }
            .frame(width: 17, height: 10.5)
            .offset(y: -5.5)
            .scaleEffect(recoil ? 1.12 : 1.0, anchor: .center)
        }
        .frame(width: 19, height: 16.5)
    }
}
