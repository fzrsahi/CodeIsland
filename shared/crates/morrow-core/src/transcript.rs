//! The live transcript tail (`JSONLTailer`, `Sources/MorrowCore/JSONLTailer.swift`):
//! the newest user prompt, assistant reply, turn status and trailing Cursor
//! question, derived from the JSONL a CLI appends to its session file.
//!
//! [`scan_lines`] is the parser: it splits a byte chunk on newlines, reads the
//! rows it cares about and hands back the bytes after the last newline as a
//! fragment for the next call. [`TailState`] is the reading position: it
//! carries the fragment, advances by the bytes actually read, hands a
//! replaced file's history back once as a replay, and rewinds on truncation.
//! Neither opens a file, watches a path or reads a clock — the platform
//! watcher does that and passes the bytes in.
//!
//! Not ported (the app-side payloads a delta also carries today): the
//! checklist (`AgentTaskTranscript`), the idle recap (`SessionRecap`), the
//! model label / reasoning effort (`ModelObservation`, `ModelLabel`, including
//! the `/model` 1M-context switch). The rows that only carry those parse to
//! nothing here.
//!
//! Unicode: Swift compares `Character`s (grapheme clusters); this compares
//! `char`s (scalar values).

use serde_json::{Map, Value};

use crate::model_label::{self, ModelObservation};
use crate::reduce::Timestamp;
use crate::session_recap::SessionRecap;

// MARK: - Model

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ConversationTurnStatus {
    Processing,
    Idle,
}

/// Trailing-question state derived from a Cursor `role`-keyed transcript.
///
/// Cursor's AskQuestion tool has no hook channel: the question is asked and
/// answered inside Cursor's own UI. The only observable signal is the
/// transcript — the asking assistant entry ends the file until the user
/// answers, at which point newer entries are appended.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CursorQuestionSignal {
    /// The newest transcript entry asks a question that has not been answered.
    /// `prompt` is the extracted question text; empty when the tool call was
    /// recognized but its arguments carried no extractable text.
    Pending { prompt: String },
    /// A newer user/assistant entry exists, so no question is pending.
    Cleared,
}

/// What one chunk of transcript bytes updated.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ScanDelta {
    pub last_user_prompt: Option<String>,
    pub last_assistant_message: Option<String>,
    pub turn_status: Option<ConversationTurnStatus>,
    pub has_activity: bool,
    pub cursor_question: Option<CursorQuestionSignal>,
    /// The newest `away_summary` no later prompt in the chunk superseded.
    pub session_recap: Option<SessionRecap>,
    /// Model / reasoning effort of the newest main-thread turn in the chunk.
    pub model_observation: Option<ModelObservation>,
    /// A `/model` switch in the chunk turned the 1M context variant on or off.
    pub configured_long_context: Option<bool>,
}

impl ScanDelta {
    /// A delta only carries signal when at least one field is set.
    pub fn is_empty(&self) -> bool {
        self.last_user_prompt.is_none()
            && self.last_assistant_message.is_none()
            && self.turn_status.is_none()
            && !self.has_activity
            && self.cursor_question.is_none()
            && self.session_recap.is_none()
            && self.model_observation.is_none()
            && self.configured_long_context.is_none()
    }

