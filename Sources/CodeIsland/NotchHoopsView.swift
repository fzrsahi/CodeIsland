import SwiftUI
import CodeIslandCore

/// Prototype variants for Notch Hoops (per /prototype Sub-shape A) so collaborators
/// can compare structurally different layouts & visual hierarchies live in the notch.
private enum NotchHoopsVariant: String, CaseIterable {
    case crtArcade = "A · CRT"
    case arenaBroadcast = "B · ARENA"
    case tacticalTelemetry = "C · TELEMETRY"
}

/// Retro basketball mini-game ("Notch Hoops") for the expanded notch `.game` tab.
/// Zero idle cost: mounted only when `.game` is active, and only runs `TimelineView`
/// while `engine.needsTick && animationGate.animationsActive` is true.
struct NotchHoopsView: View {
    var appState: AppState

    @AppStorage(SettingsKey.notchHoopsHighScore) private var storedHighScore = SettingsDefaults.notchHoopsHighScore
    @AppStorage(SettingsKey.hapticOnHover) private var hapticOnHover = SettingsDefaults.hapticOnHover
    @ObservedObject private var animationGate = MascotAnimationGate.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var variant: NotchHoopsVariant = .crtArcade
    @State private var engine = NotchHoopsEngine()
    @State private var dragTranslation: CGSize?
    @State private var lastTickDate: Date?

    private static let cyan = Color(red: 0.22, green: 0.94, blue: 0.88)
    private static let green = Color(red: 0.34, green: 0.95, blue: 0.48)
    private static let orange = Color(red: 0.98, green: 0.46, blue: 0.14)
    private static let deepOrange = Color(red: 0.72, green: 0.24, blue: 0.06)
    private static let crtBg = Color(red: 0.035, green: 0.06, blue: 0.08)

    private var isAnimating: Bool {
        engine.needsTick && animationGate.animationsActive
    }

