import SwiftUI
import MorrowCore

// MARK: - Smooth Forward Roller Coaster Spline Geometry Helper

public struct RollerCoasterGeometry {
    // Single continuous cubic Bézier curve strictly moving forward (dx > 0 everywhere)
    // Starts outside on the far left (x = 10.0), well clear of the mailbox
    // Travels smoothly across into the mailbox cavity mouth on the right (x = entryX)
    // Never moves backward, never flips upside down, enters mailbox slot cleanly

    public static func controlPoints(for width: CGFloat, isCompact: Bool) -> (p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) {
        // Never clamp wider than actual width — entryX must stay locked to the mailbox cavity (w - 22.5)
        let entryX = max(width - 22.5, 16.0)
        let entryY: CGFloat = 14.0
        let startX = max(6.0, min(10.0, entryX - 24.0))
        let span = max(entryX - startX, 8.0)

        if isCompact || width < 80 {
            // Smooth forward arc into mailbox
            return (
                p0: CGPoint(x: startX, y: entryY),
                p1: CGPoint(x: startX + span * 0.35, y: 10.5),
                p2: CGPoint(x: startX + span * 0.70, y: 16.5),
                p3: CGPoint(x: entryX, y: entryY)
            )
        } else {
            // Active / full-runway mode: graceful roller coaster wave into mailbox cavity
            return (
                p0: CGPoint(x: startX, y: entryY),
                p1: CGPoint(x: startX + span * 0.30, y: 8.5),
                p2: CGPoint(x: startX + span * 0.68, y: 17.5),
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

        let rawAngle = atan2(dy, max(dx, 0.1)) * 180.0 / .pi
        // Level out cleanly as the envelope slides into the horizontal mailbox slot
        let levelOut: Double = u > 0.86 ? max(0.0, 1.0 - Double((u - 0.86) / 0.14)) : 1.0
        return (CGPoint(x: x, y: y), rawAngle * levelOut)
    }
}

// MARK: - Staged Arrival Timeline State (Pure & Deterministic)

public struct MailArrivalTimelineState: Equatable {
    public let flightProgress: CGFloat
    public let letterScale: CGFloat
    public let letterOpacity: Double
    public let trailOpacity: Double
    public let recoilScale: CGFloat
    public let flagAngle: Double
    public let badgeProgress: CGFloat

    // Staged execution timings (seconds):
    // 0.00 - 0.16s: Wing spring expansion (envelope hidden while wing is narrow)
    // 0.16 - 0.28s: Envelope fades in at far left outside mailbox (x = 10.0)
    // 0.28 - 0.46s: Envelope holds visible & still on the left so eye locks onto origin
    // 0.46 - 1.42s: Smooth forward flight left-to-right into mailbox cavity mouth
    //               (0.86 - 1.00 flightProgress tucks envelope cleanly into cavity)
    // 1.42 - 1.58s: Mailbox recoils upon letter arrival
    // 1.54 - 1.72s: Red flag flips up (-72°)
    // 1.66 - 1.84s: +1 badge springs up above mailbox dome
    public static let standbyFadeStart: Double = 0.16
    public static let standbyFadeEnd: Double = 0.28
    public static let flightStart: Double = 0.46
    public static let flightDuration: Double = 0.96
    public static let flightEnd: Double = flightStart + flightDuration // 1.42s

    public static func evaluate(at elapsed: TimeInterval) -> MailArrivalTimelineState {
        let t = max(0.0, elapsed)

        // 1. Flight progress (strictly 0 before flightStart, smoothly eases 0 -> 1)
        let rawFlight = min(max((t - flightStart) / flightDuration, 0.0), 1.0)
        let flightProgress = CGFloat(rawFlight * rawFlight * (3.0 - 2.0 * rawFlight))

        // 2. Envelope visibility & tuck-in scale
        let letterOpacity: Double = {
            if t < standbyFadeStart {
                return 0.0
            } else if t < standbyFadeEnd {
                return (t - standbyFadeStart) / (standbyFadeEnd - standbyFadeStart)
            } else if rawFlight >= 0.86 {
                let tuckT = min(max((rawFlight - 0.86) / 0.14, 0.0), 1.0)
                return max(0.0, 1.0 - pow(tuckT, 1.4))
            }
            return 1.0
        }()

        let letterScale: CGFloat = {
            if rawFlight >= 0.86 {
                let tuckT = min(max(CGFloat((rawFlight - 0.86) / 0.14), 0.0), 1.0)
                return max(0.0, 1.0 - tuckT)
            }
            return 1.0
        }()

        // 3. Trail wake (only appears once envelope launches forward; fades out on entry)
        let trailOpacity: Double = {
            if rawFlight <= 0.02 { return 0.0 }
            if rawFlight < 0.10 {
                return 0.95 * ((rawFlight - 0.02) / 0.08)
            }
            if rawFlight >= 0.82 {
                return max(0.0, 0.95 * (1.0 - (rawFlight - 0.82) / 0.16))
            }
            return 0.95
        }()

        // 4. Mailbox recoil, flag flip, and +1 badge (STRICTLY AFTER flightEnd)
        let recoilScale: CGFloat = {
            let recoilStart = flightEnd
            let recoilDur = 0.16
            guard t >= recoilStart && t < recoilStart + recoilDur else { return 1.0 }
            let u = (t - recoilStart) / recoilDur
            return 1.0 + 0.12 * CGFloat(sin(u * .pi))
        }()

        let flagAngle: Double = {
            let flagStart = flightEnd + 0.12 // 1.54s
            let flagDur = 0.18
            let downAngle = -85.0 // Folded flat left along mailbox dome while waiting
            guard t > flagStart else { return downAngle }
            let u = min(max((t - flagStart) / flagDur, 0.0), 1.0)
            // Ease-out back from down (-85°) to upright (0°)
            let c1 = 1.70158
            let c3 = c1 + 1.0
            let eased = 1.0 + c3 * pow(u - 1.0, 3) + c1 * pow(u - 1.0, 2)
            return downAngle * (1.0 - eased)
        }()

        let badgeProgress: CGFloat = {
            let badgeStart = flightEnd + 0.24 // 1.66s
            let badgeDur = 0.18
            guard t > badgeStart else { return 0.0 }
            let u = min(max((t - badgeStart) / badgeDur, 0.0), 1.0)
            let eased = 1.0 - pow(1.0 - u, 3)
            return CGFloat(eased)
        }()

        return MailArrivalTimelineState(
            flightProgress: flightProgress,
            letterScale: letterScale,
            letterOpacity: letterOpacity,
            trailOpacity: trailOpacity,
            recoilScale: recoilScale,
            flagAngle: flagAngle,
            badgeProgress: badgeProgress
        )
    }
}

// MARK: - Compact ("Kecil") Sealed Envelope Timeline State (Pure & Deterministic)

public struct MailCompactTimelineState: Equatable {
    public let opacity: Double
    public let scale: CGFloat
    public let yOffset: CGFloat
    public let tiltDegrees: Double
    public let flapOpen: CGFloat
    public let sealScale: CGFloat
    public let badgeProgress: CGFloat

    // Staged compact micro-ritual (seconds):
    // 0.00 - 0.14s: Envelope rises cleanly with top flap open
    // 0.14 - 0.36s: Top flap folds shut onto envelope body
    // 0.32 - 0.46s: Wax seal stamps vertex + gentle tilt settles (-6° -> 0°) + micro-bounce
    // 0.46 - 0.64s: +1 badge springs up at top-right corner above envelope
    public static func evaluate(at elapsed: TimeInterval) -> MailCompactTimelineState {
        let t = max(0.0, elapsed)

        let enterU = min(max(t / 0.16, 0.0), 1.0)
        let enterEase = 1.0 - pow(1.0 - enterU, 3)

        let opacity = enterEase
        let yOffset = CGFloat((1.0 - enterEase) * 3.5)

        // Flap closes from 1.0 (open) -> 0.0 (sealed) between 0.14s and 0.36s
        let closeU = min(max((t - 0.14) / 0.22, 0.0), 1.0)
        let closeEase = closeU * closeU * (3.0 - 2.0 * closeU)
        let flapOpen = CGFloat(1.0 - closeEase)

        // Wax seal stamps at flap vertex from 0.32s -> 0.46s
        let sealU = min(max((t - 0.32) / 0.14, 0.0), 1.0)
        let sealEase: Double = {
            guard sealU > 0 else { return 0.0 }
            let c1 = 1.70158
            let c3 = c1 + 1.0
            return 1.0 + c3 * pow(sealU - 1.0, 3) + c1 * pow(sealU - 1.0, 2)
        }()

        // Subtle tactile settle bounce when seal lands (0.34s -> 0.50s)
        let bounceScale: CGFloat = {
            if t < 0.16 {
                return CGFloat(0.86 + 0.14 * enterEase)
            }
            if t >= 0.34 && t < 0.50 {
                let b = (t - 0.34) / 0.16
                return 1.0 + 0.08 * CGFloat(sin(b * .pi))
            }
            return 1.0
        }()

        let tiltU = min(max((t - 0.12) / 0.30, 0.0), 1.0)
        let tiltEase = 1.0 - pow(1.0 - tiltU, 3)
        let tiltDegrees = -6.0 * (1.0 - tiltEase)

        // +1 badge pops at top-right above envelope from 0.46s -> 0.64s
        let badgeU = min(max((t - 0.46) / 0.18, 0.0), 1.0)
        let badgeEase = 1.0 - pow(1.0 - badgeU, 3)

        return MailCompactTimelineState(
            opacity: opacity,
            scale: bounceScale,
            yOffset: yOffset,
            tiltDegrees: tiltDegrees,
            flapOpen: flapOpen,
            sealScale: CGFloat(sealEase),
            badgeProgress: CGFloat(badgeEase)
        )
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
    let overrideElapsed: TimeInterval?
    var onTap: (() -> Void)? = nil

    @ObservedObject private var mailManager = MailManager.shared
    @State private var animStartTime: Date? = nil

    public init(
        isRetro: Bool = false,
        accentColor: Color = Color(red: 0.96, green: 0.25, blue: 0.37),
        isCompact: Bool = false,
        overrideElapsed: TimeInterval? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.isRetro = isRetro
        self.accentColor = accentColor
        self.isCompact = isCompact
        self.overrideElapsed = overrideElapsed
        self.onTap = onTap
    }

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            if let fixedElapsed = overrideElapsed {
                wingContent(w: w, h: h, elapsed: max(0.0, fixedElapsed))
            } else {
                TimelineView(.animation) { timeline in
                    let start = animStartTime ?? mailManager.arrivalAnimStartTime
                    let elapsed = max(0.0, timeline.date.timeIntervalSince(start))
                    wingContent(w: w, h: h, elapsed: elapsed)
                }
            }
        }
        .frame(
            minWidth: isCompact ? 32 : 96,
            idealWidth: isCompact ? 38 : 104,
            maxWidth: .infinity
        )
        .frame(height: 32)
        .clipped()
        .contentShape(Rectangle())
        .onAppear {
            animStartTime = Date()
        }
        .onChange(of: mailManager.arrivalAnimId) {
            animStartTime = Date()
        }
        .onTapGesture {
            onTap?()
        }
    }

    @ViewBuilder
    private func wingContent(w: CGFloat, h: CGFloat, elapsed: TimeInterval) -> some View {

                if isCompact {
                    // KECIL (52pt wing): Sealed Envelope + Top-Right +1 Badge (Option B)
                    let compactState = MailCompactTimelineState.evaluate(at: elapsed)

                    HStack(spacing: 0) {
                        Spacer(minLength: 0)

                        ZStack(alignment: .topTrailing) {
                            Group {
                                if isRetro {
                                    CompactPixelEnvelopeView(
                                        flapOpen: compactState.flapOpen,
                                        sealScale: compactState.sealScale,
                                        accentColor: accentColor
                                    )
                                } else {
                                    CompactModernEnvelopeView(
                                        flapOpen: compactState.flapOpen,
                                        sealScale: compactState.sealScale,
                                        accentColor: accentColor
                                    )
                                }
                            }
                            .scaleEffect(compactState.scale)
                            .rotationEffect(.degrees(compactState.tiltDegrees))
                            .offset(y: compactState.yOffset)
                            .opacity(compactState.opacity)

                            MailPlusOneBadgeView(
                                progress: compactState.badgeProgress,
                                isRetro: isRetro,
                                isCompact: true,
                                accentColor: accentColor,
                                xOffset: 3.4,
                                baseY: 0.5,
                                yDrop: 2.5
                            )
                        }
                        .padding(.trailing, 4)
                    }
                    .frame(width: w, height: h, alignment: .trailing)
                    .transaction { $0.animation = nil }
                } else {
                    // SEDANG (118pt wing): Roller coaster flight from left outside into curb mailbox
                    let state = MailArrivalTimelineState.evaluate(at: elapsed)

                    ZStack(alignment: .topLeading) {
                        // 1. Dynamic Real-time Trailing Wake (Grows behind the envelope, fades as it enters)
                        if isRetro {
                            RollerCoasterTrailShape(progress: state.flightProgress, width: w, isCompact: isCompact)
                                .stroke(
                                    accentColor,
                                    style: StrokeStyle(lineWidth: 1.2, dash: [2.0, 2.0])
                                )
                                .opacity(state.trailOpacity)
                                .zIndex(1)
                        } else {
                            RollerCoasterTrailShape(progress: state.flightProgress, width: w, isCompact: isCompact)
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
                                .opacity(state.trailOpacity)
                                .zIndex(1)
                        }

                        // 2. Mailbox Anchor at far right (Pinned with 6pt safe corner clearance)
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)

                            ZStack(alignment: .topTrailing) {
                                if isRetro {
                                    RetroPixelCurbMailboxView(
                                        flagAngle: state.flagAngle,
                                        recoilScale: state.recoilScale,
                                        accentColor: accentColor
                                    )
                                } else {
                                    ModernCleanCurbMailboxView(
                                        flagAngle: state.flagAngle,
                                        recoilScale: state.recoilScale,
                                        accentColor: accentColor
                                    )
                                }

                                // Clean +1 badge popping cleanly above mailbox dome once mail has entered
                                MailPlusOneBadgeView(
                                    progress: state.badgeProgress,
                                    isRetro: isRetro,
                                    isCompact: false,
                                    accentColor: accentColor,
                                    xOffset: -1,
                                    baseY: -4.5,
                                    yDrop: 3.0
                                )
                            }
                            .frame(width: 19, height: 16.5)
                            .padding(.trailing, 4)
                        }
                        .frame(width: w, height: h, alignment: .trailing)
                        .zIndex(2)

                        // 3. Flying Envelope (Appears clearly on the left outside mailbox, rests briefly, then glides right into cavity)
                        let sample = RollerCoasterGeometry.sample(at: state.flightProgress, for: w, isCompact: isCompact)

                        Group {
                            if isRetro {
                                PixelMiniEnvelopeView(accentColor: accentColor)
                            } else {
                                ModernMiniEnvelopeView(accentColor: accentColor)
                            }
                        }
                        .scaleEffect(state.letterScale)
                        .rotationEffect(.degrees(sample.angle))
                        .position(sample.point)
                        .opacity(state.letterOpacity)
                        .zIndex(10)
                    }
                    .frame(width: w, height: h, alignment: .topLeading)
                    .transaction { $0.animation = nil }
                }
    }
}