    /// Lines are applied in file order, so a prompt seen after a recap in the
    /// same chunk means the recap is already stale (Swift's `didSet`).
    fn set_user_prompt(&mut self, prompt: String) {
        self.last_user_prompt = Some(prompt);
        self.session_recap = None;
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct ScanResult {
    pub delta: ScanDelta,
    /// Bytes after the final newline: the caller prepends them to the next
    /// chunk.
    pub trailing_fragment: Vec<u8>,
}

// MARK: - Reading a chunk

/// Split the given byte blob on newline boundaries and surface the latest user
/// / assistant text observed.
pub fn scan_lines(data: &[u8]) -> ScanResult {
    scan_lines_at(data, Timestamp(0.0))
}

/// [`scan_lines`], with the clock a recap without its own `timestamp` falls
/// back to (Swift's `observedAt` defaults to `Date()`). The CLI always writes
/// one, so this only matters for synthetic rows; [`scan_lines`] passes the
/// epoch because the core reads no clock.
pub fn scan_lines_at(data: &[u8], observed_at: Timestamp) -> ScanResult {
    let mut delta = ScanDelta::default();
    let mut line_start = 0;
    for (index, byte) in data.iter().enumerate() {
        if *byte != b'\n' {
            continue;
        }
        let line = &data[line_start..index];
        if !line.is_empty() {
            apply(line, &mut delta, observed_at);
        }
        line_start = index + 1;
    }
    ScanResult {
        delta,
        trailing_fragment: data[line_start..].to_vec(),
    }
}

/// The most recent turn state in a transcript blob.
pub fn latest_turn_status(data: &[u8]) -> Option<ConversationTurnStatus> {
    scan_lines(data).delta.turn_status
}

/// The trailing Cursor question state in a transcript blob, or `None` when the
/// blob held no role-keyed user/assistant entries at all.
pub fn latest_cursor_question(data: &[u8]) -> Option<CursorQuestionSignal> {
    scan_lines(data).delta.cursor_question
}

/// An attach-time scan of a transcript's tail, plus where it stopped.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct AttachScan {
    pub delta: ScanDelta,
    /// Just past the last complete line when the scan ran: hand it to
    /// [`TailState::at_offset`] so every line is read exactly once. A line
    /// still being written, or appended after the scan, belongs to the live
    /// tail.
    pub end_offset: u64,
}

/// The backfill scan over the file's last bytes: `tail` is what the platform
/// read from `tail_start` (one byte before the window, so the window's first
/// line can be told apart from a cut one) to `size`.
pub fn scan_tail_for_attach(tail: &[u8], tail_start: u64, size: u64) -> AttachScan {
    let mut first_line = 0usize;
    if tail_start > 0 {
        // The window's first line is cut unless the byte before it ended one.
        // No newline at all: the window sits inside one huge row (a tool
        // result) — nothing to scan, and the tailer starts at the end.
        let Some(boundary) = tail.iter().position(|byte| *byte == b'\n') else {
            return AttachScan {
                delta: ScanDelta::default(),
                end_offset: size,
            };
        };
        first_line = boundary + 1;
    }
    // The tailer starts after the last newline. The unterminated rest is either
    // a row still being written (it fails to parse here, and the tailer
    // completes it) or a writer that never ends its last row with a newline
    // (Cursor), whose row is parsed now and again once terminated — harmless
    // for these idempotent fields.
    let end_offset = tail
        .iter()
        .rposition(|byte| *byte == b'\n')
        .map_or(tail_start, |index| tail_start + index as u64 + 1);
    let mut window = tail[first_line..].to_vec();
    window.push(b'\n');
    AttachScan {
        delta: scan_lines(&window).delta,
        end_offset,
    }
}

// MARK: - The reading position

/// One attachment's position: a byte offset into the file, the fragment being
/// carried in memory, and whether the next read replays a replaced file.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct TailState {
    offset: u64,
    fragment: Vec<u8>,
    replay_pending: bool,
}

/// A delta and whether it re-reads a replaced file from its start — the new
/// file's history, not things that just happened.
#[derive(Clone, Debug, PartialEq)]
pub struct TailDelta {
    pub delta: ScanDelta,
    pub replays_whole_file: bool,
}

impl TailState {
    /// Attach at the end of a file of `size` bytes: what is already there
    /// belongs to the caller's backfill, and only what follows is news.
    pub fn at_end(size: u64) -> Self {
        Self {
            offset: size,
            ..Self::default()
        }
    }

    /// Attach at `offset` — where the caller's own backfill stopped — so the
    /// bytes written in the gap are read at once rather than on the next
    /// write. A file shorter than `offset` reads as a truncation on the next
    /// [`truncated`](Self::truncated).
    pub fn at_offset(offset: u64) -> Self {
        Self {
            offset,
            ..Self::default()
        }
    }

    pub fn offset(&self) -> u64 {
        self.offset
    }

    /// The file was rotated or replaced (a `/clear`, a new session on the same
    /// path): start again at byte 0, and replay `size` bytes of history once
    /// when the replacement already has any.
    pub fn replaced(&mut self, size: u64) {
        self.offset = 0;
        self.fragment.clear();
        // An empty replacement has no history; what it gets next is news.
        self.replay_pending = size > 0;
    }

