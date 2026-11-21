//! Reading checklist observations out of hooks and transcript rows
//! (`AgentTaskParsing`, `AgentTaskTool`, `AgentTaskHookParser`,
//! `AgentTaskTranscript`, `macos/Sources/MorrowCore/AgentTaskParsing.swift`).
//!
//! The list that applies the events is [`super::list::AgentTaskList`].

use serde_json::{Map, Value};

use super::{
    AgentTaskChange, AgentTaskDraft, AgentTaskEvent, AgentTaskRowPatch, AgentTaskStatus,
    ParsedStatus,
};
use crate::intake::event_normalizer::normalize;
use crate::reduce::HookEvent;

/// A checklist tool an agent can call. Names are matched case- and
/// separator-insensitively because forks re-spell them (`todo_write`,
/// `write_todos`, `todowrite`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AgentTaskTool {
    /// Claude Code ≥ 2.1 `TaskCreate {subject, description, activeForm}`.
    TaskCreate,
    /// Claude Code ≥ 2.1 `TaskUpdate {taskId, status, subject?, activeForm?}`.
    TaskUpdate,
    /// Whole-list todo writers: Claude `TodoWrite`, Gemini `write_todos`,
    /// OpenCode `todowrite`, Qwen `todo_write` — `{todos: [...]}`.
    TodoSnapshot,
    /// Codex `update_plan {explanation?, plan: [{step, status}]}`.
    PlanSnapshot,
}

impl AgentTaskTool {
    pub fn from_tool_name(tool_name: Option<&str>) -> Option<Self> {
        let normalized = normalized_tool_name(tool_name?);
        let tool = match normalized.as_str() {
            "taskcreate" => Self::TaskCreate,
            "taskupdate" => Self::TaskUpdate,
            "todowrite" | "writetodos" => Self::TodoSnapshot,
            "updateplan" => Self::PlanSnapshot,
            _ => return None,
        };
        Some(tool)
    }

    /// Events implied by a *call* of this tool (its input alone).
    pub fn call_events(
        &self,
        op_id: Option<&str>,
        input: &Map<String, Value>,
    ) -> Vec<AgentTaskEvent> {
        match self {
            Self::TaskCreate => {
                let (Some(op_id), Some(subject)) =
                    (op_id, string(input, &["subject", "title", "content"]))
                else {
                    return Vec::new();
                };
                vec![AgentTaskEvent::Create {
                    op_id: op_id.to_owned(),
                    title: subject,
                    active_form: string(input, &["activeForm", "active_form"]),
                }]
            }
            Self::TaskUpdate => {
                let Some(task_id) = id_string(field(input, &["taskId", "task_id", "id"])) else {
                    return Vec::new();
                };
                let change = change_from_update_input(input);
                if change == AgentTaskChange::default() {
                    return Vec::new();
                }
                vec![AgentTaskEvent::Update {
                    op_id: op_id.map(str::to_owned),
                    task_id,
                    change,
                    expected_from: None,
                }]
            }
            Self::TodoSnapshot => {
                // Cursor's todo_write can send only the rows that changed.
                if flag(input.get("merge")) {
                    let Some(rows) = row_patches(input.get("todos")) else {
                        return Vec::new();
                    };
                    return vec![AgentTaskEvent::Merge {
                        op_id: op_id.map(str::to_owned),
                        rows,
                    }];
                }
                let Some(items) = drafts(input.get("todos")) else {
                    return Vec::new();
                };
                vec![AgentTaskEvent::Replace {
                    op_id: op_id.map(str::to_owned),
                    items,
                }]
            }
            Self::PlanSnapshot => {
                let Some(items) = drafts(input.get("plan")) else {
                    return Vec::new();
                };
                vec![AgentTaskEvent::Replace {
                    op_id: op_id.map(str::to_owned),
                    items,
                }]
            }
        }
    }

