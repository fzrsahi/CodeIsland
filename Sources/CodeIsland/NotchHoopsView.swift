import SwiftUI
import CodeIslandCore

/// Retro CRT basketball mini-game ("Notch Hoops // Arcade") for the expanded notch `.game` tab.
/// Zero idle cost: mounted only when the `.game` tab is visible, and only runs a `TimelineView`
/// while `engine.needsTick` is true (ball in flight or feedback settling).
struct NotchHoopsView: View {
    var appState: AppState

    @AppStorage(SettingsKey.notchHoopsHighScore) private var storedHighScore = SettingsDefaults.notchHoopsHighScore
    @AppStorage(SettingsKey.hapticOnHover) private var hapticOnHover = SettingsDefaults.hapticOnHover
    @ObservedObject private var animationGate = MascotAnimationGate.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var engine = NotchHoopsEngine()
    @State private var dragTranslation: CGSize?
    @State private var lastTickDate: Date?

    private static let cyan = Color(red: 0.30, green: 0.94, blue: 0.90)
    private static let green = Color(red: 0.38, green: 0.96, blue: 0.48)
    private static let orange = Color(red: 0.96, green: 0.45, blue: 0.16)
    private static let crtBg = Color(red: 0.04, green: 0.07, blue: 0.09)

    private var isAnimating: Bool {
        engine.needsTick && animationGate.animationsActive
    }

