import XCTest
@testable import CodeIslandCore

final class NotchHoopsEngineTests: XCTestCase {
    func testInitialStateDoesNotNeedTick() {
        let engine = NotchHoopsEngine(highScore: 10, positionMode: .twoPoint, initialLaunchX: 160)
        XCTAssertEqual(engine.phase, .ready)
        XCTAssertEqual(engine.score, 0)
        XCTAssertEqual(engine.highScore, 10)
        XCTAssertEqual(engine.streak, 0)
        XCTAssertEqual(engine.ballsRemaining, NotchHoopsEngine.maxBalls)
        XCTAssertEqual(engine.currentShotZone, .twoPoint)
        XCTAssertFalse(engine.needsTick)
    }

    func testShotZoneMatchesDistanceFromHoop() {
        XCTAssertEqual(NotchHoopsEngine.shotZone(forX: 80), .threePoint)
        XCTAssertEqual(NotchHoopsEngine.shotZone(forX: 160), .twoPoint)
        XCTAssertEqual(NotchHoopsEngine.shotZone(forX: 225), .onePoint)
        XCTAssertEqual(NotchHoopsEngine.ShotZone.threePoint.points, 3)
        XCTAssertEqual(NotchHoopsEngine.ShotZone.twoPoint.points, 2)
        XCTAssertEqual(NotchHoopsEngine.ShotZone.onePoint.points, 1)
    }

    func testTinyOrDownwardSwipeDoesNotLaunch() {
        var engine = NotchHoopsEngine(initialLaunchX: 160)
        XCTAssertFalse(engine.launch(dragDeltaX: 30, dragDeltaY: -5))
        XCTAssertFalse(engine.launch(dragDeltaX: 30, dragDeltaY: 20))
        XCTAssertEqual(engine.phase, .ready)
        XCTAssertFalse(engine.needsTick)
    }

    func testPredictedTrajectoryReturnsShortArcForValidSwipe() {
        let points = NotchHoopsEngine.predictedTrajectory(fromX: 80, dragDeltaX: 60, dragDeltaY: -90)
        XCTAssertEqual(points.count, 5)
        XCTAssertGreaterThan(points.last?.x ?? 0, 80)
    }

