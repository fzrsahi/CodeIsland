//! A session's card as the reducer keeps it (`SessionSnapshot`,
//! `Sources/MorrowCore/SessionSnapshot.swift`; `SubagentState`,
//! `ToolHistoryEntry`, `ChatMessage`, `AgentStatus` in `Models.swift`).
//!
//! Only the state the reducer reads or writes. Left out, as the contract's
//! `projection_omits` does: what is set outside the reducer (git, harness,
//! AppState), the per-value ids and the agent's task list (`AgentTaskList`,
//! not ported yet). The recap, reasoning effort and 1M-context flag are kept
//! (the reducer clears the recap on a prompt) but not projected, exactly as
//! the contract's `projection_omits` says.

use std::collections::BTreeMap;

use super::hook_event::HookEvent;
use crate::agent_tasks::AgentTaskList;
use crate::intake::host_harness::{deleting_last_path_component, standardized};
use crate::session_recap::SessionRecap;

/// A point in time, seconds since 1970 (`Date.timeIntervalSince1970`). The
/// core never reads a clock: every one comes from the caller's.
#[derive(Clone, Copy, Debug, PartialEq, PartialOrd)]
pub struct Timestamp(pub f64);

/// Every session, by card id (`[String: SessionSnapshot]`).
pub type Sessions = BTreeMap<String, SessionSnapshot>;

/// `AgentStatus`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AgentStatus {
    Idle,
    Processing,
    Running,
    WaitingApproval,
    WaitingQuestion,
}

/// `SubsessionLink.Kind`: what a child session folded into its parent's
/// card is.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SubsessionKind {
    /// The child named its parent (`_parent_session_id`).
    Declared,
    /// A Cursor Agent Task.
    CursorTask,
    /// A Codex subagent thread.
    CodexThread,
    /// Another agent firing this agent's hooks (`_via_plugin`).
    PluginProxy,
}

impl SubsessionKind {
    /// `Kind(rawValue:)`.
    pub fn from_raw_value(raw: &str) -> Option<Self> {
        match raw {
            "declared" => Some(Self::Declared),
            "cursor" => Some(Self::CursorTask),
            "codex" => Some(Self::CodexThread),
            "plugin" => Some(Self::PluginProxy),
            _ => None,
        }
    }

    /// `rawValue`.
    pub fn raw_value(self) -> &'static str {
        match self {
            Self::Declared => "declared",
            Self::CursorTask => "cursor",
            Self::CodexThread => "codex",
            Self::PluginProxy => "plugin",
        }
    }
}

/// `ChatMessage`, without its per-value id.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChatMessage {
    pub is_user: bool,
    pub text: String,
}

impl ChatMessage {
    pub fn new(is_user: bool, text: &str) -> Self {
        Self {
            is_user,
            text: text.to_owned(),
        }
    }
}

/// `ToolHistoryEntry`, without its per-value id.
#[derive(Clone, Debug, PartialEq)]
pub struct ToolHistoryEntry {
    pub tool: String,
    pub description: Option<String>,
    pub timestamp: Timestamp,
    pub success: bool,
    /// `None`: the main thread's.
    pub agent_type: Option<String>,
}

/// `SubagentState`.
#[derive(Clone, Debug, PartialEq)]
pub struct SubagentState {
    pub agent_id: String,
    pub agent_type: String,
    pub status: AgentStatus,
    current_tool: Option<String>,
    pub current_tool_use_id: Option<String>,
    pub tool_description: Option<String>,
    pub start_time: Timestamp,
    pub last_activity: Timestamp,
    pub model: Option<String>,
    /// The effort the subagent's own transcript reported.
    pub reasoning_effort: Option<String>,
    pub subsession_kind: Option<SubsessionKind>,
}

impl SubagentState {
    /// `SubagentState(agentId:agentType:)`, started `now`.
    pub fn new(agent_id: &str, agent_type: &str, now: Timestamp) -> Self {
        Self {
            agent_id: agent_id.to_owned(),
            agent_type: agent_type.to_owned(),
            status: AgentStatus::Running,
            current_tool: None,
            current_tool_use_id: None,
            tool_description: None,
            start_time: now,
            last_activity: now,
            model: None,
            reasoning_effort: None,
            subsession_kind: None,
        }
    }

    pub fn current_tool(&self) -> Option<&str> {
        self.current_tool.as_deref()
    }

    /// `currentTool`'s `didSet`: another tool forgets the tool use.
    pub fn set_current_tool(&mut self, tool: Option<String>) {
        if tool != self.current_tool {
            self.current_tool_use_id = None;
        }
        self.current_tool = tool;
    }

