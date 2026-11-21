//! Hermes Agent, as the reducer reads it: `HermesHookPayload`
//! (`Sources/MorrowCore/HermesHookPayload.swift`) and the store snapshot a
//! remote hook attaches (`HermesSessionStore.Snapshot`, `applyHermesStore`
//! in `HermesSessionStore.swift`).

use serde_json::Value;

use super::hook_event::HookEvent;
use super::json;
use super::session_snapshot::{ChatMessage, SessionSnapshot};
use crate::JsonObject;

/// Platforms whose session is a single turn under its own id.
const ONE_SHOT_PLATFORMS: &[&str] = &["subagent", "cron", "curator"];
/// Platforms where someone is driving Hermes at this machine.
const LOCAL_PLATFORMS: &[&str] = &["cli", "tui", "desktop", "acp"];
/// Hooks that carry `extra.platform`.
const PLATFORM_HOOKS: &[&str] = &[
    "on_session_start",
    "pre_llm_call",
    "post_llm_call",
    "on_session_end",
];

fn extra(raw: &JsonObject) -> Option<&JsonObject> {
    json::object(raw.get("extra"))
}

/// `HermesHookPayload.model(in:)`: `extra.model`.
pub fn model(raw: &JsonObject) -> Option<&str> {
    json::string(extra(raw)?.get("model")).filter(|m| !m.trim().is_empty())
}

/// `HermesHookPayload.endsInterruptedTurn`.
pub fn ends_interrupted_turn(event: &HookEvent) -> bool {
    event.event_name == "on_session_end"
        && extra(&event.raw_json).is_some_and(|e| json::is_true(e.get("interrupted")))
}

/// `HermesHookPayload.endsOneShotRun`: the end of a delegate child's, a
/// scheduled job's or a curation pass's only turn.
pub fn ends_one_shot_run(event: &HookEvent) -> bool {
    event.event_name == "on_session_end"
        && platform(event).is_some_and(|p| ONE_SHOT_PLATFORMS.contains(&p.as_str()))
}

/// `HermesHookPayload.platform(of:)`.
pub fn platform(event: &HookEvent) -> Option<String> {
    if !PLATFORM_HOOKS.contains(&event.event_name.as_str()) {
        return None;
    }
    let platform = json::string(extra(&event.raw_json)?.get("platform"))?;
    let normalized = platform.trim().to_lowercase();
    (!normalized.is_empty()).then_some(normalized)
}

/// `HermesHookPayload.isQuiet`: a conversation held away from this machine.
pub fn is_quiet(event: &HookEvent) -> bool {
    platform(event).is_some_and(|p| !LOCAL_PLATFORMS.contains(&p.as_str()))
}

/// `HermesSessionStore.Message`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StoreMessage {
    pub row_id: i64,
    pub text: String,
}

/// `HermesSessionStore.Snapshot`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StoreSnapshot {
    pub title: Option<String>,
    pub latest_user_message: Option<StoreMessage>,
    pub latest_assistant_message: Option<StoreMessage>,
}

/// `HermesSessionStore.visibleText`.
fn visible_text(value: Option<&Value>) -> Option<String> {
    json::string(value)
        .filter(|t| !t.trim().is_empty())
        .map(str::to_owned)
}

impl StoreSnapshot {
    /// `Snapshot(payload:)`: the `_hermes_store` object,
    /// `{"title", "user": {"id", "text"}, "assistant": {"id", "text"}}`.
    pub fn from_payload(payload: Option<&Value>) -> Option<Self> {
        let object = json::object(payload)?;
        let message = |key: &str| {
            let row = json::object(object.get(key))?;
            Some(StoreMessage {
                row_id: json::int64_value(row.get("id"))?,
                text: visible_text(row.get("text"))?,
            })
        };
        Some(Self {
            title: visible_text(object.get("title")),
            latest_user_message: message("user"),
            latest_assistant_message: message("assistant"),
        })
    }
}

impl SessionSnapshot {
    /// `applyHermesStore(_:)`: the title, and a prompt or reply the hooks
    /// have not reported themselves.
    pub fn apply_hermes_store(&mut self, store: &StoreSnapshot) {
        if let Some(title) = &store.title {
            self.session_title = Some(title.clone());
        }
        let prompt = store.latest_user_message.as_ref();
        let take_prompt = prompt.is_some_and(|p| {
            !self.hermes_hooks_report_prompts && Some(&p.text) != self.last_user_prompt.as_ref()
        });
        let mut reply = None;
        if let Some(candidate) = store.latest_assistant_message.as_ref().filter(|c| {
            !self.hermes_hooks_report_replies
                && Some(&c.text) != self.last_assistant_message.as_ref()
        }) {
            match prompt {
                Some(prompt) => {
                    let answers_store_prompt = candidate.row_id > prompt.row_id;
                    if take_prompt
                        || (answers_store_prompt
                            && Some(&prompt.text) == self.last_user_prompt.as_ref())
                    {
                        reply = Some(candidate);
                    }
                }
                None => reply = Some(candidate),
            }
        }

        let mut rows: Vec<(&StoreMessage, bool)> = Vec::new();
        if let Some(prompt) = prompt.filter(|_| take_prompt) {
            rows.push((prompt, true));
        }
        if let Some(reply) = reply {
            rows.push((reply, false));
        }
        rows.sort_by_key(|(message, _)| message.row_id);
        for (message, is_user) in rows {
            if is_user {
                self.last_user_prompt = Some(message.text.clone());
                if self.last_message_is_user() {
                    self.recent_messages.pop();
                }
            } else {
                self.last_assistant_message = Some(message.text.clone());
                if self.recent_messages.last().is_some_and(|m| !m.is_user) {
                    self.recent_messages.pop();
                }
            }
            self.add_recent_message(ChatMessage::new(is_user, &message.text));
        }
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;
    use crate::intake::SourceCatalog;
    use crate::reduce::session_snapshot::Timestamp;

    fn event(value: Value) -> HookEvent {
        HookEvent::new(
            value.as_object().unwrap().clone(),
            &SourceCatalog::default(),
        )
        .unwrap()
    }

    #[test]
    fn platforms_tell_one_shot_and_quiet_runs() {
        let cron =
            event(json!({"hook_event_name": "on_session_end", "extra": {"platform": " Cron "}}));
        assert!(ends_one_shot_run(&cron));
        assert!(is_quiet(&cron));
        let cli = event(json!({"hook_event_name": "pre_llm_call", "extra": {"platform": "cli"}}));
        assert!(!is_quiet(&cli));
        let tool =
            event(json!({"hook_event_name": "pre_tool_call", "extra": {"platform": "telegram"}}));
        assert_eq!(platform(&tool), None);
    }

    #[test]
    fn the_store_fills_what_hooks_did_not_report() {
        let store = StoreSnapshot::from_payload(Some(&json!({
            "title": "T", "user": {"id": 1, "text": "hi"}, "assistant": {"id": 2, "text": "yo"}
        })))
        .unwrap();
        let mut s = SessionSnapshot::new(Timestamp(0.0));
        s.apply_hermes_store(&store);
        assert_eq!(s.session_title.as_deref(), Some("T"));
        assert_eq!(
            s.recent_messages,
            vec![ChatMessage::new(true, "hi"), ChatMessage::new(false, "yo")]
        );
    }
}