    /// Events implied by a successful *result* of this tool (hook
    /// `tool_response`). Snapshot tools repeat their call — same op key, so
    /// the list applies it once.
    pub fn result_events(
        &self,
        op_id: Option<&str>,
        input: &Map<String, Value>,
        response: Option<&Value>,
    ) -> Vec<AgentTaskEvent> {
        match self {
            Self::TaskCreate => {
                let task = json_object(response)
                    .and_then(|object| object.get("task").and_then(Value::as_object).cloned());
                let task_id = task
                    .as_ref()
                    .and_then(|task| id_string(task.get("id")))
                    .or_else(|| created_task_id_from_result_text(response.and_then(Value::as_str)));
                let Some(task_id) = task_id else {
                    return Vec::new();
                };
                vec![AgentTaskEvent::Created {
                    op_id: op_id.map(str::to_owned),
                    task_id,
                    title: task
                        .as_ref()
                        .and_then(|task| task.get("subject"))
                        .and_then(Value::as_str)
                        .map(str::to_owned)
                        .or_else(|| string(input, &["subject", "title", "content"])),
                    active_form: string(input, &["activeForm", "active_form"]),
                }]
            }
            Self::TaskUpdate => {
                let response = json_object(response).unwrap_or_default();
                if response.get("success") == Some(&Value::Bool(false)) {
                    // e.g. a TaskCompleted hook blocked the completion.
                    return op_id
                        .map(|op_id| {
                            vec![AgentTaskEvent::OpFailed {
                                op_id: op_id.to_owned(),
                            }]
                        })
                        .unwrap_or_default();
                }
                let Some(task_id) = id_string(
                    field(input, &["taskId", "task_id"]).or_else(|| response.get("taskId")),
                ) else {
                    return Vec::new();
                };
                let mut change = change_from_update_input(input);
                let status_change = response.get("statusChange").and_then(Value::as_object);
                if change.status.is_none() && !change.is_deletion {
                    if let Some(to) = status_change.and_then(|change| change.get("to")) {
                        match AgentTaskStatus::parse(Some(to)) {
                            ParsedStatus::Status(status) => change.status = Some(status),
                            ParsedStatus::Removed => change.is_deletion = true,
                            ParsedStatus::Unknown => {}
                        }
                    }
                }
                if change == AgentTaskChange::default() {
                    return Vec::new();
                }
                let expected_from = match AgentTaskStatus::parse(
                    status_change.and_then(|change| change.get("from")),
                ) {
                    ParsedStatus::Status(status) => Some(status),
                    _ => None,
                };
                vec![AgentTaskEvent::Update {
                    op_id: op_id.map(str::to_owned),
                    task_id,
                    change,
                    expected_from,
                }]
            }
            Self::TodoSnapshot | Self::PlanSnapshot => self.call_events(op_id, input),
        }
    }
}

/// Lowercased, separators dropped: `todo_write` / `TodoWrite` → `todowrite`.
pub fn normalized_tool_name(name: &str) -> String {
    name.to_lowercase()
        .chars()
        .filter(|c| *c != '_' && *c != '-' && *c != ' ')
        .collect()
}

fn field<'a>(map: &'a Map<String, Value>, keys: &[&str]) -> Option<&'a Value> {
    keys.iter().find_map(|key| map.get(*key))
}

/// The first non-blank string among `keys`.
pub fn string(map: &Map<String, Value>, keys: &[&str]) -> Option<String> {
    for key in keys {
        let Some(value) = map.get(*key).and_then(Value::as_str) else {
            continue;
        };
        let trimmed = value.trim();
        if !trimmed.is_empty() {
            return Some(trimmed.to_owned());
        }
    }
    None
}

/// Task ids are strings on the wire ("1"), but tolerate numbers.
pub fn id_string(value: Option<&Value>) -> Option<String> {
    match value? {
        Value::String(text) => {
            let trimmed = text.trim();
            (!trimmed.is_empty()).then(|| trimmed.to_owned())
        }
        Value::Number(number) => Some(number.to_string()),
        _ => None,
    }
}

/// Tool arguments arrive as an object from hooks but as a JSON *string* in
/// Codex rollouts (`function_call.arguments`).
pub fn json_object(value: Option<&Value>) -> Option<Map<String, Value>> {
    match value? {
        Value::Object(object) => Some(object.clone()),
        Value::String(text) if text.starts_with('{') => serde_json::from_str::<Value>(text)
            .ok()?
            .as_object()
            .cloned(),
        _ => None,
    }
}

