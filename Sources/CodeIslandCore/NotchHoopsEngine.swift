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

    public static let courtWidth: Double = 390
    public static let courtHeight: Double = 176
    public static let ballRadius: Double = 12
    public static let launchX: Double = 78
    public static let launchY: Double = 138
    public static let rimCenterX: Double = 326
    public static let rimY: Double = 90
    public static let rimHalfWidth: Double = 22
    public static let rimPostRadius: Double = 3.5
    public static let backboardX: Double = 352
    public static let backboardTopY: Double = 38
    public static let backboardBottomY: Double = 102
    public static let gravity: Double = 580
    public static let maxBalls: Int = 3

    public private(set) var phase: Phase = .ready
    public private(set) var score: Int = 0
    public var highScore: Int
    public private(set) var streak: Int = 0
    public private(set) var ballsRemaining: Int = maxBalls
    public private(set) var hasTakenShot: Bool = false

    public private(set) var ballX: Double = launchX
    public private(set) var ballY: Double = launchY
    public private(set) var ballVX: Double = 0
    public private(set) var ballVY: Double = 0
    public private(set) var ballRotation: Double = 0

    public private(set) var netSway: Double = 0
    public private(set) var feedbackText: String?
    public private(set) var feedbackPoints: Int = 0
    public private(set) var feedbackTimer: Double = 0

    private var prevBallY: Double = launchY
    private var touchedRimOrBackboard: Bool = false
    private var scoredCurrentShot: Bool = false

    public init(highScore: Int = 0) {
        self.highScore = max(0, highScore)
    }

    /// True only while physics or short feedback/net-sway animation requires frame ticks.
    public var needsTick: Bool {
        phase == .flying || feedbackTimer > 0 || abs(netSway) > 0.01
    }

    public mutating func resetGame() {
        phase = .ready
        score = 0
        streak = 0
        ballsRemaining = Self.maxBalls
        hasTakenShot = false
        resetBall()
        netSway = 0
        feedbackText = nil
        feedbackPoints = 0
        feedbackTimer = 0
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
        feedbackText = nil
        feedbackPoints = 0
        feedbackTimer = 0
        return true
    }

    /// Computes initial launch velocity from a drag gesture delta, or nil if below minimum swipe threshold.
    public static func launchVelocity(dragDeltaX: Double, dragDeltaY: Double) -> (vx: Double, vy: Double)? {
        // Require an upward swipe (negative Y in SwiftUI coordinates)
        guard dragDeltaY < -14 else { return nil }
        let pullUp = min(170.0, max(20.0, -dragDeltaY))
        let pullRight = min(160.0, max(-40.0, dragDeltaX))

        let vy = -(260.0 + pullUp * 2.15)
        let vx = max(120.0, min(430.0, 175.0 + pullRight * 1.45))
        return (vx, vy)
    }

    /// Predicts a short dashed trajectory arc for the aiming preview.
    public static func predictedTrajectory(
        dragDeltaX: Double,
        dragDeltaY: Double,
        steps: Int = 10,
        stepDt: Double = 0.045
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

        // Two sub-steps per frame prevent tunneling past the thin rim posts
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

        // Backboard collision
        if ballX + Self.ballRadius >= Self.backboardX &&
            ballX - Self.ballRadius <= Self.backboardX + 6 &&
            ballY >= Self.backboardTopY &&
            ballY <= Self.backboardBottomY {
            ballX = Self.backboardX - Self.ballRadius
            ballVX = -abs(ballVX) * 0.65
            touchedRimOrBackboard = true
        }

        // Left & right rim post collisions
        collideWithRimPost(postX: Self.rimCenterX - Self.rimHalfWidth, postY: Self.rimY)
        collideWithRimPost(postX: Self.rimCenterX + Self.rimHalfWidth, postY: Self.rimY)

        // Hoop-through scoring detection (crossing rimY downward inside the rim opening)
        if !scoredCurrentShot &&
            ballVY > 0 &&
            prevBallY <= Self.rimY &&
            ballY >= Self.rimY &&
            abs(ballX - Self.rimCenterX) <= (Self.rimHalfWidth - Self.ballRadius * 0.25) {
            scoredCurrentShot = true
            let isSwish = !touchedRimOrBackboard
            let basePoints = isSwish ? 2 : 1
            let bonus = streak >= 2 ? 1 : 0
            let points = basePoints + bonus

            score += points
            streak += 1
            if score > highScore {
                highScore = score
            }
            netSway = isSwish ? 1.0 : 0.65
            feedbackText = isSwish ? "SWISH!" : "BUCKET!"
            feedbackPoints = points
            feedbackTimer = 1.15
        }

        // Out-of-bounds / floor resolution
        if ballY > Self.courtHeight + Self.ballRadius * 1.5 ||
            ballX > Self.courtWidth + Self.ballRadius * 2 ||
            ballX < -Self.ballRadius * 2 {
            if !scoredCurrentShot {
                streak = 0
                ballsRemaining = max(0, ballsRemaining - 1)
                feedbackText = "MISS!"
                feedbackPoints = 0
                feedbackTimer = 0.9
            }

            resetBall()
            phase = ballsRemaining > 0 ? .ready : .gameOver
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

        // Separate ball from post
        ballX = postX + nx * minDist
        ballY = postY + ny * minDist

        // Reflect velocity along collision normal
        let vn = ballVX * nx + ballVY * ny
        if vn < 0 {
            let restitution = 0.68
            ballVX -= (1.0 + restitution) * vn * nx
            ballVY -= (1.0 + restitution) * vn * ny
            touchedRimOrBackboard = true
        }
    }

    private mutating func resetBall() {
        ballX = Self.launchX
        ballY = Self.launchY
        ballVX = 0
        ballVY = 0
        ballRotation = 0
    }
}
