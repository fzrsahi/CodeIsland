import Foundation
@testable import MorrowCore

/// A sequence of hook events through the reducer, from the sessions its
/// seeds build. `origin` names the test (or bridge golden fixture) the
/// payloads come from.
struct CoreReducerCase {
    let name: String
    let origin: String
    var maxHistory = 20
    var replyCompletePlaceholder = "Reply complete"
    var customSources: [String] = []
    var seeds: [(String, (inout SessionSnapshot) -> Void)] = []
    let events: [[String: Any]]
}

/// A moment and the session it happened to, for ``AttentionPolicy``.
struct CoreAttentionCase {
    let name: String
    let moment: AttentionMoment
    let subject: AttentionSubject
}

/// The core contract cases (``CoreContractJSONExporter``). Payloads are
/// taken from the reducer, Cursor folding and Agent Sub-Sessions tests and
/// from the bridge's golden output; the attention cases are
/// `AttentionPolicyTests`' own rows.
enum CoreContractCases {
    static var attention: [CoreAttentionCase] {
        let tables = [
            ("hook", AttentionPolicyTests.hookRows),
            ("request", AttentionPolicyTests.requestRows),
            ("elsewhere", AttentionPolicyTests.elsewhereTurnRows),
            ("reminder", AttentionPolicyTests.reminderRows),
        ]
        return tables.flatMap { table, rows in
            rows.map { CoreAttentionCase(name: "\(table)/\($0.rule)", moment: $0.moment, subject: $0.subject) }
        }
    }

    static let reducer: [CoreReducerCase] = lifecycle + tools + waits + subagents + cursor + sources + terminal

    // MARK: - Helpers

    /// The event a bridge golden fixture forwarded, with its `$PIDn` tokens
    /// as pids (4242 + n) and `$ROOT` as `/tmp/golden`.
    static func bridge(_ name: String) -> [String: Any] {
        var json = BridgeGoldenExpectations.all[name]!.forwarded!
        for n in 0..<2 {
            json = json.replacingOccurrences(of: "\"$PID\(n)\"", with: "\(4242 + n)")
                .replacingOccurrences(of: "$PID\(n)", with: "\(4242 + n)")
        }
        json = json.replacingOccurrences(of: "$ROOT", with: "/tmp/golden")
        return try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    }

    static func hook(_ name: String, _ session: String, _ extra: [String: Any] = [:]) -> [String: Any] {
        ["hook_event_name": name, "session_id": session].merging(extra) { _, new in new }
    }

    static func source(_ source: String) -> (inout SessionSnapshot) -> Void {
        { $0.source = source }
    }

    // MARK: - Session lifecycle