fn change_from_update_input(input: &Map<String, Value>) -> AgentTaskChange {
    let mut change = AgentTaskChange::default();
    match AgentTaskStatus::parse(input.get("status")) {
        ParsedStatus::Status(status) => change.status = Some(status),
        ParsedStatus::Removed => change.is_deletion = true,
        ParsedStatus::Unknown => {}
    }
    change.title = string(input, &["subject", "title"]);
    change.active_form = string(input, &["activeForm", "active_form"]);
    change
}

/// A boolean argument, tolerating `"true"` from loosely typed callers.
pub fn flag(value: Option<&Value>) -> bool {
    match value {
        Some(Value::Bool(flag)) => *flag,
        Some(Value::String(text)) => text.to_lowercase() == "true",
        _ => false,
    }
}

const ROW_TITLE_KEYS: &[&str] = &[
    "content",
    "subject",
    "step",
    "title",
    "description",
    "text",
    "task",
];

/// The rows of a list argument, which arrives as an array from hooks and as a
/// JSON string from Codex rollouts. `None` when it is not a list.
fn row_objects(value: Option<&Value>) -> Option<Vec<Map<String, Value>>> {
    let array = match value? {
        Value::Array(array) => array.clone(),
        Value::String(text) if text.starts_with('[') => serde_json::from_str::<Value>(text)
            .ok()?
            .as_array()?
            .clone(),
        _ => return None,
    };
    Some(
        array
            .into_iter()
            .filter_map(|row| row.as_object().cloned())
            .collect(),
    )
}

/// Rows of a whole-list snapshot. `None` when `value` is not a list at all
/// (malformed call); an empty array is a real "list cleared".
pub fn drafts(value: Option<&Value>) -> Option<Vec<AgentTaskDraft>> {
    let rows = row_objects(value)?;
    Some(
        rows.into_iter()
            .filter_map(|row| {
                let title = string(&row, ROW_TITLE_KEYS)?;
                let status = match AgentTaskStatus::parse(row.get("status")) {
                    ParsedStatus::Status(status) => status,
                    ParsedStatus::Removed => return None,
                    ParsedStatus::Unknown => AgentTaskStatus::Pending,
                };
                Some(AgentTaskDraft {
                    title,
                    active_form: string(&row, &["activeForm", "active_form"]),
                    status,
                    row_id: id_string(row.get("id")),
                })
            })
            .collect(),
    )
}

/// Rows of a `merge: true` list update. Unlike a snapshot row, any field may
/// be missing — `{id, status}` is the common case.
pub fn row_patches(value: Option<&Value>) -> Option<Vec<AgentTaskRowPatch>> {
    let rows = row_objects(value)?;
    Some(
        rows.into_iter()
            .filter_map(|row| {
                let mut change = AgentTaskChange::default();
                match AgentTaskStatus::parse(row.get("status")) {
                    ParsedStatus::Status(status) => change.status = Some(status),
                    ParsedStatus::Removed => change.is_deletion = true,
                    ParsedStatus::Unknown => {}
                }
                change.title = string(&row, ROW_TITLE_KEYS);
                change.active_form = string(&row, &["activeForm", "active_form"]);
                let row_id = id_string(row.get("id"));
                if row_id.is_none() && change.title.is_none() {
                    return None;
                }
                if change == AgentTaskChange::default() {
                    return None;
                }
                Some(AgentTaskRowPatch { row_id, change })
            })
            .collect(),
    )
}

/// Claude's text result for `TaskCreate`: "Task #7 created successfully: …".
pub fn created_task_id_from_result_text(text: Option<&str>) -> Option<String> {
    let text = text?;
    let hash = text.find("Task #")? + "Task #".len();
    let end = text[hash..].find(" created successfully")? + hash;
    let id = text[hash..end].trim();
    if id.is_empty() || id.contains(' ') {
        return None;
    }
    Some(id.to_owned())
}

/// The first text of a result row's content: a bare string, or a block's.
pub fn result_text(content: Option<&Value>) -> Option<String> {
    match content? {
        Value::String(text) => Some(text.clone()),
        Value::Array(blocks) => blocks
            .iter()
            .find_map(|block| block.get("text").and_then(Value::as_str).map(str::to_owned)),
        _ => None,
    }
}

// MARK: - Hooks

