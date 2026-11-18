import XCTest
@testable import Morrow
import MorrowCore

/// Two hosts whose integrated terminals were unreachable from the island:
/// Orca (#302) and Zed (#307). Both hand their PTY a rebuilt environment, so
/// bundle-id-based routing never fired and the click fell through to a generic
/// fallback — a blank Terminal.app window for Orca, nothing at all for Zed.
final class OrcaAndZedActivationTests: XCTestCase {

    // MARK: - Orca

    func testOrcaEnvIsCapturedFromTheHookPayload() throws {
        var sessions: [String: SessionSnapshot] = ["s": SessionSnapshot()]
        let event = try makeEvent([
            "_orca_terminal_handle": "term_abc123",
            "_orca_worktree_id": "wt_1on1",
        ])

        extractMetadata(into: &sessions, sessionId: "s", event: event)

        XCTAssertEqual(sessions["s"]?.orcaTerminalHandle, "term_abc123")
        XCTAssertEqual(sessions["s"]?.orcaWorktreeId, "wt_1on1")
    }

    func testOrcaIsLabelledEvenWhenItStrippedTermProgram() {
        var session = SessionSnapshot()
        session.orcaTerminalHandle = "term_abc123"
        // Claude Agent Teams sessions arrive with neither TERM_PROGRAM nor a
        // bundle id; without the ORCA_* fallback this read as an unknown terminal.
        XCTAssertEqual(session.terminalName, "Orca")
    }

    func testTwoWorktreesOfOneRepoCarryDistinctTerminalHandles() throws {
        // The whole point of the handle: both cards share the repo name, so a
        // title match cannot tell them apart — only the handle can.
        var sessions: [String: SessionSnapshot] = [
            "main": SessionSnapshot(),
            "child": SessionSnapshot(),
        ]
        extractMetadata(
            into: &sessions,
            sessionId: "main",
            event: try makeEvent(["_orca_terminal_handle": "term_main", "cwd": "/Users/me/bucket"])
        )
        extractMetadata(
            into: &sessions,
            sessionId: "child",
            event: try makeEvent(["_orca_terminal_handle": "term_1on1", "cwd": "/Users/me/orca/workspaces/bucket/1on1"])
        )

        XCTAssertNotEqual(sessions["main"]?.orcaTerminalHandle, sessions["child"]?.orcaTerminalHandle)
    }

    // MARK: - Zed

    func testZedTerminalResolvesToItsBundleIdFromTermProgramAlone() {
        XCTAssertEqual(TerminalActivator.termProgramToIDEBundleId["zed"], "dev.zed.Zed")
    }

    func testZedSessionWithoutABundleIdStillCountsAsAnIDETerminal() {
        var session = SessionSnapshot()
        session.termApp = "zed"
        XCTAssertTrue(
            session.isIDETerminal,
            "Zed gives its terminal a rebuilt env with no __CFBundleIdentifier"
        )
    }

    func testAPlainTerminalWithoutABundleIdIsStillNotAnIDETerminal() {
        var session = SessionSnapshot()
        session.termApp = "Ghostty"
        XCTAssertFalse(session.isIDETerminal)
    }

    // MARK: - Helpers

    private func makeEvent(_ extra: [String: Any]) throws -> HookEvent {
        var payload: [String: Any] = [
            "hook_event_name": "SessionStart",
            "session_id": "s",
        ]
        for (key, value) in extra { payload[key] = value }
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try XCTUnwrap(HookEvent(from: data))
    }
}
