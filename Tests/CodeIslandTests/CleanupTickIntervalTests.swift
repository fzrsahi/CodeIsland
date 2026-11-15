import XCTest
@testable import CodeIsland

/// The idle sweep's cadence (idle-perf ticket 11). The decision is a pure
/// function so the schedule can be tested without a timer.
@MainActor
final class CleanupTickIntervalTests: XCTestCase {
    func testNoSessionsStopsTheSweep() {
        XCTAssertNil(AppState.cleanupInterval(sessionCount: 0, hasActiveSession: false))
        XCTAssertNil(AppState.cleanupInterval(sessionCount: 0, hasActiveSession: true))
    }

    func testAllIdleSessionsSlowTheSweepDown() {
        XCTAssertEqual(AppState.cleanupInterval(sessionCount: 3, hasActiveSession: false), 15)
    }

    func testAnActiveSessionKeepsTheSweepFast() {
        XCTAssertEqual(AppState.cleanupInterval(sessionCount: 1, hasActiveSession: true), 3)
        XCTAssertEqual(AppState.cleanupInterval(sessionCount: 30, hasActiveSession: true), 3)
    }

    func testTheCodexPollMatchesTheCoordinatorsCadence() {
        // The coordinator's default interval is the contract the timer copies.
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertFalse(SessionDiscoveryCoordinator.shouldPollCodexDesktopDiscovery(
            runningBundleIdentifiers: [AppState.codexAppBundleId],
            lastPollAt: now.addingTimeInterval(-5),
            now: now
        ))
        XCTAssertTrue(SessionDiscoveryCoordinator.shouldPollCodexDesktopDiscovery(
            runningBundleIdentifiers: [AppState.codexAppBundleId],
            lastPollAt: now.addingTimeInterval(-AppState.codexDesktopPollInterval),
            now: now
        ))
    }

    func testRemovingASessionDropsItsPendingToolUses() {
        let state = AppState()
        state.pendingToolUses[ToolUseKey(sessionId: "gone", toolUseId: "a")] = PreToolUseRecord(
            sessionId: "gone", toolName: nil, toolDescription: nil, toolInput: nil, receivedAt: Date()
        )
        state.pendingToolUses[ToolUseKey(sessionId: "kept", toolUseId: "b")] = PreToolUseRecord(
            sessionId: "kept", toolName: nil, toolDescription: nil, toolInput: nil, receivedAt: Date()
        )

        state.removeSession("gone")

        XCTAssertNil(state.pendingToolUses[ToolUseKey(sessionId: "gone", toolUseId: "a")])
        XCTAssertNotNil(state.pendingToolUses[ToolUseKey(sessionId: "kept", toolUseId: "b")])
    }
}
