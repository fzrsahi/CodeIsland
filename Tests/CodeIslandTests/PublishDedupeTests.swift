import XCTest
@testable import CodeIsland
import CodeIslandCore

/// Unit tests for the ticket-12 publish-on-change decision (#12):
/// deciding "send or skip" is a pure function; these pin its contract.
final class PublishDedupeTests: XCTestCase {
    func testChangedContentSends() {
        XCTAssertEqual(
            PublishDedupe.shouldSend(
                lastSent: "a", next: "b",
                isPrimaryFrame: false, isHeartbeat: false, isInteractive: false,
                secondsSinceFullSync: 0
            ),
            .send
        )
    }

    func testIdenticalContentSkips() {
        XCTAssertEqual(
            PublishDedupe.shouldSend(
                lastSent: "a", next: "a",
                isPrimaryFrame: false, isHeartbeat: false, isInteractive: false,
                secondsSinceFullSync: 0
            ),
            .skip
        )
    }

    func testNoCacheAlwaysSends() {
        XCTAssertEqual(
            PublishDedupe.shouldSend(
                lastSent: nil, next: "a",
                isPrimaryFrame: false, isHeartbeat: false, isInteractive: false,
                secondsSinceFullSync: 0
            ),
            .send
        )
    }

    func testNothingToSendSkips() {
        XCTAssertEqual(
            PublishDedupe.shouldSend(
                lastSent: "a", next: nil,
                isPrimaryFrame: false, isHeartbeat: false, isInteractive: false,
                secondsSinceFullSync: 0
            ),
            .skip
        )
    }

    func testPrimaryFrameAlwaysSends() {
        // Firmware uses inter-frame spacing for animation tempo.
        XCTAssertEqual(
            PublishDedupe.shouldSend(
                lastSent: "a", next: "a",
                isPrimaryFrame: true, isHeartbeat: false, isInteractive: false,
                secondsSinceFullSync: 0
            ),
            .send
        )
    }

    func testHeartbeatAlwaysSends() {
        XCTAssertEqual(
            PublishDedupe.shouldSend(
                lastSent: "a", next: "a",
                isPrimaryFrame: false, isHeartbeat: true, isInteractive: false,
                secondsSinceFullSync: 0
            ),
            .send
        )
    }

    func testInteractiveRetryAlwaysSends() {
        XCTAssertEqual(
            PublishDedupe.shouldSend(
                lastSent: "a", next: "a",
                isPrimaryFrame: false, isHeartbeat: false, isInteractive: true,
                secondsSinceFullSync: 0
            ),
            .send
        )
    }

    func testFullResyncSendsIdenticalContent() {
        XCTAssertEqual(
            PublishDedupe.shouldSend(
                lastSent: "a", next: "a",
                isPrimaryFrame: false, isHeartbeat: false, isInteractive: false,
                secondsSinceFullSync: PublishDedupe.fullResyncInterval
            ),
            .send
        )
        XCTAssertEqual(
            PublishDedupe.shouldSend(
                lastSent: "a", next: "a",
                isPrimaryFrame: false, isHeartbeat: false, isInteractive: false,
                secondsSinceFullSync: .infinity
            ),
            .send
        )
    }

    func testJustBeforeResyncSkipsIdentical() {
        XCTAssertEqual(
            PublishDedupe.shouldSend(
                lastSent: "a", next: "a",
                isPrimaryFrame: false, isHeartbeat: false, isInteractive: false,
                secondsSinceFullSync: PublishDedupe.fullResyncInterval - 1
            ),
            .skip
        )
    }

    func testCompanionKeyIgnoresSequenceAndUpdatedAt() {
        let first = AppleCompanionStatePayload(
            sequence: 1, sessionId: "s", source: "claude", status: .idle,
            toolName: nil, workspaceName: nil, messages: [],
            pendingAction: nil, updatedAt: Date(timeIntervalSince1970: 100)
        )
        let second = AppleCompanionStatePayload(
            sequence: 2, sessionId: "s", source: "claude", status: .idle,
            toolName: nil, workspaceName: nil, messages: [],
            pendingAction: nil, updatedAt: Date(timeIntervalSince1970: 200)
        )
        XCTAssertEqual(
            PublishDedupe.companionContentKey(for: first),
            PublishDedupe.companionContentKey(for: second)
        )
    }

    func testCompanionKeyChangesWithContent() {
        let idle = AppleCompanionStatePayload(
            sequence: 1, sessionId: "s", source: "claude", status: .idle,
            toolName: nil, workspaceName: nil, messages: [],
            pendingAction: nil
        )
        let running = AppleCompanionStatePayload(
            sequence: 1, sessionId: "s", source: "claude", status: .running,
            toolName: nil, workspaceName: nil, messages: [],
            pendingAction: nil
        )
        XCTAssertNotEqual(
            PublishDedupe.companionContentKey(for: idle),
            PublishDedupe.companionContentKey(for: running)
        )
    }
}