// MARK: - Shared +1 Arrival Badge

private struct MailPlusOneBadgeView: View {
    let progress: CGFloat
    let isRetro: Bool
    let isCompact: Bool
    let accentColor: Color
    let xOffset: CGFloat
    let baseY: CGFloat
    let yDrop: CGFloat

    var body: some View {
        if progress > 0.01 {
            let fgColor = AppColorTheme.contrastingForeground(on: accentColor)
            let isLight = AppColorTheme.isLightColor(accentColor)
            Text("+1")
                .font(.system(
                    size: isCompact ? 7.2 : 6.8,
                    weight: .heavy,
                    design: isRetro ? .monospaced : .rounded
                ))
                .foregroundStyle(fgColor)
                .padding(.horizontal, isCompact ? 2.7 : 2.8)
                .padding(.vertical, isCompact ? 0.7 : 0.8)
                .background(
                    RoundedRectangle(cornerRadius: 2.8)
                        .fill(accentColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2.8)
                                .stroke(Color.black.opacity(isLight ? 0.28 : 0.0), lineWidth: 0.45)
                        )
                        .shadow(color: accentColor.opacity(0.45), radius: 1.2, y: 0.4)
                )
                .scaleEffect(0.5 + 0.5 * progress)
                .opacity(Double(progress))
                .offset(x: xOffset, y: baseY + (1.0 - progress) * yDrop)
        }
    }
}