    /// `finishesAnotherToolUse(_:)`.
    pub fn finishes_another_tool_use(&self, event: &HookEvent) -> bool {
        is_step(
            event,
            self.current_tool_use_id.as_deref(),
            self.current_tool(),
        )
    }
}

/// `SessionSnapshot`, the fields the reducer reads or writes.
#[derive(Clone, Debug, PartialEq)]
pub struct SessionSnapshot {
    pub status: AgentStatus,
    current_tool: Option<String>,
    /// The tool use that put up the current tool, when it named one.
    pub current_tool_use_id: Option<String>,
    pub tool_description: Option<String>,
    pub last_activity: Timestamp,
    pub cwd: Option<String>,
    pub model: Option<String>,
    pub permission_mode: Option<String>,
    pub tool_history: Vec<ToolHistoryEntry>,
    pub total_tool_call_count: i64,
    pub subagents: BTreeMap<String, SubagentState>,
    /// The agent's own checklist (TaskCreate / TodoWrite / update_plan).
    pub agent_tasks: AgentTaskList,
    closed_subagent_ids: Vec<String>,
    pub start_time: Timestamp,
    pub last_user_prompt: Option<String>,
    pub last_assistant_message: Option<String>,
    pub live_codex_output: Option<String>,
    pub transcript_path: Option<String>,
    pub recent_messages: Vec<ChatMessage>,
    pub term_app: Option<String>,
    pub iterm_session_id: Option<String>,
    pub tty_path: Option<String>,
    pub kitty_window_id: Option<String>,
    pub tmux_pane: Option<String>,
    pub tmux_client_tty: Option<String>,
    pub tmux_env: Option<String>,
    pub term_bundle_id: Option<String>,
    pub cmux_surface_id: Option<String>,
    pub cmux_workspace_id: Option<String>,
    pub zellij_pane_id: Option<String>,
    pub zellij_session_name: Option<String>,
    pub wezterm_pane_id: Option<String>,
    pub herdr_pane_id: Option<String>,
    pub herdr_socket_path: Option<String>,
    pub herdr_binary_path: Option<String>,
    pub superset_workspace_id: Option<String>,
    pub superset_pane_id: Option<String>,
    pub orca_terminal_handle: Option<String>,
    pub orca_worktree_id: Option<String>,
    pub claude_desktop_session_id: Option<String>,
    /// The CLI's pid on this machine (the bridge's `_ppid`).
    pub cli_pid: Option<i32>,
    pub cli_start_time: Option<Timestamp>,
    /// A remote session's agent pid on its own host.
    pub remote_pid: Option<i32>,
    pub source: String,
    pub interrupted: bool,
    pub last_turn_failed: bool,
    pub task_round_ended: bool,
    pub session_title: Option<String>,
    pub provider_session_id: Option<String>,
    pub parent_session_id: Option<String>,
    pub remote_host_id: Option<String>,
    pub remote_host_name: Option<String>,
    pub model_reported_at: Option<Timestamp>,
    /// Claude Code's idle recap (`SessionRecap`), cleared by the next prompt.
    pub recap: Option<SessionRecap>,
    /// The reasoning effort the newest transcript line reported.
    pub reasoning_effort: Option<String>,
    /// A `/model` switch's word on the 1M context variant.
    pub configured_long_context: Option<bool>,
    pub hermes_hooks_report_prompts: bool,
    pub hermes_hooks_report_replies: bool,
    pub hermes_chat_elsewhere: bool,
}

/// `SessionSnapshot.ideCompletionSources`.
pub const IDE_COMPLETION_SOURCES: &[&str] = &[
    "cursor",
    "cursor-cli",
    "qoder",
    "qoder-cli",
    "trae",
    "traecn",
    "codebuddy",
    "codybuddycn",
];

/// `SessionSnapshot.maxClosedSubagentIds`.
pub const MAX_CLOSED_SUBAGENT_IDS: usize = 256;

/// `SessionSnapshot.agentMetadataDirNames`.
const AGENT_METADATA_DIR_NAMES: &[&str] = &[
    ".claude",
    ".cursor",
    ".codex",
    ".gemini",
    ".qoder",
    ".qoder-cn",
    ".qoderwork",
    ".trae",
    ".trae-cn",
    ".kiro",
    ".copilot",
    ".factory",
    ".codebuddy",
    ".codybuddycn",
    ".stepfun",
    ".workbuddy",
    ".hermes",
    ".kimi",
    ".kimi-code",
    ".grok",
    ".pi",
    ".omp",
    ".qwen",
    ".zcode",
    ".openclaw",
    ".morrow",
    ".codeisland",
];