    /// The file is shorter than the offset: it was truncated, so rewind and
    /// pick up the new prefix.
    pub fn truncated(&mut self) {
        self.offset = 0;
        self.fragment.clear();
    }

    /// Take the bytes just read from [`offset`](Self::offset); `None` when
    /// they carry no signal.
    pub fn receive(&mut self, appended: &[u8]) -> Option<TailDelta> {
        let replays_whole_file = self.replay_pending;
        self.replay_pending = false;

        let mut combined = std::mem::take(&mut self.fragment);
        combined.extend_from_slice(appended);
        let scan = scan_lines(&combined);
        self.fragment = scan.trailing_fragment;
        // Advance by the bytes actually read from disk — the trailing fragment
        // is carried purely in memory and its file bytes are already consumed
        // here. Mixing the fragment into the offset math drifts the offset past
        // EOF after every fragment episode; the next small append then looks
        // like a truncation and re-scans the whole file from byte 0 on each
        // event, pinning a core on overnight-grown transcripts.
        self.offset += appended.len() as u64;

        if scan.delta.is_empty() {
            return None;
        }
        Some(TailDelta {
            delta: scan.delta,
            replays_whole_file,
        })
    }
}

// MARK: - One line

fn apply(line: &[u8], delta: &mut ScanDelta, observed_at: Timestamp) {
    // Fast path: realistic Claude transcripts are ~75% tool_use / tool_result /
    // meta rows we don't care about. Skipping the JSON parse for those saves a
    // measurable chunk of CPU per byte during streaming bursts.
    if quick_type_probe(line) == QuickTypeKind::Irrelevant {
        return;
    }
    let Ok(json) = serde_json::from_slice::<Value>(line) else {
        return;
    };
    let Some(root) = json.as_object() else {
        return;
    };
    if root.get("isMeta") == Some(&Value::Bool(true)) {
        return;
    }

    let payload = root.get("payload").and_then(Value::as_object);
    let message = root
        .get("message")
        .and_then(Value::as_object)
        .or(payload)
        .unwrap_or(root);
    // Re-verify the type after a real parse — the byte probe can be fooled by
    // nested content that happens to contain the literal `"type":"assistant"`.
    let kind = root.get("type").and_then(Value::as_str).or_else(|| {
        payload
            .and_then(|payload| payload.get("type"))
            .and_then(Value::as_str)
    });

    match kind {
        Some("user" | "USER_INPUT") => {
            if let Some(text) = extract_text(message.get("content")) {
                if text.contains("[Request interrupted by user]")
                    || text.contains("interrupted by user")
                    || text.contains("Request was cancelled")
                {
                    delta.turn_status = Some(ConversationTurnStatus::Idle);
                }
                match claude_command_echo(&text) {
                    Some(ClaudeCommandEcho::Local) => {
                        // /model, /effort, /clear…: no turn, so no new prompt —
                        // and no reason to drop the recap. /model's output is
                        // the only record of a switch to or from the 1M
                        // variant; a model seen earlier in the chunk predates
                        // it.
                        if let Some(long_context) = model_label::long_context_switch(&text) {
                            delta.configured_long_context = Some(long_context);
                            delta.model_observation = None;
                        }
                    }
                    Some(ClaudeCommandEcho::Prompt(command)) => delta.set_user_prompt(command),
                    None => delta.set_user_prompt(text),
                }
            }
        }
        Some("assistant" | "PLANNER_RESPONSE") => {
            let stop_reason = message
                .get("stop_reason")
                .and_then(Value::as_str)
                .or_else(|| root.get("stop_reason").and_then(Value::as_str))
                .map(str::to_lowercase);
            if let Some(reason) = stop_reason {
                if reason.contains("interrupt") || reason.contains("cancel") || reason == "abort" {
                    delta.turn_status = Some(ConversationTurnStatus::Idle);
                }
            }
            if let Some(text) = extract_text(message.get("content")) {
                delta.last_assistant_message = Some(text);
            } else if let Some(thinking) = message.get("thinking").and_then(Value::as_str) {
                let trimmed = thinking.trim();
                if !trimmed.is_empty() {
                    delta.last_assistant_message = Some(trimmed.to_owned());
                }
            }
            // Claude: `message.model` + top-level effort. Sidechain lines are a
            // subagent's turns (older CLIs inlined them in the parent file) and
            // must not relabel the parent with the subagent's model.
            if root.get("isSidechain") != Some(&Value::Bool(true)) {
                if let Some(observation) = ModelObservation::from_values(
                    message.get("model"),
                    root.get("perTurnEffort").or_else(|| root.get("effort")),
                    root.get("timestamp"),
                ) {
                    delta.model_observation = Some(observation);
                }
            }
        }
        Some("system") => {
            // Claude Code's idle recap; other system subtypes carry nothing we
            // show.
            if let Some(recap) = SessionRecap::from_transcript_line(root, observed_at) {
                delta.session_recap = Some(recap);
            }
        }
        Some("turn_context") => {
            // Codex writes the turn's model and effort once per turn.
            if let Some(observation) = ModelObservation::from_codex_turn_context(root) {
                delta.model_observation = Some(observation);
            }
        }
        Some("event_msg") => {
            delta.has_activity = true;
            let Some(payload) = payload else {
                return;
            };
            let Some(event_type) = payload.get("type").and_then(Value::as_str) else {
                return;
            };
            if let Some(text) = codex_public_assistant_text(root) {
                delta.last_assistant_message = Some(text);
            }
            match event_type {
                "task_started" => {
                    delta.last_assistant_message = None;
                    delta.turn_status = Some(ConversationTurnStatus::Processing);
                }
                "user_message" => {
                    delta.last_assistant_message = None;
                    if let Some(message) = normalized_text(payload.get("message")) {
                        delta.set_user_prompt(message);
                    }
                }
                // "turn_failed" is not in today's codex EventMsg enum — kept as
                // a forward-compatible guess at the obvious name for a failed
                // turn.
                "task_complete" | "turn_aborted" | "turn_failed" => {
                    delta.turn_status = Some(ConversationTurnStatus::Idle);
                }
                _ => {}
            }
        }
        Some("response_item") => {
            delta.has_activity = true;
            if let Some(text) = codex_public_assistant_text(root) {
                delta.last_assistant_message = Some(text);
            }
        }
        Some("tool_call") => delta.has_activity = true,
        Some("turn_start") => delta.turn_status = Some(ConversationTurnStatus::Processing),
        _ => {
            // Cursor agent transcripts key their entries on a top-level `role`
            // instead of `type`. Restrict the branch to lines with no `type` at
            // all so type-keyed formats never route here.
            if kind.is_none() {
                if let Some(role) = root.get("role").and_then(Value::as_str) {
                    apply_cursor_role_line(role, message, delta);
                }
            }
        }
    }
}

