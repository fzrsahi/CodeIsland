import XCTest
import AppKit
@testable import Morrow
import MorrowCore

/// Answers must reach the session whose card the user acted on, not whatever
/// request happens to sit at the head of the queue. (#308)
@MainActor
final class AppStateAnswerRoutingTests: XCTestCase {

    // MARK: - Questions

    func testAnswerGoesToTheCardsSessionWhenAnotherSessionIsQueuedFirst() async throws {
        let appState = AppState()
        let first = try makeAskUserQuestionEvent(sessionId: "gitops-ansible", text: "Deploy which env?")
        let second = try makeAskUserQuestionEvent(sessionId: "liverpool-cleanup", text: "Delete the branch?")

        let firstResponse = await startHookRequest { appState.handleAskUserQuestion(first, continuation: $0) }
        let secondResponse = await startHookRequest { appState.handleAskUserQuestion(second, continuation: $0) }
        XCTAssertEqual(appState.questionQueue.count, 2)

        // The user is looking at the second session's card.
        appState.answerQuestionMulti(
            [(question: "Delete the branch?", answer: "Yes")],
            expectedSessionId: "liverpool-cleanup"
        )

        // Assert on the queue BEFORE awaiting, and stop on failure: a routing
        // regression resolves the wrong continuation, so the await below would
        // only end in awaitValue's timeout instead of a named failure.
        guard assertQueue(
            appState.questionQueue.map { $0.event.sessionId },
            ["gitops-ansible"],
            "the addressed session must be the one dequeued, and the other must stay queued"
        ) else { return }

        let answers = try extractAnswers(from: await awaitValue(of: secondResponse))
        XCTAssertEqual(answers["Delete the branch?"] as? String, "Yes")

        firstResponse.cancel()
    }

    func testAnswerIsDroppedWhenTheCardsRequestIsNoLongerQueued() async throws {
        let appState = AppState()
        let stale = try makeAskUserQuestionEvent(sessionId: "gitops-ansible", text: "Deploy which env?")
        let other = try makeAskUserQuestionEvent(sessionId: "liverpool-cleanup", text: "Delete the branch?")

        let staleResponse = await startHookRequest { appState.handleAskUserQuestion(stale, continuation: $0) }
        _ = await startHookRequest { appState.handleAskUserQuestion(other, continuation: $0) }

        // The first session answered in its own terminal and dropped its socket,
        // which drains its queue entry and promotes the other session to head.
        appState.handlePeerDisconnect(sessionId: "gitops-ansible")
        _ = try await awaitValue(of: staleResponse)
        XCTAssertEqual(appState.questionQueue.count, 1)
        XCTAssertEqual(appState.questionQueue[0].event.sessionId, "liverpool-cleanup")

        // A click on the now-stale card must not answer the surviving session.
        appState.surface = .questionCard(sessionId: "gitops-ansible")
        appState.answerQuestionMulti(
            [(question: "Deploy which env?", answer: "staging")],
            expectedSessionId: "gitops-ansible"
        )

        XCTAssertEqual(appState.questionQueue.count, 1, "surviving session must still be waiting")
        XCTAssertEqual(appState.questionQueue[0].event.sessionId, "liverpool-cleanup")
        XCTAssertNotEqual(
            appState.surface,
            .questionCard(sessionId: "gitops-ansible"),
            "a card with no queued request must not stay on screen — it would sit expanded and empty"
        )
    }

