import XCTest
@testable import Morrow
import MorrowCore

/// Agents already running in their own always-proceed mode (Antigravity Turbo,
/// Cursor YOLO) should not be gated a second time on the island — that second
/// confirmation is the exact interruption the mode exists to remove (#283).
final class AutoApproveSourceTests: XCTestCase {

    func testListedSourceIsAutoApproved() throws {
        let event = try makeEvent(source: "google-antigravity")
        XCTAssertTrue(HookServer.isAutoApprovedSource(event, approved: ["google-antigravity"]))
    }

    func testAliasSpellingResolvesOntoTheListedSource() throws {
        // The user typed the canonical id; the CLI reports one of its aliases.
        XCTAssertTrue(HookServer.isAutoApprovedSource(
            try makeEvent(source: "agy"),
            approved: ["google-antigravity"]
        ))
        XCTAssertTrue(HookServer.isAutoApprovedSource(
            try makeEvent(source: "antigravity-cli"),
            approved: ["google-antigravity"]
        ))
    }

    func testUnlistedSourceStillPrompts() throws {
        XCTAssertFalse(HookServer.isAutoApprovedSource(
            try makeEvent(source: "claude"),
            approved: ["google-antigravity"]
        ))
    }

    func testTheClaudeForkIsNotSweptUpByTheGoogleEntry() throws {
        // "antigravity" (the Claude Code fork) and "google-antigravity" (the
        // Gemini IDE) are different products that must not share a decision.
        XCTAssertFalse(HookServer.isAutoApprovedSource(
            try makeEvent(source: "antigravity"),
            approved: ["google-antigravity"]
        ))
    }

    func testEmptyListNeverAutoApproves() throws {
        XCTAssertFalse(HookServer.isAutoApprovedSource(try makeEvent(source: "google-antigravity"), approved: []))
    }

    func testMissingSourceNeverAutoApproves() throws {
        let payload: [String: Any] = [
            "hook_event_name": "PermissionRequest",
            "session_id": "s",
            "tool_name": "Bash",
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let event = try XCTUnwrap(HookEvent(from: data))
        XCTAssertFalse(HookServer.isAutoApprovedSource(event, approved: ["google-antigravity"]))
    }

    @MainActor
    func testSettingParsesCommaSeparatedListWithWhitespaceAndCase() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: SettingsKey.autoApproveSources)
        defer {
            if let saved {
                defaults.set(saved, forKey: SettingsKey.autoApproveSources)
            } else {
                defaults.removeObject(forKey: SettingsKey.autoApproveSources)
            }
        }
        defaults.set(" Google-Antigravity , cursor ", forKey: SettingsKey.autoApproveSources)

        let parsed = SettingsManager.shared.autoApproveSources
        XCTAssertTrue(parsed.contains("google-antigravity"))
        XCTAssertTrue(parsed.contains("cursor"))
    }

    // MARK: - Helpers

    private func makeEvent(source: String) throws -> HookEvent {
        let payload: [String: Any] = [
            "hook_event_name": "PermissionRequest",
            "session_id": "s-\(source)",
            "_source": source,
            "tool_name": "Bash",
            "tool_input": ["command": "ls"],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try XCTUnwrap(HookEvent(from: data))
    }
}