    static let lifecycle: [CoreReducerCase] = [
        CoreReducerCase(
            name: "lifecycle/claude-session-life",
            origin: "HookEventFactsTests.testReducerNeverEmitsAttentionEffects",
            events: [
                hook("SessionStart", "claude", ["cwd": "/repo"]),
                hook("UserPromptSubmit", "claude", ["prompt": "fix it"]),
                hook("PreToolUse", "claude", ["tool_name": "Bash"]),
                hook("PostToolUseFailure", "claude", ["tool_name": "Bash"]),
                hook("SubagentStart", "claude", ["agent_id": "a1", "agent_type": "Explore"]),
                hook("PreToolUse", "claude", ["agent_id": "a1", "tool_name": "Read"]),
                hook("SubagentStop", "claude", ["agent_id": "a1"]),
                hook("Stop", "claude", ["last_assistant_message": "done"]),
                hook("StopFailure", "claude", ["error": "rate_limit"]),
                hook("SessionEnd", "claude"),
            ]
        ),
        CoreReducerCase(
            name: "lifecycle/effect-order",
            origin: "HookEventFactsTests.testReduceEventKeepsTheOldEffectOrder",
            events: [
                hook("UserPromptSubmit", "s", ["cwd": "/tmp/r", "prompt": "go"]),
                hook("Stop", "s", ["cwd": "/tmp/r", "last_assistant_message": "x"]),
                hook("UserPromptSubmit", "s", ["cwd": "/tmp/r", "prompt": "again"]),
            ]
        ),
        CoreReducerCase(
            name: "lifecycle/policy-reading",
            origin: "HookEventFactsTests.testReduceEventAddsThePolicysIntents",
            events: [
                hook("SessionStart", "s", ["cwd": "/repo"]),
                hook("UserPromptSubmit", "s", ["prompt": "go"]),
                hook("PostToolUseFailure", "s", ["tool_name": "Bash"]),
                hook("TaskComplete", "s"),
                hook("Stop", "s"),
            ]
        ),
        CoreReducerCase(
            name: "lifecycle/claude-native-session-start",
            origin: "bridge golden claude-native-session-start",
            events: [bridge("claude-native-session-start")]
        ),
        CoreReducerCase(
            name: "lifecycle/stop-failure",
            origin: "TurnFailureSoundTests.testStopFailureEndsTheTurnAndRingsTurnFailed",
            events: [
                hook("UserPromptSubmit", "s2", ["prompt": "go"]),
                hook("StopFailure", "s2", [
                    "error_type": "rate_limit", "error": "Rate limit exceeded", "last_assistant_message": "I'll start by…",
                ]),
            ]
        ),
        CoreReducerCase(
            name: "lifecycle/plain-stop",
            origin: "TurnFailureSoundTests.testPlainStopStillRingsCompletion",
            events: [hook("Stop", "s3")]
        ),
        CoreReducerCase(
            name: "lifecycle/stop-placeholder-injected",
            origin: "ReplyCompletePlaceholderTests.testStopEventUsesInjectedPlaceholderWhenNoMessageContent",
            replyCompletePlaceholder: "返信完了",
            seeds: [("cb-session", { $0.source = "codebuddy"; $0.addRecentMessage(ChatMessage(isUser: true, text: "do the thing")) })],
            events: [hook("Stop", "cb-session", ["_source": "codebuddy"])]
        ),
        CoreReducerCase(
            name: "lifecycle/stop-message-content",
            origin: "ReplyCompletePlaceholderTests.testStopEventUsesMessageContentWhenPresent",
            seeds: [("cb-session", { $0.source = "codebuddy"; $0.addRecentMessage(ChatMessage(isUser: true, text: "do the thing")) })],
            events: [hook("Stop", "cb-session", ["_source": "codebuddy", "message": "Task finished"])]
        ),
        CoreReducerCase(
            name: "lifecycle/stop-placeholder-skipped-after-reply",
            origin: "ReplyCompletePlaceholderTests.testPlaceholderIsSkippedWhenLastAssistantMessageAlreadySet",
            seeds: [("cb-session", {
                $0.source = "codebuddy"
                $0.lastAssistantMessage = "previous reply"
                $0.addRecentMessage(ChatMessage(isUser: true, text: "follow-up"))
            })],
            events: [hook("Stop", "cb-session", ["_source": "codebuddy"])]
        ),
        CoreReducerCase(
            name: "lifecycle/task-complete-placeholder-injected",
            origin: "ReplyCompletePlaceholderTests.testTaskRoundCompleteUsesInjectedPlaceholderWhenNoMessageContent",
            replyCompletePlaceholder: "답변 완료",
            seeds: [("cline-session", { $0.source = "cline"; $0.addRecentMessage(ChatMessage(isUser: true, text: "do the thing")) })],
            events: [hook("TaskComplete", "cline-session", ["_source": "cline"])]
        ),
        CoreReducerCase(
            name: "lifecycle/process-id-out-of-range",
            origin: "SubsessionReducerTests.testProcessIdOutsidePidRangeIsIgnored",
            events: [
                hook("SessionStart", "parent-thread", ["_source": "codex", "_ppid": 9_999_999_999]),
                hook("PreToolUse", "parent-thread", ["_source": "codex", "_ppid": 9_999_999_999]),
                hook("PreToolUse", "parent-thread", ["_source": "claude", "agent_id": "child-thread", "_ppid": 9_999_999_999]),
                hook("PreToolUse", "parent-thread", ["_source": "codex", "_ppid": 4242]),
            ]
        ),
        CoreReducerCase(
            name: "lifecycle/kimi-content-part-prompt",
            origin: "bridge golden kimi-user-prompt",
            events: [bridge("kimi-user-prompt")]
        ),
    ]

    // MARK: - Tool steps

    static func step(_ name: String, tool: String, id: String?, command: String, agent: String? = nil) -> [String: Any] {
        var json: [String: Any] = ["hook_event_name": name, "session_id": "s1", "tool_name": tool, "tool_input": ["command": command]]
        json["tool_use_id"] = id
        json["agent_id"] = agent
        return json
    }