    /// The case the empty-panel bug actually needs: another session is still
    /// waiting (so the queue is not empty), but Smart Suppress declines to
    /// auto-open its card. `showNextPending` used to leave the old card's
    /// surface untouched, and with the card rendering only its own session's
    /// request that means an expanded, blank notch. (#308)
    func testStaleCardCollapsesWhenAutoOpenIsSuppressed() async throws {
        UserDefaults.standard.set(true, forKey: SettingsKey.smartSuppress)
        defer { UserDefaults.standard.removeObject(forKey: SettingsKey.smartSuppress) }

        let appState = AppState()
        var suppressed = SessionSnapshot()
        suppressed.termApp = "Ghostty"
        suppressed.termBundleId = "com.mitchellh.ghostty"
        // "s-other"'s Ghostty is in front; the card's own session has no terminal.
        installVisibilityProbe(.terminalInFront { $0.termBundleId == "com.mitchellh.ghostty" })
        appState.sessions["s-other"] = suppressed
        XCTAssertFalse(
            appState.shouldAutoOpenPendingSurface(for: "s-other"),
            "test setup must model Smart Suppress declining to auto-open this session"
        )

        let stale = try makePermissionRequestEvent(sessionId: "s-stale", command: "echo 1")
        let other = try makePermissionRequestEvent(sessionId: "s-other", command: "echo 2")

        let staleResponse = await startHookRequest { appState.handlePermissionRequest(stale, continuation: $0) }
        _ = await startHookRequest { appState.handlePermissionRequest(other, continuation: $0) }

        appState.surface = .approvalCard(sessionId: "s-stale")
        appState.handlePeerDisconnect(sessionId: "s-stale")
        _ = try await awaitValue(of: staleResponse)

        XCTAssertEqual(appState.permissionQueue.map { $0.event.sessionId }, ["s-other"])
        XCTAssertEqual(
            appState.surface,
            .collapsed,
            "the drained card must not stay up — it has no request left to render"
        )
    }

    func testStaleCardCollapsesWhenItsRequestIsDrained() async throws {
        let appState = AppState()
        let only = try makeAskUserQuestionEvent(sessionId: "s-only", text: "Proceed?")

        let response = await startHookRequest { appState.handleAskUserQuestion(only, continuation: $0) }
        appState.surface = .questionCard(sessionId: "s-only")

        // Answered in the terminal instead: the socket drops and the entry drains.
        appState.handlePeerDisconnect(sessionId: "s-only")
        _ = try await awaitValue(of: response)

        XCTAssertEqual(
            appState.surface,
            .collapsed,
            "nothing is queued, so the panel must collapse rather than render an empty card"
        )
    }

    func testSkipTargetsTheCardsSession() async throws {
        let appState = AppState()
        let first = try makeAskUserQuestionEvent(sessionId: "s-first", text: "First?")
        let second = try makeAskUserQuestionEvent(sessionId: "s-second", text: "Second?")

        _ = await startHookRequest { appState.handleAskUserQuestion(first, continuation: $0) }
        let secondResponse = await startHookRequest { appState.handleAskUserQuestion(second, continuation: $0) }

        appState.skipQuestion(expectedSessionId: "s-second")

        guard assertQueue(
            appState.questionQueue.map { $0.event.sessionId },
            ["s-first"],
            "skip must dequeue the addressed session"
        ) else { return }
        let behavior = try extractPermissionBehavior(from: await awaitValue(of: secondResponse))
        XCTAssertEqual(behavior, "deny")
    }

    // MARK: - Answer state across cards (#333)

