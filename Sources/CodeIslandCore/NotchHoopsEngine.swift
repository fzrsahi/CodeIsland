import Foundation

/// Lightweight, pure-Swift 2D physics and scoring engine for the Notch Hoops mini-game.
/// Designed for zero idle overhead: `needsTick` is only true while a ball is in flight
/// or a brief score/net feedback animation is settling.
public struct NotchHoopsEngine: Sendable {
    public enum Phase: Equatable, Sendable {
        case ready
        case flying
        case gameOver
    }

    public enum SoundEvent: Hashable, Sendable {
        case launch
        case rimOrBackboard
        case bounce
        case score(isSwish: Bool)
        case miss
        case gameOver
    }

    /// Distance-based scoring zones measured from the hoop on the right.
    public enum ShotZone: String, CaseIterable, Sendable {
        case onePoint = "1P"
        case twoPoint = "2P"
        case threePoint = "3P"

        public var points: Int {
            switch self {
            case .onePoint: return 1
            case .twoPoint: return 2
            case .threePoint: return 3
            }
        }

        public var xRange: ClosedRange<Double> {
            switch self {
            case .onePoint: return 204...248
            case .twoPoint: return 122...194
            case .threePoint: return 46...112
            }
        }
    }

    /// Player-selectable starting position mode: random per turn or locked to a zone.
    public enum PositionMode: String, CaseIterable, Sendable {
        case random = "RND"
        case onePoint = "1P"
        case twoPoint = "2P"
        case threePoint = "3P"
    }

    public static let courtWidth: Double = 460
    public static let courtHeight: Double = 256
    public static let ballRadius: Double = 12
    public static let launchY: Double = 212
    public static let floorY: Double = launchY + ballRadius + 4
    public static let rimCenterX: Double = 396
    public static let rimY: Double = 124
    public static let rimHalfWidth: Double = 22
    public static let rimPostRadius: Double = 3.5
    public static let backboardX: Double = 424
    public static let backboardTopY: Double = 70
    public static let backboardBottomY: Double = 134
    public static let gravity: Double = 580
    public static let maxBalls: Int = 3

    /// X thresholds separating 3PT, 2PT, and 1PT zones on the court floor.
    public static let threePointLineX: Double = 118
    public static let onePointLineX: Double = 200

    public private(set) var phase: Phase = .ready
    public private(set) var score: Int = 0
    public var highScore: Int
    public private(set) var streak: Int = 0
    public private(set) var ballsRemaining: Int = maxBalls
    public private(set) var hasTakenShot: Bool = false

    public var positionMode: PositionMode = .random {
        didSet {
            if phase == .ready {
                pickNextLaunchPosition()
            }
        }
    }
    public private(set) var currentLaunchX: Double = 82
    public var currentShotZone: ShotZone {
        Self.shotZone(forX: currentLaunchX)
    }

    public private(set) var ballX: Double = 82
    public private(set) var ballY: Double = launchY
    public private(set) var ballVX: Double = 0
    public private(set) var ballVY: Double = 0
    public private(set) var ballRotation: Double = 0

    public private(set) var netSway: Double = 0
    public private(set) var feedbackText: String?
    public private(set) var feedbackPoints: Int = 0
    public private(set) var feedbackTimer: Double = 0
    public private(set) var pendingSoundEvents: [SoundEvent] = []

    /// Returns and clears queued sound cues emitted since the last drain.
    public mutating func drainSoundEvents() -> [SoundEvent] {
        guard !pendingSoundEvents.isEmpty else { return [] }
        let events = pendingSoundEvents
        pendingSoundEvents.removeAll(keepingCapacity: true)
        return events
    }

    private var prevBallY: Double = launchY
    private var touchedRimOrBackboard: Bool = false
    private var scoredCurrentShot: Bool = false
    private var wentBehindBackboard: Bool = false
    private var floorBounces: Int = 0

    public init(highScore: Int = 0, positionMode: PositionMode = .random, initialLaunchX: Double? = nil) {
        self.highScore = max(0, highScore)
        self.positionMode = positionMode
        if let initialLaunchX {
            self.currentLaunchX = initialLaunchX
            self.ballX = initialLaunchX
        } else {
            pickNextLaunchPosition()
        }
    }

    /// True only while physics or short feedback/net-sway animation requires frame ticks.
    public var needsTick: Bool {
        phase == .flying || feedbackTimer > 0 || abs(netSway) > 0.01
    }

    public static func shotZone(forX x: Double) -> ShotZone {
        if x >= onePointLineX {
            return .onePoint
        } else if x >= threePointLineX {
            return .twoPoint
        } else {
            return .threePoint
        }
    }

