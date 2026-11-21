import Foundation
@testable import MorrowCore

/// Exports ``CoreContractCases`` into `fixtures/core/reducer.json` and
/// `fixtures/core/attention.json`: the core contract a port must reproduce,
/// `reduce(sessions, event) -> (sessions', effects, facts)` and
/// `attention(moment, subject) -> intents`.
///
/// Every case is run through the Swift code at export (and again by
/// ``CoreContractTests``), so the files record what Swift does, not what a
/// test expects. Two inputs are pinned to keep the output reproducible
/// without touching `Sources/`:
/// - The clock. A date the reducer stamped while applying step k is written
///   `$Tk`; one stamped while the case built its initial sessions, `$T0`; a
///   fixed date a case seeded, ISO 8601. A date from the wall clock outside
///   those windows fails the export.
/// - The configuration. A case's `custom_sources` are written to the
///   `custom_cli_configs_v1` default for its run, and the custom agent
///   commands are pinned to none.
enum CoreContractJSONExporter {
    static let reducerFilename = "reducer.json"
    static let attentionFilename = "attention.json"

    /// `SessionSnapshot` state the projection leaves out: set outside the
    /// reducer (git, harness, transcript tailing, AppState), identities
    /// generated per value (`ChatMessage.id`, `ToolHistoryEntry.id`), and
    /// `AgentTaskList`'s transient bookkeeping.
    static let projectionOmits = [
        "aiworkClientType", "alwaysAllowedTools", "configuredLongContext", "cursorPendingQuestion",
        "gitBranch", "gitIsWorktree", "hostHarness", "isYoloMode", "reasoningEffort", "recap",
        "sessionTitleSource", "recentMessages[].id", "toolHistory[].id", "agentTasks (bookkeeping)",
    ]

    // MARK: - Running a case

    /// When each step ran, for turning dates back into `$Tk`.
    struct Clock {
        private(set) var windows: [ClosedRange<Date>] = []
        private var start: Date?

        mutating func begin() {
            // Strictly after the last window, so no date can sit in two.
            if let last = windows.last?.upperBound {
                while Date() <= last {}
            }
            start = Date()
        }

        mutating func end() {
            windows.append(start!...Date())
        }

        func token(_ date: Date) throws -> String {
            if let index = windows.firstIndex(where: { $0.contains(date) }) {
                return "$T\(index)"
            }
            guard abs(date.timeIntervalSinceNow) > 86_400 else {
                throw CoreContractError("a wall-clock date outside every step: \(date)")
            }
            return ISO8601DateFormatter().string(from: date)
        }
    }

    static func reducerCaseDocument(_ c: CoreReducerCase) throws -> [String: Any] {
        try withConfiguration(customSources: c.customSources) {
            var clock = Clock()
            clock.begin()
            var sessions: [String: SessionSnapshot] = [:]
            for (id, seed) in c.seeds {
                var session = SessionSnapshot()
                seed(&session)
                sessions[id] = session
            }
            clock.end()
            let initial = try project(sessions, clock: clock)

            var steps: [[String: Any]] = []
            for payload in c.events {
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
                guard let event = HookEvent(from: data) else {
                    throw CoreContractError("\(c.name): not a hook event: \(payload)")
                }
                clock.begin()
                let reduction = reduceHookEvent(
                    sessions: &sessions,
                    event: event,
                    maxHistory: c.maxHistory,
                    replyCompletePlaceholder: c.replyCompletePlaceholder
                )
                clock.end()
                let subject = AttentionSubject(sessions[event.sessionId ?? "default"])
                let intents = AttentionPolicy.intents(for: .hookEvent(reduction.facts), subject: subject)
                steps.append([
                    "event": try JSONSerialization.jsonObject(with: data),
                    "sessions": try project(sessions, clock: clock),
                    "effects": reduction.effects.map(effectDocument),
                    "facts": factsDocument(reduction.facts),
                    "subject": subjectDocument(subject),
                    "intents": intentsDocument(intents),
                ])
            }
            return [
                "name": c.name,
                "origin": c.origin,
                "max_history": c.maxHistory,
                "reply_complete_placeholder": c.replyCompletePlaceholder,
                "custom_sources": c.customSources,
                "sessions": initial,
                "steps": steps,
            ]
        }
    }