    /// The #333 report, end to end: two sessions each ask one question. The
    /// first card is answered, the second session's card replaces it in the
    /// same slot, and the second session used to receive the first answer
    /// ("是否立即触发构建？ → openURL 传裸路径"), because the card's answer
    /// state survived the swap and answers are mapped by position.
    func testEachSessionReceivesOnlyTheAnswerGivenOnItsOwnCard() async throws {
        let appState = AppState()
        let first = try makeAskUserQuestionEvent(
            sessionId: "s-openurl",
            text: "How should openURL receive the path?",
            options: ["openURL 传裸路径", "file:// URL"]
        )
        let second = try makeAskUserQuestionEvent(
            sessionId: "s-build",
            text: "是否立即触发构建（含后续飞书通知）？",
            options: ["立即触发", "稍后"]
        )

        let firstResponse = await startHookRequest { appState.handleAskUserQuestion(first, continuation: $0) }
        let secondResponse = await startHookRequest { appState.handleAskUserQuestion(second, continuation: $0) }
        XCTAssertEqual(appState.surface, .questionCard(sessionId: "s-openurl"))

        // One wizard for both cards: the worst case, where the view keeps its
        // @State across the swap.
        var wizard = QuestionWizardState()
        try chooseOnCardOnScreen("openURL 传裸路径", in: appState, wizard: &wizard)

        guard assertQueue(
            appState.questionQueue.map { $0.event.sessionId },
            ["s-build"],
            "answering the first card must resolve only the first session"
        ) else { return }
        let firstAnswers = try extractAnswers(from: await awaitValue(of: firstResponse))
        XCTAssertEqual(
            firstAnswers as? [String: String],
            ["How should openURL receive the path?": "openURL 传裸路径"]
        )

        // The second session's card is promoted into the same slot.
        XCTAssertEqual(appState.surface, .questionCard(sessionId: "s-build"))
        try chooseOnCardOnScreen("立即触发", in: appState, wizard: &wizard)

        guard assertQueue(
            appState.questionQueue.map { $0.event.sessionId },
            [],
            "the second card's answer must resolve the second session"
        ) else { return }
        let secondAnswers = try extractAnswers(from: await awaitValue(of: secondResponse))
        XCTAssertEqual(
            secondAnswers as? [String: String],
            ["是否立即触发构建（含后续飞书通知）？": "立即触发"],
            "the second session must get the answer given on its own card, never the first session's"
        )
    }

    /// Model-side guard for the same failure: whatever the view does, a set of
    /// answers that is not one-per-question for this request is never mapped
    /// onto its questions by position.
    func testAnswerSetCollectedForAnotherRequestIsRefused() async throws {
        let appState = AppState()
        let first = try makeAskUserQuestionEvent(sessionId: "s-first", text: "First?")
        let second = try makeAskUserQuestionEvent(sessionId: "s-second", text: "Second?")

        _ = await startHookRequest { appState.handleAskUserQuestion(first, continuation: $0) }
        let secondResponse = await startHookRequest { appState.handleAskUserQuestion(second, continuation: $0) }

        // What the card sent before the fix: the first card's answer leading
        // the second card's.
        appState.answerQuestionMulti([
            AskUserQuestionAnswer(question: "First?", answer: "No", selectedOptions: ["No"], customInput: nil),
            AskUserQuestionAnswer(question: "Second?", answer: "Yes", selectedOptions: ["Yes"], customInput: nil),
        ], expectedSessionId: "s-second")
        // Right size, wrong question.
        appState.answerQuestionMulti(
            [AskUserQuestionAnswer(question: "First?", answer: "No", selectedOptions: ["No"], customInput: nil)],
            expectedSessionId: "s-second"
        )

        guard assertQueue(
            appState.questionQueue.map { $0.event.sessionId },
            ["s-first", "s-second"],
            "answers that do not belong to the request must not resolve it"
        ) else { return }

        appState.answerQuestionMulti(
            [AskUserQuestionAnswer(question: "Second?", answer: "Yes", selectedOptions: ["Yes"], customInput: nil)],
            expectedSessionId: "s-second"
        )
        guard assertQueue(
            appState.questionQueue.map { $0.event.sessionId },
            ["s-first"],
            "the request's own answer still goes through"
        ) else { return }
        let answers = try extractAnswers(from: await awaitValue(of: secondResponse))
        XCTAssertEqual(answers as? [String: String], ["Second?": "Yes"])
    }