    func testThreeMissesTriggerGameOverAndResetRestoresState() {
        var engine = NotchHoopsEngine(positionMode: .twoPoint, initialLaunchX: 160)

        for expectedRemaining in [2, 1, 0] {
            XCTAssertTrue(engine.launch(dragDeltaX: -40, dragDeltaY: -20))
            XCTAssertEqual(engine.phase, .flying)
            XCTAssertTrue(engine.needsTick)

            for _ in 0..<400 {
                engine.step(dt: 1.0 / 60.0)
                XCTAssertGreaterThanOrEqual(engine.ballX, NotchHoopsEngine.ballRadius - 0.01)
                XCTAssertLessThanOrEqual(engine.ballX, NotchHoopsEngine.courtWidth - NotchHoopsEngine.ballRadius + 0.01)
                XCTAssertLessThanOrEqual(engine.ballY, NotchHoopsEngine.floorY - NotchHoopsEngine.ballRadius + 0.01)
                if engine.phase != .flying { break }
            }

            XCTAssertEqual(engine.ballsRemaining, expectedRemaining)
            XCTAssertEqual(engine.streak, 0)
            XCTAssertEqual(engine.phase, expectedRemaining > 0 ? .ready : .gameOver)
        }

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

    func testDistanceBasedScoringProducesExactZonePointsAndMinimalLabel() {
        let cases: [(launchX: Double, expectedPoints: Int)] = [
            (225, 1), // 1PT zone
            (160, 2), // 2PT zone
            (85, 3),  // 3PT zone
        ]

        for testCase in cases {
            var scoredEngine: NotchHoopsEngine?
            for dragX in stride(from: 20.0, through: 200.0, by: 5.0) {
                for dragY in stride(from: -50.0, through: -170.0, by: -5.0) {
                    var candidate = NotchHoopsEngine(highScore: 0, positionMode: .random, initialLaunchX: testCase.launchX)
                    XCTAssertTrue(candidate.launch(dragDeltaX: dragX, dragDeltaY: dragY))
                    for _ in 0..<300 {
                        candidate.step(dt: 1.0 / 60.0)
                        if candidate.score > 0 {
                            scoredEngine = candidate
                            break
                        }
                        if candidate.phase != .flying { break }
                    }
                    if scoredEngine != nil { break }
                }
                if scoredEngine != nil { break }
            }

            let result = try! XCTUnwrap(scoredEngine, "Expected a valid swipe for launchX=\(testCase.launchX)")
            XCTAssertEqual(result.score, testCase.expectedPoints)
            XCTAssertEqual(result.feedbackText, "+\(testCase.expectedPoints)")
            XCTAssertEqual(result.streak, 1)
            XCTAssertEqual(result.highScore, testCase.expectedPoints)
        }
    }

    func testSoundEventsEmittedOnLaunchScoreMissAndGameOver() {
        // 1. Launch + score
        var scoring = NotchHoopsEngine(highScore: 0, positionMode: .twoPoint, initialLaunchX: 160)
        var scored = false
        for dragX in stride(from: 20.0, through: 200.0, by: 5.0) {
            for dragY in stride(from: -50.0, through: -170.0, by: -5.0) {
                var candidate = NotchHoopsEngine(highScore: 0, positionMode: .twoPoint, initialLaunchX: 160)
                if candidate.launch(dragDeltaX: dragX, dragDeltaY: dragY) {
                    var events = candidate.drainSoundEvents()
                    for _ in 0..<300 {
                        candidate.step(dt: 1.0 / 60.0)
                        events.append(contentsOf: candidate.drainSoundEvents())
                        if candidate.score > 0 { break }
                    }
                    if candidate.score > 0 {
                        XCTAssertEqual(events.first, .launch)
                        XCTAssertTrue(events.contains(where: {
                            if case .score = $0 { return true }
                            return false
                        }))
                        scored = true
                        break
                    }
                }
            }
            if scored { break }
        }
        XCTAssertTrue(scored)
        XCTAssertTrue(scoring.drainSoundEvents().isEmpty)

        // 2. Miss & game over
        var missEngine = NotchHoopsEngine(positionMode: .twoPoint, initialLaunchX: 160)
        var allMissEvents: [NotchHoopsEngine.SoundEvent] = []
        for _ in 0..<3 {
            XCTAssertTrue(missEngine.launch(dragDeltaX: -40, dragDeltaY: -20))
            allMissEvents.append(contentsOf: missEngine.drainSoundEvents())
            for _ in 0..<400 {
                missEngine.step(dt: 1.0 / 60.0)
                allMissEvents.append(contentsOf: missEngine.drainSoundEvents())
                if missEngine.phase != .flying { break }
            }
        }
        XCTAssertTrue(allMissEvents.contains(.miss))
        XCTAssertTrue(allMissEvents.contains(.gameOver))
    }

    func testOvershootBehindBackboardCannotBounceBackAndScore() {
        // Strong high-right swipe from 1P spot overshoots over the backboard to the right wall
        var engine = NotchHoopsEngine(highScore: 0, positionMode: .onePoint, initialLaunchX: 225)
        XCTAssertTrue(engine.launch(dragDeltaX: 160, dragDeltaY: -180))

        for _ in 0..<400 {
            engine.step(dt: 1.0 / 60.0)
            if engine.phase != .flying { break }
        }

        XCTAssertEqual(engine.score, 0)
        XCTAssertEqual(engine.ballsRemaining, NotchHoopsEngine.maxBalls - 1)
    }

    func testBankShotOffBackboardStillScores() {
        var foundBankScore = false
        for dragX in stride(from: 60.0, through: 170.0, by: 2.0) {
            for dragY in stride(from: -70.0, through: -160.0, by: -2.0) {
                var engine = NotchHoopsEngine(highScore: 0, positionMode: .twoPoint, initialLaunchX: 160)
                XCTAssertTrue(engine.launch(dragDeltaX: dragX, dragDeltaY: dragY))
                var hitBackboard = false
                for _ in 0..<300 {
                    engine.step(dt: 1.0 / 60.0)
                    let events = engine.drainSoundEvents()
                    if events.contains(.rimOrBackboard) { hitBackboard = true }
                    if engine.score > 0 && hitBackboard {
                        foundBankScore = true
                        break
                    }
                    if engine.phase != .flying { break }
                }
                if foundBankScore { break }
            }
            if foundBankScore { break }
        }
        XCTAssertTrue(foundBankScore)
    }

    func testOvershootPastBackboardPassesThroughWithoutInvisibleWallBounce() {
        var engine = NotchHoopsEngine(highScore: 0, positionMode: .onePoint, initialLaunchX: 225)
        XCTAssertTrue(engine.launch(dragDeltaX: 180, dragDeltaY: -120))

        var maxBallX = engine.ballX
        var keptPositiveVelocityPastBackboard = true
        for _ in 0..<400 {
            engine.step(dt: 1.0 / 60.0)
            if engine.phase != .flying { break }
            maxBallX = max(maxBallX, engine.ballX)
            if engine.ballX > NotchHoopsEngine.backboardX + 6 && engine.ballVX <= 0 {
                keptPositiveVelocityPastBackboard = false
            }
        }

        XCTAssertGreaterThan(maxBallX, NotchHoopsEngine.courtWidth)
        XCTAssertTrue(keptPositiveVelocityPastBackboard)
        XCTAssertEqual(engine.score, 0)
        XCTAssertEqual(engine.phase, .ready)
        XCTAssertEqual(engine.ballsRemaining, NotchHoopsEngine.maxBalls - 1)
    }
}
