//! Event names in the island's terms (`EventNormalizer`,
//! `Sources/MorrowCore/EventNormalizer.swift`), verbatim.

/// The island's PascalCase name for `name`; `name` itself when it has none.
pub fn normalize(name: &str) -> &str {
    match name {
        // Cursor (camelCase)
        "beforeSubmitPrompt" => "UserPromptSubmit",
        "beforeShellExecution" => "PreToolUse",
        "afterShellExecution" => "PostToolUse",
        "beforeReadFile" => "PreToolUse",
        "afterFileEdit" => "PostToolUse",
        "beforeMCPExecution" => "PreToolUse",
        "afterMCPExecution" => "PostToolUse",
        "afterAgentThought" => "Notification",
        "afterAgentResponse" => "AfterAgentResponse",
        "stop" => "Stop",
        // Gemini
        "BeforeTool" => "PermissionRequest",
        "AfterTool" => "PostToolUse",
        "BeforeAgent" => "SubagentStart",
        "AfterAgent" => "SubagentStop",
        // GitHub Copilot CLI
        "sessionStart" => "SessionStart",
        "sessionEnd" => "SessionEnd",
        "userPromptSubmitted" => "UserPromptSubmit",
        "preToolUse" => "PreToolUse",
        "postToolUse" => "PostToolUse",
        "errorOccurred" => "Notification",
        // Kiro CLI
        "agentSpawn" => "SessionStart",
        "userPromptSubmit" => "UserPromptSubmit",
        // Traecli (snake_case)
        "session_start" => "SessionStart",
        "session_end" => "SessionEnd",
        "user_prompt_submit" => "UserPromptSubmit",
        "pre_tool_use" => "PreToolUse",
        "post_tool_use" => "PostToolUse",
        "post_tool_use_failure" => "PostToolUseFailure",
        "permission_request" => "PermissionRequest",
        "permission_denied" => "PermissionDenied",
        "stop_failure" | "StopFailure" => "Stop",
        "subagent_start" => "SubagentStart",
        "subagent_stop" => "SubagentStop",
        "pre_compact" => "PreCompact",
        "post_compact" => "PostCompact",
        "notification" => "Notification",
        // Hermes
        "pre_tool_call" => "PreToolUse",
        "post_tool_call" => "PostToolUse",
        "pre_llm_call" => "UserPromptSubmit",
        "post_llm_call" => "AgentTurnSettled",
        "on_session_start" => "SessionStart",
        "on_session_end" => "Stop",
        "on_session_finalize" => "SessionEnd",
        "on_session_reset" => "SessionEnd",
        // Cline
        "TaskStart" => "SessionStart",
        "TaskResume" => "UserPromptSubmit",
        "TaskComplete" => "TaskRoundComplete",
        "TaskCancel" => "TaskRoundComplete",
        other => other,
    }
}

#[cfg(test)]
mod tests {
    use super::normalize;

    #[test]
    fn claude_names_pass_through_and_aliases_map() {
        for name in [
            "PermissionRequest",
            "Notification",
            "PreToolUse",
            "Stop",
            "",
        ] {
            assert_eq!(normalize(name), name);
        }
        assert_eq!(normalize("permission_request"), "PermissionRequest");
        assert_eq!(normalize("BeforeTool"), "PermissionRequest");
        assert_eq!(normalize("afterAgentThought"), "Notification");
    }
}