    /// The card is keyed by request, not session: the next request of the
    /// same session (or of another agent in it) must get a fresh card, and a
    /// request keeps its card while it is updated in place.
    func testQuestionCardIdentityIsPerRequest() async throws {
        let appState = AppState()
        let first = try makeAskUserQuestionEvent(sessionId: "s-a", text: "First?")
        let second = try makeAskUserQuestionEvent(sessionId: "s-b", text: "Second?")

        _ = await startHookRequest { appState.handleAskUserQuestion(first, continuation: $0) }
        let firstId = try XCTUnwrap(appState.pendingQuestion(forSession: "s-a")?.id)

        _ = await startHookRequest { appState.handleAskUserQuestion(second, continuation: $0) }
        let secondId = try XCTUnwrap(appState.pendingQuestion(forSession: "s-b")?.id)
        XCTAssertNotEqual(firstId, secondId)
        XCTAssertEqual(
            appState.pendingQuestion(forSession: "s-a")?.id,
            firstId,
            "queueing another request must not change a shown card's identity"
        )

        appState.questionQueue[0].askUserQuestionState?.answers["First?"] = "Yes"
        XCTAssertEqual(
            appState.pendingQuestion(forSession: "s-a")?.id,
            firstId,
            "a partial answer (iPhone) updates the request in place, same card"
        )

        // The same session asking again is a different request.
        let again = try makeAskUserQuestionEvent(sessionId: "s-a", text: "First?")
        _ = await startHookRequest { appState.handleAskUserQuestion(again, continuation: $0) }
        let againId = try XCTUnwrap(appState.pendingQuestion(forSession: "s-a")?.id)
        XCTAssertNotEqual(againId, firstId, "a re-asked question must not inherit the previous card's state")
    }

    // MARK: - Permissions

    func testApproveGoesToTheCardsSessionWhenAnotherSessionIsQueuedFirst() async throws {
        let appState = AppState()
        let first = try makePermissionRequestEvent(sessionId: "s-first", command: "echo 1")
        let second = try makePermissionRequestEvent(sessionId: "s-second", command: "echo 2")

        _ = await startHookRequest { appState.handlePermissionRequest(first, continuation: $0) }
        let secondResponse = await startHookRequest { appState.handlePermissionRequest(second, continuation: $0) }
        XCTAssertEqual(appState.permissionQueue.count, 2)

        appState.approvePermission(expectedSessionId: "s-second")

        // Queue first — see the note in the question-routing test above.
        guard assertQueue(
            appState.permissionQueue.map { $0.event.sessionId },
            ["s-first"],
            "approve must dequeue the addressed session"
        ) else { return }
        let response = try await awaitValue(of: secondResponse)
        XCTAssertEqual(try extractPermissionBehavior(from: response), "allow")
    }

    func testDenyIsDroppedWhenTheCardsRequestIsNoLongerQueued() async throws {
        let appState = AppState()
        let stale = try makePermissionRequestEvent(sessionId: "s-stale", command: "echo 1")
        let other = try makePermissionRequestEvent(sessionId: "s-other", command: "echo 2")

        let staleResponse = await startHookRequest { appState.handlePermissionRequest(stale, continuation: $0) }
        _ = await startHookRequest { appState.handlePermissionRequest(other, continuation: $0) }

        appState.handlePeerDisconnect(sessionId: "s-stale")
        _ = try await awaitValue(of: staleResponse)
        XCTAssertEqual(appState.permissionQueue.map { $0.event.sessionId }, ["s-other"])

        appState.surface = .approvalCard(sessionId: "s-stale")
        appState.denyPermission(expectedSessionId: "s-stale")

        XCTAssertEqual(
            appState.permissionQueue.map { $0.event.sessionId },
            ["s-other"],
            "the surviving session's approval must remain pending"
        )
        XCTAssertNotEqual(appState.surface, .approvalCard(sessionId: "s-stale"))
    }

    func testDismissTargetsTheCardsSession() async throws {
        let appState = AppState()
        let first = try makePermissionRequestEvent(sessionId: "s-first", command: "echo 1")
        let second = try makePermissionRequestEvent(sessionId: "s-second", command: "echo 2")

        _ = await startHookRequest { appState.handlePermissionRequest(first, continuation: $0) }
        _ = await startHookRequest { appState.handlePermissionRequest(second, continuation: $0) }

        appState.surface = .approvalCard(sessionId: "s-second")
        appState.dismissPermissionPrompt(expectedSessionId: "s-second")

        // Dismissing hides that session's prompt and hands the panel to the
        // session that is still visible. Had it dismissed the head instead, the
        // panel would have swung to the session the user just dismissed.
        XCTAssertEqual(appState.surface, .approvalCard(sessionId: "s-first"))
        XCTAssertEqual(appState.permissionQueue.count, 2, "dismiss hides, it must not resolve")
    }