// MARK: - Compact Sealed Envelope Views (Mode Kecil 52pt)

private struct CompactModernEnvelopeView: View {
    let flapOpen: CGFloat
    let sealScale: CGFloat
    let accentColor: Color

    var body: some View {
        Canvas { context, size in
            let bodyRect = CGRect(x: 0.5, y: 5.5, width: size.width - 1.0, height: size.height - 6.5)
            let bodyPath = Path(roundedRect: bodyRect, cornerRadius: 3.0)

            // Subtle directional grounding shadow
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.42), radius: 1.4, x: 0, y: 1.0))
                layer.fill(
                    bodyPath,
                    with: .linearGradient(
                        Gradient(colors: [Color.white, Color(white: 0.89)]),
                        startPoint: CGPoint(x: bodyRect.midX, y: bodyRect.minY),
                        endPoint: CGPoint(x: bodyRect.midX, y: bodyRect.maxY)
                    )
                )
            }

            // Inner pocket recess visible while flap is open
            let leftHinge = CGPoint(x: bodyRect.minX + 1.4, y: bodyRect.minY + 0.6)
            let rightHinge = CGPoint(x: bodyRect.maxX - 1.4, y: bodyRect.minY + 0.6)
            if flapOpen > 0.45 {
                let openAlpha = min(max((flapOpen - 0.45) / 0.55, 0), 1)
                var pocket = Path()
                pocket.move(to: leftHinge)
                pocket.addLine(to: CGPoint(x: bodyRect.midX, y: bodyRect.minY + 6.2))
                pocket.addLine(to: rightHinge)
                pocket.closeSubpath()
                context.fill(pocket, with: .color(Color(white: 0.72).opacity(Double(openAlpha) * 0.55)))
            }

            // Lower paper fold lines for envelope depth
            var bottomFold = Path()
            bottomFold.move(to: CGPoint(x: bodyRect.minX + 1.6, y: bodyRect.maxY - 1.5))
            bottomFold.addLine(to: CGPoint(x: bodyRect.midX - 2.4, y: bodyRect.midY + 1.0))
            bottomFold.move(to: CGPoint(x: bodyRect.maxX - 1.6, y: bodyRect.maxY - 1.5))
            bottomFold.addLine(to: CGPoint(x: bodyRect.midX + 2.4, y: bodyRect.midY + 1.0))
            context.stroke(bottomFold, with: .color(Color(white: 0.76).opacity(0.85)), lineWidth: 0.9)

            // Crisp outer hairline border
            context.stroke(bodyPath, with: .color(Color.white.opacity(0.95)), lineWidth: 0.9)

            // Animated hinged flap: folds from open (upward) down to sealed V-crease
            let clampedOpen = min(max(flapOpen, 0), 1)
            let tipY = leftHinge.y + (1.0 - clampedOpen) * 7.6 - clampedOpen * 5.2
            var flapPath = Path()
            flapPath.move(to: leftHinge)
            flapPath.addLine(to: CGPoint(x: bodyRect.midX, y: tipY))
            flapPath.addLine(to: rightHinge)
            let inkAccent = AppColorTheme.envelopeAccentStroke(for: accentColor)

            if clampedOpen > 0.5 {
                flapPath.closeSubpath()
                context.fill(
                    flapPath,
                    with: .linearGradient(
                        Gradient(colors: [Color(white: 0.90), Color(white: 0.98)]),
                        startPoint: CGPoint(x: bodyRect.midX, y: tipY),
                        endPoint: leftHinge
                    )
                )
                context.stroke(flapPath, with: .color(inkAccent.opacity(0.88)), lineWidth: 1.0)
            } else {
                var closedFill = flapPath
                closedFill.closeSubpath()
                context.fill(
                    closedFill,
                    with: .linearGradient(
                        Gradient(colors: [Color.white, Color(white: 0.94)]),
                        startPoint: leftHinge,
                        endPoint: CGPoint(x: bodyRect.midX, y: tipY)
                    )
                )
                context.stroke(
                    flapPath,
                    with: .color(inkAccent),
                    style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round)
                )
            }

            // Tactile wax / accent seal at the closed flap apex
            let clampedSeal = min(max(sealScale, 0), 1)
            if clampedSeal > 0.05 {
                let sealRadius = 3.3 * clampedSeal
                let sealCenter = CGPoint(x: bodyRect.midX, y: leftHinge.y + 7.5)
                let sealRect = CGRect(
                    x: sealCenter.x - sealRadius,
                    y: sealCenter.y - sealRadius,
                    width: sealRadius * 2,
                    height: sealRadius * 2
                )
                context.fill(Path(ellipseIn: sealRect), with: .color(inkAccent))
                context.stroke(Path(ellipseIn: sealRect), with: .color(Color.white.opacity(0.92)), lineWidth: 0.85)

                let highlightRect = CGRect(
                    x: sealCenter.x - sealRadius * 0.42,
                    y: sealCenter.y - sealRadius * 0.42,
                    width: sealRadius * 0.55,
                    height: sealRadius * 0.55
                )
                context.fill(Path(ellipseIn: highlightRect), with: .color(Color.white.opacity(0.5)))
            }
        }
        .frame(width: 25, height: 22)
    }
}