    private var courtStatusLabel: String {
        switch engine.phase {
        case .gameOver:
            return "CRT COURT // GAME OVER"
        case .flying:
            return "CRT COURT // ACTIVE"
        case .ready:
            return engine.hasTakenShot ? "CRT COURT // ACTIVE" : "CRT COURT // READY"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            leftHudColumn
                .frame(width: 210, alignment: .leading)

            rightCourtColumn
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 12)
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

    // MARK: - Left Arcade HUD

    private var leftHudColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("NOTCH HOOPS")
                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Self.cyan)
                HStack(spacing: 6) {
                    Text("// ARCADE")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Self.cyan.opacity(0.9))
                    Image(systemName: "basketball.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Self.orange)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                statRow(label: "SCORE:", value: String(format: "%02d", engine.score), valueColor: Self.cyan)
                statRow(label: "HIGH:", value: String(format: "%02d", engine.highScore), valueColor: Self.cyan)

                HStack(spacing: 6) {
                    Text("STREAK:")
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("\(engine.streak)")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Self.cyan)
                    if engine.streak >= 2 {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Self.orange)
                    }
                }

                HStack(spacing: 6) {
                    Text("BALLS:")
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                    HStack(spacing: 5) {
                        ForEach(0..<NotchHoopsEngine.maxBalls, id: \.self) { index in
                            Circle()
                                .fill(index < engine.ballsRemaining ? Self.orange : Color.white.opacity(0.22))
                                .overlay(
                                    Circle()
                                        .stroke(Color.black.opacity(0.5), lineWidth: 1)
                                )
                                .frame(width: 11, height: 11)
                        }
                    }
                }
            }
            .padding(.top, 2)

            Spacer(minLength: 4)

            HStack(spacing: 8) {
                Button {
                    if engine.phase == .gameOver {
                        engine.resetGame()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("PLAY")
                        Image(systemName: "play.fill")
                            .font(.system(size: 8.5))
                    }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(engine.phase == .gameOver ? 0.92 : 0.65))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06))
                    .overlay(
                        Rectangle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    engine.resetGame()
                    dragTranslation = nil
                    lastTickDate = nil
                } label: {
                    HStack(spacing: 4) {
                        Text("RETRY")
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9))
                    }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06))
                    .overlay(
                        Rectangle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 176)
    }

    private func statRow(label: String, value: String, valueColor: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
            Text(value)
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundStyle(valueColor)
        }
    }

    // MARK: - Right CRT Court

    private var rightCourtColumn: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(courtStatusLabel)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(engine.phase == .gameOver ? Self.orange : Self.cyan.opacity(0.9))

            ZStack {
                if isAnimating {
                    TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 30.0 : 1.0 / 60.0)) { timeline in
                        courtCanvas
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
                    courtCanvas
                }

                if engine.phase == .gameOver {
                    VStack(spacing: 6) {
                        Text("GAME OVER")
                            .font(.system(size: 16, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Self.orange)
                        Text("SCORE \(engine.score)  •  BEST \(engine.highScore)")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                        Button {
                            engine.resetGame()
                        } label: {
                            Text("PLAY AGAIN")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Self.cyan)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Color.black.opacity(0.78))
                    .overlay(Rectangle().stroke(Self.orange.opacity(0.6), lineWidth: 1))
                }
            }
            .frame(height: 158)
            .background(Self.crtBg)
            .overlay(
                Rectangle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
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
    }

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

            // Subtle static CRT scanlines (every 6pt)
            var scanPath = Path()
            var sy: CGFloat = 2
            while sy < size.height {
                scanPath.move(to: CGPoint(x: 0, y: sy))
                scanPath.addLine(to: CGPoint(x: size.width, y: sy))
                sy += 6
            }
            context.stroke(scanPath, with: .color(.white.opacity(0.035)), lineWidth: 1)

            // Subtle radial court glow behind hoop
            let hoopCenter = pt(NotchHoopsEngine.rimCenterX, NotchHoopsEngine.rimY)
            let glowRect = CGRect(x: hoopCenter.x - 90, y: hoopCenter.y - 70, width: 180, height: 140)
            context.fill(
                Path(ellipseIn: glowRect),
                with: .radialGradient(
                    Gradient(colors: [Self.cyan.opacity(0.11), .clear]),
                    center: hoopCenter,
                    startRadius: 4,
                    endRadius: 90
                )
            )

            // Backboard
            let bbTop = pt(NotchHoopsEngine.backboardX, NotchHoopsEngine.backboardTopY)
            let bbBottom = pt(NotchHoopsEngine.backboardX, NotchHoopsEngine.backboardBottomY)
            let bbRect = CGRect(
                x: bbTop.x,
                y: bbTop.y,
                width: max(5, 7 * scale),
                height: bbBottom.y - bbTop.y
            )
            context.fill(Path(bbRect), with: .color(Self.cyan.opacity(0.18)))
            context.stroke(Path(bbRect), with: .color(Self.cyan.opacity(0.9)), lineWidth: 1.5)

            // Aim trajectory dots while dragging
            if let drag = dragTranslation, engine.phase == .ready {
                let points = NotchHoopsEngine.predictedTrajectory(
                    dragDeltaX: Double(drag.width),
                    dragDeltaY: Double(drag.height)
                )
                for (idx, p) in points.enumerated() {
                    let c = pt(p.x, p.y)
                    let r = max(1.8, 3.0 * scale)
                    let alpha = max(0.25, 0.9 - Double(idx) * 0.06)
                    context.fill(
                        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                        with: .color(Self.cyan.opacity(alpha))
                    )
                }
            }

            // Basketball
            let ballPos = pt(engine.ballX, engine.ballY)
            let ballR = NotchHoopsEngine.ballRadius * scale
            let ballRect = CGRect(x: ballPos.x - ballR, y: ballPos.y - ballR, width: ballR * 2, height: ballR * 2)
            context.fill(Path(ellipseIn: ballRect), with: .color(Self.orange))
            context.stroke(Path(ellipseIn: ballRect), with: .color(.black.opacity(0.85)), lineWidth: 1.4)

            // Rotating seam lines on the basketball
            var seamPath = Path()
            let angle = engine.ballRotation
            let dx = cos(angle) * ballR * 0.85
            let dy = sin(angle) * ballR * 0.85
            seamPath.move(to: CGPoint(x: ballPos.x - dx, y: ballPos.y - dy))
            seamPath.addLine(to: CGPoint(x: ballPos.x + dx, y: ballPos.y + dy))
            seamPath.move(to: CGPoint(x: ballPos.x - dy, y: ballPos.y + dx))
            seamPath.addLine(to: CGPoint(x: ballPos.x + dy, y: ballPos.y - dx))
            context.stroke(seamPath, with: .color(.black.opacity(0.65)), lineWidth: 1.1)

            // Net (drawn after ball so ball passes behind rim front & through net)
            let rimLeft = pt(NotchHoopsEngine.rimCenterX - NotchHoopsEngine.rimHalfWidth, NotchHoopsEngine.rimY)
            let rimRight = pt(NotchHoopsEngine.rimCenterX + NotchHoopsEngine.rimHalfWidth, NotchHoopsEngine.rimY)
            let netBottomY = rimLeft.y + 28 * scale
            let swayOffset = CGFloat(engine.netSway) * 7.0 * scale
            let netLeftBottom = CGPoint(x: rimLeft.x + 6 * scale + swayOffset, y: netBottomY)
            let netRightBottom = CGPoint(x: rimRight.x - 6 * scale + swayOffset, y: netBottomY)

            var netPath = Path()
            let cols = 4
            for i in 0...cols {
                let t = CGFloat(i) / CGFloat(cols)
                let topX = rimLeft.x + (rimRight.x - rimLeft.x) * t
                let botX = netLeftBottom.x + (netRightBottom.x - netLeftBottom.x) * t
                netPath.move(to: CGPoint(x: topX, y: rimLeft.y))
                netPath.addLine(to: CGPoint(x: botX, y: netBottomY))
            }
            for row in 1...2 {
                let t = CGFloat(row) / 3.0
                let y = rimLeft.y + (netBottomY - rimLeft.y) * t
                let lx = rimLeft.x + (netLeftBottom.x - rimLeft.x) * t
                let rx = rimRight.x + (netRightBottom.x - rimRight.x) * t
                netPath.move(to: CGPoint(x: lx, y: y))
                netPath.addLine(to: CGPoint(x: rx, y: y))
            }
            context.stroke(netPath, with: .color(.white.opacity(0.75)), lineWidth: 1.0)

            // Rim bar
            var rimPath = Path()
            rimPath.move(to: rimLeft)
            rimPath.addLine(to: rimRight)
            context.stroke(rimPath, with: .color(Self.orange), lineWidth: max(2.5, 3.2 * scale))

            // "SWIPE UP ↗" hint before first shot
            if !engine.hasTakenShot && dragTranslation == nil && engine.phase == .ready {
                let hintPos = pt(NotchHoopsEngine.launchX + 2, NotchHoopsEngine.launchY - 26)
                context.draw(
                    Text("SWIPE UP ↗")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8)),
                    at: hintPos
                )
            }

            // Floating score / miss feedback
            if let feedback = engine.feedbackText, engine.feedbackTimer > 0 {
                let alpha = min(1.0, engine.feedbackTimer * 1.4)
                let fbPos = pt(NotchHoopsEngine.rimCenterX - 18, NotchHoopsEngine.rimY - 34)
                let label = engine.feedbackPoints > 0 ? "\(feedback) +\(engine.feedbackPoints) PT\(engine.feedbackPoints > 1 ? "S" : "")" : feedback
                context.draw(
                    Text(label)
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor((engine.feedbackPoints > 0 ? Self.green : Self.orange).opacity(alpha)),
                    at: fbPos
                )
            }
        }
    }

    private func updateInteractionLock(dragging: Bool, phase: NotchHoopsEngine.Phase) {
        appState.isGameInteractionLocked = dragging || phase == .flying
    }
}