    // MARK: - Card rendering

    func testCardLookupReturnsTheAddressedSessionsRequest() async throws {
        let appState = AppState()
        let first = try makePermissionRequestEvent(sessionId: "s-first", command: "echo 1")
        let second = try makePermissionRequestEvent(sessionId: "s-second", command: "echo 2")

        _ = await startHookRequest { appState.handlePermissionRequest(first, continuation: $0) }
        _ = await startHookRequest { appState.handlePermissionRequest(second, continuation: $0) }

        XCTAssertEqual(appState.pendingPermission(forSession: "s-second")?.event.sessionId, "s-second")
        XCTAssertNil(appState.pendingPermission(forSession: "s-missing"))
        XCTAssertEqual(appState.permissionQueuePosition(forSession: "s-second"), 2)
    }

    func testQuestionCardLookupReturnsTheAddressedSessionsRequest() async throws {
        let appState = AppState()
        let first = try makeAskUserQuestionEvent(sessionId: "s-first", text: "First?")
        let second = try makeAskUserQuestionEvent(sessionId: "s-second", text: "Second?")

        _ = await startHookRequest { appState.handleAskUserQuestion(first, continuation: $0) }
        _ = await startHookRequest { appState.handleAskUserQuestion(second, continuation: $0) }

        XCTAssertEqual(appState.pendingQuestion(forSession: "s-second")?.question.question, "Second?")
        XCTAssertNil(appState.pendingQuestion(forSession: "s-missing"))
        XCTAssertEqual(appState.questionQueuePosition(forSession: "s-second"), 2)
    }

    // MARK: - Head-of-queue behaviour is preserved for surfaces that mirror it

    func testOmittedSessionStillResolvesTheHead() async throws {
        let appState = AppState()
        let first = try makePermissionRequestEvent(sessionId: "s-first", command: "echo 1")
        let second = try makePermissionRequestEvent(sessionId: "s-second", command: "echo 2")

        let firstResponse = await startHookRequest { appState.handlePermissionRequest(first, continuation: $0) }
        _ = await startHookRequest { appState.handlePermissionRequest(second, continuation: $0) }
        XCTAssertEqual(appState.permissionQueue.count, 2, "a one-element queue could not detect a change here")

        // Buddy/companion surfaces mirror the head and pass no session.
        appState.approvePermission()

        guard assertQueue(
            appState.permissionQueue.map { $0.event.sessionId },
            ["s-second"],
            "with no session passed, the head must be the one resolved"
        ) else { return }
        let response = try await awaitValue(of: firstResponse)
        XCTAssertEqual(try extractPermissionBehavior(from: response), "allow")
    }

