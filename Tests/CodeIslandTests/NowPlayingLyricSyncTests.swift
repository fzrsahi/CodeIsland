import XCTest
@testable import CodeIsland

final class NowPlayingLyricSyncTests: XCTestCase {

    @MainActor
    func testLyricLineProgression() {
        let manager = NowPlayingManager.shared
        manager.lyrics = [
            LyricLine(id: 0, timestamp: 0.0, text: "Break my heart again, yeah, yeah"),
            LyricLine(id: 1, timestamp: 4.5, text: "Break my heart again, yeah, yeah"),
            LyricLine(id: 2, timestamp: 8.2, text: "Break my heart again"),
            LyricLine(id: 3, timestamp: 12.0, text: "I thought we had it all, but it's just never enough")
        ]
        manager.trackDuration = 180.0

        // At position 0, current lyric should be id 0. The position comes from
        // the anchor now, so a test seeks rather than assigning it.
        manager.seek(to: 0.0)
        XCTAssertEqual(manager.currentLyricText, "Break my heart again, yeah, yeah")

        // Seek past 4.5s
        manager.seek(to: 5.0)
        XCTAssertEqual(manager.currentLyricIndex, 1)
        XCTAssertEqual(manager.currentLyricText, "Break my heart again, yeah, yeah")

        // Seek past 8.2s
        manager.seek(to: 9.0)
        XCTAssertEqual(manager.currentLyricIndex, 2)
        XCTAssertEqual(manager.currentLyricText, "Break my heart again")

        // Seek past 12.0s
        manager.seek(to: 15.0)
        XCTAssertEqual(manager.currentLyricIndex, 3)
        XCTAssertEqual(manager.currentLyricText, "I thought we had it all, but it's just never enough")
    }

    @MainActor
    func testFallbackDurationCalculationWhenZero() {
        let manager = NowPlayingManager.shared
        manager.trackDuration = 0
        manager.lyrics = [
            LyricLine(id: 0, timestamp: 0.0, text: "First line"),
            LyricLine(id: 1, timestamp: 10.0, text: "Second line"),
            LyricLine(id: 2, timestamp: 35.0, text: "Final line")
        ]

        if manager.trackDuration <= 0, let lastTs = manager.lyrics.last?.timestamp, lastTs > 0 {
            manager.trackDuration = lastTs + 5.0
        }

        XCTAssertEqual(manager.trackDuration, 40.0)
    }
}

// MARK: - Next-line scheduling from the anchor (idle-perf ticket 08)

final class NowPlayingLyricWakeTests: XCTestCase {
    private let lines = [
        LyricLine(id: 0, timestamp: 0.0, text: "one"),
        LyricLine(id: 1, timestamp: 4.5, text: "two"),
        LyricLine(id: 2, timestamp: 8.2, text: "three"),
    ]

    func testTheNextLineDecidesTheDelay() {
        XCTAssertEqual(NowPlayingManager.nextLyricDelay(lyrics: lines, position: 2.0) ?? -1, 2.5, accuracy: 0.001)
        XCTAssertEqual(NowPlayingManager.nextLyricDelay(lyrics: lines, position: 0.0) ?? -1, 4.5, accuracy: 0.001)
    }

    func testTheLastLineNeedsNoWake() {
        XCTAssertNil(NowPlayingManager.nextLyricDelay(lyrics: lines, position: 9.0))
    }

    func testAPositionJustBeforeTheLineStillWakes() {
        let delay = NowPlayingManager.nextLyricDelay(lyrics: lines, position: 8.199)
        XCTAssertNotNil(delay)
        XCTAssertGreaterThanOrEqual(delay!, 0.05, "a zero-length timer would spin")
    }

    func testTheSyncOffsetShiftsWhichLineIsNext() {
        // A positive offset moves the effective position forward, so a later
        // line is already current.
        let withoutOffset = NowPlayingManager.nextLyricDelay(lyrics: lines, position: 5.0)
        let withOffset = NowPlayingManager.nextLyricDelay(lyrics: lines, position: 5.0 + 4.0)
        XCTAssertEqual(withoutOffset!, 3.2, accuracy: 0.001)
        XCTAssertNil(withOffset)
    }
}