/// Checklist events carried by one hook event.
///
/// Callers must route subagent (`agent_id`) events elsewhere first — a
/// child's own checklist does not belong on the parent card.
pub fn hook_events(event: &HookEvent, normalized_event_name: &str) -> Vec<AgentTaskEvent> {
    match normalized_event_name {
        "UserPromptSubmit" => return vec![AgentTaskEvent::NewTurn],
        "Stop" | "Interrupt" | "TaskRoundComplete" => return vec![AgentTaskEvent::TurnEnded],
        "PreToolUse" | "PostToolUse" | "PostToolUseFailure" | "PermissionDenied" => {}
        _ => return Vec::new(),
    }
    let Some(tool) = AgentTaskTool::from_tool_name(event.tool_name.as_deref()) else {
        return Vec::new();
    };
    let op_id = event.tool_use_id.as_deref();
    let input = event
        .tool_input
        .clone()
        .or_else(|| json_object(event.raw("tool_input").or_else(|| event.raw("arguments"))))
        .unwrap_or_default();
    match normalized_event_name {
        "PreToolUse" => tool.call_events(op_id, &input),
        "PostToolUse" => tool.result_events(
            op_id,
            &input,
            event
                .raw("tool_response")
                .or_else(|| event.raw("toolResponse")),
        ),
        // Failed or denied: whatever the PreToolUse applied never happened.
        _ => op_id
            .map(|op_id| {
                vec![AgentTaskEvent::OpFailed {
                    op_id: op_id.to_owned(),
                }]
            })
            .unwrap_or_default(),
    }
}

/// [`hook_events`] for an event whose name has not been normalized yet.
pub fn hook_events_named(event: &HookEvent) -> Vec<AgentTaskEvent> {
    hook_events(event, normalize(&event.event_name))
}

// MARK: - Transcripts

/// Events carried by one decoded transcript row: Claude Code JSONL (and the
/// Claude-format forks) plus Codex rollouts.
pub fn events_from_line(json: &Map<String, Value>) -> Vec<AgentTaskEvent> {
    // Older Claude builds interleave subagent rows into the parent
    // transcript; a child's checklist never belongs on the parent card.
    if json.get("isSidechain") == Some(&Value::Bool(true)) {
        return Vec::new();
    }
    match json.get("type").and_then(Value::as_str) {
        Some("assistant") => claude_assistant_events(json),
        Some("user") => claude_user_events(json),
        Some("response_item") => codex_response_item_events(json),
        Some("event_msg") => codex_event_msg_events(json),
        _ => Vec::new(),
    }
}

fn claude_assistant_events(json: &Map<String, Value>) -> Vec<AgentTaskEvent> {
    let message = json
        .get("message")
        .and_then(Value::as_object)
        .unwrap_or(json);
    let Some(blocks) = message.get("content").and_then(Value::as_array) else {
        return Vec::new();
    };
    let mut events = Vec::new();
    for block in blocks {
        let Some(block) = block.as_object() else {
            continue;
        };
        if block.get("type").and_then(Value::as_str) != Some("tool_use") {
            continue;
        }
        let Some(tool) = AgentTaskTool::from_tool_name(block.get("name").and_then(Value::as_str))
        else {
            continue;
        };
        let input = json_object(block.get("input")).unwrap_or_default();
        events.extend(tool.call_events(block.get("id").and_then(Value::as_str), &input));
    }
    events
}

fn claude_user_events(json: &Map<String, Value>) -> Vec<AgentTaskEvent> {
    if json.get("isMeta") == Some(&Value::Bool(true)) {
        return Vec::new();
    }
    // The compaction summary is written as a user row but starts no turn.
    let starts_turn = json.get("isCompactSummary") != Some(&Value::Bool(true));
    let message = json
        .get("message")
        .and_then(Value::as_object)
        .unwrap_or(json);

    match message.get("content") {
        Some(Value::String(text)) => {
            // A local slash command (/model, /effort) and its output are user
            // rows too, but no turn.
            let is_prompt = starts_turn
                && !text.trim().is_empty()
                && crate::transcript::claude_command_echo(text)
                    != Some(crate::transcript::ClaudeCommandEcho::Local);
            if is_prompt {
                vec![AgentTaskEvent::NewTurn]
            } else {
                Vec::new()
            }
        }
        Some(Value::Array(blocks)) => {
            let mut events = Vec::new();
            let has_text = blocks.iter().any(|block| {
                block.get("type").and_then(Value::as_str) == Some("text")
                    && block
                        .get("text")
                        .and_then(Value::as_str)
                        .is_some_and(|text| !text.trim().is_empty())
            });
            if starts_turn && has_text {
                events.push(AgentTaskEvent::NewTurn);
            }
            let results: Vec<&Map<String, Value>> = blocks
                .iter()
                .filter_map(Value::as_object)
                .filter(|block| block.get("type").and_then(Value::as_str) == Some("tool_result"))
                .collect();
            // `toolUseResult` is the structured result of the row's tool call;
            // it is only unambiguous when the row answers exactly one call.
            let structured = if results.len() == 1 {
                json.get("toolUseResult").and_then(Value::as_object)
            } else {
                None
            };
            for block in results {
                let Some(op_id) = block.get("tool_use_id").and_then(Value::as_str) else {
                    continue;
                };
                if block.get("is_error") == Some(&Value::Bool(true)) {
                    events.push(AgentTaskEvent::OpFailed {
                        op_id: op_id.to_owned(),
                    });
                    continue;
                }
                events.extend(claude_result_events(
                    op_id,
                    structured,
                    block.get("content"),
                ));
            }
            events
        }
        _ => Vec::new(),
    }
}

