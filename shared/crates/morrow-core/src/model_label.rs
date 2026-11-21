//! The model tag on a session card (`ModelObservation`, `ModelLabel`,
//! `Sources/MorrowCore/ModelLabel.swift`): the model and reasoning effort a
//! transcript line reported, and the friendly name the card shows
//! ("Opus 5.5 · xhigh", "Opus 5.5 1M").
//!
//! They travel as a pair because the effort belongs to that turn's model: a
//! turn that switched to a model without an effort setting drops the old
//! effort instead of keeping it.

use serde_json::{Map, Value};

use crate::reduce::Timestamp;
use crate::time::parse_iso8601;

/// Newest assistant model/effort in a Claude transcript blob, sidechain lines
/// included — for a subagent's own transcript, where every line is a sidechain
/// line. (The live tailer skips sidechain lines on purpose: in a parent
/// transcript they belong to someone else.)
pub fn latest_in_claude_transcript(data: &[u8]) -> Option<ModelObservation> {
    let marker = b"\"type\":\"assistant\"";
    for line in data.split(|byte| *byte == b'\n').rev() {
        if !contains(line, marker) {
            continue;
        }
        let Ok(Value::Object(json)) = serde_json::from_slice::<Value>(line) else {
            continue;
        };
        if json.get("type").and_then(Value::as_str) != Some("assistant") {
            continue;
        }
        let message = json.get("message").and_then(Value::as_object);
        let observation = ModelObservation::from_values(
            message.and_then(|message| message.get("model")),
            json.get("perTurnEffort").or_else(|| json.get("effort")),
            None,
        );
        if let Some(observation) = observation {
            return Some(observation);
        }
    }
    None
}

/// The last `turn_context` in a Codex rollout within the last `max_bytes` of
/// `data`, searched backwards in `chunk_size` pieces before `end` (default:
/// the end of the blob).
///
/// A fixed tail window is not enough: a forked child thread opens with a copy
/// of its parent's history, and a long turn's tool output can push the turn's
/// one `turn_context` far back. Rows are only parsed when they carry the
/// marker. The platform hands in the bytes; the core reads no file.
pub fn latest_codex_turn_context(
    data: &[u8],
    end: Option<u64>,
    max_bytes: u64,
    chunk_size: u64,
) -> Option<ModelObservation> {
    if chunk_size == 0 {
        return None;
    }
    let size = data.len() as u64;
    let end = end.map_or(size, |end| end.min(size));
    let mut chunk_end = end;
    let floor = end.saturating_sub(max_bytes);
    // Head of the region already searched: the tail of a row that began in an
    // earlier chunk (its newline excluded).
    let mut carry: Vec<u8> = Vec::new();
    while chunk_end > floor {
        let chunk_start = floor.max(chunk_end.saturating_sub(chunk_size));
        let piece = data.get(chunk_start as usize..chunk_end as usize)?;
        let mut region = piece.to_vec();
        region.extend_from_slice(&carry);
        let mut rows: &[u8] = &region;
        if chunk_start > 0 {
            // Up to the first newline, the row may have started earlier.
            match region.iter().position(|byte| *byte == b'\n') {
                Some(newline) => {
                    carry = region[..newline].to_vec();
                    rows = &region[newline + 1..];
                }
                None => {
                    carry = region;
                    chunk_end = chunk_start;
                    continue;
                }
            }
        }
        if let Some(observation) = last_turn_context(rows) {
            return Some(observation);
        }
        chunk_end = chunk_start;
    }
    None
}

const TURN_CONTEXT_MARKER: &[u8] = b"\"type\":\"turn_context\"";

fn last_turn_context(rows: &[u8]) -> Option<ModelObservation> {
    if !contains(rows, TURN_CONTEXT_MARKER) {
        return None;
    }
    for row in rows.split(|byte| *byte == b'\n').rev() {
        if !contains(row, TURN_CONTEXT_MARKER) {
            continue;
        }
        let Ok(Value::Object(json)) = serde_json::from_slice::<Value>(row) else {
            continue;
        };
        if json.get("type").and_then(Value::as_str) != Some("turn_context") {
            continue;
        }
        if let Some(observation) = ModelObservation::from_codex_turn_context(&json) {
            return Some(observation);
        }
    }
    None
}

fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    !needle.is_empty()
        && haystack.len() >= needle.len()
        && haystack
            .windows(needle.len())
            .any(|window| window == needle)
}

/// Model + reasoning effort seen together on one transcript line.
///
/// Claude writes both on every assistant line (`message.model` and the
/// top-level `effort`); Codex on every `turn_context`.
#[derive(Clone, Debug)]
pub struct ModelObservation {
    pub model: String,
    pub effort: Option<String>,
    /// The transcript line's own `timestamp`, kept raw: it is only parsed
    /// ([`observed_at`](Self::observed_at)) by the attach-time backfill, never
    /// on the hot path.
    pub line_timestamp: Option<String>,
}