    static let tools: [CoreReducerCase] = [
        CoreReducerCase(
            name: "tools/failed-tool-keeps-turn",
            origin: "TurnFailureSoundTests.testReducerDoesNotRingForAFailedTool",
            events: [hook("PreToolUse", "s1", ["tool_name": "Bash"]), hook("PostToolUseFailure", "s1", ["tool_name": "Bash"])]
        ),
        CoreReducerCase(
            name: "tools/overtaken-post-keeps-running-tool",
            origin: "OutOfOrderToolStepTests.testAnOvertakenPostLeavesTheRunningToolUp",
            events: [
                step("PreToolUse", tool: "Bash", id: "a", command: "make"),
                step("PreToolUse", tool: "Bash", id: "b", command: "make test"),
                step("PostToolUse", tool: "Bash", id: "a", command: "make"),
                step("PostToolUse", tool: "Bash", id: "b", command: "make test"),
            ]
        ),
        CoreReducerCase(
            name: "tools/overtaken-failure-keeps-running-tool",
            origin: "OutOfOrderToolStepTests.testAnOvertakenFailureLeavesTheRunningToolUp",
            events: [
                step("PreToolUse", tool: "Bash", id: "a", command: "make"),
                step("PreToolUse", tool: "Read", id: "b", command: "cat"),
                step("PostToolUseFailure", tool: "Bash", id: "a", command: "make"),
            ]
        ),
        CoreReducerCase(
            name: "tools/steps-without-ids",
            origin: "OutOfOrderToolStepTests.testStepsWithoutIdsGoAsBefore",
            events: [
                step("PreToolUse", tool: "Bash", id: nil, command: "make"),
                step("PreToolUse", tool: "Read", id: nil, command: "cat"),
                step("PostToolUse", tool: "Bash", id: nil, command: "make"),
            ]
        ),
        CoreReducerCase(
            name: "tools/step-naming-no-tool-use",
            origin: "OutOfOrderToolStepTests.testAStepNamingNoToolUseFinishesTheRunningOne",
            events: [
                step("PreToolUse", tool: "Bash", id: "a", command: "make"),
                step("PostToolUse", tool: "Bash", id: nil, command: "make"),
            ]
        ),
        CoreReducerCase(
            name: "tools/subagent-start-forgets-tool-use",
            origin: "OutOfOrderToolStepTests.testAnotherChangeOfTheRunningToolForgetsItsToolUse",
            events: [
                step("PreToolUse", tool: "Bash", id: "a", command: "make"),
                hook("SubagentStart", "s1", ["agent_type": "Explore"]),
            ]
        ),
        CoreReducerCase(
            name: "tools/overtaken-subagent-post",
            origin: "OutOfOrderToolStepTests.testAnOvertakenSubagentPostLeavesItsRunningToolUp",
            events: [
                step("PreToolUse", tool: "Bash", id: "a", command: "make", agent: "sub-1"),
                step("PreToolUse", tool: "Bash", id: "b", command: "make test", agent: "sub-1"),
                step("PostToolUse", tool: "Bash", id: "a", command: "make", agent: "sub-1"),
                step("PostToolUseFailure", tool: "Bash", id: "a", command: "make", agent: "sub-1"),
                step("PostToolUse", tool: "Bash", id: "b", command: "make test", agent: "sub-1"),
            ]
        ),
        CoreReducerCase(
            name: "tools/claude-in-tmux",
            origin: "bridge golden claude-in-tmux-pretooluse",
            events: [bridge("claude-in-tmux-pretooluse")]
        ),
        CoreReducerCase(
            name: "tools/codex-cli-model-and-transcript",
            origin: "bridge golden codex-cli-pretooluse",
            events: [bridge("codex-cli-pretooluse")]
        ),
        CoreReducerCase(
            name: "tools/cline-steps",
            origin: "bridge golden cline-pretooluse, cline-posttooluse",
            events: [bridge("cline-pretooluse"), bridge("cline-posttooluse")]
        ),
    ]

    // MARK: - Permission and question waits

    static let waits: [CoreReducerCase] = [
        CoreReducerCase(
            name: "waits/notification-question",
            origin: "bridge golden claude-notification-question",
            events: [bridge("claude-notification-question")]
        ),
        CoreReducerCase(
            name: "waits/notification-idle-prompt",
            origin: "bridge golden claude-notification-plain",
            events: [bridge("claude-notification-plain")]
        ),
        CoreReducerCase(
            name: "waits/notification-non-string-question",
            origin: "bridge golden claude-notification-non-string-question",
            events: [bridge("claude-notification-non-string-question")]
        ),
        CoreReducerCase(
            name: "waits/permission-request",
            origin: "bridge golden claude-permission-deny, codebuddy-permission",
            events: [bridge("claude-permission-deny"), bridge("codebuddy-permission")]
        ),
        CoreReducerCase(
            name: "waits/permission-prompt-notification-holds-until-tool-ends",
            origin: "reduceHookEvent Notification permission_prompt (#290)",
            events: [
                hook("PreToolUse", "cb-1", ["_source": "codebuddy", "tool_name": "Bash", "tool_input": ["command": "make"]]),
                hook("Notification", "cb-1", [
                    "_source": "codebuddy", "notification_type": "permission_prompt",
                    "message": "CodeBuddy needs your permission to use Bash",
                ]),
                hook("PreToolUse", "cb-1", ["_source": "codebuddy", "tool_name": "Read"]),
                hook("PostToolUse", "cb-1", ["_source": "codebuddy", "tool_name": "Bash"]),
            ]
        ),
        CoreReducerCase(
            name: "waits/cursor-merged-question",
            origin: "CursorSessionFoldingTests.testMergedCursorNotificationWithQuestionSetsWaitingQuestion",
            seeds: [(cursorParent, {
                $0.source = "cursor"
                $0.status = .running
                $0.subagents[cursorChild] = SubagentState(agentId: cursorChild, agentType: "cursor-subagent")
            })],
            events: [hook("Notification", cursorParent, [
                "_source": "cursor", "agent_id": cursorChild, "agent_type": "cursor-subagent",
                "question": "Which approach should we take?", "options": ["A", "B"],
            ])]
        ),
    ]

