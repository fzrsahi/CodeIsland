import SwiftUI
import CodeIslandCore

// MARK: - Smooth Forward Roller Coaster Spline Geometry Helper

public struct RollerCoasterGeometry {
    // Single continuous cubic Bézier curve strictly moving forward (dx > 0 everywhere)
    // Starts outside on the left (x = 6.0)
    // Travels smoothly across into the mailbox door on the right (x = entryX)
    // Never moves backward, never flips upside down, perfectly enters mailbox slot

    public static func controlPoints(for width: CGFloat, isCompact: Bool) -> (p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) {
        let effectiveWidth = max(width, 48)
        let entryX = max(effectiveWidth - 24, 28)
        let entryY: CGFloat = 14.0

        if isCompact || effectiveWidth < 85 {
            // Direct smooth curved swoop into mailbox
            return (
                p0: CGPoint(x: 6.0, y: 14.0),
                p1: CGPoint(x: 6.0 + (entryX - 6.0) * 0.35, y: 11.5),
                p2: CGPoint(x: 6.0 + (entryX - 6.0) * 0.70, y: 16.5),
                p3: CGPoint(x: entryX, y: entryY)
            )
        } else {
            // Active Agent mode: graceful roller coaster wave
            return (
                p0: CGPoint(x: 6.0, y: 14.0),
                p1: CGPoint(x: 6.0 + (entryX - 6.0) * 0.30, y: 8.5),
                p2: CGPoint(x: 6.0 + (entryX - 6.0) * 0.65, y: 19.5),
                p3: CGPoint(x: entryX, y: entryY)
            )
        }
    }

    public static func sample(at progress: CGFloat, for width: CGFloat, isCompact: Bool) -> (point: CGPoint, angle: Double) {
        let u = min(max(progress, 0.0), 1.0)
        let cp = controlPoints(for: width, isCompact: isCompact)

        let om = 1.0 - u
        let om2 = om * om
        let om3 = om2 * om
        let u2 = u * u
        let u3 = u2 * u

        // Position on cubic Bézier
        let x = om3 * cp.p0.x + 3 * om2 * u * cp.p1.x + 3 * om * u2 * cp.p2.x + u3 * cp.p3.x
        let y = om3 * cp.p0.y + 3 * om2 * u * cp.p1.y + 3 * om * u2 * cp.p2.y + u3 * cp.p3.y

        // First derivative (tangent direction - strictly dx > 0)
        let dx = 3 * om2 * (cp.p1.x - cp.p0.x) + 6 * om * u * (cp.p2.x - cp.p1.x) + 3 * u2 * (cp.p3.x - cp.p2.x)
        let dy = 3 * om2 * (cp.p1.y - cp.p0.y) + 6 * om * u * (cp.p2.y - cp.p1.y) + 3 * u2 * (cp.p3.y - cp.p2.y)

        let angle = atan2(dy, max(dx, 0.1)) * 180.0 / .pi
        return (CGPoint(x: x, y: y), angle)
    }
}

// MARK: - Synchronized Realtime Trail Shape (Behind the moving envelope)

private struct RollerCoasterTrailShape: Shape {
    var progress: CGFloat
    var width: CGFloat
    var isCompact: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard progress > 0.02 else { return path }
        let clamped = min(max(progress, 0.0), 1.0)
        let totalSteps = max(4, Int(clamped * 40))
        let effectiveW = width > 0 ? width : rect.width

        for i in 0...totalSteps {
            let t = clamped * CGFloat(i) / CGFloat(totalSteps)
            let pt = RollerCoasterGeometry.sample(at: t, for: effectiveW, isCompact: isCompact).point
            if i == 0 {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }
        return path
    }
}

// MARK: - Main Mail Arrival Right Wing View

public struct MailArrivalWingView: View {
    let isRetro: Bool
    let accentColor: Color
    let isCompact: Bool
    var onTap: (() -> Void)? = nil