/// Handle one Cursor `role`-keyed transcript entry.
fn apply_cursor_role_line(role: &str, message: &Map<String, Value>, delta: &mut ScanDelta) {
    match role {
        "user" => {
            delta.cursor_question = Some(CursorQuestionSignal::Cleared);
            if let Some(text) = normalized_cursor_chat_text(message.get("content")) {
                delta.set_user_prompt(text);
            }
        }
        "assistant" => {
            delta.cursor_question = Some(match cursor_question_prompt(message.get("content")) {
                Some(prompt) => CursorQuestionSignal::Pending { prompt },
                None => CursorQuestionSignal::Cleared,
            });
            if let Some(text) = normalized_cursor_chat_text(message.get("content")) {
                delta.last_assistant_message = Some(text);
            }
        }
        _ => {}
    }
}

// MARK: - Claude command echoes

/// How Claude Code records a slash command typed in the terminal.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ClaudeCommandEcho {
    /// A built-in the CLI handles itself (/model, /effort, /clear, /compact)
    /// or that command's output: no turn, so not a prompt.
    Local,
    /// A prompt command (skill, custom command) that does start a turn, as the
    /// user typed it: "/design tidy the layout".
    Prompt(String),
}

const LOCAL_COMMAND_TAGS: &[&str] = &[
    "<command-name>",
    "<local-command-stdout>",
    "<local-command-stderr>",
    "<local-command-caveat>",
];

