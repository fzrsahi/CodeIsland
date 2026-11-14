import XCTest
@testable import CodeIsland

/// Discovery's scan throttle (idle-perf ticket 14). An agent writing its
/// transcript used to buy a full process-table scan every couple of seconds.
final class DiscoveryScanPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    // MARK: Interesting events

    func testTheTranscriptBeingTailedIsNotNews() {
        let tailed: Set<String> = ["/home/u/.claude/projects/p/s.jsonl"]
        XCTAssertFalse(DiscoveryScanPolicy.isInteresting(
            path: "/home/u/.claude/projects/p/s.jsonl", tailedPaths: tailed
        ))
        XCTAssertFalse(DiscoveryScanPolicy.hasInterestingEvent(
            paths: ["/home/u/.claude/projects/p/s.jsonl"], tailedPaths: tailed
        ))
    }

    func testEveryOtherStoreWriteIsNews() {
        let tailed: Set<String> = ["/home/u/.claude/projects/p/s.jsonl"]
        // A WAL/SHM side file, a new session's transcript, a lease.
        XCTAssertTrue(DiscoveryScanPolicy.isInteresting(
            path: "/home/u/.claude/projects/p/s.jsonl-wal", tailedPaths: tailed
        ))
        XCTAssertTrue(DiscoveryScanPolicy.isInteresting(
            path: "/home/u/.claude/projects/p/new.jsonl", tailedPaths: tailed
        ))
        XCTAssertTrue(DiscoveryScanPolicy.isInteresting(
            path: "/home/u/.kiro/session-leases/x", tailedPaths: tailed
        ))
    }

    func testABatchWithAnyInterestingPathCounts() {
        let tailed: Set<String> = ["/a/s.jsonl"]
        XCTAssertTrue(DiscoveryScanPolicy.hasInterestingEvent(
            paths: ["/a/s.jsonl", "/a/s.jsonl-shm"], tailedPaths: tailed
        ))
    }

    // MARK: Throttle

    func testTheFirstEventScansImmediately() {
        var throttle = DiscoveryScanThrottle()
        XCTAssertEqual(throttle.decide(hasInterestingEvent: true, now: t0), .scanNow)
    }

    func testAnUninterestingBatchNeverScans() {
        var throttle = DiscoveryScanThrottle()
        XCTAssertEqual(throttle.decide(hasInterestingEvent: false, now: t0), .ignore)
    }

    func testABurstIsLeadingPlusTrailing() {
        var throttle = DiscoveryScanThrottle()
        // Leading scan at t0.
        XCTAssertEqual(throttle.decide(hasInterestingEvent: true, now: t0), .scanNow)
        throttle.noteScanStarted(at: t0)
        // A write one second later cannot scan yet; it schedules the closing scan.
        XCTAssertEqual(
            throttle.decide(hasInterestingEvent: true, now: t0.addingTimeInterval(1)),
            .scanLater(t0.addingTimeInterval(DiscoveryScanPolicy.minimumGap))
        )
        // The trailing scan runs when the gap has passed.
        XCTAssertEqual(
            throttle.decide(hasInterestingEvent: true, now: t0.addingTimeInterval(5)),
            .scanNow
        )
    }

    func testTheClosingScanIsNeverLostWhenTheBurstKeepsGoing() {
        var throttle = DiscoveryScanThrottle()
        throttle.noteScanStarted(at: t0)
        var scheduled: Date?
        // Writes keep arriving every second; the closing scan stays armed.
        for second in 1...4 {
            if case .scanLater(let due) = throttle.decide(
                hasInterestingEvent: true, now: t0.addingTimeInterval(TimeInterval(second))
            ) {
                scheduled = due
            }
        }
        XCTAssertEqual(scheduled, t0.addingTimeInterval(DiscoveryScanPolicy.minimumGap))
        // At the scheduled instant it scans, whatever else is happening.
        XCTAssertEqual(
            throttle.decide(hasInterestingEvent: true, now: t0.addingTimeInterval(5)), .scanNow
        )
    }

    func testAScanLongAgoDoesNotDelayTheNextOne() {
        var throttle = DiscoveryScanThrottle()
        throttle.noteScanStarted(at: t0)
        XCTAssertEqual(
            throttle.decide(hasInterestingEvent: true, now: t0.addingTimeInterval(60)), .scanNow
        )
    }

    func testResettingForgetsTheClock() {
        var throttle = DiscoveryScanThrottle()
        throttle.noteScanStarted(at: t0)
        throttle.reset()
        XCTAssertEqual(throttle.decide(hasInterestingEvent: true, now: t0.addingTimeInterval(1)), .scanNow)
    }

    // MARK: Process snapshot

    func testAPathIsReadOncePerScanAndRememberedAfterwards() {
        let cache = ProcessPathCache()
        let identity = ProcessIdentity(pid: 4242, startTime: t0)

        cache.beginScan()
        XCTAssertNil(cache.scanPath(for: identity))
        cache.store("/usr/bin/claude", for: identity)
        // Every other source in the same scan gets the same answer.
        XCTAssertEqual(cache.scanPath(for: identity), "/usr/bin/claude")
        cache.endScan()

        // A later scan reads nothing for a process it already knows.
        cache.beginScan()
        XCTAssertEqual(cache.path(for: identity), "/usr/bin/claude")
        cache.endScan()
    }

    func testAReusedPidIsANewProcess() {
        let cache = ProcessPathCache()
        let before = ProcessIdentity(pid: 4242, startTime: t0)
        let after = ProcessIdentity(pid: 4242, startTime: t0.addingTimeInterval(60))
        cache.beginScan()
        cache.store("/usr/bin/claude", for: before)
        cache.endScan()

        XCTAssertNil(cache.path(for: after), "a reused pid must not answer with the old process's path")
    }
}
