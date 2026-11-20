//! Claude Code's "while you were away" recap (`SessionRecap`,
//! `Sources/MorrowCore/SessionRecap.swift`).
//!
//! A few minutes after a turn goes idle Claude Code appends
//! `{"type":"system","subtype":"away_summary","content":"…","timestamp":"…"}`
//! to the transcript: one or two sentences on what got done and what is
//! waiting on the user. The card shows it on idle cards until a newer user
//! prompt starts another turn.

use serde_json::{Map, Value};

use crate::reduce::Timestamp;
use crate::time::parse_iso8601;

#[derive(Clone, Debug, PartialEq)]
pub struct SessionRecap {
    pub text: String,
    /// When Claude Code wrote the recap (the line's `timestamp`), falling back
    /// to the moment it was observed (the caller's clock).
    pub created_at: Timestamp,
}

impl SessionRecap {
    pub fn new(text: impl Into<String>, created_at: Timestamp) -> Self {
        Self {
            text: text.into(),
            created_at,
        }
    }

    /// A prompt submitted at or after the recap was written starts a new turn.
    pub fn is_superseded(&self, prompt_at: Timestamp) -> bool {
        prompt_at.0 >= self.created_at.0
    }

    /// Build from a parsed transcript line, or `None` when it is not a usable
    /// main-thread `away_summary`.
    pub fn from_transcript_line(json: &Map<String, Value>, observed_at: Timestamp) -> Option<Self> {
        if json.get("subtype").and_then(Value::as_str) != Some("away_summary") {
            return None;
        }
        if json.get("isSidechain") == Some(&Value::Bool(true)) {
            return None;
        }
        let text = Self::cleaned_text(json.get("content"))?;
        let created_at = json
            .get("timestamp")
            .and_then(Value::as_str)
            .and_then(parse_iso8601)
            .unwrap_or(observed_at);
        Some(Self { text, created_at })
    }

    /// Trim the raw `content` and drop the "(disable recaps in /config)" hint
    /// the CLI appends for its own TUI — an instruction for the terminal, not
    /// part of the summary. Matched on "/config" inside a trailing
    /// parenthetical so other CLI languages and wordings are covered too.
    pub fn cleaned_text(raw: Option<&Value>) -> Option<String> {
        let mut text = raw?.as_str()?.trim().to_owned();
        if text.is_empty() {
            return None;
        }
        if text.ends_with(')') {
            if let Some(open) = text.rfind('(') {
                if text[open..].contains("/config") {
                    text = text[..open].trim().to_owned();
                }
            }
        }
        (!text.is_empty()).then_some(text)
    }
}