/// Classify a user row's text as a slash-command echo, or `None` for an
/// ordinary prompt.
pub fn claude_command_echo(text: &str) -> Option<ClaudeCommandEcho> {
    let trimmed = text.trim_start();
    if !trimmed.starts_with('<') {
        return None;
    }
    if LOCAL_COMMAND_TAGS
        .iter()
        .any(|tag| trimmed.starts_with(tag))
    {
        return Some(ClaudeCommandEcho::Local);
    }
    if !trimmed.starts_with("<command-message>") {
        return None;
    }
    let mut name = tagged_value("command-name", trimmed).filter(|name| !name.is_empty())?;
    if !name.starts_with('/') {
        name = format!("/{name}");
    }
    let args = tagged_value("command-args", trimmed).unwrap_or_default();
    Some(ClaudeCommandEcho::Prompt(if args.is_empty() {
        name
    } else {
        format!("{name} {args}")
    }))
}

fn tagged_value(tag: &str, text: &str) -> Option<String> {
    let open = format!("<{tag}>");
    let close = format!("</{tag}>");
    let start = text.find(&open)? + open.len();
    let end = text[start..].find(&close)? + start;
    Some(text[start..end].trim().to_owned())
}

// MARK: - Codex

/// Extract assistant text that Codex deliberately persists for display. Raw or
/// encrypted reasoning and every response-item `agent_message` are excluded:
/// the latter may be inter-agent traffic.
pub fn codex_public_assistant_text(json: &Map<String, Value>) -> Option<String> {
    let kind = json.get("type").and_then(Value::as_str)?;
    let payload = json.get("payload").and_then(Value::as_object)?;
    let payload_type = payload.get("type").and_then(Value::as_str)?;

    if kind == "event_msg" && payload_type == "agent_message" {
        return normalized_text(payload.get("message"));
    }
    if kind != "response_item" {
        return None;
    }
    if payload_type == "message" && payload.get("role").and_then(Value::as_str) == Some("assistant")
    {
        return codex_text_blocks(payload.get("content"), &["output_text"]);
    }
    None
}

fn codex_text_blocks(value: Option<&Value>, accepted_types: &[&str]) -> Option<String> {
    let blocks = value?.as_array()?;
    let parts: Vec<String> = blocks
        .iter()
        .filter_map(|block| {
            let block = block.as_object()?;
            let kind = block.get("type").and_then(Value::as_str)?;
            if !accepted_types.contains(&kind) {
                return None;
            }
            normalized_text(block.get("text"))
        })
        .collect();
    (!parts.is_empty()).then(|| parts.join("\n"))
}

fn normalized_text(value: Option<&Value>) -> Option<String> {
    let text = value?.as_str()?.trim();
    (!text.is_empty()).then(|| text.to_owned())
}

// MARK: - Cursor

/// Strip Cursor transcript wrappers so hook and transcript copies can dedupe.
pub fn normalized_cursor_chat_text(content: Option<&Value>) -> Option<String> {
    let mut text = extract_text(content)?;
    while let Some(start) = text.find("<timestamp>") {
        let Some(end) = text[start..].find("</timestamp>") else {
            break;
        };
        let end = start + end + "</timestamp>".len();
        text.replace_range(start..end, "");
    }
    if let Some(start) = text.find("<user_query>") {
        if let Some(end) = text[start..].find("</user_query>") {
            text = text[start + "<user_query>".len()..start + end].to_owned();
        }
    }
    let trimmed = text.trim();
    (!trimmed.is_empty()).then(|| trimmed.to_owned())
}

/// Extract the question text when a Cursor assistant `content` array carries a
/// blocking question tool call. `None` when the entry asks no question
/// (including `run_async` questions, which don't block the agent); an empty
/// string means "a question is pending but its text could not be extracted".
pub fn cursor_question_prompt(content: Option<&Value>) -> Option<String> {
    let blocks = content?.as_array()?;
    for block in blocks {
        let Some(block) = block.as_object() else {
            continue;
        };
        if block.get("type").and_then(Value::as_str) != Some("tool_use") {
            continue;
        }
        let Some(name) = block.get("name").and_then(Value::as_str) else {
            continue;
        };
        if !is_cursor_question_tool_name(name) {
            continue;
        }
        let input = block.get("input").and_then(Value::as_object);
        // Async questions let the agent keep working — not a blocking wait. The
        // args casing follows the model-facing schema, observed as both
        // snake_case and camelCase across tool versions.
        let is_async = |key: &str| {
            input
                .and_then(|input| input.get(key))
                .and_then(Value::as_bool)
                == Some(true)
        };
        if is_async("run_async") || is_async("runAsync") {
            continue;
        }
        return Some(cursor_question_text(input));
    }
    None
}