private struct CompactPixelEnvelopeView: View {
    let flapOpen: CGFloat
    let sealScale: CGFloat
    let accentColor: Color

    var body: some View {
        Canvas { context, _ in
            let p: CGFloat = 1.95

            func px(_ col: Int, _ row: Int, _ color: Color) {
                context.fill(
                    Path(CGRect(x: CGFloat(col) * p, y: CGFloat(row) * p, width: p, height: p)),
                    with: .color(color)
                )
            }

            let paper = Color.white
            let paperEdge = Color(white: 0.84)
            let paperBack = Color(white: 0.91)
            let pocketDark = Color(white: 0.62)

            // Envelope body occupies rows 3...10 (13 cols wide: 0...12)
            for row in 3...10 {
                for col in 0...12 {
                    let isBorder = row == 3 || row == 10 || col == 0 || col == 12
                    px(col, row, isBorder ? paperEdge : paper)
                }
            }

            // Inner bottom fold diagonals for crisp 8-bit envelope silhouette
            px(1, 9, paperEdge)
            px(2, 8, paperEdge)
            px(3, 7, paperEdge)
            px(9, 7, paperEdge)
            px(10, 8, paperEdge)
            px(11, 9, paperEdge)

            if flapOpen > 0.62 {
                // Open flap stepped upward across rows 0..2
                for col in 5...7 { px(col, 0, paperBack) }
                for col in 3...9 { px(col, 1, paperBack) }
                for col in 1...11 { px(col, 2, paper) }
                // Highlight flap crest in accent color
                px(5, 0, accentColor)
                px(6, 0, accentColor)
                px(7, 0, accentColor)
                px(3, 1, accentColor)
                px(4, 1, accentColor)
                px(8, 1, accentColor)
                px(9, 1, accentColor)
                // Shaded interior pocket
                for col in 2...10 { px(col, 3, pocketDark) }
                for col in 4...8 { px(col, 4, pocketDark) }
                px(6, 5, pocketDark)
            } else if flapOpen > 0.25 {
                // Mid-fold across top hinge
                for col in 1...11 { px(col, 3, accentColor) }
                for col in 3...9 { px(col, 4, paperEdge) }
            } else {
                // Sealed V-flap crease in accent color
                px(1, 3, accentColor)
                px(2, 4, accentColor)
                px(3, 4, accentColor)
                px(4, 5, accentColor)
                px(5, 5, accentColor)
                px(6, 6, accentColor)
                px(7, 5, accentColor)
                px(8, 5, accentColor)
                px(9, 4, accentColor)
                px(10, 4, accentColor)
                px(11, 3, accentColor)
            }

            // Pixel wax seal centered on closed apex (6, 6)
            if sealScale > 0.65 {
                for row in 5...7 {
                    for col in 5...7 {
                        px(col, row, accentColor)
                    }
                }
                px(5, 5, .white.opacity(0.65))
            } else if sealScale > 0.15 {
                px(6, 6, accentColor)
                px(6, 5, accentColor)
            }
        }
        .frame(width: 25.35, height: 21.45)
    }
}