impl ModelObservation {
    pub fn new(model: impl Into<String>, effort: Option<String>) -> Self {
        Self {
            model: model.into(),
            effort,
            line_timestamp: None,
        }
    }

    /// When the line was written, if it said.
    pub fn observed_at(&self) -> Option<Timestamp> {
        self.line_timestamp.as_deref().and_then(parse_iso8601)
    }

    /// Build from raw transcript values; `None` for missing ids and
    /// placeholders such as Claude's `<synthetic>` (API-error stand-ins, not a
    /// real model).
    pub fn from_values(
        model: Option<&Value>,
        effort: Option<&Value>,
        timestamp: Option<&Value>,
    ) -> Option<Self> {
        let raw = model?.as_str()?;
        let trimmed = raw.trim();
        if trimmed.is_empty() || trimmed.starts_with('<') {
            return None;
        }
        Some(Self {
            model: trimmed.to_owned(),
            effort: normalised_effort(effort.and_then(Value::as_str)),
            line_timestamp: timestamp.and_then(Value::as_str).map(str::to_owned),
        })
    }

    /// Model and effort from a Codex `turn_context` line.
    pub fn from_codex_turn_context(json: &Map<String, Value>) -> Option<Self> {
        let payload = json.get("payload").and_then(Value::as_object)?;
        let settings = payload
            .get("collaboration_mode")
            .and_then(Value::as_object)
            .and_then(|mode| mode.get("settings"))
            .and_then(Value::as_object);
        Self::from_values(
            payload
                .get("model")
                .or_else(|| settings.and_then(|settings| settings.get("model"))),
            payload
                .get("effort")
                .or_else(|| settings.and_then(|settings| settings.get("reasoning_effort"))),
            json.get("timestamp"),
        )
    }
}

/// The same model and effort, whenever the line was written.
impl PartialEq for ModelObservation {
    fn eq(&self, other: &Self) -> bool {
        self.model == other.model && self.effort == other.effort
    }
}

impl Eq for ModelObservation {}

// MARK: - Labels

/// Friendly model / reasoning-effort label for session cards: Claude ids
/// become "Opus 5.5" / "Haiku 4.5", a `[1m]` context variant appends "1M",
/// every other id keeps its own spelling minus provider paths and date
/// stamps, and the effort rides along as a "· xhigh" suffix.
pub fn label(model: Option<&str>, effort: Option<&str>) -> Option<String> {
    let name = display_name(model)?;
    let Some(effort) = normalised_effort(effort) else {
        return Some(name);
    };
    Some(format!("{name} \u{00b7} {effort}"))
}

/// Display name for a raw model id, or `None` for empty ids and placeholders.
pub fn display_name(model: Option<&str>) -> Option<String> {
    let mut id = model?.trim().to_owned();
    if id.is_empty() || id.starts_with('<') {
        return None;
    }

    // Claude Code spells the long-context variant as a bracket suffix
    // ("claude-opus-5-5[1m]"); the API id in the transcript never has it.
    let mut context_tag: Option<String> = None;
    if id.ends_with(']') {
        if let Some(open) = id.rfind('[') {
            let inner = id[open + 1..id.len() - 1].trim();
            if !inner.is_empty() {
                context_tag = Some(inner.to_uppercase());
            }
            id = id[..open].trim().to_owned();
        }
    }

    let base = stripped_model_id(&id);
    if base.is_empty() {
        return None;
    }
    let name = claude_display_name(&base).unwrap_or(base);
    Some(match context_tag {
        Some(tag) => format!("{name} {tag}"),
        None => name,
    })
}

/// Lowercased effort, `None` when absent or blank.
pub fn normalised_effort(effort: Option<&str>) -> Option<String> {
    let trimmed = effort?.trim().to_lowercase();
    (!trimmed.is_empty()).then_some(trimmed)
}

/// Which model id to keep when a transcript reports `observed`.
///
/// The transcript always carries the bare API id, while hooks may report the
/// configured `[1m]` variant of the same model. Replacing it would silently
/// drop the "1M" tag every turn, so a decorated id of the same base survives;
/// anything else (a real /model switch) takes the observed id.
pub fn merged_model_id(current: Option<&str>, observed: &str) -> String {
    let Some(current) = current else {
        return observed.to_owned();
    };
    if current == observed {
        return observed.to_owned();
    }
    if !current.ends_with(']') {
        return observed.to_owned();
    }
    let Some(open) = current.rfind('[') else {
        return observed.to_owned();
    };
    if current[..open].trim() == observed {
        current.to_owned()
    } else {
        observed.to_owned()
    }
}

/// Whether `observed` names the model `current` already holds — the same id,
/// or the bare API id of `current`'s context variant.
pub fn is_same_model(current: Option<&str>, observed: &str) -> bool {
    match current {
        Some(current) => merged_model_id(Some(current), observed) == current,
        None => false,
    }
}