impl SessionSnapshot {
    /// `SessionSnapshot(startTime:)`: started and last active `now`.
    pub fn new(now: Timestamp) -> Self {
        Self {
            status: AgentStatus::Idle,
            current_tool: None,
            current_tool_use_id: None,
            tool_description: None,
            last_activity: now,
            cwd: None,
            model: None,
            permission_mode: None,
            tool_history: Vec::new(),
            total_tool_call_count: 0,
            subagents: BTreeMap::new(),
            agent_tasks: AgentTaskList::new(),
            closed_subagent_ids: Vec::new(),
            start_time: now,
            last_user_prompt: None,
            last_assistant_message: None,
            live_codex_output: None,
            transcript_path: None,
            recent_messages: Vec::new(),
            term_app: None,
            iterm_session_id: None,
            tty_path: None,
            kitty_window_id: None,
            tmux_pane: None,
            tmux_client_tty: None,
            tmux_env: None,
            term_bundle_id: None,
            cmux_surface_id: None,
            cmux_workspace_id: None,
            zellij_pane_id: None,
            zellij_session_name: None,
            wezterm_pane_id: None,
            herdr_pane_id: None,
            herdr_socket_path: None,
            herdr_binary_path: None,
            superset_workspace_id: None,
            superset_pane_id: None,
            orca_terminal_handle: None,
            orca_worktree_id: None,
            claude_desktop_session_id: None,
            cli_pid: None,
            cli_start_time: None,
            remote_pid: None,
            source: "claude".to_owned(),
            interrupted: false,
            last_turn_failed: false,
            task_round_ended: false,
            session_title: None,
            provider_session_id: None,
            parent_session_id: None,
            remote_host_id: None,
            remote_host_name: None,
            model_reported_at: None,
            recap: None,
            reasoning_effort: None,
            configured_long_context: None,
            hermes_hooks_report_prompts: false,
            hermes_hooks_report_replies: false,
            hermes_chat_elsewhere: false,
        }
    }

    pub fn current_tool(&self) -> Option<&str> {
        self.current_tool.as_deref()
    }

    /// `currentTool`'s `didSet`: another tool forgets the tool use.
    pub fn set_current_tool(&mut self, tool: Option<String>) {
        if tool != self.current_tool {
            self.current_tool_use_id = None;
        }
        self.current_tool = tool;
    }

    /// Agent ids closed by SubagentStop/Stop/SessionEnd, oldest first.
    pub fn closed_subagent_ids(&self) -> &[String] {
        &self.closed_subagent_ids
    }

    /// `recordClosedSubagentId`: evicts the oldest past
    /// [`MAX_CLOSED_SUBAGENT_IDS`].
    pub fn record_closed_subagent_id(&mut self, id: &str) {
        let trimmed = id.trim();
        if trimmed.is_empty() || self.has_closed_subagent_id(trimmed) {
            return;
        }
        self.closed_subagent_ids.push(trimmed.to_owned());
        let overflow = self
            .closed_subagent_ids
            .len()
            .saturating_sub(MAX_CLOSED_SUBAGENT_IDS);
        self.closed_subagent_ids.drain(..overflow);
    }

    /// `clearClosedSubagentId`.
    pub fn clear_closed_subagent_id(&mut self, id: &str) {
        let trimmed = id.trim();
        self.closed_subagent_ids.retain(|closed| closed != trimmed);
    }

    /// `hasClosedSubagentId`.
    pub fn has_closed_subagent_id(&self, id: &str) -> bool {
        let trimmed = id.trim();
        !trimmed.is_empty() && self.closed_subagent_ids.iter().any(|c| c == trimmed)
    }

    /// `restoreClosedSubagentIds`: in order, without the live cap.
    pub fn restore_closed_subagent_ids(&mut self, ids: &[String]) {
        self.closed_subagent_ids.clear();
        for id in ids {
            let trimmed = id.trim();
            if !trimmed.is_empty() && !self.has_closed_subagent_id(trimmed) {
                self.closed_subagent_ids.push(trimmed.to_owned());
            }
        }
    }

    /// `addRecentMessage` (max 3).
    pub fn add_recent_message(&mut self, message: ChatMessage) {
        self.recent_messages.push(message);
        self.cap_recent_messages();
    }

    /// `insertRecentMessage(_:at:)` (max 3).
    pub fn insert_recent_message(&mut self, message: ChatMessage, at: usize) {
        self.recent_messages.insert(at, message);
        self.cap_recent_messages();
    }