    // MARK: - Subagents and Agent Sub-Sessions

    static let parent = "parent-thread"
    static let child = "child-thread"

    /// A child's hook as the router hands it over in Show separately.
    static func linked(_ event: String, source: String, _ extra: [String: Any] = [:]) -> [String: Any] {
        hook(event, child, ["_source": source, SubsessionRouter.linkedParentKey: parent].merging(extra) { _, new in new })
    }

    /// A child's hook as the router hands it over in Merge.
    static func folded(_ event: String, kind: SubsessionLink.Kind, _ extra: [String: Any] = [:]) -> [String: Any] {
        var raw = hook(event, child, ["_source": kind == .cursorTask ? "cursor" : "codex"].merging(extra) { _, new in new })
        SubsessionRouter.fold(&raw, link: SubsessionLink(kind: kind, childCardId: child, agentId: child, parentCardId: parent), into: parent)
        return raw
    }

    static let subagents: [CoreReducerCase] = ["codex", "cursor", "opencode", "pi"].map { source in
        CoreReducerCase(
            name: "subagents/linked-child-stays-quiet-\(source)",
            origin: "SubsessionReducerTests.testLinkedChildOfEveryKindStaysQuiet",
            events: [
                linked("SessionStart", source: source),
                linked("UserPromptSubmit", source: source, ["prompt": "task"]),
                linked("PreToolUse", source: source, ["tool_name": "Bash"]),
                linked("Stop", source: source, ["last_assistant_message": "done"]),
            ]
        )
    } + [SubsessionLink.Kind.codexThread, .cursorTask, .declared].map { kind in
        CoreReducerCase(
            name: "subagents/folded-child-reopens-\(kind.rawValue)",
            origin: "SubsessionReducerTests.testFoldedChildOfEveryKindReopensForItsNextTurn",
            seeds: [(parent, { _ in })],
            events: [
                folded("UserPromptSubmit", kind: kind, ["prompt": "task"]),
                folded("Stop", kind: kind),
                folded("PostToolUse", kind: kind),
                folded("UserPromptSubmit", kind: kind, ["prompt": "follow-up"]),
                folded("PreToolUse", kind: kind, ["tool_name": "Edit"]),
            ]
        )
    } + [
        CoreReducerCase(
            name: "subagents/link-survives-session-start",
            origin: "SubsessionReducerTests.testLinkSurvivesTheSessionStartRebuild",
            events: [
                linked("UserPromptSubmit", source: "codex", ["prompt": "task"]),
                linked("SessionStart", source: "codex"),
                hook("PreToolUse", child, ["_source": "codex"]),
                hook("SessionStart", child, ["_source": "codex"]),
                linked("SessionStart", source: "codex", [SubsessionRouter.linkedParentKey: "other-parent"]),
                hook("SessionStart", parent, ["_source": "codex"]),
            ]
        ),
        CoreReducerCase(
            name: "subagents/child-naming-itself-as-agent-is-linked",
            origin: "SubsessionReducerTests.testChildWhoseHooksNameItselfAsAgentIsStillLinked",
            events: [linked("PreToolUse", source: "codex", ["agent_id": child, "tool_name": "exec_command"])]
        ),
        CoreReducerCase(
            name: "subagents/folded-row-marked-own-subagent-not",
            origin: "SubsessionReducerTests.testFoldedChildRowIsMarkedAndAnAgentsOwnSubagentIsNot",
            seeds: [(parent, source("codex"))],
            events: [
                folded("PreToolUse", kind: .codexThread, ["tool_name": "exec_command"]),
                hook("SubagentStart", parent, ["_source": "codex", "agent_id": "own-agent", "agent_type": "worker"]),
            ]
        ),
        CoreReducerCase(
            name: "subagents/stop-while-subagent-works",
            origin: "HookEventFactsTests.testAStopWithASubagentStillWorkingEndsNoTurn",
            events: [hook("SubagentStart", "p", ["agent_id": "a1"]), hook("Stop", "p")]
        ),
        CoreReducerCase(
            name: "subagents/filed-under-subagent-then-session-end",
            origin: "HookEventFactsTests.testEventsThatDoNotMoveTheSessionItself",
            events: [hook("PreToolUse", "p", ["agent_id": "a1", "tool_name": "Read"]), hook("SessionEnd", "p")]
        ),
        CoreReducerCase(
            name: "subagents/subagent-turn-end-reported",
            origin: "HookEventFactsTests.testASubagentsTurnEndIsReportedAsSuch",
            events: [
                hook("Stop", cursorChild, ["_source": "cursor", "transcript_path": cursorTranscript]),
                hook("Stop", "main-thread", ["_source": "codex"]),
            ]
        ),
    ]