    /// Runs `body` with `customSources` as the user's custom CLIs and no
    /// custom agent commands, then puts both settings back.
    private static func withConfiguration<T>(customSources: [String], _ body: () throws -> T) throws -> T {
        let defaults = UserDefaults.standard
        let keys = [SessionSnapshot.customCLIConfigsKey, CustomAgentCommandStore.preferenceKey]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(
            try JSONSerialization.data(withJSONObject: customSources.map { ["source": $0] }),
            forKey: SessionSnapshot.customCLIConfigsKey
        )
        // An empty list makes the store seed commands from ~/.claude-* dirs
        // on this machine; one disabled command means none.
        CustomAgentCommandStore.saveCommands([
            CustomAgentCommand(command: "core-contract-none", displayName: "", isEnabled: false),
        ])
        return try body()
    }

    // MARK: - Projection

    static func project(_ sessions: [String: SessionSnapshot], clock: Clock) throws -> [String: Any] {
        try sessions.mapValues { try sessionDocument($0, clock: clock) }
    }

    /// A session as the contract sees it. `status`, `source`, `start_time`
    /// and `last_activity` are always present; any other field is left out
    /// while it is nil, false, zero or empty.
    static func sessionDocument(_ s: SessionSnapshot, clock: Clock) throws -> [String: Any] {
        var doc: [String: Any] = [
            "status": statusName(s.status),
            "source": s.source,
            "start_time": try clock.token(s.startTime),
            "last_activity": try clock.token(s.lastActivity),
        ]
        let strings: [(String, String?)] = [
            ("current_tool", s.currentTool), ("current_tool_use_id", s.currentToolUseId),
            ("tool_description", s.toolDescription), ("cwd", s.cwd), ("model", s.model),
            ("permission_mode", s.permissionMode), ("transcript_path", s.transcriptPath),
            ("last_user_prompt", s.lastUserPrompt), ("last_assistant_message", s.lastAssistantMessage),
            ("live_codex_output", s.liveCodexOutput), ("session_title", s.sessionTitle),
            ("provider_session_id", s.providerSessionId), ("parent_session_id", s.parentSessionId),
            ("remote_host_id", s.remoteHostId), ("remote_host_name", s.remoteHostName),
            ("term_app", s.termApp), ("iterm_session_id", s.itermSessionId), ("tty_path", s.ttyPath),
            ("kitty_window_id", s.kittyWindowId), ("tmux_pane", s.tmuxPane),
            ("tmux_client_tty", s.tmuxClientTty), ("tmux_env", s.tmuxEnv), ("term_bundle_id", s.termBundleId),
            ("cmux_surface_id", s.cmuxSurfaceId), ("cmux_workspace_id", s.cmuxWorkspaceId),
            ("zellij_pane_id", s.zellijPaneId), ("zellij_session_name", s.zellijSessionName),
            ("wezterm_pane_id", s.weztermPaneId), ("herdr_pane_id", s.herdrPaneId),
            ("herdr_socket_path", s.herdrSocketPath), ("herdr_binary_path", s.herdrBinaryPath),
            ("superset_workspace_id", s.supersetWorkspaceId), ("superset_pane_id", s.supersetPaneId),
            ("orca_terminal_handle", s.orcaTerminalHandle), ("orca_worktree_id", s.orcaWorktreeId),
            ("claude_desktop_session_id", s.claudeDesktopSessionId),
        ]
        for (key, value) in strings { doc[key] = value }
        let flags: [(String, Bool)] = [
            ("interrupted", s.interrupted), ("last_turn_failed", s.lastTurnFailed),
            ("task_round_ended", s.taskRoundEnded), ("hermes_hooks_report_prompts", s.hermesHooksReportPrompts),
            ("hermes_hooks_report_replies", s.hermesHooksReportReplies), ("hermes_chat_elsewhere", s.hermesChatElsewhere),
        ]
        for (key, value) in flags where value { doc[key] = true }
        doc["cli_pid"] = s.cliPid.map { Int($0) }
        doc["remote_pid"] = s.remotePid.map { Int($0) }
        doc["cli_start_time"] = try s.cliStartTime.map(clock.token)
        doc["model_reported_at"] = try s.modelReportedAt.map(clock.token)
        if s.totalToolCallCount != 0 { doc["total_tool_call_count"] = s.totalToolCallCount }
        if !s.recentMessages.isEmpty {
            doc["recent_messages"] = s.recentMessages.map { ["is_user": $0.isUser, "text": $0.text] }
        }
        if !s.toolHistory.isEmpty {
            doc["tool_history"] = try s.toolHistory.map { entry -> [String: Any] in
                var item: [String: Any] = [
                    "tool": entry.tool,
                    "success": entry.success,
                    "timestamp": try clock.token(entry.timestamp),
                ]
                item["description"] = entry.description
                item["agent_type"] = entry.agentType
                return item
            }
        }
        if !s.subagents.isEmpty {
            doc["subagents"] = try s.subagents.mapValues { sub -> [String: Any] in
                var item: [String: Any] = [
                    "agent_type": sub.agentType,
                    "status": statusName(sub.status),
                    "start_time": try clock.token(sub.startTime),
                    "last_activity": try clock.token(sub.lastActivity),
                ]
                item["current_tool"] = sub.currentTool
                item["current_tool_use_id"] = sub.currentToolUseId
                item["tool_description"] = sub.toolDescription
                item["model"] = sub.model
                item["subsession_kind"] = sub.subsessionKind?.rawValue
                return item
            }
        }
        if !s.closedSubagentIds.isEmpty { doc["closed_subagent_ids"] = s.closedSubagentIds }
        if !s.agentTasks.items.isEmpty || s.agentTasks.completedAt != nil {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            var tasks: [String: Any] = [
                "items": try JSONSerialization.jsonObject(with: encoder.encode(s.agentTasks.items)),
            ]
            tasks["completed_at"] = try s.agentTasks.completedAt.map(clock.token)
            doc["agent_tasks"] = tasks
        }
        return doc
    }