/// The result row does not name its tool, so recognise it by shape.
fn claude_result_events(
    op_id: &str,
    structured: Option<&Map<String, Value>>,
    content: Option<&Value>,
) -> Vec<AgentTaskEvent> {
    if let Some(structured) = structured {
        // TaskCreate → {task: {id, subject}}. TaskGet returns the same key
        // *with* a status; a read changes nothing, so skip it.
        if let Some(task) = structured.get("task").and_then(Value::as_object) {
            if task.get("status").is_none() {
                if let Some(task_id) = id_string(task.get("id")) {
                    return vec![AgentTaskEvent::Created {
                        op_id: Some(op_id.to_owned()),
                        task_id,
                        title: task
                            .get("subject")
                            .and_then(Value::as_str)
                            .map(str::to_owned),
                        active_form: None,
                    }];
                }
            }
        }
        // TaskUpdate → {success, taskId, updatedFields, statusChange?}.
        let success = structured.get("success").and_then(Value::as_bool);
        if success.is_some() && structured.get("updatedFields").is_some() {
            if let Some(task_id) = id_string(structured.get("taskId")) {
                if success != Some(true) {
                    return vec![AgentTaskEvent::OpFailed {
                        op_id: op_id.to_owned(),
                    }];
                }
                let Some(status_change) = structured.get("statusChange").and_then(Value::as_object)
                else {
                    return Vec::new();
                };
                let mut change = AgentTaskChange::default();
                match AgentTaskStatus::parse(status_change.get("to")) {
                    ParsedStatus::Status(status) => change.status = Some(status),
                    ParsedStatus::Removed => change.is_deletion = true,
                    ParsedStatus::Unknown => return Vec::new(),
                }
                let expected_from = match AgentTaskStatus::parse(status_change.get("from")) {
                    ParsedStatus::Status(status) => Some(status),
                    _ => None,
                };
                return vec![AgentTaskEvent::Update {
                    op_id: Some(op_id.to_owned()),
                    task_id,
                    change,
                    expected_from,
                }];
            }
        }
        return Vec::new();
    }
    // Rows answering several calls at once carry no usable toolUseResult;
    // TaskCreate's text result still names the new id. Any other tool (an MCP
    // server's, say) may print the same words, so the list only lets this
    // complete a TaskCreate draft — never add a row.
    let Some(text) = result_text(content) else {
        return Vec::new();
    };
    let Some(task_id) = created_task_id_from_result_text(Some(&text)) else {
        return Vec::new();
    };
    let title = text.find("created successfully:").map(|index| {
        text[index + "created successfully:".len()..]
            .trim()
            .to_owned()
    });
    vec![AgentTaskEvent::CreatedPerText {
        op_id: op_id.to_owned(),
        task_id,
        title,
    }]
}

fn codex_response_item_events(json: &Map<String, Value>) -> Vec<AgentTaskEvent> {
    let Some(payload) = json.get("payload").and_then(Value::as_object) else {
        return Vec::new();
    };
    if payload.get("type").and_then(Value::as_str) != Some("function_call") {
        return Vec::new();
    }
    let Some(tool) = AgentTaskTool::from_tool_name(payload.get("name").and_then(Value::as_str))
    else {
        return Vec::new();
    };
    let input = json_object(payload.get("arguments")).unwrap_or_default();
    tool.call_events(payload.get("call_id").and_then(Value::as_str), &input)
}