/// True when `name` is Cursor's question tool, matched loosely (case- and
/// separator-insensitive) because the transcript records the model-facing tool
/// name, which Cursor has renamed across releases.
pub fn is_cursor_question_tool_name(name: &str) -> bool {
    let normalized = name.to_lowercase().replace(['_', '-'], "");
    matches!(
        normalized.as_str(),
        "askquestion" | "askquestions" | "askuserquestion" | "askfollowupquestion"
    )
}

/// Compose display text from AskQuestion tool args:
/// `{title, questions: [{id, prompt, options, allow_multiple}]}`. Prefers the
/// first question's prompt (with a numeric `(+N)` suffix when more follow),
/// falls back to the title, then to a flat `question`/`prompt` field, and
/// finally to "" so the caller still knows a question is pending.
fn cursor_question_text(input: Option<&Map<String, Value>>) -> String {
    let Some(input) = input else {
        return String::new();
    };

    let mut prompts: Vec<String> = Vec::new();
    if let Some(questions) = input.get("questions").and_then(Value::as_array) {
        for question in questions {
            let raw = question
                .get("prompt")
                .or_else(|| question.get("question"))
                .and_then(Value::as_str);
            if let Some(text) = raw.map(str::trim).filter(|text| !text.is_empty()) {
                prompts.push(text.to_owned());
            }
        }
    }
    if let Some(first) = prompts.first() {
        return if prompts.len() > 1 {
            format!("{first} (+{})", prompts.len() - 1)
        } else {
            first.clone()
        };
    }
    if let Some(title) = input
        .get("title")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|title| !title.is_empty())
    {
        return title.to_owned();
    }
    // Forward-compatible flat shape.
    input
        .get("question")
        .or_else(|| input.get("prompt"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|text| !text.is_empty())
        .map(str::to_owned)
        .unwrap_or_default()
}

// MARK: - Text extraction

/// Concatenate every `text` block from a Claude-style `content` value. Accepts
/// either a bare string or an array of content blocks.
pub fn extract_text(content: Option<&Value>) -> Option<String> {
    let content = content?;
    if let Some(raw) = content.as_str() {
        let text = strip_display_wrappers(raw);
        if is_thinking_blob(&text) {
            return None;
        }
        let trimmed = text.trim();
        return (!trimmed.is_empty()).then(|| trimmed.to_owned());
    }
    if let Some(blocks) = content.as_array() {
        let mut parts: Vec<String> = Vec::new();
        for block in blocks {
            let Some(block) = block.as_object() else {
                continue;
            };
            if block.get("type").and_then(Value::as_str) != Some("text") {
                continue;
            }
            let Some(raw) = block.get("text").and_then(Value::as_str) else {
                continue;
            };
            // The compatible export writes the reasoning pass as a TEXT block
            // whose content is a {"type":"thinking",…} JSON string — skip it so
            // the public reply is the only thing on the card.
            if is_thinking_blob(raw) {
                continue;
            }
            let trimmed = strip_display_wrappers(raw).trim().to_owned();
            if !trimmed.is_empty() {
                parts.push(trimmed);
            }
        }
        return (!parts.is_empty()).then(|| parts.join("\n"));
    }
    None
}

/// Remove transcript wrappers the user never typed that some CLIs embed inside
/// message text: Codex's `<USER_REQUEST>` (everything outside is dropped) and
/// leading `<system-reminder>` spans. Only spans that open the text are
/// injected; a tag someone quotes mid-message is content and stays.
pub fn strip_display_wrappers(raw: &str) -> String {
    let mut text = raw.to_owned();
    if let Some(start) = text.find("<USER_REQUEST>") {
        let open = start + "<USER_REQUEST>".len();
        if let Some(end) = text[open..].find("</USER_REQUEST>") {
            text = text[open..open + end].to_owned();
        }
    }
    while let Some(start) = text.find(|c: char| !c.is_whitespace()) {
        if !text[start..].starts_with("<system-reminder>") {
            break;
        }
        let Some(end) = text[start..].find("</system-reminder>") else {
            break;
        };
        let end = start + end + "</system-reminder>".len();
        text.replace_range(..end, "");
    }
    text
}