    static func statusName(_ status: AgentStatus) -> String {
        switch status {
        case .idle: return "idle"
        case .processing: return "processing"
        case .running: return "running"
        case .waitingApproval: return "waitingApproval"
        case .waitingQuestion: return "waitingQuestion"
        }
    }

    static func effectDocument(_ effect: SideEffect) -> [String: Any] {
        switch effect {
        case .playSound(let sound): return ["type": "playSound", "sound": sound]
        case .tryMonitorSession(let id): return ["type": "tryMonitorSession", "session_id": id]
        case .stopMonitor(let id): return ["type": "stopMonitor", "session_id": id]
        case .removeSession(let id): return ["type": "removeSession", "session_id": id]
        case .enqueueCompletion(let id): return ["type": "enqueueCompletion", "session_id": id]
        case .setActiveSession(let id): return ["type": "setActiveSession", "session_id": orNull(id)]
        }
    }

    static func factsDocument(_ facts: HookEventFacts) -> [String: Any] {
        [
            "raw_event_name": facts.rawEventName,
            "event_name": facts.eventName,
            "applied_to_session": facts.appliedToSession,
            "ended_turn": facts.endedTurn,
            "held_elsewhere": facts.heldElsewhere,
            "turn_error": facts.turnError.map { ["type": orNull($0.type), "detail": orNull($0.detail)] } ?? NSNull(),
            "subagent_turn": facts.subagentTurn,
        ]
    }