    /// The single-answer path (`Notification` questions, not the AskUserQuestion
    /// wizard) routes by session too.
    func testSingleAnswerQuestionTargetsTheCardsSession() async throws {
        let appState = AppState()
        let first = try makeNotificationQuestionEvent(sessionId: "s-first", text: "First?")
        let second = try makeNotificationQuestionEvent(sessionId: "s-second", text: "Second?")

        _ = await startHookRequest { appState.handleQuestion(first, continuation: $0) }
        let secondResponse = await startHookRequest { appState.handleQuestion(second, continuation: $0) }
        XCTAssertEqual(appState.questionQueue.count, 2)

        appState.answerQuestion("B", expectedSessionId: "s-second")

        guard assertQueue(
            appState.questionQueue.map { $0.event.sessionId },
            ["s-first"],
            "the single-answer path must dequeue the addressed session"
        ) else { return }
        let responseData = try await awaitValue(of: secondResponse)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        )
        let output = try XCTUnwrap(json["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(output["answer"] as? String, "B")
    }

    /// A dismissed approval is hidden but stays queued, so a liveness check based
    /// on queue membership alone would keep its card on screen — re-rendering the
    /// request the user just dismissed.
    func testDismissedCardDoesNotStayOnScreenWhenAutoOpenIsSuppressed() async throws {
        UserDefaults.standard.set(true, forKey: SettingsKey.smartSuppress)
        defer { UserDefaults.standard.removeObject(forKey: SettingsKey.smartSuppress) }

        let appState = AppState()
        var suppressed = SessionSnapshot()
        suppressed.termApp = "Ghostty"
        suppressed.termBundleId = "com.mitchellh.ghostty"
        installVisibilityProbe(.terminalInFront { $0.termBundleId == "com.mitchellh.ghostty" })
        appState.sessions["s-other"] = suppressed
        XCTAssertFalse(appState.shouldAutoOpenPendingSurface(for: "s-other"))

        let dismissed = try makePermissionRequestEvent(sessionId: "s-dismissed", command: "echo 1")
        let other = try makePermissionRequestEvent(sessionId: "s-other", command: "echo 2")

        _ = await startHookRequest { appState.handlePermissionRequest(dismissed, continuation: $0) }
        _ = await startHookRequest { appState.handlePermissionRequest(other, continuation: $0) }

        appState.surface = .approvalCard(sessionId: "s-dismissed")
        appState.dismissPermissionPrompt(expectedSessionId: "s-dismissed")

        XCTAssertNotEqual(
            appState.surface,
            .approvalCard(sessionId: "s-dismissed"),
            "a dismissed card must not stay up just because its request is still queued"
        )
        XCTAssertEqual(appState.permissionQueue.count, 2, "dismiss hides, it must not resolve")
    }

    func testDismissIsDroppedWhenTheCardsRequestIsNoLongerQueued() async throws {
        let appState = AppState()
        let stale = try makePermissionRequestEvent(sessionId: "s-stale", command: "echo 1")
        let other = try makePermissionRequestEvent(sessionId: "s-other", command: "echo 2")

        let staleResponse = await startHookRequest { appState.handlePermissionRequest(stale, continuation: $0) }
        _ = await startHookRequest { appState.handlePermissionRequest(other, continuation: $0) }

        appState.handlePeerDisconnect(sessionId: "s-stale")
        _ = try await awaitValue(of: staleResponse)

        appState.surface = .approvalCard(sessionId: "s-stale")
        appState.dismissPermissionPrompt(expectedSessionId: "s-stale")

        XCTAssertEqual(
            appState.permissionQueue.map { $0.event.sessionId },
            ["s-other"],
            "dismissing a card whose request is gone must not hide a different session's prompt"
        )
        XCTAssertNotEqual(appState.surface, .approvalCard(sessionId: "s-stale"))

        // The queue assertions above cannot see the damage a head-based dismiss
        // would do: dismissing hides without dequeuing, so the queue looks the
        // same either way. Whether s-other was wrongly marked dismissed only
        // shows up in whether the panel will still offer its card.
        appState.showNextPending()
        XCTAssertEqual(
            appState.surface,
            .approvalCard(sessionId: "s-other"),
            "s-other must remain offerable — a wrongly-dismissed session is filtered out and the panel stays collapsed"
        )
    }

    // MARK: - Surface accessors

    func testSurfaceSessionAccessorsAreKindMatched() {
        XCTAssertEqual(IslandSurface.approvalCard(sessionId: "a").approvalSessionId, "a")
        XCTAssertNil(IslandSurface.questionCard(sessionId: "q").approvalSessionId)
        XCTAssertEqual(IslandSurface.questionCard(sessionId: "q").questionSessionId, "q")
        XCTAssertNil(IslandSurface.approvalCard(sessionId: "a").questionSessionId)
        // A completion card is neither: a shortcut fired over it addresses nothing.
        XCTAssertNil(IslandSurface.completionCard(sessionId: "c").approvalSessionId)
        XCTAssertNil(IslandSurface.completionCard(sessionId: "c").questionSessionId)
    }

    // MARK: - iPhone Buddy

    /// #320/#308 — the phone names the session its card was showing. Without
    /// that, a tap resolved against the head of the queue, and a Bluetooth
    /// round trip makes the window for another request to arrive far wider
    /// than it ever was on the panel: you approve something you never saw.
    func testCompanionApproveTargetsTheSessionThePhoneWasShowing() async throws {
        let appState = AppState()
        let first = try makePermissionRequestEvent(sessionId: "s-first", command: "rm -rf /")
        let second = try makePermissionRequestEvent(sessionId: "s-second", command: "echo 2")

        _ = await startHookRequest { appState.handlePermissionRequest(first, continuation: $0) }
        let secondResponse = await startHookRequest { appState.handlePermissionRequest(second, continuation: $0) }
        XCTAssertEqual(appState.permissionQueue.count, 2)

        appState.handleBuddyControlCommand(.approveCurrentPermission, expectedSessionId: "s-second")

        guard assertQueue(
            appState.permissionQueue.map { $0.event.sessionId },
            ["s-first"],
            "the phone's approve must dequeue the session it named, not the queue head"
        ) else { return }
        let behavior = try extractPermissionBehavior(from: await awaitValue(of: secondResponse))
        XCTAssertEqual(behavior, "allow")
    }

    /// The hardware Buddy shows whatever is featured and puts no session id on
    /// the wire, so it keeps acting on the head of the queue. Passing nil must
    /// stay equivalent to the old behaviour.
    func testHardwareBuddyWithoutASessionIdStillActsOnTheQueueHead() async throws {
        let appState = AppState()
        let first = try makePermissionRequestEvent(sessionId: "s-first", command: "echo 1")

        let firstResponse = await startHookRequest { appState.handlePermissionRequest(first, continuation: $0) }
        XCTAssertEqual(appState.permissionQueue.count, 1)

        appState.handleBuddyControlCommand(.approveCurrentPermission)

        guard assertQueue(appState.permissionQueue.map { $0.event.sessionId }, [], "head of queue") else { return }
        let headBehavior = try extractPermissionBehavior(from: await awaitValue(of: firstResponse))
        XCTAssertEqual(headBehavior, "allow")
    }

    func testCompanionAnswerTargetsTheSessionThePhoneWasShowing() async throws {
        let appState = AppState()
        let first = try makeNotificationQuestionEvent(sessionId: "s-first", text: "First?")
        let second = try makeNotificationQuestionEvent(sessionId: "s-second", text: "Second?")

        _ = await startHookRequest { appState.handleQuestion(first, continuation: $0) }
        let secondResponse = await startHookRequest { appState.handleQuestion(second, continuation: $0) }
        XCTAssertEqual(appState.questionQueue.count, 2)

        appState.answerCompanionQuestion("from the phone", expectedSessionId: "s-second")

        guard assertQueue(
            appState.questionQueue.map { $0.event.sessionId },
            ["s-first"],
            "the phone's answer must dequeue the session it named"
        ) else { return }
        _ = try await awaitValue(of: secondResponse)
    }

    /// Same as above for AskUserQuestion. The non-head branch handed the
    /// answer to answerQuestion(), which ignores wizard requests, so an
    /// iPhone answer for any session but the head was silently dropped.
    func testCompanionAnswerReachesAnAskUserQuestionQueuedBehindAnotherSession() async throws {
        let appState = AppState()
        let first = try makeAskUserQuestionEvent(sessionId: "s-first", text: "First?")
        let second = try makeAskUserQuestionEvent(sessionId: "s-second", text: "Second?")

        _ = await startHookRequest { appState.handleAskUserQuestion(first, continuation: $0) }
        let secondResponse = await startHookRequest { appState.handleAskUserQuestion(second, continuation: $0) }
        XCTAssertEqual(appState.questionQueue.count, 2)

        appState.answerCompanionQuestion("No", expectedSessionId: "s-second")

        guard assertQueue(
            appState.questionQueue.map { $0.event.sessionId },
            ["s-first"],
            "the phone's answer must resolve the AskUserQuestion it named"
        ) else { return }
        XCTAssertNil(
            appState.questionQueue[0].askUserQuestionState?.answers["First?"],
            "the head session's question must not be touched"
        )
        let answers = try extractAnswers(from: await awaitValue(of: secondResponse))
        XCTAssertEqual(answers as? [String: String], ["Second?": "No"])
    }

    // MARK: - Helpers

    /// Assert the post-action queue, and report whether it held. Every await in
    /// this suite only completes when the *right* continuation was resolved, so
    /// a test that keeps going after this fails sits out awaitValue's timeout
    /// instead of reporting what went wrong.
    private func assertQueue(
        _ actual: [String?],
        _ expected: [String],
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let expectedOptionals = expected.map { Optional($0) }
        XCTAssertEqual(actual, expectedOptionals, message, file: file, line: line)
        return actual == expectedOptionals
    }

    private func makeAskUserQuestionEvent(
        sessionId: String,
        text: String,
        options: [String] = ["Yes", "No"]
    ) throws -> HookEvent {
        let payload: [String: Any] = [
            "hook_event_name": "PermissionRequest",
            "session_id": sessionId,
            "tool_name": "AskUserQuestion",
            "tool_input": [
                "questions": [[
                    "question": text,
                    "header": "Pick",
                    "options": options.map { ["label": $0, "description": ""] },
                ]]
            ],
        ]
        return try makeEvent(payload)
    }

    /// Pick `option` on the question card that is on screen, the way
    /// QuestionBar does — through `wizard`, which (like the view's @State)
    /// the caller keeps across cards — and submit it from that card.
    private func chooseOnCardOnScreen(
        _ option: String,
        in appState: AppState,
        wizard: inout QuestionWizardState
    ) throws {
        let sid = try XCTUnwrap(appState.surface.questionSessionId, "a question card must be on screen")
        let card = try XCTUnwrap(appState.pendingQuestion(forSession: sid))
        let items = try XCTUnwrap(card.askUserQuestionState?.items)
        let chosen = AskUserQuestionAnswer(
            question: items[0].payload.question,
            answer: option,
            selectedOptions: [option],
            customInput: nil
        )
        let submission = try XCTUnwrap(
            wizard.record(chosen, for: card.id, questionCount: items.count),
            "a single-question card submits on its only answer"
        )
        appState.answerQuestionMulti(submission, expectedSessionId: sid)
    }

    private func makeNotificationQuestionEvent(sessionId: String, text: String) throws -> HookEvent {
        let payload: [String: Any] = [
            "hook_event_name": "Notification",
            "session_id": sessionId,
            "question": text,
            "options": ["A", "B"],
        ]
        return try makeEvent(payload)
    }

    private func makePermissionRequestEvent(sessionId: String, command: String) throws -> HookEvent {
        let payload: [String: Any] = [
            "hook_event_name": "PermissionRequest",
            "session_id": sessionId,
            "tool_name": "Bash",
            "tool_input": ["command": command, "description": command],
        ]
        return try makeEvent(payload)
    }

    private func makeEvent(_ payload: [String: Any]) throws -> HookEvent {
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let event = HookEvent(from: data) else {
            XCTFail("Failed to parse HookEvent")
            throw NSError(domain: "AppStateAnswerRoutingTests", code: 1)
        }
        return event
    }

    private func extractAnswers(from responseData: Data) throws -> [String: Any] {
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: responseData) as? [String: Any])
        let hookSpecificOutput = try XCTUnwrap(json["hookSpecificOutput"] as? [String: Any])
        let decision = try XCTUnwrap(hookSpecificOutput["decision"] as? [String: Any])
        let updatedInput = try XCTUnwrap(decision["updatedInput"] as? [String: Any])
        return try XCTUnwrap(updatedInput["answers"] as? [String: Any])
    }

    private func extractPermissionBehavior(from responseData: Data) throws -> String {
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: responseData) as? [String: Any])
        let hookSpecificOutput = try XCTUnwrap(json["hookSpecificOutput"] as? [String: Any])
        let decision = try XCTUnwrap(hookSpecificOutput["decision"] as? [String: Any])
        return try XCTUnwrap(decision["behavior"] as? String)
    }
}