    @ObservedObject private var mailManager = MailManager.shared
    @State private var animStartTime: Date? = nil

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

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let effectiveCompact = isCompact || w < 85

            TimelineView(.animation) { timeline in
                let start = animStartTime ?? mailManager.arrivalAnimStartTime
                let elapsed = max(0.0, timeline.date.timeIntervalSince(start))
                
                // Staged Timing:
                // 0.00s - 0.10s: Brief cushion for wing spring expansion
                // 0.10s - 1.05s: Smooth flight from left outside (x=6) to mailbox door (x=entryX)
                // 1.05s - 1.18s: Letter slides into mailbox cavity and scales down to 0
                // 1.18s - 1.28s: Mailbox recoils/bounces
                // 1.28s - 1.38s: Red flag raises
                // 1.38s+: +1 badge pops up above mailbox dome
                let flightDuration: Double = effectiveCompact ? 0.75 : 1.05
                let flightProgress: CGFloat = {
                    let activeElapsed = max(0.0, elapsed - 0.08)
                    let p = min(max(CGFloat(activeElapsed / flightDuration), 0.0), 1.0)
                    // Smooth cubic ease-in-out
                    return p * p * (3.0 - 2.0 * p)
                }()

                let totalDuration: Double = effectiveCompact ? 1.05 : 1.40
                let totalProgress = min(max(CGFloat(elapsed / totalDuration), 0.0), 1.0)

                let flagUp = totalProgress >= 0.88
                let mailboxRecoil = totalProgress >= 0.82 && totalProgress < 0.94
                let showBadge = totalProgress >= 0.92

                ZStack(alignment: .topLeading) {
                    // 1. Dynamic Real-time Trailing Wake (Grows behind the envelope, fades as it enters)
                    let trailOpacity: Double = {
                        if flightProgress < 0.04 { return 0.0 }
                        if flightProgress > 0.88 {
                            return max(0.0, 1.0 - Double((flightProgress - 0.88) / 0.12))
                        }
                        return 0.95
                    }()

                    if isRetro {
                        // Dotted Pixel Trail
                        RollerCoasterTrailShape(progress: flightProgress, width: w, isCompact: effectiveCompact)
                            .stroke(
                                accentColor,
                                style: StrokeStyle(lineWidth: 1.2, dash: [2.0, 2.0])
                            )
                            .opacity(trailOpacity)
                            .zIndex(1)
                    } else {
                        // Luminous Gradient Vapor Trail
                        RollerCoasterTrailShape(progress: flightProgress, width: w, isCompact: effectiveCompact)
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
                            .zIndex(1)
                    }

                    // 2. Mailbox Anchor at far right (Pinned with 6pt safe corner clearance)
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

                            // Clean +1 badge popping cleanly above mailbox dome once mail has entered
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
                    .zIndex(2)

                    // 3. Flying Envelope (Starts strictly outside on left x=6, travels right, enters mailbox opening)
                    let sample = RollerCoasterGeometry.sample(at: flightProgress, for: w, isCompact: effectiveCompact)
                    let letterScale: CGFloat = {
                        if flightProgress >= 0.88 {
                            // Tucks cleanly into mailbox slot
                            return max(0.0, 1.0 - (flightProgress - 0.88) / 0.12)
                        }
                        return 1.0
                    }()
                    let letterOpacity: Double = {
                        if flightProgress < 0.02 {
                            return Double(flightProgress / 0.02)
                        }
                        if flightProgress >= 0.90 {
                            return max(0.0, 1.0 - Double((flightProgress - 0.90) / 0.10))
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
                    .zIndex(10)
                }
                .frame(width: w, height: h, alignment: .topLeading)
                .transaction { $0.animation = nil }
            }
        }
        .frame(height: 32)
        .contentShape(Rectangle())
        .onAppear {
            animStartTime = Date()
        }
        .onChange(of: mailManager.arrivalAnimId) { _ in
            animStartTime = Date()
        }
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

                // Entrance cavity on left (facing incoming letters from center notch)
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