    // MARK: - Cursor folding

    static let cursorParent = "e1247fd5-d9a0-48ef-8457-0304606b1833"
    static let cursorChild = "2528cb91-6379-48f2-aff8-40f4b804dafa"
    static let cursorTranscript = "/Users/u/.cursor/projects/x/agent-transcripts/\(cursorParent)/\(cursorParent).jsonl"
    static let fixedStart = Date(timeIntervalSince1970: 1_700_000_000)

    static func cursorEvent(_ name: String, _ session: String = cursorParent, _ extra: [String: Any] = [:]) -> [String: Any] {
        hook(name, session, ["_source": "cursor"].merging(extra) { _, new in new })
    }

    static func cursorTaskRow(_ s: inout SessionSnapshot, running: Bool = false) {
        var sub = SubagentState(agentId: cursorChild, agentType: "cursor-subagent")
        if running { sub.status = .running }
        s.subagents[cursorChild] = sub
    }

    static let cursor: [CoreReducerCase] = [
        CoreReducerCase(
            name: "cursor/merged-task-response-updates-parent-chat",
            origin: "CursorSessionFoldingTests.testMergedCursorSubagentAfterAgentResponseUpdatesParentChatWithoutCompleting",
            maxHistory: 10,
            seeds: [(cursorParent, {
                $0.source = "cursor"; $0.status = .running
                $0.lastUserPrompt = "main prompt"; $0.lastAssistantMessage = "parent reply"
                cursorTaskRow(&$0)
            })],
            events: [cursorEvent("afterAgentResponse", cursorParent, [
                "agent_id": cursorChild, "agent_type": "cursor-subagent", "text": "child-only reply",
            ])]
        ),
        CoreReducerCase(
            name: "cursor/merged-task-prompt-updates-parent-chat",
            origin: "CursorSessionFoldingTests.testMergedCursorUserPromptSubmitUpdatesParentChat",
            maxHistory: 10,
            seeds: [(cursorParent, {
                $0.source = "cursor"; $0.status = .running; $0.lastUserPrompt = "old prompt"
                $0.addRecentMessage(ChatMessage(isUser: true, text: "old prompt"))
                cursorTaskRow(&$0)
            })],
            events: [cursorEvent("beforeSubmitPrompt", cursorParent, [
                "agent_id": cursorChild, SubsessionRouter.foldedKey: "cursor", "prompt": "continue after the root cause",
            ])]
        ),
        CoreReducerCase(
            name: "cursor/codex-subagent-prompt-leaves-parent-chat",
            origin: "CursorSessionFoldingTests.testCodexSubagentUserPromptSubmitDoesNotOverwriteParentChat",
            maxHistory: 10,
            seeds: [(parent, {
                $0.source = "codex"; $0.status = .running; $0.lastUserPrompt = "parent prompt"
                $0.addRecentMessage(ChatMessage(isUser: true, text: "parent prompt"))
                $0.subagents[child] = SubagentState(agentId: child, agentType: "worker")
            })],
            events: [hook("UserPromptSubmit", parent, [
                "_source": "codex", "agent_id": child, "prompt": "child-only prompt must not replace parent",
            ])]
        ),
        CoreReducerCase(
            name: "cursor/codex-subagent-response-leaves-parent-chat",
            origin: "CursorSessionFoldingTests.testCodexSubagentAfterAgentResponseDoesNotOverwriteParentChat",
            maxHistory: 10,
            seeds: [(parent, {
                $0.source = "codex"; $0.status = .running; $0.lastAssistantMessage = "parent reply"
                $0.addRecentMessage(ChatMessage(isUser: false, text: "parent reply"))
                $0.subagents[child] = SubagentState(agentId: child, agentType: "worker")
            })],
            events: [hook("AfterAgentResponse", parent, [
                "_source": "codex", "agent_id": child, "text": "child-only reply must not replace parent",
            ])]
        ),
        CoreReducerCase(
            name: "cursor/task-stop-tombstones-until-restart",
            origin: "CursorSessionFoldingTests.testSubagentStopRecordsClosedTombstoneAndClearsOnRestart",
            maxHistory: 10,
            seeds: [(cursorParent, { $0.source = "cursor"; $0.status = .running; cursorTaskRow(&$0) })],
            events: [
                cursorEvent("stop", cursorParent, ["agent_id": cursorChild, "agent_type": "cursor-subagent"]),
                cursorEvent("SubagentStart", cursorParent, ["agent_id": cursorChild, "agent_type": "cursor-subagent"]),
            ]
        ),
        CoreReducerCase(
            name: "cursor/late-response-keeps-tombstone",
            origin: "CursorSessionFoldingTests.testLateAfterAgentResponseDoesNotClearStopTombstone",
            maxHistory: 10,
            seeds: [(cursorParent, { $0.source = "cursor"; $0.status = .processing; $0.recordClosedSubagentId(cursorChild) })],
            events: [cursorEvent("afterAgentResponse", cursorParent, [
                "agent_id": cursorChild, "agent_type": "cursor-subagent", "text": "late child reply",
            ])]
        ),
        CoreReducerCase(
            name: "cursor/separate-task-stop-self-tombstones",
            origin: "CursorSessionFoldingTests.testSeparateCursorStopSelfTombstonesSessionId",
            maxHistory: 10,
            seeds: [(cursorChild, {
                $0.source = "cursor"; $0.status = .running; $0.transcriptPath = cursorTranscript
                $0.cliPid = 12_345; $0.cliStartTime = fixedStart
            })],
            events: [cursorEvent("stop", cursorChild)]
        ),
        CoreReducerCase(
            name: "cursor/parent-stop-keeps-pid",
            origin: "CursorSessionFoldingTests.testParentCursorStopDoesNotSelfTombstoneOrClearCliPid",
            maxHistory: 10,
            seeds: [(cursorParent, {
                $0.source = "cursor"; $0.status = .running; $0.transcriptPath = cursorTranscript
                $0.cliPid = 98_765; $0.cliStartTime = fixedStart
            })],
            events: [cursorEvent("stop")]
        ),
        CoreReducerCase(
            name: "cursor/parent-response-while-task-runs",
            origin: "CursorSessionFoldingTests.testParentAfterAgentResponseKeepsActiveWhileFoldedTaskRunning",
            maxHistory: 10,
            seeds: [(cursorParent, {
                $0.source = "cursor"; $0.status = .running; $0.currentTool = "Agent"; $0.toolDescription = "cursor-subagent"
                cursorTaskRow(&$0, running: true)
            })],
            events: [cursorEvent("afterAgentResponse", cursorParent, ["text": "parent turn done; task still working"])]
        ),
        CoreReducerCase(
            name: "cursor/prompt-clears-self-tombstone",
            origin: "CursorSessionFoldingTests.testUserPromptSubmitClearsCursorSelfTombstone",
            maxHistory: 10,
            seeds: [(cursorChild, { $0.source = "cursor"; $0.recordClosedSubagentId(cursorChild) })],
            events: [cursorEvent("beforeSubmitPrompt", cursorChild, ["prompt": "retry"])]
        ),
        CoreReducerCase(
            name: "cursor/parent-stop-while-task-runs",
            origin: "CursorSessionFoldingTests.testParentStopKeepsActiveWhileFoldedTaskRunning",
            maxHistory: 10,
            seeds: [(cursorParent, {
                $0.source = "cursor"; $0.status = .running; $0.currentTool = "Agent"
                cursorTaskRow(&$0, running: true)
            })],
            events: [cursorEvent("stop", cursorParent, ["stop_reason": "user", "last_assistant_message": "main turn ended"])]
        ),
        CoreReducerCase(
            name: "cursor/merge-first-task-hook-fills-parent",
            origin: "CursorSessionFoldingTests.testMergeFirstTaskHookFillsParentSourceAndTranscript",
            maxHistory: 10,
            events: [cursorEvent("beforeReadFile", cursorParent, [
                "agent_id": cursorChild, "agent_type": "cursor-subagent", SubsessionRouter.foldedKey: "cursor",
                "transcript_path": cursorTranscript, "_ppid": 42_424, "tool_name": "Read",
            ])]
        ),
        CoreReducerCase(
            name: "cursor/merge-first-task-hook-keeps-known-parent",
            origin: "CursorSessionFoldingTests.testMergeFirstTaskHookDoesNotOverwriteKnownParentSource",
            maxHistory: 10,
            seeds: [(cursorParent, {
                $0.source = "cursor"; $0.cwd = "/tmp/known"; $0.transcriptPath = "/known.jsonl"; $0.cliPid = 7
            })],
            events: [hook("beforeReadFile", cursorParent, [
                "_source": "cursor-cli", "agent_id": cursorChild, "cwd": "/tmp/child-only",
                "transcript_path": "/child.jsonl", "_ppid": 99, "tool_name": "Read",
            ])]
        ),
        CoreReducerCase(
            name: "cursor/prompt-clears-merged-tombstone",
            origin: "CursorSessionFoldingTests.testCursorUserPromptSubmitClearsMergedTombstoneAndReopens",
            maxHistory: 10,
            seeds: [(cursorParent, { $0.source = "cursor"; $0.status = .processing; $0.recordClosedSubagentId(cursorChild) })],
            events: [cursorEvent("beforeSubmitPrompt", cursorParent, [
                "agent_id": cursorChild, "agent_type": "cursor-subagent", SubsessionRouter.foldedKey: "cursor",
                "prompt": "retry the task",
            ])]
        ),
        CoreReducerCase(
            name: "cursor/late-tool-blocked-by-tombstone",
            origin: "CursorSessionFoldingTests.testLatePreToolUseStillBlockedByClosedTombstone",
            maxHistory: 10,
            seeds: [(cursorParent, { $0.source = "cursor"; $0.status = .processing; $0.recordClosedSubagentId(cursorChild) })],
            events: [cursorEvent("beforeReadFile", cursorParent, ["agent_id": cursorChild, "tool_name": "Read"])]
        ),
        CoreReducerCase(
            name: "cursor/prompt-and-final-response",
            origin: "HookEventFactsTests.testReducerNeverEmitsAttentionEffects",
            events: [
                cursorEvent("beforeSubmitPrompt", "cursor", ["prompt": "hi"]),
                cursorEvent("afterAgentResponse", "cursor", ["text": "hello"]),
            ]
        ),
        CoreReducerCase(
            name: "cursor/ide-turn-from-the-bridge",
            origin: "bridge golden cursor-native-before-shell, cursor-imported-claude-permission-never-held, cursor-imported-claude-stop",
            events: [
                bridge("cursor-native-before-shell"),
                bridge("cursor-imported-claude-permission-never-held"),
                bridge("cursor-imported-claude-stop"),
            ]
        ),
        CoreReducerCase(
            name: "cursor/cli-turn-from-the-bridge",
            origin: "bridge golden cursor-agent-imported-claude, cursor-agent-hooks-json",
            events: [bridge("cursor-agent-imported-claude"), bridge("cursor-agent-hooks-json")]
        ),
        CoreReducerCase(
            name: "cursor/without-version",
            origin: "bridge golden cursor-without-version",
            events: [bridge("cursor-without-version")]
        ),
    ]