    fn cap_recent_messages(&mut self) {
        let overflow = self.recent_messages.len().saturating_sub(3);
        self.recent_messages.drain(..overflow);
    }

    /// `recordTool`.
    pub fn record_tool(
        &mut self,
        tool: &str,
        description: Option<&str>,
        success: bool,
        agent_type: Option<&str>,
        max_history: usize,
        now: Timestamp,
    ) {
        self.total_tool_call_count += 1;
        self.tool_history.push(ToolHistoryEntry {
            tool: tool.to_owned(),
            description: description.map(str::to_owned),
            timestamp: now,
            success,
            agent_type: agent_type.map(str::to_owned),
        });
        if self.tool_history.len() > max_history {
            self.tool_history.remove(0);
        }
    }

    /// `finishesAnotherToolUse(_:)`: a step of a tool use other than the one
    /// running, when both name theirs.
    pub fn finishes_another_tool_use(&self, event: &HookEvent) -> bool {
        is_step(
            event,
            self.current_tool_use_id.as_deref(),
            self.current_tool(),
        )
    }

    /// `isRemote`.
    pub fn is_remote(&self) -> bool {
        self.remote_host_id
            .as_deref()
            .is_some_and(|host| !host.trim().is_empty())
    }

    /// The last chat row is the user's.
    pub(crate) fn last_message_is_user(&self) -> bool {
        self.recent_messages.last().is_some_and(|m| m.is_user)
    }

    /// `activeSubagentCount != 0`.
    pub(crate) fn has_active_subagents(&self) -> bool {
        self.subagents
            .values()
            .any(|s| s.status != AgentStatus::Idle)
    }
}

/// `SessionSnapshot.isStep(_:ofAnotherToolUseThan:showing:)`.
fn is_step(event: &HookEvent, running: Option<&str>, tool: Option<&str>) -> bool {
    match (tool, running, event.tool_use_id.as_deref()) {
        (Some(_), Some(running), Some(finished)) => finished != running,
        _ => false,
    }
}

/// `SessionSnapshot.isUnhelpfulHookCwd`: `$HOME`, or an agent's metadata
/// directory right under it.
pub fn is_unhelpful_hook_cwd(cwd: &str, home: &str) -> bool {
    if is_home_directory_path(cwd, home) {
        return true;
    }
    let last = super::json::last_path_component(cwd);
    AGENT_METADATA_DIR_NAMES.contains(&last)
        && is_home_directory_path(&deleting_last_path_component(cwd), home)
}

/// `SessionSnapshot.isHomeDirectoryPath`, lexically.
fn is_home_directory_path(path: &str, home: &str) -> bool {
    let expanded = match path.strip_prefix('~') {
        Some(rest) if rest.is_empty() || rest.starts_with('/') => format!("{home}{rest}"),
        _ => path.to_owned(),
    };
    !expanded.is_empty() && standardized(&expanded) == standardized(home)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn closed_ids_are_trimmed_and_capped() {
        let mut s = SessionSnapshot::new(Timestamp(0.0));
        s.record_closed_subagent_id(" a ");
        assert!(s.has_closed_subagent_id("a"));
        for i in 0..MAX_CLOSED_SUBAGENT_IDS {
            s.record_closed_subagent_id(&i.to_string());
        }
        assert!(!s.has_closed_subagent_id("a"));
        assert_eq!(s.closed_subagent_ids().len(), MAX_CLOSED_SUBAGENT_IDS);
    }

    #[test]
    fn changing_the_tool_forgets_its_tool_use() {
        let mut s = SessionSnapshot::new(Timestamp(0.0));
        s.set_current_tool(Some("Bash".into()));
        s.current_tool_use_id = Some("t1".into());
        s.set_current_tool(Some("Bash".into()));
        assert_eq!(s.current_tool_use_id.as_deref(), Some("t1"));
        s.set_current_tool(Some("Read".into()));
        assert_eq!(s.current_tool_use_id, None);
    }

    #[test]
    fn home_and_metadata_dirs_are_unhelpful() {
        assert!(is_unhelpful_hook_cwd("/home/dev", "/home/dev"));
        assert!(is_unhelpful_hook_cwd("/home/dev/.claude/", "/home/dev"));
        assert!(is_unhelpful_hook_cwd("~", "/home/dev"));
        assert!(!is_unhelpful_hook_cwd("/home/dev/app", "/home/dev"));
        assert!(!is_unhelpful_hook_cwd("/srv/.claude", "/home/dev"));
    }
}