    var body: some View {
        VStack(spacing: 6) {
            switch variant {
            case .crtArcade:
                variantACrtArcade
            case .arenaBroadcast:
                variantBArenaBroadcast
            case .tacticalTelemetry:
                variantCTacticalTelemetry
            }

            prototypeSwitcherBar
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .onAppear {
            engine.highScore = max(engine.highScore, storedHighScore)
            lastTickDate = nil
        }
        .onDisappear {
            appState.isGameInteractionLocked = false
            lastTickDate = nil
        }
        .onChange(of: engine.highScore) { _, newValue in
            if newValue > storedHighScore {
                storedHighScore = newValue
            }
        }
        .onChange(of: engine.phase) { _, newPhase in
            updateInteractionLock(dragging: dragTranslation != nil, phase: newPhase)
        }
    }

    // MARK: - Variant A: CRT Arcade (2-Column Pixel Cabinet)

    private var variantACrtArcade: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    PixelText(text: "NOTCH HOOPS", color: Self.cyan, pixelSize: 2.0)
                    HStack(spacing: 6) {
                        PixelText(text: "ARCADE", color: .white.opacity(0.75), pixelSize: 1.4)
                        Circle()
                            .fill(Self.orange)
                            .frame(width: 8, height: 8)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    hudStatRow(label: "SCORE", value: String(format: "%02d", engine.score), color: Self.cyan)
                    hudStatRow(label: "HIGH", value: String(format: "%02d", engine.highScore), color: .white.opacity(0.9))

                    HStack(spacing: 6) {
                        Text("STREAK")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 52, alignment: .leading)
                        Text("\(engine.streak)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(engine.streak >= 2 ? Self.orange : Self.cyan)
                        if engine.streak >= 2 {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Self.orange)
                        }
                    }

                    HStack(spacing: 6) {
                        Text("BALLS")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 52, alignment: .leading)
                        ballsIndicator
                    }
                }
                .padding(.top, 2)

                Spacer(minLength: 2)

                Button {
                    resetRound()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: engine.phase == .gameOver ? "play.fill" : "arrow.counterclockwise")
                            .font(.system(size: 9.5, weight: .bold))
                        Text(engine.phase == .gameOver ? "NEW GAME" : "RESET")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(engine.phase == .gameOver ? .black : .white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(engine.phase == .gameOver ? Self.cyan : Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(engine.phase == .gameOver ? Self.cyan : Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .frame(width: 196, height: 168, alignment: .leading)

            interactiveCourt(height: 168, showScanlines: true, showFloor: true)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Self.cyan.opacity(0.25), lineWidth: 1)
                )
        }
    }

    // MARK: - Variant B: Arena Broadcast (Full-Width Court + Floating Scorebug)

    private var variantBArenaBroadcast: some View {
        ZStack(alignment: .topLeading) {
            interactiveCourt(height: 172, showScanlines: false, showFloor: true)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )

            // Compact Broadcast Scorebug overlaid in top-left
            HStack(spacing: 8) {
                Text("HOOPS")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Self.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                HStack(spacing: 4) {
                    Text(String(format: "%02d", engine.score))
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text("/ BEST \(String(format: "%02d", engine.highScore))")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.6))
                }

                if engine.streak >= 2 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9.5))
                        Text("\(engine.streak)")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(Self.orange)
                }

                ballsIndicator

                Button {
                    resetRound()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Reset Game")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(8)
        }
    }

    // MARK: - Variant C: Tactical Telemetry (Top Strip + Wide Court + Live Aim Readout)

    private var variantCTacticalTelemetry: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Circle().fill(engine.phase == .gameOver ? Self.orange : Self.green).frame(width: 6, height: 6)
                    Text("NOTCH HOOPS")
                        .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.92))
                }

                telemetryPill(label: "PTS", value: String(format: "%02d", engine.score), accent: Self.cyan)
                telemetryPill(label: "BEST", value: String(format: "%02d", engine.highScore), accent: .white.opacity(0.85))
                telemetryPill(label: "STRK", value: "\(engine.streak)", accent: engine.streak >= 2 ? Self.orange : Self.cyan)

                if let drag = dragTranslation,
                   let v = NotchHoopsEngine.launchVelocity(dragDeltaX: Double(drag.width), dragDeltaY: Double(drag.height)) {
                    let speed = Int(hypot(v.vx, v.vy))
                    telemetryPill(label: "PWR", value: "\(speed)", accent: Self.green)
                }

                Spacer()

                ballsIndicator

                Button {
                    resetRound()
                } label: {
                    Text("RETRY")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            interactiveCourt(height: 140, showScanlines: true, showFloor: true)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        }
    }

    // MARK: - Shared HUD & Prototype Switcher

    private func hudStatRow(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    private func telemetryPill(label: String, value: String, accent: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(accent)
        }
    }

    private var ballsIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<NotchHoopsEngine.maxBalls, id: \.self) { index in
                let active = index < engine.ballsRemaining
                ZStack {
                    Circle()
                        .fill(active ? Self.orange : Color.white.opacity(0.12))
                        .frame(width: 11, height: 11)
                    if active {
                        Circle()
                            .stroke(Color.black.opacity(0.55), lineWidth: 0.9)
                            .frame(width: 11, height: 11)
                        Rectangle()
                            .fill(Color.black.opacity(0.45))
                            .frame(width: 9, height: 0.8)
                    } else {
                        Circle()
                            .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
                            .frame(width: 11, height: 11)
                    }
                }
            }
        }
    }

    private var prototypeSwitcherBar: some View {
        HStack(spacing: 4) {
            Text("LAYOUT:")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
            ForEach(NotchHoopsVariant.allCases, id: \.self) { item in
                let selected = variant == item
                Button {
                    variant = item
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 9, weight: selected ? .bold : .medium, design: .monospaced))
                        .foregroundStyle(selected ? .black : .white.opacity(0.65))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(selected ? Self.cyan : Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("SWIPE TO SHOOT")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    // MARK: - Interactive Court & Upgraded Canvas Artwork

    private func interactiveCourt(height: CGFloat, showScanlines: Bool, showFloor: Bool) -> some View {
        ZStack {
            if isAnimating {
                TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 30.0 : 1.0 / 60.0)) { timeline in
                    courtCanvas(showScanlines: showScanlines, showFloor: showFloor)
                        .onChange(of: timeline.date) { oldDate, newDate in
                            let previous = lastTickDate ?? oldDate
                            let dt = newDate.timeIntervalSince(previous)
                            lastTickDate = newDate
                            engine.step(dt: dt)
                            if !engine.needsTick {
                                lastTickDate = nil
                                updateInteractionLock(dragging: dragTranslation != nil, phase: engine.phase)
                            }
                        }
                }
            } else {
                courtCanvas(showScanlines: showScanlines, showFloor: showFloor)
            }

            if engine.phase == .gameOver {
                VStack(spacing: 6) {
                    Text("GAME OVER")
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Self.orange)
                    Text("SCORE \(engine.score)  •  BEST \(engine.highScore)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.85))
                    Button {
                        resetRound()
                    } label: {
                        Text("PLAY AGAIN")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Self.cyan)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color.black.opacity(0.82))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Self.orange.opacity(0.6), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .frame(height: height)
        .background(Self.crtBg)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    guard engine.phase == .ready else { return }
                    dragTranslation = value.translation
                    updateInteractionLock(dragging: true, phase: engine.phase)
                }
                .onEnded { value in
                    let translation = value.translation
                    dragTranslation = nil
                    guard engine.phase == .ready else {
                        updateInteractionLock(dragging: false, phase: engine.phase)
                        return
                    }
                    lastTickDate = Date()
                    let launched = engine.launch(
                        dragDeltaX: Double(translation.width),
                        dragDeltaY: Double(translation.height)
                    )
                    if launched && hapticOnHover {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    }
                    updateInteractionLock(dragging: false, phase: engine.phase)
                }
        )
    }

    private func courtCanvas(showScanlines: Bool, showFloor: Bool) -> some View {
        Canvas { context, size in
            let scaleX = size.width / NotchHoopsEngine.courtWidth
            let scaleY = size.height / NotchHoopsEngine.courtHeight
            let scale = min(scaleX, scaleY)
            let offsetX = (size.width - NotchHoopsEngine.courtWidth * scale) / 2
            let offsetY = (size.height - NotchHoopsEngine.courtHeight * scale) / 2

            func pt(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: offsetX + x * scale, y: offsetY + y * scale)
            }

            // 1. Subtle court floor & perspective lines
            if showFloor {
                let floorY = pt(0, NotchHoopsEngine.launchY + NotchHoopsEngine.ballRadius + 4).y
                let floorRect = CGRect(x: 0, y: floorY, width: size.width, height: max(0, size.height - floorY))
                context.fill(Path(floorRect), with: .color(Color.white.opacity(0.03)))

                var floorLine = Path()
                floorLine.move(to: CGPoint(x: 0, y: floorY))
                floorLine.addLine(to: CGPoint(x: size.width, y: floorY))
                context.stroke(floorLine, with: .color(Self.cyan.opacity(0.18)), lineWidth: 1)

                // Key/paint arc on the right
                let keyStart = pt(NotchHoopsEngine.rimCenterX - 75, NotchHoopsEngine.launchY + NotchHoopsEngine.ballRadius + 4)
                var arcPath = Path()
                arcPath.move(to: keyStart)
                arcPath.addLine(to: CGPoint(x: size.width, y: keyStart.y + 10))
                context.stroke(arcPath, with: .color(Self.cyan.opacity(0.10)), lineWidth: 1)
            }

            // 2. Subtle CRT scanlines
            if showScanlines {
                var scanPath = Path()
                var sy: CGFloat = 2
                while sy < size.height {
                    scanPath.move(to: CGPoint(x: 0, y: sy))
                    scanPath.addLine(to: CGPoint(x: size.width, y: sy))
                    sy += 5
                }
                context.stroke(scanPath, with: .color(.white.opacity(0.03)), lineWidth: 1)
            }

            // 3. Hoop radial ambient glow
            let hoopCenter = pt(NotchHoopsEngine.rimCenterX, NotchHoopsEngine.rimY)
            let glowRect = CGRect(x: hoopCenter.x - 95, y: hoopCenter.y - 75, width: 190, height: 150)
            context.fill(
                Path(ellipseIn: glowRect),
                with: .radialGradient(
                    Gradient(colors: [Self.cyan.opacity(0.13), .clear]),
                    center: hoopCenter,
                    startRadius: 4,
                    endRadius: 95
                )
            )

            // 4. 3D-Perspective Backboard + Mounting Bracket + Shooter's Square
            let bbTop = pt(NotchHoopsEngine.backboardX, NotchHoopsEngine.backboardTopY)
            let bbBottom = pt(NotchHoopsEngine.backboardX, NotchHoopsEngine.backboardBottomY)
            let bbThickness = max(5, 7 * scale)
            let bbHeight = bbBottom.y - bbTop.y
            let depthDx = 10 * scale
            let depthDy = -7 * scale

            // Wall bracket strut
            var bracket = Path()
            let midY = bbTop.y + bbHeight * 0.5
            bracket.move(to: CGPoint(x: bbTop.x + bbThickness, y: midY))
            bracket.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(bracket, with: .color(Self.cyan.opacity(0.45)), lineWidth: max(2.5, 3.5 * scale))

            // Angled backboard face (subtle 3D perspective)
            var bbFace = Path()
            bbFace.move(to: bbTop)
            bbFace.addLine(to: CGPoint(x: bbTop.x + depthDx, y: bbTop.y + depthDy))
            bbFace.addLine(to: CGPoint(x: bbBottom.x + depthDx, y: bbBottom.y + depthDy))
            bbFace.addLine(to: bbBottom)
            bbFace.closeSubpath()
            context.fill(bbFace, with: .color(Self.cyan.opacity(0.14)))
            context.stroke(bbFace, with: .color(Self.cyan.opacity(0.88)), lineWidth: 1.4)

            // Front edge thickness
            let bbEdge = CGRect(x: bbTop.x - 1.5, y: bbTop.y, width: 3, height: bbHeight)
            context.fill(Path(bbEdge), with: .color(Self.cyan.opacity(0.85)))

            // Inner shooter's square
            var square = Path()
            let sqTopY = bbTop.y + bbHeight * 0.36
            let sqBotY = bbTop.y + bbHeight * 0.72
            square.move(to: CGPoint(x: bbTop.x + 2 * scale, y: sqTopY))
            square.addLine(to: CGPoint(x: bbTop.x + depthDx * 0.72, y: sqTopY + depthDy * 0.72))
            square.addLine(to: CGPoint(x: bbTop.x + depthDx * 0.72, y: sqBotY + depthDy * 0.72))
            square.addLine(to: CGPoint(x: bbTop.x + 2 * scale, y: sqBotY))
            square.closeSubpath()
            context.stroke(square, with: .color(Self.orange.opacity(0.85)), lineWidth: 1.2)

            // 5. Aim trajectory dots while dragging
            if let drag = dragTranslation, engine.phase == .ready {
                let points = NotchHoopsEngine.predictedTrajectory(
                    dragDeltaX: Double(drag.width),
                    dragDeltaY: Double(drag.height)
                )
                for (idx, p) in points.enumerated() {
                    let c = pt(p.x, p.y)
                    let r = max(1.8, 3.0 * scale)
                    let alpha = max(0.22, 0.92 - Double(idx) * 0.06)
                    context.fill(
                        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                        with: .color(Self.cyan.opacity(alpha))
                    )
                }
            }

            // 6. Back half of the 3D oval rim (drawn behind the ball)
            let rimLeft = pt(NotchHoopsEngine.rimCenterX - NotchHoopsEngine.rimHalfWidth, NotchHoopsEngine.rimY)
            let rimRight = pt(NotchHoopsEngine.rimCenterX + NotchHoopsEngine.rimHalfWidth, NotchHoopsEngine.rimY)
            let rimOvalRect = CGRect(
                x: rimLeft.x,
                y: rimLeft.y - 4.5 * scale,
                width: rimRight.x - rimLeft.x,
                height: 9 * scale
            )
            var backRim = Path()
            backRim.addArc(
                center: CGPoint(x: rimOvalRect.midX, y: rimOvalRect.midY),
                radius: rimOvalRect.width / 2,
                startAngle: .degrees(180),
                endAngle: .degrees(360),
                clockwise: false
            )
            context.stroke(
                backRim.applying(CGAffineTransform(translationX: 0, y: -rimOvalRect.midY)
                    .scaledBy(x: 1, y: 0.22)
                    .translatedBy(x: 0, y: rimOvalRect.midY / 0.22)),
                with: .color(Self.deepOrange),
                lineWidth: max(2, 2.5 * scale)
            )

            // 7. Ground shadow under the basketball (scales & fades with altitude)
            let floorBaselineY = pt(0, NotchHoopsEngine.launchY + NotchHoopsEngine.ballRadius + 4).y
            let ballPos = pt(engine.ballX, engine.ballY)
            let ballR = NotchHoopsEngine.ballRadius * scale
            let heightAboveFloor = max(0, floorBaselineY - (ballPos.y + ballR))
            let shadowFactor = max(0.25, 1.0 - heightAboveFloor / (140 * scale))
            let shadowW = ballR * 1.9 * shadowFactor
            let shadowH = max(2.5, 4.5 * scale * shadowFactor)
            let shadowRect = CGRect(x: ballPos.x - shadowW / 2, y: floorBaselineY - shadowH / 2, width: shadowW, height: shadowH)
            context.fill(Path(ellipseIn: shadowRect), with: .color(.black.opacity(0.45 * shadowFactor)))

            // 8. Shaded Basketball with Curved Ribs
            let ballRect = CGRect(x: ballPos.x - ballR, y: ballPos.y - ballR, width: ballR * 2, height: ballR * 2)
            context.fill(
                Path(ellipseIn: ballRect),
                with: .radialGradient(
                    Gradient(colors: [Color(red: 1.0, green: 0.62, blue: 0.26), Self.orange, Self.deepOrange]),
                    center: CGPoint(x: ballPos.x - ballR * 0.3, y: ballPos.y - ballR * 0.3),
                    startRadius: 1,
                    endRadius: ballR * 1.35
                )
            )

            // Curved seam ribs clipped to ball circle
            context.drawLayer { ballCtx in
                ballCtx.clip(to: Path(ellipseIn: ballRect))
                ballCtx.translateBy(x: ballPos.x, y: ballPos.y)
                ballCtx.rotate(by: .radians(engine.ballRotation))

                var ribs = Path()
                // Equator & meridian
                ribs.move(to: CGPoint(x: -ballR, y: 0))
                ribs.addLine(to: CGPoint(x: ballR, y: 0))
                ribs.move(to: CGPoint(x: 0, y: -ballR))
                ribs.addLine(to: CGPoint(x: 0, y: ballR))
                // Left & right curved side panels
                ribs.addArc(center: CGPoint(x: -ballR * 1.15, y: 0), radius: ballR * 0.95, startAngle: .degrees(-55), endAngle: .degrees(55), clockwise: false)
                ribs.move(to: CGPoint(x: ballR * 1.15, y: 0))
                ribs.addArc(center: CGPoint(x: ballR * 1.15, y: 0), radius: ballR * 0.95, startAngle: .degrees(125), endAngle: .degrees(235), clockwise: false)
                ballCtx.stroke(ribs, with: .color(.black.opacity(0.6)), lineWidth: 1.1)
            }
            context.stroke(Path(ellipseIn: ballRect), with: .color(.black.opacity(0.85)), lineWidth: 1.3)

            // 9. Diamond-Mesh Net (in front of ball)
            let netBottomY = rimLeft.y + 30 * scale
            let swayOffset = CGFloat(engine.netSway) * 8.0 * scale
            let netLeftBot = rimLeft.x + 7 * scale + swayOffset
            let netRightBot = rimRight.x - 7 * scale + swayOffset

            var netPath = Path()
            let strands = 5
            for i in 0..<strands {
                let t0 = CGFloat(i) / CGFloat(strands - 1)
                let t1 = CGFloat(i + 1) / CGFloat(strands - 1)
                let topX0 = rimLeft.x + (rimRight.x - rimLeft.x) * t0
                let botX0 = netLeftBot + (netRightBot - netLeftBot) * t0
                if i < strands - 1 {
                    let topX1 = rimLeft.x + (rimRight.x - rimLeft.x) * t1
                    let botX1 = netLeftBot + (netRightBot - netLeftBot) * t1
                    // Diagonal criss-cross diamond mesh
                    netPath.move(to: CGPoint(x: topX0, y: rimLeft.y))
                    netPath.addLine(to: CGPoint(x: botX1, y: netBottomY))
                    netPath.move(to: CGPoint(x: topX1, y: rimLeft.y))
                    netPath.addLine(to: CGPoint(x: botX0, y: netBottomY))
                }
            }
            context.stroke(netPath, with: .color(.white.opacity(0.72)), lineWidth: 1.0)

            // 10. Front half of the 3D oval rim
            context.stroke(
                Path(ellipseIn: rimOvalRect),
                with: .color(Self.orange),
                lineWidth: max(2.2, 2.8 * scale)
            )

            // 11. "SWIPE UP ↗" cue before first shot
            if !engine.hasTakenShot && dragTranslation == nil && engine.phase == .ready {
                let hintPos = pt(NotchHoopsEngine.launchX + 6, NotchHoopsEngine.launchY - 28)
                context.draw(
                    Text("SWIPE UP ↗")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.82)),
                    at: hintPos
                )
            }

            // 12. Floating score / miss feedback
            if let feedback = engine.feedbackText, engine.feedbackTimer > 0 {
                let alpha = min(1.0, engine.feedbackTimer * 1.4)
                let fbPos = pt(NotchHoopsEngine.rimCenterX - 18, NotchHoopsEngine.rimY - 34)
                let label = engine.feedbackPoints > 0
                    ? "\(feedback) +\(engine.feedbackPoints) PT\(engine.feedbackPoints > 1 ? "S" : "")"
                    : feedback
                context.draw(
                    Text(label)
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor((engine.feedbackPoints > 0 ? Self.green : Self.orange).opacity(alpha)),
                    at: fbPos
                )
            }
        }
    }

    private func resetRound() {
        engine.resetGame()
        dragTranslation = nil
        lastTickDate = nil
    }

    private func updateInteractionLock(dragging: Bool, phase: NotchHoopsEngine.Phase) {
        appState.isGameInteractionLocked = dragging || phase == .flying
    }
}