    // MARK: - Sources

    static let sources: [CoreReducerCase] = [
        CoreReducerCase(
            name: "sources/custom-source-configured",
            origin: "bridge golden custom-source-fallback-session",
            customSources: ["mycli"],
            events: [bridge("custom-source-fallback-session")]
        ),
        CoreReducerCase(
            name: "sources/custom-source-not-configured",
            origin: "bridge golden custom-source-fallback-session",
            events: [bridge("custom-source-fallback-session")]
        ),
        CoreReducerCase(
            name: "sources/alias-normalized",
            origin: "bridge golden plugin-source-alias-normalized",
            events: [bridge("plugin-source-alias-normalized")]
        ),
        CoreReducerCase(
            name: "sources/qoder-ide-stop",
            origin: "bridge golden qoder-ide-stop",
            events: [bridge("qoder-ide-stop")]
        ),
        CoreReducerCase(
            name: "sources/cline-round-latches",
            origin: "HookEventFactsTests.testReducerNeverEmitsAttentionEffects",
            events: [
                hook("TaskStart", "cline", ["_source": "cline"]),
                hook("TaskComplete", "cline", ["_source": "cline"]),
                hook("PreToolUse", "cline", ["_source": "cline", "tool_name": "x"]),
            ]
        ),
        CoreReducerCase(
            name: "sources/cline-task-start",
            origin: "bridge golden cline-task-start",
            events: [bridge("cline-task-start")]
        ),
        CoreReducerCase(
            name: "sources/codex-interrupt-latches",
            origin: "HookEventFactsTests.testReducerNeverEmitsAttentionEffects",
            events: [
                hook("UserPromptSubmit", "codex", ["_source": "codex", "prompt": "go"]),
                hook("Interrupt", "codex", ["_source": "codex"]),
                hook("PostToolUse", "codex", ["_source": "codex", "tool_name": "shell"]),
            ]
        ),
        CoreReducerCase(
            name: "sources/codex-desktop-card-id",
            origin: "bridge golden codex-desktop-app-server",
            events: [bridge("codex-desktop-app-server")]
        ),
        CoreReducerCase(
            name: "sources/claude-desktop-code-tab",
            origin: "bridge golden claude-desktop-code-tab",
            events: [bridge("claude-desktop-code-tab")]
        ),
        CoreReducerCase(
            name: "sources/hermes-one-shot-run-ends-card",
            origin: "HookEventFactsTests.testEventsThatDoNotMoveTheSessionItself",
            events: [hook("on_session_end", "hermes-child", [
                "_source": "hermes", "extra": ["platform": "subagent", "completed": true],
            ])]
        ),
        CoreReducerCase(
            name: "sources/hermes-held-elsewhere",
            origin: "HookEventFactsTests.testAConversationHeldElsewhereIsReported",
            events: [
                hook("on_session_end", "gw", ["_source": "hermes", "extra": ["platform": "telegram", "completed": true]]),
                hook("on_session_end", "local", ["_source": "hermes", "extra": ["platform": "cli", "completed": true]]),
            ]
        ),
    ]