// MARK: - Modern Crisp Mini Envelope

private struct ModernMiniEnvelopeView: View {
    let accentColor: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.0, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white, Color(red: 0.91, green: 0.94, blue: 0.98)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 12.5, height: 8.5)
                .shadow(color: Color.black.opacity(0.38), radius: 1.2, y: 0.5)

            // Subtle lower paper fold lines
            Path { path in
                path.move(to: CGPoint(x: 0.6, y: 8.0))
                path.addLine(to: CGPoint(x: 4.5, y: 4.5))
                path.move(to: CGPoint(x: 11.9, y: 8.0))
                path.addLine(to: CGPoint(x: 8.0, y: 4.5))
            }
            .stroke(Color(red: 0.75, green: 0.80, blue: 0.88).opacity(0.75), lineWidth: 0.65)
            .frame(width: 12.5, height: 8.5)

            // Crisp top V-flap clipped cleanly inside the rounded card
            Path { path in
                path.move(to: CGPoint(x: 0.4, y: 0.4))
                path.addLine(to: CGPoint(x: 6.25, y: 4.7))
                path.addLine(to: CGPoint(x: 12.1, y: 0.4))
            }
            .stroke(
                AppColorTheme.envelopeAccentStroke(for: accentColor),
                style: StrokeStyle(lineWidth: 0.95, lineCap: .round, lineJoin: .round)
            )
            .frame(width: 12.5, height: 8.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 2.0, style: .continuous))
    }
}

