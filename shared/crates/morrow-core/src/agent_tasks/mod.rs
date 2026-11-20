//! The agent's own checklist (`AgentTaskStatus`, `AgentTaskItem`,
//! `AgentTaskDraft`, `AgentTaskRowPatch`, `AgentTaskChange`, `AgentTaskEvent`,
//! `Sources/MorrowCore/AgentTaskList.swift`): TaskCreate/TaskUpdate (Claude
//! Code), TodoWrite (older Claude Code and forks), `update_plan` (Codex),
//! `write_todos` / `todowrite` (Gemini / OpenCode).
//!
//! [`parsing`] reads checklist events out of a hook or a transcript row;
//! [`list`] is the `AgentTaskList` those events are applied to.

pub mod list;
pub mod parsing;

pub use list::AgentTaskList;

use serde_json::Value;

/// Lifecycle of one entry in an agent's own task checklist.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AgentTaskStatus {
    Pending,
    InProgress,
    Completed,
}

/// Outcome of reading a provider's free-form status string.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ParsedStatus {
    Status(AgentTaskStatus),
    /// The entry left the list (Claude `deleted`, Gemini/OpenCode `cancelled`).
    Removed,
    /// Absent or unrecognised — callers pick a default.
    Unknown,
}

impl AgentTaskStatus {
    /// The wire spelling a persisted checklist carries.
    pub fn raw_value(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::InProgress => "in_progress",
            Self::Completed => "completed",
        }
    }

    /// A status this build does not know (written by a newer version and read
    /// back after a downgrade) decodes as `pending` instead of failing the
    /// checklist — and with it the whole persisted session.
    pub fn from_raw_value(raw: &str) -> Self {
        match Self::parse(Some(&Value::String(raw.to_owned()))) {
            ParsedStatus::Status(status) => status,
            ParsedStatus::Removed | ParsedStatus::Unknown => Self::Pending,
        }
    }

    /// Normalise the status vocabularies of every checklist tool we read.
    /// They all say `pending` / `in_progress` / `completed`, but forks drift
    /// on casing and separators.
    pub fn parse(raw: Option<&Value>) -> ParsedStatus {
        let Some(raw) = raw.and_then(Value::as_str) else {
            return ParsedStatus::Unknown;
        };
        let key = raw.to_lowercase().replace(['-', ' '], "_");
        match key.trim() {
            "pending" | "todo" | "not_started" | "open" | "queued" => {
                ParsedStatus::Status(Self::Pending)
            }
            "in_progress" | "inprogress" | "active" | "running" | "doing" | "started" => {
                ParsedStatus::Status(Self::InProgress)
            }
            "completed" | "complete" | "done" | "finished" => ParsedStatus::Status(Self::Completed),
            "deleted" | "removed" | "cancelled" | "canceled" => ParsedStatus::Removed,
            _ => ParsedStatus::Unknown,
        }
    }
}

/// One row of an agent's checklist as shown on the session card.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AgentTaskItem {
    /// Stable row identity, assigned once and never rewritten.
    pub id: String,
    /// Provider task id: Claude's `TaskCreate` result, or the row id a
    /// snapshot list carries. `None` for rows without one and for a create
    /// whose result is pending.
    pub task_id: Option<String>,
    /// tool_use id of the `TaskCreate` call that introduced the row.
    pub create_op_id: Option<String>,
    pub title: String,
    /// Present-continuous label ("Running tests") shown while in progress.
    pub active_form: Option<String>,
    pub status: AgentTaskStatus,
}

impl AgentTaskItem {
    /// What the compact row says while this item is the one being worked on.
    pub fn progress_label(&self) -> &str {
        self.active_form.as_deref().unwrap_or(&self.title)
    }
}

/// A row of a snapshot-style list (TodoWrite, update_plan, write_todos): the
/// tool re-sends the whole list every time, so rows carry no identity of
/// their own beyond the row id a tool may send.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AgentTaskDraft {
    pub title: String,
    pub active_form: Option<String>,
    pub status: AgentTaskStatus,
    /// The row's own id when the tool sends one (Cursor `todo_write`).
    pub row_id: Option<String>,
}

/// One row of a `todo_write` call with `merge: true` (Cursor): only the
/// fields it carries change, on the row with the same id.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct AgentTaskRowPatch {
    pub row_id: Option<String>,
    pub change: AgentTaskChange,
}