    public mutating func resetGame() {
        phase = .ready
        score = 0
        streak = 0
        ballsRemaining = Self.maxBalls
        hasTakenShot = false
        pickNextLaunchPosition()
        netSway = 0
        feedbackText = nil
        feedbackPoints = 0
        feedbackTimer = 0
        pendingSoundEvents.removeAll(keepingCapacity: true)
    }

    /// Picks a new starting X position based on `positionMode` (random across all zones or within the chosen zone).
    public mutating func pickNextLaunchPosition() {
        let zone: ShotZone
        switch positionMode {
        case .random:
            zone = ShotZone.allCases.randomElement() ?? .twoPoint
        case .onePoint:
            zone = .onePoint
        case .twoPoint:
            zone = .twoPoint
        case .threePoint:
            zone = .threePoint
        }
        currentLaunchX = Double.random(in: zone.xRange)
        resetBall()
    }

    /// Sets an explicit starting X position (e.g., when clicking/tapping a spot on the floor or in tests).
    public mutating func setLaunchPosition(x: Double) {
        guard phase == .ready else { return }
        let clamped = min(max(x, ShotZone.threePoint.xRange.lowerBound), ShotZone.onePoint.xRange.upperBound)
        currentLaunchX = clamped
        resetBall()
    }

    /// Converts a user drag delta (in court points) into a shot velocity.
    /// Swipe up-right (positive X, negative Y) launches toward the hoop.
    /// Returns false if the drag is too small or the engine is not ready.
    @discardableResult
    public mutating func launch(dragDeltaX: Double, dragDeltaY: Double) -> Bool {
        guard phase == .ready else { return false }
        let velocity = Self.launchVelocity(dragDeltaX: dragDeltaX, dragDeltaY: dragDeltaY)
        guard let velocity else { return false }

        hasTakenShot = true
        phase = .flying
        ballVX = velocity.vx
        ballVY = velocity.vy
        prevBallY = ballY
        touchedRimOrBackboard = false
        scoredCurrentShot = false
        wentBehindBackboard = false
        floorBounces = 0
        feedbackText = nil
        feedbackPoints = 0
        feedbackTimer = 0
        pendingSoundEvents.append(.launch)
        return true
    }

    /// Computes initial launch velocity from a drag gesture delta, or nil if below minimum swipe threshold.
    /// Intentionally unassisted horizontally so players must judge distance & angle for 1P/2P/3P shots.
    public static func launchVelocity(dragDeltaX: Double, dragDeltaY: Double) -> (vx: Double, vy: Double)? {
        guard dragDeltaY < -14 else { return nil }
        let pullUp = min(210.0, max(14.0, -dragDeltaY))
        let pullRight = min(220.0, max(-80.0, dragDeltaX))

        let vy = -(250.0 + pullUp * 2.55)
        let vx = max(40.0, min(520.0, 65.0 + pullRight * 2.15))
        return (vx, vy)
    }

    /// Predicts a short dashed trajectory arc near the ball (kept short so aiming remains a skill challenge).
    public static func predictedTrajectory(
        fromX launchX: Double,
        dragDeltaX: Double,
        dragDeltaY: Double,
        steps: Int = 5,
        stepDt: Double = 0.042
    ) -> [(x: Double, y: Double)] {
        guard let v = launchVelocity(dragDeltaX: dragDeltaX, dragDeltaY: dragDeltaY) else {
            return []
        }
        var points: [(x: Double, y: Double)] = []
        points.reserveCapacity(steps)
        for i in 1...steps {
            let t = Double(i) * stepDt
            let x = launchX + v.vx * t
            let y = launchY + v.vy * t + 0.5 * gravity * t * t
            if y > courtHeight { break }
            points.append((x, y))
        }
        return points
    }

    /// Advances the simulation by `dt` seconds (clamped for stability).
    public mutating func step(dt rawDt: Double) {
        let dt = min(max(rawDt, 0), 1.0 / 30.0)
        guard dt > 0 else { return }

        if feedbackTimer > 0 {
            feedbackTimer = max(0, feedbackTimer - dt)
            if feedbackTimer == 0 {
                feedbackText = nil
                feedbackPoints = 0
            }
        }

        if abs(netSway) > 0.01 {
            netSway *= max(0, 1.0 - dt * 5.0)
        } else {
            netSway = 0
        }

        guard phase == .flying else { return }

        let subSteps = 2
        let subDt = dt / Double(subSteps)
        for _ in 0..<subSteps {
            stepPhysics(dt: subDt)
            if phase != .flying { break }
        }
    }