fn codex_event_msg_events(json: &Map<String, Value>) -> Vec<AgentTaskEvent> {
    let Some(payload) = json.get("payload").and_then(Value::as_object) else {
        return Vec::new();
    };
    match payload.get("type").and_then(Value::as_str) {
        Some("task_started" | "user_message") => vec![AgentTaskEvent::NewTurn],
        Some("task_complete" | "turn_aborted" | "turn_failed") => {
            vec![AgentTaskEvent::TurnEnded]
        }
        _ => Vec::new(),
    }
}

// MARK: - Attach-time backfill

/// Checklist events in a JSONL blob, in order. A leading partial row (window
/// cut mid-line) and a trailing unterminated row are ignored. The platform
/// reads the file; the core scans the bytes.
pub fn scan(
    data: &[u8],
    starts_at_line_boundary: bool,
    max_line_bytes: usize,
) -> Vec<AgentTaskEvent> {
    let mut events = Vec::new();
    let mut skip_first = !starts_at_line_boundary;
    for line in data.split(|byte| *byte == b'\n') {
        if skip_first {
            skip_first = false;
            continue;
        }
        if line.is_empty() || line.len() > max_line_bytes || !may_carry_task_event(line) {
            continue;
        }
        let Ok(Value::Object(json)) = serde_json::from_slice::<Value>(line) else {
            continue;
        };
        events.extend(events_from_line(&json));
    }
    events
}

/// Byte prefilter so the backfill decodes only rows that can matter. It must
/// pass every row the live parser acts on: a row it drops here is missing
/// from the replay that rebuilds the list from empty.
pub fn may_carry_task_event(line: &[u8]) -> bool {
    if names_checklist_tool(line) {
        return true;
    }
    if OPERATION_MARKERS
        .iter()
        .any(|marker| contains(line, marker))
    {
        return true;
    }
    // A Claude prompt row: a user row that answers no tool call.
    contains(line, b"\"type\":\"user\"") && !contains(line, b"\"tool_use_id\"")
}

const NAME_MARKER: &[u8] = b"\"name\":\"";
/// Longer than any checklist tool name, so a huge value cannot be scanned.
const MAX_NAME_BYTES: usize = 32;
const CHECKLIST_TOOL_NAMES: &[&str] = &[
    "taskcreate",
    "taskupdate",
    "todowrite",
    "writetodos",
    "updateplan",
];

/// Whether any `"name":"…"` value in the row is a checklist tool, spelled any
/// way `AgentTaskTool::from_tool_name` accepts.
fn names_checklist_tool(line: &[u8]) -> bool {
    let mut offset = 0;
    while offset < line.len() {
        let Some(found) = find(&line[offset..], NAME_MARKER) else {
            return false;
        };
        let value_start = offset + found + NAME_MARKER.len();
        let mut normalized = String::new();
        let mut index = value_start;
        while index < line.len() && index - value_start < MAX_NAME_BYTES && line[index] != b'"' {
            let byte = line[index];
            match byte {
                b'_' | b'-' | b' ' => {}
                b'A'..=b'Z' => normalized.push((byte + 32) as char),
                _ => normalized.push(byte as char),
            }
            index += 1;
        }
        if index < line.len()
            && line[index] == b'"'
            && CHECKLIST_TOOL_NAMES.contains(&normalized.as_str())
        {
            return true;
        }
        offset = value_start;
    }
    false
}

/// Key-order independent: TaskCreate results say "created successfully" in
/// their text, TaskUpdate results always carry `updatedFields`.
const OPERATION_MARKERS: &[&[u8]] = &[
    b" created successfully",
    b"\"updatedFields\":",
    b"\"is_error\":true",
    b"\"type\":\"task_started\"",
    b"\"type\":\"user_message\"",
    b"\"type\":\"task_complete\"",
    b"\"type\":\"turn_aborted\"",
    b"\"type\":\"turn_failed\"",
];

fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    find(haystack, needle).is_some()
}

fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() || haystack.len() < needle.len() {
        return None;
    }
    haystack
        .windows(needle.len())
        .position(|window| window == needle)
}