/// `id` with its context variant set explicitly: `[1m]` on, or no bracket
/// suffix at all.
pub fn with_long_context(id: &str, long_context: bool) -> String {
    let base = match (id.ends_with(']'), id.rfind('[')) {
        (true, Some(open)) => id[..open].trim(),
        _ => id.trim(),
    };
    if long_context {
        format!("{base}[1m]")
    } else {
        base.to_owned()
    }
}

/// What Claude Code's `/model` output says about the 1M context variant —
/// "Set model to `Opus 5 (1M context) (default)` and saved…" is true, "Set
/// model to Fable 5 and saved…" false — or `None` when the text is not a
/// model switch. (The display name is all it gives, not the id.)
pub fn long_context_switch(text: &str) -> Option<bool> {
    let lower = text.to_lowercase();
    if !lower.contains("set model to") {
        return None;
    }
    Some(lower.contains("1m context") || lower.contains("[1m]"))
}

// MARK: - Private shaping

/// Drop routing decoration that is not part of the model's name: provider
/// paths ("anthropic/…", "github-copilot/…"), Bedrock region/vendor prefixes
/// and version suffixes, Vertex "@date" suffixes, and trailing date stamps
/// ("-20251001", "-2024-08-06").
fn stripped_model_id(raw: &str) -> String {
    let mut id = raw.to_owned();
    if let Some(slash) = id.rfind('/') {
        if slash + 1 < id.len() {
            id = id[slash + 1..].to_owned();
        }
    }
    if let Some(vendor) = id.find("anthropic.") {
        id = id[vendor + "anthropic.".len()..].to_owned();
    }
    if let Some(at) = id.find('@') {
        id = id[..at].to_owned();
    }
    // Bedrock revision "-v1:0". Requires the colon so names that merely end in
    // a version ("deepseek-v3") keep it.
    if let Some(dash) = id.rfind("-v") {
        let tail = &id[dash + 2..];
        if tail.contains(':')
            && tail.starts_with(|c: char| c.is_ascii_digit())
            && tail.chars().all(|c| c.is_ascii_digit() || c == ':')
        {
            id = id[..dash].to_owned();
        }
    }
    stripping_date_suffix(&id)
}

fn stripping_date_suffix(id: &str) -> String {
    let mut parts: Vec<&str> = id.split('-').collect();
    if parts.len() <= 1 {
        return id.to_owned();
    }
    // "-YYYYMMDD"
    if let Some(last) = parts.last() {
        if last.len() == 8 && last.chars().all(|c| c.is_ascii_digit()) {
            parts.pop();
            return parts.join("-");
        }
    }
    // "-YYYY-MM-DD"
    if parts.len() > 3 {
        let tail = &parts[parts.len() - 3..];
        let lengths: Vec<usize> = tail.iter().map(|part| part.len()).collect();
        if lengths == [4, 2, 2]
            && tail
                .iter()
                .all(|part| part.chars().all(|c| c.is_ascii_digit()))
        {
            parts.truncate(parts.len() - 3);
            return parts.join("-");
        }
    }
    id.to_owned()
}

/// "claude-opus-5-5" → "Opus 5.5", "claude-3-5-sonnet" → "Sonnet 3.5", bare
/// aliases "opus" → "Opus". `None` when the id is not a Claude family id this
/// parser understands, so the caller falls back to the raw id.
fn claude_display_name(id: &str) -> Option<String> {
    let lower = id.to_lowercase();
    if CLAUDE_ALIASES.contains(&lower.as_str()) {
        return Some(capitalized(&lower));
    }
    let rest = lower.strip_prefix("claude-")?;

    let mut family: Option<&str> = None;
    let mut version: Vec<&str> = Vec::new();
    for part in rest.split('-') {
        if part.is_empty() {
            continue;
        }
        if is_version_component(part) {
            version.push(part);
        } else if family.is_none() && part.chars().all(char::is_alphabetic) {
            family = Some(part);
        } else {
            // Unknown suffix ("-thinking", a codename, …): don't guess.
            return None;
        }
    }
    let family = family?;
    if version.len() > 2 {
        return None;
    }
    let name = capitalized(family);
    Some(if version.is_empty() {
        name
    } else {
        format!("{name} {}", version.join("."))
    })
}

/// 1–2 digit numbers or dotted versions ("1.2"); 8-digit dates are already
/// stripped, so a long all-digit run here is not a version.
fn is_version_component(part: &str) -> bool {
    if part.is_empty() || !part.starts_with(|c: char| c.is_ascii_digit()) {
        return false;
    }
    if !part.chars().all(|c| c.is_ascii_digit() || c == '.') {
        return false;
    }
    part.contains('.') || part.chars().count() <= 2
}

fn capitalized(word: &str) -> String {
    let mut chars = word.chars();
    match chars.next() {
        Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
        None => String::new(),
    }
}

/// Claude Code's model aliases (`/model opus`); shown capitalized.
const CLAUDE_ALIASES: &[&str] = &["opus", "sonnet", "haiku", "fable"];
