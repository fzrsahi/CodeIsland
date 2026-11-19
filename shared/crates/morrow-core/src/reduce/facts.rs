//! What a hook event did, for the attention policy to read
//! (`HookEventFacts`, `Sources/MorrowCore/AttentionPolicy.swift`), and the
//! `PushEventClassifier` readings it is built from (`PushPolicy.swift`).

use serde_json::Value;

use super::hermes;
use super::hook_event::HookEvent;
use super::json;
use super::session_snapshot::SessionSnapshot;
use super::subsession::{is_cursor_family_source, is_likely_cursor_task_card};
use crate::JsonObject;
use crate::intake::SourceCatalog;
use crate::intake::event_normalizer::normalize;

/// `PushSessionError`: the error a turn stopped on.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PushSessionError {
    pub r#type: Option<String>,
    pub detail: Option<String>,
}

/// `HookEventFacts`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HookEventFacts {
    /// The event's name on the wire (`StopFailure`, `on_session_end`, …).
    pub raw_event_name: String,
    /// The island's name for it (`EventNormalizer`).
    pub event_name: String,
    /// The event moved this session's own state.
    pub applied_to_session: bool,
    /// The event ended the session's turn with nothing left working under it.
    pub ended_turn: bool,
    /// A Hermes hook from a conversation held away from this machine.
    pub held_elsewhere: bool,
    /// The error the turn stopped on.
    pub turn_error: Option<PushSessionError>,
    /// The turn that ended is a subagent's.
    pub subagent_turn: bool,
}

impl HookEventFacts {
    /// `HookEventFacts(event:)`: what the event says about itself, before
    /// the reducer has applied it.
    pub fn new(event: &HookEvent) -> Self {
        Self {
            raw_event_name: event.event_name.clone(),
            event_name: normalize(&event.event_name).to_owned(),
            applied_to_session: false,
            ended_turn: false,
            held_elsewhere: hermes::is_quiet(event),
            turn_error: session_error(&event.event_name, &event.raw_json),
            subagent_turn: false,
        }
    }
}

fn text(value: Option<&Value>) -> Option<String> {
    json::trimmed(value).map(str::to_owned)
}

/// `PushEventClassifier.sessionError(eventName:raw:)`: `StopFailure`'s
/// class and text, or Copilot's unrecoverable `errorOccurred`.
pub fn session_error(event_name: &str, raw: &JsonObject) -> Option<PushSessionError> {
    match event_name {
        "StopFailure" | "stop_failure" => Some(PushSessionError {
            r#type: text(raw.get("error")),
            detail: text(raw.get("last_assistant_message"))
                .or_else(|| text(raw.get("error_details")))
                .or_else(|| text(raw.get("message"))),
        }),
        "errorOccurred" | "ErrorOccurred" => {
            if json::is_true(raw.get("recoverable")) {
                return None;
            }
            let error = json::object(raw.get("error"));
            Some(PushSessionError {
                r#type: error.and_then(|e| text(e.get("name"))),
                detail: error
                    .and_then(|e| text(e.get("message")))
                    .or_else(|| text(raw.get("error"))),
            })
        }
        _ => None,
    }
}

/// `PushEventClassifier.isSubagentCompletion`: an explicit subagent id, or a
/// Cursor Task card kept separate.
pub fn is_subagent_completion(
    agent_id: Option<&str>,
    session_id: &str,
    session: Option<&SessionSnapshot>,
    sources: &SourceCatalog,
) -> bool {
    if agent_id.is_some_and(|id| !id.is_empty()) {
        return true;
    }
    let Some(session) = session else {
        return false;
    };
    is_cursor_family_source(Some(&session.source), sources)
        && is_likely_cursor_task_card(
            session_id,
            session.provider_session_id.as_deref(),
            session.transcript_path.as_deref(),
        )
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn stop_failure_and_copilot_errors() {
        let raw = json!({"error": "rate_limit", "last_assistant_message": " API Error "});
        assert_eq!(
            session_error("StopFailure", raw.as_object().unwrap()),
            Some(PushSessionError {
                r#type: Some("rate_limit".into()),
                detail: Some("API Error".into())
            })
        );
        let recoverable = json!({"recoverable": true, "error": {"name": "x"}});
        assert_eq!(
            session_error("errorOccurred", recoverable.as_object().unwrap()),
            None
        );
        assert_eq!(session_error("Stop", raw.as_object().unwrap()), None);
    }
}