    private mutating func stepPhysics(dt: Double) {
        prevBallY = ballY
        ballVY += Self.gravity * dt
        ballX += ballVX * dt
        ballY += ballVY * dt
        ballRotation += (ballVX * dt) / Self.ballRadius

        // Backboard collision (front vs back so a ball behind the board never teleports in front)
        if ballX + Self.ballRadius >= Self.backboardX &&
            ballX - Self.ballRadius <= Self.backboardX + 6 &&
            ballY + Self.ballRadius >= Self.backboardTopY &&
            ballY - Self.ballRadius <= Self.backboardBottomY {
            if ballX < Self.backboardX + 3 {
                ballX = Self.backboardX - Self.ballRadius
                if ballVX > 25 {
                    pendingSoundEvents.append(.rimOrBackboard)
                }
                ballVX = -abs(ballVX) * 0.65
            } else {
                ballX = Self.backboardX + 6 + Self.ballRadius
                if ballVX < -25 {
                    pendingSoundEvents.append(.rimOrBackboard)
                }
                ballVX = abs(ballVX) * 0.65
            }
            touchedRimOrBackboard = true
        }

        // Left & right rim post collisions
        collideWithRimPost(postX: Self.rimCenterX - Self.rimHalfWidth, postY: Self.rimY)
        collideWithRimPost(postX: Self.rimCenterX + Self.rimHalfWidth, postY: Self.rimY)

        if ballX - Self.ballRadius > Self.backboardX + 6 {
            wentBehindBackboard = true
        }

        // Hoop-through scoring detection (crossing rimY downward inside the rim opening)
        if !scoredCurrentShot &&
            !wentBehindBackboard &&
            ballVY > 0 &&
            prevBallY <= Self.rimY &&
            ballY >= Self.rimY &&
            abs(ballX - Self.rimCenterX) <= Self.rimHalfWidth {
            scoredCurrentShot = true
            let isSwish = !touchedRimOrBackboard
            let points = currentShotZone.points

            score += points
            streak += 1
            if score > highScore {
                highScore = score
            }
            netSway = isSwish ? 1.0 : 0.65
            feedbackText = "+\(points)"
            feedbackPoints = points
            feedbackTimer = 1.1
            pendingSoundEvents.append(.score(isSwish: isSwish))
        }

        // Side walls & ceiling containment so the ball never disappears off-screen
        if ballX - Self.ballRadius <= 0 {
            ballX = Self.ballRadius
            ballVX = abs(ballVX) * 0.65
        } else if ballX + Self.ballRadius >= Self.courtWidth {
            ballX = Self.courtWidth - Self.ballRadius
            // Dampen right-wall rebound behind the backboard so overshoots drop out instead of bouncing back over the rim
            ballVX = -abs(ballVX) * 0.20
            wentBehindBackboard = true
        }
        if ballY - Self.ballRadius <= 2 {
            ballY = Self.ballRadius + 2
            ballVY = abs(ballVY) * 0.55
        }

        // Court floor bounce & turn resolution
        if ballY + Self.ballRadius >= Self.floorY {
            ballY = Self.floorY - Self.ballRadius
            floorBounces += 1
            let impactSpeed = abs(ballVY)
            ballVY = -impactSpeed * 0.50
            ballVX *= 0.80

            if floorBounces >= 2 || abs(ballVY) < 55 {
                if !scoredCurrentShot {
                    streak = 0
                    ballsRemaining = max(0, ballsRemaining - 1)
                    feedbackText = "MISS"
                    feedbackPoints = 0
                    feedbackTimer = 0.85
                }

                if ballsRemaining > 0 {
                    if !scoredCurrentShot {
                        pendingSoundEvents.append(.miss)
                    }
                    pickNextLaunchPosition()
                    phase = .ready
                } else {
                    pendingSoundEvents.append(.gameOver)
                    resetBall()
                    phase = .gameOver
                }
            } else if impactSpeed > 50 {
                pendingSoundEvents.append(.bounce)
            }
        }
    }

    private mutating func collideWithRimPost(postX: Double, postY: Double) {
        let dx = ballX - postX
        let dy = ballY - postY
        let minDist = Self.ballRadius + Self.rimPostRadius
        let distSq = dx * dx + dy * dy
        guard distSq < minDist * minDist, distSq > 0.0001 else { return }

        let dist = sqrt(distSq)
        let nx = dx / dist
        let ny = dy / dist

        ballX = postX + nx * minDist
        ballY = postY + ny * minDist

        let vn = ballVX * nx + ballVY * ny
        if vn < 0 {
            let restitution = 0.68
            ballVX -= (1.0 + restitution) * vn * nx
            ballVY -= (1.0 + restitution) * vn * ny
            touchedRimOrBackboard = true
            if vn < -40 {
                pendingSoundEvents.append(.rimOrBackboard)
            }
        }
    }

    private mutating func resetBall() {
        ballX = currentLaunchX
        ballY = Self.launchY
        ballVX = 0
        ballVY = 0
        ballRotation = 0
    }
}
