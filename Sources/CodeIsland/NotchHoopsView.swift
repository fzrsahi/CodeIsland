import SwiftUI
import AppKit
import CodeIslandCore

/// Retro pixel-art basketball mini-game ("Notch Hoops // Arena") for the expanded notch `.game` tab.
/// Zero idle cost: mounted only when `.game` is active, and only runs `TimelineView`
/// while `engine.needsTick && animationGate.animationsActive` is true.
struct NotchHoopsView: View {
    var appState: AppState

    @AppStorage(SettingsKey.notchHoopsHighScore) private var storedHighScore = SettingsDefaults.notchHoopsHighScore
    @AppStorage(SettingsKey.notchHoopsPositionMode) private var storedPositionMode = SettingsDefaults.notchHoopsPositionMode
    @AppStorage(SettingsKey.hapticOnHover) private var hapticOnHover = SettingsDefaults.hapticOnHover
    @ObservedObject private var animationGate = MascotAnimationGate.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var engine: NotchHoopsEngine
    @State private var dragTranslation: CGSize?
    @State private var lastTickDate: Date?

    init(
        appState: AppState,
        initialEngine: NotchHoopsEngine = NotchHoopsEngine(),
        initialDrag: CGSize? = nil
    ) {
        self.appState = appState
        _engine = State(initialValue: initialEngine)
        _dragTranslation = State(initialValue: initialDrag)
    }

    private static let cyan = Color(red: 0.30, green: 0.94, blue: 0.90)
    private static let green = Color(red: 0.42, green: 0.96, blue: 0.48)
    private static let orange = Color(red: 0.96, green: 0.45, blue: 0.16)
    private static let deepOrange = Color(red: 0.68, green: 0.22, blue: 0.06)
    private static let crtBg = Color(red: 0.03, green: 0.055, blue: 0.07)

    private var isAnimating: Bool {
        engine.needsTick && animationGate.animationsActive
    }

    var body: some View {
        ZStack(alignment: .top) {
            interactiveCourt
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )

            // Top HUD overlay: Scorebug (left) + Position Filter & Reset (right)
            HStack(alignment: .center) {
                broadcastScorebug
                Spacer()
                positionFilterBar
            }
            .padding(8)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .onAppear {
            engine.highScore = max(engine.highScore, storedHighScore)
            if let mode = NotchHoopsEngine.PositionMode(rawValue: storedPositionMode),
               engine.positionMode != mode {
                engine.positionMode = mode
            }
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
        .onChange(of: storedHighScore) { _, newValue in
            if newValue == 0 {
                engine.highScore = 0
            }
        }
        .onChange(of: storedPositionMode) { _, newValue in
            if let mode = NotchHoopsEngine.PositionMode(rawValue: newValue),
               engine.positionMode != mode {
                engine.positionMode = mode
            }
        }
        .onChange(of: engine.phase) { _, newPhase in
            updateInteractionLock(dragging: dragTranslation != nil, phase: newPhase)
        }
    }

    // MARK: - Top-Left Broadcast Scorebug

    private var broadcastScorebug: some View {
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

            // Highlighted 3PT indicator shown exclusively when shooting from 3-point range
            if engine.currentShotZone == .threePoint {
                Text("3PT")
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                    .foregroundStyle(Self.green)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Self.green.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Self.green.opacity(0.55), lineWidth: 0.8)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
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
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.75))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Top-Right Position Filter & Reset

    private var positionFilterBar: some View {
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(NotchHoopsEngine.PositionMode.allCases, id: \.self) { mode in
                    let selected = engine.positionMode == mode
                    Button {
                        engine.positionMode = mode
                        storedPositionMode = mode.rawValue
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 9, weight: selected ? .bold : .medium, design: .monospaced))
                            .foregroundStyle(selected ? .black : .white.opacity(0.7))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(selected ? Self.cyan : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(mode == .random ? "Randomize shooting spot each turn" : "Shoot from \(mode.rawValue) zone")
                }
            }
            .padding(2)
            .background(Color.black.opacity(0.75))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            Button {
                resetRound()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 24, height: 24)
                    .background(Color.black.opacity(0.75))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Reset Game")
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
                            .stroke(Color.black.opacity(0.6), lineWidth: 0.9)
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

    // MARK: - Interactive Court