    // MARK: - Terminal metadata and remote hosts

    static let remoteHook: [String: Any] = [
        "cwd": "/home/me/project", "_source": "codex", "_ppid": 4242,
        "_remote_host_id": "devbox", "_remote_host_name": "Dev Box",
    ]

    static let terminal: [CoreReducerCase] = [
        CoreReducerCase(
            name: "terminal/every-key",
            origin: "bridge golden terminal-env-everything",
            events: [bridge("terminal-env-everything")]
        ),
        CoreReducerCase(
            name: "terminal/partial",
            origin: "bridge golden terminal-env-partial",
            events: [bridge("terminal-env-partial")]
        ),
        CoreReducerCase(
            name: "terminal/zellij-on-session-start",
            origin: "MultiplexerEnvCaptureTests.testSessionStartCapturesZellijPaneAndSessionName",
            maxHistory: 100,
            events: [hook("SessionStart", "sess-1", ["_zellij": "0.40.0", "_zellij_pane_id": "12", "_zellij_session_name": "main"])]
        ),
        CoreReducerCase(
            name: "terminal/zellij-on-later-event",
            origin: "MultiplexerEnvCaptureTests.testNonSessionStartEventStillCapturesZellijFields",
            maxHistory: 100,
            seeds: [("sess-2", { _ in })],
            events: [hook("PostToolUse", "sess-2", ["_zellij_pane_id": "7", "_zellij_session_name": "work"])]
        ),
        CoreReducerCase(
            name: "terminal/superset-from-env-object",
            origin: "MultiplexerEnvCaptureTests.testSupersetCapturedFromEnvSubObject",
            maxHistory: 100,
            events: [hook("SessionStart", "sess-superset-env", [
                "_env": ["SUPERSET_WORKSPACE_ID": "ws-env", "SUPERSET_TERMINAL_ID": "term-7"],
            ])]
        ),
        CoreReducerCase(
            name: "terminal/herdr-on-session-start",
            origin: "MultiplexerEnvCaptureTests.testSessionStartCapturesCompleteHerdrRoute",
            maxHistory: 100,
            events: [hook("SessionStart", "sess-herdr", [
                "_term_bundle": "com.mitchellh.ghostty", "_herdr_pane_id": "w2:p1",
                "_herdr_socket_path": "/tmp/herdr.sock", "_herdr_bin_path": "/opt/homebrew/bin/herdr",
            ])]
        ),
        CoreReducerCase(
            name: "terminal/remote-session-start-keeps-pid-apart",
            origin: "RemoteHookLocalFieldsTests.testRemoteHookNeverSetsCliPid",
            maxHistory: 10,
            events: [hook("SessionStart", "s1", remoteHook)]
        ),
        CoreReducerCase(
            name: "terminal/remote-subagent-hook-creates-remote-card",
            origin: "RemoteHookLocalFieldsTests.testCardCreatedByARemoteSubagentHookIsRemote",
            maxHistory: 10,
            events: [hook("PreToolUse", "s1", remoteHook.merging([
                "agent_id": "sub-1", "agent_type": "worker", "tool_name": "Bash",
            ]) { _, new in new })]
        ),
        CoreReducerCase(
            name: "terminal/local-hook-sets-cli-pid",
            origin: "RemoteHookLocalFieldsTests.testLocalHookStillSetsCliPid",
            maxHistory: 10,
            events: [hook("PreToolUse", "s1", ["cwd": "/home/me/project", "_source": "codex", "_ppid": 4242, "tool_name": "Bash"])]
        ),
    ]
}