/// Field changes carried by one Claude `TaskUpdate`.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct AgentTaskChange {
    pub status: Option<AgentTaskStatus>,
    pub is_deletion: bool,
    pub title: Option<String>,
    pub active_form: Option<String>,
}

impl AgentTaskChange {
    pub fn with_status(status: AgentTaskStatus) -> Self {
        Self {
            status: Some(status),
            ..Self::default()
        }
    }

    /// Later changes win field by field; a deletion is final.
    pub fn merged_with(&self, later: &Self) -> Self {
        Self {
            status: later.status.or(self.status),
            is_deletion: self.is_deletion || later.is_deletion,
            title: later.title.clone().or_else(|| self.title.clone()),
            active_form: later
                .active_form
                .clone()
                .or_else(|| self.active_form.clone()),
        }
    }
}

/// One observation about an agent's checklist, from a hook or a transcript row.
///
/// Hooks and the transcript describe the *same* tool calls, and Claude's
/// PostToolUse hooks run async (they can overtake the next PreToolUse), so
/// every operation carries the provider's tool-call id (`op_id`). The list
/// applies each (kind, op_id) once, whichever channel delivers it first.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum AgentTaskEvent {
    /// A new user prompt began a turn.
    NewTurn,
    /// The agent's turn ended (Stop hook; Codex `task_complete` /
    /// `turn_aborted`).
    TurnEnded,
    /// `TaskCreate` was called; its provider id is not known yet.
    Create {
        op_id: String,
        title: String,
        active_form: Option<String>,
    },
    /// `TaskCreate` returned the provider id for the call `op_id`.
    Created {
        op_id: Option<String>,
        task_id: String,
        title: Option<String>,
        active_form: Option<String>,
    },
    /// A transcript result row that only *reads* like a `TaskCreate` result
    /// ("Task #7 created successfully: …") and carries no structured result.
    /// Result rows do not name their tool and MCP tools can print the same
    /// words, so this only completes the draft the call `op_id` created; it
    /// never adds a row of its own.
    CreatedPerText {
        op_id: String,
        task_id: String,
        title: Option<String>,
    },
    /// `TaskUpdate` for `task_id`. `expected_from` is set when the event comes
    /// from a *result* (`statusChange.from`): an async result that lost the
    /// race to a newer update must not roll the status back.
    Update {
        op_id: Option<String>,
        task_id: String,
        change: AgentTaskChange,
        expected_from: Option<AgentTaskStatus>,
    },
    /// The call `op_id` failed or was rejected — undo whatever it did.
    OpFailed { op_id: String },
    /// A full-list snapshot replaced the checklist (TodoWrite / update_plan).
    Replace {
        op_id: Option<String>,
        items: Vec<AgentTaskDraft>,
    },
    /// A partial snapshot merged into the checklist by row id (Cursor
    /// `todo_write` with `merge: true`); rows it doesn't mention stay.
    Merge {
        op_id: Option<String>,
        rows: Vec<AgentTaskRowPatch>,
    },
}

impl AgentTaskEvent {
    /// Whether this event can put rows on a list that starts out empty. A
    /// transcript whose only events are prompts, failures or text-only
    /// results holds no checklist history, so replaying it must not replace
    /// what hooks or persistence built.
    pub fn builds_list(&self) -> bool {
        matches!(
            self,
            Self::Create { .. }
                | Self::Created { .. }
                | Self::Update { .. }
                | Self::Replace { .. }
                | Self::Merge { .. }
        )
    }

    pub fn is_turn_boundary(&self) -> bool {
        matches!(self, Self::NewTurn | Self::TurnEnded)
    }

    /// Dedupe key for this operation, or `None` when it is naturally
    /// idempotent.
    pub fn dedupe_key(&self) -> Option<String> {
        match self {
            Self::NewTurn | Self::TurnEnded => None,
            Self::Create { op_id, .. } => Some(format!("c|{op_id}")),
            Self::Created { op_id, .. } => op_id.as_ref().map(|op_id| format!("r|{op_id}")),
            Self::CreatedPerText { op_id, .. } => Some(format!("r|{op_id}")),
            Self::Update { op_id, .. } => op_id.as_ref().map(|op_id| format!("u|{op_id}")),
            Self::OpFailed { op_id } => Some(format!("f|{op_id}")),
            // One call is either a replace or a merge, so they share the key.
            Self::Replace { op_id, .. } | Self::Merge { op_id, .. } => {
                op_id.as_ref().map(|op_id| format!("w|{op_id}"))
            }
        }
    }
}
