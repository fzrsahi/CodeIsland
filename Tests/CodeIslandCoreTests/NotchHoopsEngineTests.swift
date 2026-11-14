import XCTest
@testable import CodeIslandCore

final class NotchHoopsEngineTests: XCTestCase {
    func testInitialStateDoesNotNeedTick() {
        let engine = NotchHoopsEngine(highScore: 10)
        XCTAssertEqual(engine.phase, .ready)
        XCTAssertEqual(engine.score, 0)
        XCTAssertEqual(engine.highScore, 10)
        XCTAssertEqual(engine.streak, 0)
        XCTAssertEqual(engine.ballsRemaining, NotchHoopsEngine.maxBalls)
        XCTAssertFalse(engine.needsTick)
    }

    func testTinyOrDownwardSwipeDoesNotLaunch() {
        var engine = NotchHoopsEngine()
        XCTAssertFalse(engine.launch(dragDeltaX: 30, dragDeltaY: -5))
        XCTAssertFalse(engine.launch(dragDeltaX: 30, dragDeltaY: 20))
        XCTAssertEqual(engine.phase, .ready)
        XCTAssertFalse(engine.needsTick)
    }

    func testPredictedTrajectoryReturnsArcForValidSwipe() {
        let points = NotchHoopsEngine.predictedTrajectory(dragDeltaX: 60, dragDeltaY: -90)
        XCTAssertFalse(points.isEmpty)
        XCTAssertGreaterThan(points.last?.x ?? 0, NotchHoopsEngine.launchX)
    }

    func testThreeMissesTriggerGameOverAndResetRestoresState() {
        var engine = NotchHoopsEngine()

        for expectedRemaining in [2, 1, 0] {
            XCTAssertTrue(engine.launch(dragDeltaX: -40, dragDeltaY: -20))
            XCTAssertEqual(engine.phase, .flying)
            XCTAssertTrue(engine.needsTick)

            // Step until the ball falls out of bounds
            for _ in 0..<240 {
                engine.step(dt: 1.0 / 60.0)
                if engine.phase != .flying { break }
            }

            XCTAssertEqual(engine.ballsRemaining, expectedRemaining)
            XCTAssertEqual(engine.streak, 0)
            XCTAssertEqual(engine.phase, expectedRemaining > 0 ? .ready : .gameOver)
        }

        // Let feedback timer settle
        for _ in 0..<90 {
            engine.step(dt: 1.0 / 60.0)
        }
        XCTAssertFalse(engine.needsTick)

        engine.resetGame()
        XCTAssertEqual(engine.phase, .ready)
        XCTAssertEqual(engine.ballsRemaining, NotchHoopsEngine.maxBalls)
        XCTAssertEqual(engine.score, 0)
        XCTAssertFalse(engine.needsTick)
    }

    func testScoringShotUpdatesScoreStreakAndHighScore() {
        var engine = NotchHoopsEngine(highScore: 0)

        // Find a drag vector that lands in the hoop and simulate it
        var scored = false
        for dragX in stride(from: 20.0, through: 120.0, by: 5.0) {
            for dragY in stride(from: -60.0, through: -150.0, by: -5.0) {
                var candidate = NotchHoopsEngine(highScore: 0)
                XCTAssertTrue(candidate.launch(dragDeltaX: dragX, dragDeltaY: dragY))
                for _ in 0..<300 {
                    candidate.step(dt: 1.0 / 60.0)
                    if candidate.score > 0 {
                        engine = candidate
                        scored = true
                        break
                    }
                    if candidate.phase != .flying { break }
                }
                if scored { break }
            }
            if scored { break }
        }

        XCTAssertTrue(scored, "Expected at least one swipe vector to score in the hoop")
        XCTAssertGreaterThan(engine.score, 0)
        XCTAssertEqual(engine.streak, 1)
        XCTAssertEqual(engine.highScore, engine.score)
        XCTAssertEqual(engine.ballsRemaining, NotchHoopsEngine.maxBalls)
    }
}