/// Detect a reasoning pass disguised as display text: a text block whose
/// content is the JSON string
/// `{"type":"thinking","thinking":"…","thinkingSignature":"…"}`. A real
/// user/assistant message is never this shape.
pub fn is_thinking_blob(text: &str) -> bool {
    let trimmed = text.trim();
    if !trimmed.starts_with('{') || !trimmed.ends_with('}') {
        return false;
    }
    let Ok(Value::Object(object)) = serde_json::from_str::<Value>(trimmed) else {
        return false;
    };
    let type_is_thinking = object
        .get("type")
        .and_then(Value::as_str)
        .is_some_and(|kind| kind.to_lowercase().contains("thinking"));
    if !type_is_thinking && !object.contains_key("thinkingSignature") {
        return false;
    }
    object.get("thinking").is_some_and(Value::is_string)
}

// MARK: - Fast path

/// Types the panel cares about; `irrelevant` skips the JSON parser entirely.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum QuickTypeKind {
    User,
    Assistant,
    CodexEvent,
    CodexResponseItem,
    /// A line with no interesting `type` but a leading `"role":"user|assistant"`
    /// marker (Cursor's transcript shape).
    CursorRole,
    /// Claude `system` line whose subtype is `away_summary` (session recap).
    ClaudeRecap,
    /// Codex `turn_context` (the turn's model + reasoning effort).
    CodexTurnContext,
    KiroTool,
    Irrelevant,
}

const TYPE_MARKER: &[u8] = b"\"type\":\"";
const ROLE_MARKER: &[u8] = b"\"role\":\"";
const USER_BYTES: &[u8] = b"user\"";
const ASSISTANT_BYTES: &[u8] = b"assistant\"";
const USER_INPUT_BYTES: &[u8] = b"USER_INPUT\"";
const PLANNER_RESPONSE_BYTES: &[u8] = b"PLANNER_RESPONSE\"";
const EVENT_MSG_BYTES: &[u8] = b"event_msg\"";
const RESPONSE_ITEM_BYTES: &[u8] = b"response_item\"";
const TOOL_CALL_BYTES: &[u8] = b"tool_call\"";
const SYSTEM_BYTES: &[u8] = b"system\"";
const TURN_CONTEXT_BYTES: &[u8] = b"turn_context\"";
const AWAY_SUMMARY_MARKER: &[u8] = b"\"subtype\":\"away_summary\"";
const CODEX_MESSAGE_PAYLOAD_MARKER: &[u8] = b"\"payload\":{\"type\":\"message\",";
const CODEX_ASSISTANT_ROLE_MARKER: &[u8] = b"\"role\":\"assistant\"";
const CODEX_OUTPUT_TEXT_MARKER: &[u8] = b"\"type\":\"output_text\"";
const CODEX_PLAN_UPDATE_MARKER: &[u8] = b"\"name\":\"update_plan\"";

/// How much of a long row the probe looks at before giving up.
const PROBE_PREFIX: usize = 4096;