// MARK: - Authentic 8-Bit Pixel Mini Envelope (Crisp Stepped Bitmap Sprite)

private struct PixelMiniEnvelopeView: View {
    let accentColor: Color

    // 11x8 pixel matrix:
    // 0 = transparent, 1 = crisp white paper, 2 = cool-grey pixel shade,
    // 3 = accent stepped V-flap, 4 = coral-red wax seal
    private static let rows: [[UInt8]] = [
        [3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 3],
        [1, 3, 3, 1, 1, 1, 1, 1, 3, 3, 1],
        [1, 1, 1, 3, 3, 1, 3, 3, 1, 1, 1],
        [1, 1, 1, 1, 3, 4, 3, 1, 1, 1, 1],
        [1, 1, 1, 1, 1, 4, 1, 1, 1, 1, 1],
        [1, 1, 2, 1, 1, 1, 1, 1, 2, 1, 1],
        [1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1],
        [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]
    ]

    var body: some View {
        let px: CGFloat = 1.15
        let w = CGFloat(Self.rows[0].count) * px
        let h = CGFloat(Self.rows.count) * px

        Canvas { ctx, _ in
            let shade = Color(red: 0.78, green: 0.82, blue: 0.89)
            let seal = Color(red: 0.96, green: 0.26, blue: 0.38)
            let inkAccent = AppColorTheme.envelopeAccentStroke(for: accentColor)

            for (r, row) in Self.rows.enumerated() {
                for (c, cell) in row.enumerated() where cell != 0 {
                    let rect = CGRect(
                        x: CGFloat(c) * px,
                        y: CGFloat(r) * px,
                        width: px,
                        height: px
                    )
                    let color: Color
                    switch cell {
                    case 1: color = .white
                    case 2: color = shade
                    case 3: color = inkAccent
                    default: color = seal
                    }
                    ctx.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: w, height: h)
    }
}

// MARK: - Modern Sleek macOS Curb Mailbox (19x16.5, Anodized Aluminum Barrel, Cylindrical Post & Capsule Flag)

private struct ModernCleanCurbMailboxView: View {
    let flagAngle: Double
    let recoilScale: CGFloat
    let accentColor: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // 1. Sleek Cylindrical Anodized Post with Mounting Collar
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color(red: 0.14, green: 0.17, blue: 0.22))
                    .frame(width: 4.4, height: 1.1)

                RoundedRectangle(cornerRadius: 0.9)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.28, green: 0.33, blue: 0.40),
                                Color(red: 0.62, green: 0.68, blue: 0.76),
                                Color(red: 0.40, green: 0.46, blue: 0.54),
                                Color(red: 0.18, green: 0.22, blue: 0.28)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 2.6, height: 5.5)
            }
            .offset(x: 7.8, y: 0)

            // 2. Smooth Rounded Barrel Mailbox Body (Apple macOS dimensional shading)
            ZStack(alignment: .trailing) {
                // Main brushed-titanium cylindrical hood
                Path { path in
                    path.move(to: CGPoint(x: 1.0, y: 9.8))
                    path.addLine(to: CGPoint(x: 1.0, y: 4.2))
                    path.addQuadCurve(to: CGPoint(x: 4.2, y: 1.0), control: CGPoint(x: 1.0, y: 1.2))
                    path.addLine(to: CGPoint(x: 13.0, y: 1.0))
                    path.addQuadCurve(to: CGPoint(x: 16.0, y: 4.2), control: CGPoint(x: 16.0, y: 1.2))
                    path.addLine(to: CGPoint(x: 16.0, y: 9.2))
                    path.addQuadCurve(to: CGPoint(x: 15.0, y: 10.2), control: CGPoint(x: 16.0, y: 10.2))
                    path.addLine(to: CGPoint(x: 2.0, y: 10.2))
                    path.addQuadCurve(to: CGPoint(x: 1.0, y: 9.8), control: CGPoint(x: 1.0, y: 10.2))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.88, green: 0.91, blue: 0.96), // Top specular rim
                            Color(red: 0.56, green: 0.62, blue: 0.71), // Brushed aluminum
                            Color(red: 0.28, green: 0.33, blue: 0.42), // Anodized midtone
                            Color(red: 0.14, green: 0.18, blue: 0.25)  // Deep underside
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    // Soft top-edge glass sheen along the roof
                    Path { path in
                        path.move(to: CGPoint(x: 4.0, y: 1.6))
                        path.addLine(to: CGPoint(x: 13.2, y: 1.6))
                    }
                    .stroke(Color.white.opacity(0.65), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
                )
                .overlay(
                    // Subtle separation rim so body reads cleanly on pure black notch
                    Path { path in
                        path.move(to: CGPoint(x: 1.0, y: 9.8))
                        path.addLine(to: CGPoint(x: 1.0, y: 4.2))
                        path.addQuadCurve(to: CGPoint(x: 4.2, y: 1.0), control: CGPoint(x: 1.0, y: 1.2))
                        path.addLine(to: CGPoint(x: 13.0, y: 1.0))
                        path.addQuadCurve(to: CGPoint(x: 16.0, y: 4.2), control: CGPoint(x: 16.0, y: 1.2))
                        path.addLine(to: CGPoint(x: 16.0, y: 9.2))
                        path.addQuadCurve(to: CGPoint(x: 15.0, y: 10.2), control: CGPoint(x: 16.0, y: 10.2))
                        path.addLine(to: CGPoint(x: 2.0, y: 10.2))
                        path.addQuadCurve(to: CGPoint(x: 1.0, y: 9.8), control: CGPoint(x: 1.0, y: 10.2))
                        path.closeSubpath()
                    }
                    .stroke(Color.white.opacity(0.24), lineWidth: 0.45)
                )

                // Recessed Dark Arch Entrance on left (subtle bevel + soft accent inner rim)
                Path { path in
                    path.move(to: CGPoint(x: 1.1, y: 10.0))
                    path.addLine(to: CGPoint(x: 1.1, y: 4.3))
                    path.addQuadCurve(to: CGPoint(x: 3.3, y: 1.5), control: CGPoint(x: 1.2, y: 1.6))
                    path.addQuadCurve(to: CGPoint(x: 5.5, y: 4.3), control: CGPoint(x: 5.4, y: 1.6))
                    path.addLine(to: CGPoint(x: 5.5, y: 10.0))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.02, green: 0.03, blue: 0.07),
                            Color(red: 0.07, green: 0.10, blue: 0.17)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    Path { path in
                        path.move(to: CGPoint(x: 1.1, y: 10.0))
                        path.addLine(to: CGPoint(x: 1.1, y: 4.3))
                        path.addQuadCurve(to: CGPoint(x: 3.3, y: 1.5), control: CGPoint(x: 1.2, y: 1.6))
                        path.addQuadCurve(to: CGPoint(x: 5.5, y: 4.3), control: CGPoint(x: 5.4, y: 1.6))
                        path.addLine(to: CGPoint(x: 5.5, y: 10.0))
                        path.closeSubpath()
                    }
                    .stroke(accentColor.opacity(0.75), lineWidth: 0.6)
                )

                // Sleek Capsule Red Flag bolted cleanly to brushed metallic stud
                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.38, blue: 0.42),
                                        Color(red: 0.88, green: 0.15, blue: 0.24)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 1.3, height: 4.8)

                        RoundedRectangle(cornerRadius: 0.65, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.45, blue: 0.48),
                                        Color(red: 0.92, green: 0.20, blue: 0.28)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 3.3, height: 1.9)
                    }
                    .rotationEffect(.degrees(flagAngle), anchor: UnitPoint(x: 0.2, y: 0.88))

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.94, blue: 0.56),
                                    Color(red: 0.92, green: 0.72, blue: 0.14)
                                ],
                                center: .topLeading,
                                startRadius: 0.1,
                                endRadius: 1.6
                            )
                        )
                        .frame(width: 1.9, height: 1.9)
                        .shadow(color: Color.black.opacity(0.35), radius: 0.5)
                        .offset(x: -0.3, y: 3.4)
                }
                .frame(width: 3.3, height: 5.0, alignment: .topLeading)
                .offset(x: 1.2, y: -2.0)
            }
            .frame(width: 17, height: 10.5)
            .offset(y: -5.6)
            .scaleEffect(recoilScale, anchor: .center)
        }
        .frame(width: 19, height: 16.5)
    }
}