    static func subjectDocument(_ subject: AttentionSubject) -> [String: Any] {
        ["is_child": subject.isChild, "interrupted": subject.interrupted]
    }

    static func intentsDocument(_ intents: AttentionIntents) -> [String: Any] {
        var followUp: Any = NSNull()
        switch intents.followUp {
        case .trackCompletion(let turnFailed)?:
            followUp = ["type": "trackCompletion", "turn_failed": turnFailed]
        case .restartWait(let kind)?:
            followUp = ["type": "restartWait", "kind": kind.rawValue]
        case nil:
            break
        }
        return [
            "sound": orNull(intents.sound),
            "completion": intents.completion.map { ["turn_failed": $0.turnFailed] } ?? NSNull(),
            "push": intents.push.map { ["kind": pushKindDocument($0.kind), "smart_suppressible": $0.smartSuppressible] } ?? NSNull(),
            "follow_up": followUp,
        ]
    }

    static func pushKindDocument(_ kind: AttentionPushKind) -> [String: Any] {
        switch kind {
        case .error: return ["type": "error"]
        case .completion(let isSubagent, let interrupted):
            return ["type": "completion", "is_subagent": isSubagent, "interrupted": interrupted]
        case .approval: return ["type": "approval"]
        case .question: return ["type": "question"]
        case .displayOnlyWait: return ["type": "displayOnlyWait"]
        }
    }

    static func momentDocument(_ moment: AttentionMoment) -> [String: Any] {
        switch moment {
        case .hookEvent(let facts):
            return ["type": "hookEvent", "facts": factsDocument(facts)]
        case .approvalQueued(let first):
            return ["type": "approvalQueued", "first_of_burst": first]
        case .questionQueued(let first, let suppressible):
            return ["type": "questionQueued", "first_of_burst": first, "smart_suppressible": suppressible]
        case .requestRaisedElsewhere:
            return ["type": "requestRaisedElsewhere"]
        case .displayOnlyWaitBegan(let kind, let announce):
            return ["type": "displayOnlyWaitBegan", "kind": kind.rawValue, "announce": announce]
        case .turnStarted(let newSession):
            return ["type": "turnStarted", "new_session": newSession]
        case .turnEnded(let end, let host):
            let endName: String
            switch end {
            case .completed: endName = "completed"
            case .failed: endName = "failed"
            case .stopped: endName = "stopped"
            }
            return ["type": "turnEnded", "end": endName, "host": host == .claudeDesktop ? "claudeDesktop" : "aiwork"]
        case .reminderDue(let kind, let turnFailed):
            return ["type": "reminderDue", "kind": kind.rawValue, "turn_failed": turnFailed]
        case .appLaunched:
            return ["type": "appLaunched"]
        }
    }

    // MARK: - Bundles

    static func reducerDocument() throws -> [String: Any] {
        [
            "contract": "reducer",
            "projection_omits": projectionOmits,
            "cases": try CoreContractCases.reducer.map(reducerCaseDocument),
        ]
    }

    static func attentionDocument() -> [String: Any] {
        [
            "contract": "attention",
            "cases": CoreContractCases.attention.map { row in
                [
                    "name": row.name,
                    "moment": momentDocument(row.moment),
                    "subject": subjectDocument(row.subject),
                    "intents": intentsDocument(AttentionPolicy.intents(for: row.moment, subject: row.subject)),
                ] as [String: Any]
            },
        ]
    }

    static func documents() throws -> [(String, [String: Any])] {
        [(reducerFilename, try reducerDocument()), (attentionFilename, attentionDocument())]
    }

    static func exportAll(to fixturesRoot: URL) throws {
        let dir = fixturesRoot.appendingPathComponent("core", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (filename, document) in try documents() {
            var out = try JSONSerialization.data(
                withJSONObject: document,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            out.append(0x0A)
            try out.write(to: dir.appendingPathComponent(filename))
        }
    }
}

private func orNull(_ value: Any?) -> Any {
    value ?? NSNull()
}

struct CoreContractError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