/// Byte-scan the line for every `"type":"` occurrence and peek at the value. A
/// single pass that gives up as soon as it sees a value it does not care
/// about, letting the caller skip the JSON parser entirely.
pub fn quick_type_probe(line: &[u8]) -> QuickTypeKind {
    let total = line.len();
    if total < TYPE_MARKER.len() + 2 {
        return QuickTypeKind::Irrelevant;
    }
    let marker_length = TYPE_MARKER.len();
    let mut index = 0;
    // Every `"type":"..."` occurrence in the line gets checked, not only the
    // first — a JSON object may carry nested `"type":"text"` rows before the
    // outer type we care about.
    while index + marker_length <= total {
        if &line[index..index + marker_length] != TYPE_MARKER {
            index += 1;
            continue;
        }
        let value_start = index + marker_length;
        if value_start < total {
            match line[value_start] {
                b'u' if has_exact_value(line, value_start, USER_BYTES) => {
                    return QuickTypeKind::User;
                }
                b'U' if has_exact_value(line, value_start, USER_INPUT_BYTES) => {
                    return QuickTypeKind::User;
                }
                b'a' if has_exact_value(line, value_start, ASSISTANT_BYTES) => {
                    return QuickTypeKind::Assistant;
                }
                b'P' if has_exact_value(line, value_start, PLANNER_RESPONSE_BYTES) => {
                    return QuickTypeKind::Assistant;
                }
                b'e' if has_exact_value(line, value_start, EVENT_MSG_BYTES) => {
                    return QuickTypeKind::CodexEvent;
                }
                b'r' if has_exact_value(line, value_start, RESPONSE_ITEM_BYTES) => {
                    // Keep large tool results on the no-parse path: only the
                    // compact public-message shapes (and the plan-update calls
                    // that carry activity) reach the JSON parser.
                    return if is_codex_public_response_candidate(line)
                        || contains_marker(line, CODEX_PLAN_UPDATE_MARKER)
                    {
                        QuickTypeKind::CodexResponseItem
                    } else {
                        QuickTypeKind::Irrelevant
                    };
                }
                b's' => {
                    // Only the recap subtype earns a parse; turn_duration /
                    // stop_hook_summary rows stay on the skip path. The subtype
                    // sits right after `type`, so a bounded probe keeps an
                    // unusually long system row O(1) here.
                    if has_exact_value(line, value_start, SYSTEM_BYTES)
                        && contains_marker(
                            &line[..line.len().min(PROBE_PREFIX)],
                            AWAY_SUMMARY_MARKER,
                        )
                    {
                        return QuickTypeKind::ClaudeRecap;
                    }
                }
                b't' => {
                    if has_exact_value(line, value_start, TURN_CONTEXT_BYTES) {
                        return QuickTypeKind::CodexTurnContext;
                    }
                    if has_exact_value(line, value_start, TOOL_CALL_BYTES) {
                        return QuickTypeKind::KiroTool;
                    }
                }
                _ => {}
            }
        }
        // Skip past this marker and keep looking — nested objects often carry
        // their own `type` key we don't care about.
        index = value_start + 1;
    }

    // No interesting `type` value — check for Cursor's `role`-keyed shape
    // before giving up. Its writer serializes `{role, message}` with `role` as
    // the first key, so a prefix check suffices; scanning the whole line would
    // misroute the bulk of Codex rollouts (their `response_item` lines carry a
    // nested `"role":"assistant"`) into the JSON parser.
    let role_length = ROLE_MARKER.len();
    if total > role_length + 1 && line[0] == b'{' && &line[1..1 + role_length] == ROLE_MARKER {
        let value_start = 1 + role_length;
        if has_exact_value(line, value_start, USER_BYTES)
            || has_exact_value(line, value_start, ASSISTANT_BYTES)
        {
            return QuickTypeKind::CursorRole;
        }
    }
    QuickTypeKind::Irrelevant
}

/// Only response items with the compact public-message shapes emitted by Codex
/// earn a parse. Model output carries a Responses API id between `type` and
/// `role`, so the three markers are matched independently rather than as one
/// contiguous run. Quotes inside string values are escaped, so a user message
/// quoting `"role":"assistant"` cannot match; `apply` re-checks the parsed role.
fn is_codex_public_response_candidate(line: &[u8]) -> bool {
    let prefix = &line[..line.len().min(PROBE_PREFIX)];
    contains_marker(prefix, CODEX_MESSAGE_PAYLOAD_MARKER)
        && contains_marker(prefix, CODEX_ASSISTANT_ROLE_MARKER)
        && contains_marker(prefix, CODEX_OUTPUT_TEXT_MARKER)
}

fn contains_marker(line: &[u8], marker: &[u8]) -> bool {
    !marker.is_empty()
        && line.len() >= marker.len()
        && line.windows(marker.len()).any(|window| window == marker)
}

fn has_exact_value(line: &[u8], start: usize, expect: &[u8]) -> bool {
    line.len() >= start + expect.len() && &line[start..start + expect.len()] == expect
}
