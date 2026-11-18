import XCTest
@testable import Morrow
import MorrowCore

/// CodeBuddy's `Notification` event carries a `notification_type` that says what
/// the agent is waiting for. CodeIsland used to ignore it entirely, which cost it
/// both ways: boot-time auth chatter minted a phantom card (#288), and a real
/// "waiting for your permission" left the card spinning on thinking (#290).
@MainActor
final class NotificationKindTests: XCTestCase {

    func testAuthSuccessNotificationNeverCreatesASession() throws {
        let appState = AppState()
        let event = try makeNotification(
            sessionId: "cb-auth",
            type: "auth_success",
            message: "Login successful"
        )

        appState.handleEvent(event)

        XCTAssertNil(
            appState.sessions["cb-auth"],
            "auth chatter arrives before SessionStart under its own id — it must not mint a card"
        )
    }

    func testAuthSuccessDoesNotDisturbAnAlreadyTrackedSession() throws {
        let appState = AppState()
        var session = SessionSnapshot()
        session.status = .processing
        session.toolDescription = "Editing main.swift"
        appState.sessions["cb-live"] = session

        let event = try makeNotification(sessionId: "cb-live", type: "auth_success", message: "Login successful")
        appState.handleEvent(event)

        XCTAssertEqual(appState.sessions["cb-live"]?.status, .processing)
        XCTAssertEqual(appState.sessions["cb-live"]?.toolDescription, "Editing main.swift")
    }

    func testPermissionPromptNotificationSurfacesTheWaitInsteadOfThinking() throws {
        let appState = AppState()
        var session = SessionSnapshot()
        session.status = .processing
        appState.sessions["cb-perm"] = session

        let event = try makeNotification(
            sessionId: "cb-perm",
            type: "permission_prompt",
            message: "needs your permission to use AskUserQuestion"
        )
        appState.handleEvent(event)

        XCTAssertEqual(
            appState.sessions["cb-perm"]?.status,
            .waitingApproval,
            "the CLI is blocked on the user — the card must not keep spinning"
        )
        XCTAssertEqual(
            appState.sessions["cb-perm"]?.toolDescription,
            "needs your permission to use AskUserQuestion"
        )
    }

    func testIdlePromptNotificationSettlesTheCard() throws {
        let appState = AppState()
        var session = SessionSnapshot()
        session.status = .processing
        appState.sessions["cb-idle"] = session

        let event = try makeNotification(
            sessionId: "cb-idle",
            type: "idle_prompt",
            message: "waiting for your input"
        )
        appState.handleEvent(event)

        XCTAssertEqual(appState.sessions["cb-idle"]?.status, .idle)
    }

    func testUnknownNotificationTypeLeavesStatusAlone() throws {
        let appState = AppState()
        var session = SessionSnapshot()
        session.status = .processing
        appState.sessions["cb-unknown"] = session

        let event = try makeNotification(sessionId: "cb-unknown", type: "some_future_kind", message: "hi")
        appState.handleEvent(event)

        XCTAssertEqual(appState.sessions["cb-unknown"]?.status, .processing)
    }

    // MARK: - Helpers

    private func makeNotification(sessionId: String, type: String, message: String) throws -> HookEvent {
        let payload: [String: Any] = [
            "hook_event_name": "Notification",
            "session_id": sessionId,
            "_source": "codebuddy",
            "cwd": "/tmp/project",
            "message": message,
            "notification_type": type,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try XCTUnwrap(HookEvent(from: data))
    }
}