    private var interactiveCourt: some View {
        ZStack {
            if isAnimating {
                TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 30.0 : 1.0 / 60.0)) { timeline in
                    courtCanvas
                        .onChange(of: timeline.date) { oldDate, newDate in
                            let previous = lastTickDate ?? oldDate
                            let dt = newDate.timeIntervalSince(previous)
                            lastTickDate = newDate
                            engine.step(dt: dt)
                            flushSoundEvents()
                            if !engine.needsTick {
                                lastTickDate = nil
                                updateInteractionLock(dragging: dragTranslation != nil, phase: engine.phase)
                            }
                        }
                }
            } else {
                courtCanvas
            }

            CourtGestureOverlay(
                isEnabled: engine.phase == .ready,
                onDragChanged: { translation in
                    guard engine.phase == .ready else { return }
                    dragTranslation = translation
                    updateInteractionLock(dragging: true, phase: engine.phase)
                },
                onDragEnded: { translation in
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
                    flushSoundEvents()
                    updateInteractionLock(dragging: false, phase: engine.phase)
                }
            )

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
                .background(Color.black.opacity(0.84))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Self.orange.opacity(0.6), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .frame(height: 250)
        .background(Self.crtBg)
        .contentShape(Rectangle())
    }

    // MARK: - Pixel-Art Court Canvas

    private var courtCanvas: some View {
        Canvas { context, size in
            let scaleX = size.width / NotchHoopsEngine.courtWidth
            let scaleY = size.height / NotchHoopsEngine.courtHeight
            let scale = min(scaleX, scaleY)
            let offsetX = (size.width - NotchHoopsEngine.courtWidth * scale) / 2
            let offsetY = (size.height - NotchHoopsEngine.courtHeight * scale) / 2

            func pt(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: offsetX + x * scale, y: offsetY + y * scale)
            }

            // Snap helper for crisp pixel-art steps
            let px = max(1.5, (2.0 * scale).rounded())
            func snap(_ v: CGFloat) -> CGFloat { (v / px).rounded() * px }

            // 1. Subtle CRT radial teal glow (matching reference image)
            let glowCenter = pt(NotchHoopsEngine.rimCenterX - 60, NotchHoopsEngine.rimY + 10)
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .radialGradient(
                    Gradient(colors: [Self.cyan.opacity(0.11), Color.clear]),
                    center: glowCenter,
                    startRadius: 10,
                    endRadius: size.width * 0.55
                )
            )

            // 2. Subtle CRT scanlines
            var scanPath = Path()
            var sy: CGFloat = 2
            while sy < size.height {
                scanPath.move(to: CGPoint(x: 0, y: sy))
                scanPath.addLine(to: CGPoint(x: size.width, y: sy))
                sy += 5
            }
            context.stroke(scanPath, with: .color(.white.opacity(0.028)), lineWidth: 1)

            // 3. Clean court floor baseline (1P/2P/3P distances handled by system)
            let floorY = pt(0, NotchHoopsEngine.launchY + NotchHoopsEngine.ballRadius + 4).y
            context.fill(
                Path(CGRect(x: 0, y: floorY, width: size.width, height: max(0, size.height - floorY))),
                with: .color(Color.white.opacity(0.025))
            )
            var floorLine = Path()
            floorLine.move(to: CGPoint(x: 0, y: floorY))
            floorLine.addLine(to: CGPoint(x: size.width, y: floorY))
            context.stroke(floorLine, with: .color(Self.cyan.opacity(0.20)), lineWidth: 1)

            // 4. Pixel-art Backboard + Bracket + Rim Glow
            let hoopCenter = pt(NotchHoopsEngine.rimCenterX, NotchHoopsEngine.rimY)
            context.fill(
                Path(ellipseIn: CGRect(x: hoopCenter.x - 65, y: hoopCenter.y - 50, width: 130, height: 100)),
                with: .radialGradient(
                    Gradient(colors: [Self.cyan.opacity(0.16), .clear]),
                    center: hoopCenter,
                    startRadius: 2,
                    endRadius: 65
                )
            )

            let bbTop = pt(NotchHoopsEngine.backboardX, NotchHoopsEngine.backboardTopY)
            let bbBottom = pt(NotchHoopsEngine.backboardX, NotchHoopsEngine.backboardBottomY)
            let bbHeight = bbBottom.y - bbTop.y
            let depthDx = 14 * scale
            let depthDy = -10 * scale

            // Angled backboard face
            var bbFace = Path()
            bbFace.move(to: bbTop)
            bbFace.addLine(to: CGPoint(x: bbTop.x + depthDx, y: bbTop.y + depthDy))
            bbFace.addLine(to: CGPoint(x: bbBottom.x + depthDx, y: bbBottom.y + depthDy))
            bbFace.addLine(to: bbBottom)
            bbFace.closeSubpath()
            context.fill(bbFace, with: .color(Color(red: 0.72, green: 0.96, blue: 0.96).opacity(0.85)))
            context.stroke(bbFace, with: .color(Self.cyan), lineWidth: px)

            // Dark cyan side thickness on backboard front edge
            context.fill(
                Path(CGRect(x: snap(bbTop.x - px), y: snap(bbTop.y), width: px * 1.4, height: bbHeight)),
                with: .color(Color(red: 0.14, green: 0.55, blue: 0.58))
            )

            // Inner orange shooter's square
            var sq = Path()
            let sqTopY = bbTop.y + bbHeight * 0.36
            let sqBotY = bbTop.y + bbHeight * 0.72
            sq.move(to: CGPoint(x: bbTop.x + 2 * scale, y: sqTopY))
            sq.addLine(to: CGPoint(x: bbTop.x + depthDx * 0.72, y: sqTopY + depthDy * 0.72))
            sq.addLine(to: CGPoint(x: bbTop.x + depthDx * 0.72, y: sqBotY + depthDy * 0.72))
            sq.addLine(to: CGPoint(x: bbTop.x + 2 * scale, y: sqBotY))
            sq.closeSubpath()
            context.stroke(sq, with: .color(Self.orange), lineWidth: px * 0.8)

            // Rim mounting bracket
            let rimRight = pt(NotchHoopsEngine.rimCenterX + NotchHoopsEngine.rimHalfWidth, NotchHoopsEngine.rimY)
            let bracketWidth: CGFloat = max(4, bbTop.x - rimRight.x + 1)
            context.fill(
                Path(CGRect(x: rimRight.x - 1, y: rimRight.y - px * 0.5, width: bracketWidth, height: px * 2.2)),
                with: .color(Self.orange)
            )

            // 5. Dashed Cyan Aim Trajectory Arc
            if let drag = dragTranslation, engine.phase == .ready {
                let points = NotchHoopsEngine.predictedTrajectory(
                    fromX: engine.currentLaunchX,
                    dragDeltaX: Double(drag.width),
                    dragDeltaY: Double(drag.height)
                )
                for i in 0..<points.count {
                    let p = pt(points[i].x, points[i].y)
                    let prev = i == 0 ? pt(engine.currentLaunchX, NotchHoopsEngine.launchY) : pt(points[i - 1].x, points[i - 1].y)
                    var seg = Path()
                    seg.move(to: CGPoint(x: (prev.x + p.x) * 0.5, y: (prev.y + p.y) * 0.5))
                    seg.addLine(to: p)
                    let alpha = max(0.35, 0.95 - Double(i) * 0.12)
                    context.stroke(seg, with: .color(Self.cyan.opacity(alpha)), style: StrokeStyle(lineWidth: px, lineCap: .round))
                }
            }

            // 6. Back half of pixel-stepped 3D oval rim (behind ball)
            let rimLeft = pt(NotchHoopsEngine.rimCenterX - NotchHoopsEngine.rimHalfWidth, NotchHoopsEngine.rimY)
            let rimOvalRect = CGRect(
                x: rimLeft.x,
                y: rimLeft.y - 4.5 * scale,
                width: rimRight.x - rimLeft.x,
                height: 9 * scale
            )
            var backRim = Path()
            backRim.move(to: CGPoint(x: rimOvalRect.minX, y: rimOvalRect.midY))
            backRim.addQuadCurve(
                to: CGPoint(x: rimOvalRect.maxX, y: rimOvalRect.midY),
                control: CGPoint(x: rimOvalRect.midX, y: rimOvalRect.minY - 3 * scale)
            )
            context.stroke(backRim, with: .color(Self.deepOrange), lineWidth: px * 1.1)

            // 7. Ground shadow under basketball
            let ballPos = pt(engine.ballX, engine.ballY)
            let ballR = NotchHoopsEngine.ballRadius * scale
            let heightAboveFloor = max(0, floorY - (ballPos.y + ballR))
            let shadowFactor = max(0.25, 1.0 - heightAboveFloor / (140 * scale))
            let shadowW = ballR * 1.8 * shadowFactor
            let shadowH = max(2.5, 4 * scale * shadowFactor)
            context.fill(
                Path(ellipseIn: CGRect(x: ballPos.x - shadowW / 2, y: floorY - shadowH / 2, width: shadowW, height: shadowH)),
                with: .color(.black.opacity(0.45 * shadowFactor))
            )

            // 8. Pixel-art Basketball with warm orange glow
            context.fill(
                Path(ellipseIn: CGRect(x: ballPos.x - ballR * 1.6, y: ballPos.y - ballR * 1.6, width: ballR * 3.2, height: ballR * 3.2)),
                with: .radialGradient(
                    Gradient(colors: [Self.orange.opacity(0.28), .clear]),
                    center: ballPos,
                    startRadius: ballR * 0.4,
                    endRadius: ballR * 1.6
                )
            )
            drawPixelBasketball(context: context, center: ballPos, radius: ballR, rotation: engine.ballRotation, px: px)

            // 9. Pixel-art Diamond-Mesh Net (in front of ball)
            let netBottomY = rimLeft.y + 30 * scale
            let swayOffset = CGFloat(engine.netSway) * 8.0 * scale
            let netLeftBot = rimLeft.x + 7 * scale + swayOffset
            let netRightBot = rimRight.x - 7 * scale + swayOffset

            var netPath = Path()
            let strands = 5
            for i in 0..<(strands - 1) {
                let t0 = CGFloat(i) / CGFloat(strands - 1)
                let t1 = CGFloat(i + 1) / CGFloat(strands - 1)
                let topX0 = rimLeft.x + (rimRight.x - rimLeft.x) * t0
                let topX1 = rimLeft.x + (rimRight.x - rimLeft.x) * t1
                let botX0 = netLeftBot + (netRightBot - netLeftBot) * t0
                let botX1 = netLeftBot + (netRightBot - netLeftBot) * t1
                netPath.move(to: CGPoint(x: topX0, y: rimLeft.y + 2))
                netPath.addLine(to: CGPoint(x: botX1, y: netBottomY))
                netPath.move(to: CGPoint(x: topX1, y: rimLeft.y + 2))
                netPath.addLine(to: CGPoint(x: botX0, y: netBottomY))
            }
            context.stroke(netPath, with: .color(.white.opacity(0.82)), lineWidth: max(1.1, px * 0.65))

            // 10. Front half of pixel-stepped 3D oval rim
            context.stroke(Path(ellipseIn: rimOvalRect), with: .color(Self.orange), lineWidth: px * 1.25)

            // 11. "SWIPE UP ↗" + Pixel Hand Cue before first shot
            if !engine.hasTakenShot && dragTranslation == nil && engine.phase == .ready {
                let hintPos = pt(engine.currentLaunchX - 36, NotchHoopsEngine.launchY - 22)
                context.draw(
                    Text("SWIPE UP ↗")
                        .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9)),
                    at: hintPos
                )
                drawPixelHand(context: context, origin: CGPoint(x: hintPos.x - 4, y: hintPos.y + 10), px: max(1.3, px * 0.75))
            }

            // 12. Minimalist Score / Miss Feedback (+1, +2, +3 or MISS)
            if let feedback = engine.feedbackText, engine.feedbackTimer > 0 {
                let alpha = min(1.0, engine.feedbackTimer * 1.5)
                let fbPos = pt(NotchHoopsEngine.rimCenterX - 6, NotchHoopsEngine.rimY - 30)
                context.draw(
                    Text(feedback)
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundColor((engine.feedbackPoints > 0 ? Self.green : Self.orange).opacity(alpha)),
                    at: fbPos
                )
            }
        }
    }

    /// Draws a crisp pixel-stepped basketball with black outline, orange shading, and rotating seams.
    private func drawPixelBasketball(
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        rotation: Double,
        px: CGFloat
    ) {
        let ballRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(
            Path(ellipseIn: ballRect),
            with: .radialGradient(
                Gradient(colors: [Color(red: 1.0, green: 0.60, blue: 0.22), Self.orange, Self.deepOrange]),
                center: CGPoint(x: center.x - radius * 0.28, y: center.y - radius * 0.28),
                startRadius: 1,
                endRadius: radius * 1.3
            )
        )

        context.drawLayer { ballCtx in
            ballCtx.clip(to: Path(ellipseIn: ballRect))
            ballCtx.translateBy(x: center.x, y: center.y)
            ballCtx.rotate(by: .radians(rotation))

            var ribs = Path()
            ribs.move(to: CGPoint(x: -radius, y: 0))
            ribs.addLine(to: CGPoint(x: radius, y: 0))
            ribs.move(to: CGPoint(x: 0, y: -radius))
            ribs.addLine(to: CGPoint(x: 0, y: radius))
            ribs.addArc(center: CGPoint(x: -radius * 1.15, y: 0), radius: radius * 0.95, startAngle: .degrees(-55), endAngle: .degrees(55), clockwise: false)
            ribs.move(to: CGPoint(x: radius * 1.15, y: 0))
            ribs.addArc(center: CGPoint(x: radius * 1.15, y: 0), radius: radius * 0.95, startAngle: .degrees(125), endAngle: .degrees(235), clockwise: false)
            ballCtx.stroke(ribs, with: .color(.black.opacity(0.75)), lineWidth: max(1.1, px * 0.65))
        }
        context.stroke(Path(ellipseIn: ballRect), with: .color(.black.opacity(0.92)), lineWidth: max(1.3, px * 0.75))
    }

    /// Draws a tiny 8×9 pixel-art pointing hand cursor matching the reference graphic.
    private func drawPixelHand(context: GraphicsContext, origin: CGPoint, px: CGFloat) {
        let grid: [String] = [
            "...11...",
            "..1221..",
            "..1221..",
            "..12211.",
            ".1122121",
            "12222221",
            "12222221",
            ".122221.",
            "..1111.."
        ]
        let skin = Color(red: 0.95, green: 0.74, blue: 0.58)
        for (rowIdx, row) in grid.enumerated() {
            for (colIdx, ch) in row.enumerated() where ch != "." {
                let rect = CGRect(
                    x: origin.x + CGFloat(colIdx) * px,
                    y: origin.y + CGFloat(rowIdx) * px,
                    width: px + 0.3,
                    height: px + 0.3
                )
                context.fill(Path(rect), with: .color(ch == "1" ? .black : skin))
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

    private func flushSoundEvents() {
        for event in engine.drainSoundEvents() {
            NotchHoopsSoundPlayer.shared.play(event)
        }
    }
}

/// AppKit mouse-drag overlay so court swipes work reliably on the first click/drag inside the nonactivating notch panel.
struct CourtGestureOverlay: NSViewRepresentable {
    var isEnabled: Bool
    var onDragChanged: (CGSize) -> Void
    var onDragEnded: (CGSize) -> Void

    func makeNSView(context: Context) -> DragTrackingNSView {
        let view = DragTrackingNSView()
        view.isEnabled = isEnabled
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: DragTrackingNSView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded
    }

    final class DragTrackingNSView: NSView {
        var isEnabled: Bool = true
        var onDragChanged: ((CGSize) -> Void)?
        var onDragEnded: ((CGSize) -> Void)?
        private var dragStart: NSPoint?

        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard isEnabled, bounds.contains(point) else { return nil }
            return self
        }

        override func mouseDown(with event: NSEvent) {
            guard isEnabled else {
                super.mouseDown(with: event)
                return
            }
            window?.makeKey()
            dragStart = convert(event.locationInWindow, from: nil)
        }

        override func mouseDragged(with event: NSEvent) {
            guard isEnabled, let start = dragStart else { return }
            let current = convert(event.locationInWindow, from: nil)
            let delta = CGSize(width: current.x - start.x, height: current.y - start.y)
            guard hypot(delta.width, delta.height) >= 4 else { return }
            onDragChanged?(delta)
        }

        override func mouseUp(with event: NSEvent) {
            guard let start = dragStart else { return }
            dragStart = nil
            let current = convert(event.locationInWindow, from: nil)
            let delta = CGSize(width: current.x - start.x, height: current.y - start.y)
            onDragEnded?(delta)
        }
    }
}