// MARK: - Authentic 8-Bit Pixel Art Curb Mailbox (19x16.5, Solid Shading, Volume & Depth)

private struct RetroPixelCurbMailboxView: View {
    let flagAngle: Double
    let recoilScale: CGFloat
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

                // 3. Pixel Red Flag bolted cleanly to stationary Brass Pivot Pin
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Rectangle().fill(Color(red: 0.97, green: 0.44, blue: 0.44)).frame(width: 3.0, height: 1.8)
                        Rectangle().fill(Color(red: 0.88, green: 0.18, blue: 0.18)).frame(width: 1.2, height: 3.2)
                    }
                    .rotationEffect(.degrees(flagAngle), anchor: UnitPoint(x: 0.2, y: 0.88))

                    Rectangle()
                        .fill(Color(red: 0.99, green: 0.88, blue: 0.28))
                        .frame(width: 1.8, height: 1.8)
                        .offset(x: -0.3, y: 3.5)
                }
                .frame(width: 3.0, height: 5.0, alignment: .topLeading)
                .offset(x: 1.5, y: -2.2)
            }
            .frame(width: 17, height: 10.5)
            .offset(y: -5.5)
            .scaleEffect(recoilScale, anchor: .center)
        }
        .frame(width: 19, height: 16.5)
    }
}
