//! Text the reducer pulls out of a payload: the private helpers of
//! `SessionSnapshot.swift` (`firstStringFromEvent`,
//! `stringFromHookJSONValue`, `notificationKind`, …), `QuestionPayload.from`
//! (`Models.swift`), `ClaudeDesktopCodeSession.isValidHostSessionId` and the
//! chat-text normalization of `JSONLTailer`.

use serde_json::Value;

use super::hook_event::HookEvent;
use super::json;
use crate::JsonObject;

/// `stringFromHookJSONValue`: a non-blank string as it is, or the text parts
/// of a content-part array (`[{ "type": "text", "text": "…" }]`) joined.
fn string_from_hook_json_value(value: Option<&Value>) -> Option<String> {
    match value? {
        Value::String(s) => (!s.trim().is_empty()).then(|| s.clone()),
        Value::Array(items) => {
            let joined: String = items
                .iter()
                .filter_map(Value::as_object)
                .filter(|part| match part.get("type") {
                    Some(Value::String(t)) => t == "text",
                    _ => true,
                })
                .filter_map(|part| json::string(part.get("text")))
                .filter(|text| !text.trim().is_empty())
                .collect();
            (!joined.is_empty()).then_some(joined)
        }
        _ => None,
    }
}

fn first_string_from_dict(dict: &JsonObject, keys: &[&str]) -> Option<String> {
    keys.iter()
        .find_map(|key| string_from_hook_json_value(dict.get(*key)))
}

/// `firstStringFromEvent(_:keys:includeNested:)`: top level first, then
/// `payload`, `data` and Hermes's `extra`.
pub fn first_string_from_event(
    event: &HookEvent,
    keys: &[&str],
    include_nested: bool,
) -> Option<String> {
    first_string_from_dict(&event.raw_json, keys).or_else(|| {
        if !include_nested {
            return None;
        }
        ["payload", "data", "extra"]
            .iter()
            .find_map(|c| first_string_from_dict(json::object(event.raw(c))?, keys))
    })
}

/// `notificationKind(from:)`: `notification_type`, lowercased.
pub fn notification_kind(event: &HookEvent) -> Option<String> {
    let raw = first_string_from_event(event, &["notification_type", "notificationType"], true)?;
    let kind = raw.trim().to_lowercase();
    (!kind.is_empty()).then_some(kind)
}

/// `subagentType(from:)`.
pub fn subagent_type(event: &HookEvent) -> String {
    first_string_from_event(event, &["agent_type", "agentType"], false)
        .unwrap_or_else(|| "Agent".to_owned())
}

/// `QuestionPayload.from(event:) != nil`: the Notification carries a
/// `question` string.
pub fn has_question(event: &HookEvent) -> bool {
    json::string(event.raw("question")).is_some()
}

/// `ClaudeDesktopCodeSession.isValidHostSessionId`:
/// `^local_[A-Za-z0-9-]{1,64}$`.
pub fn is_valid_claude_desktop_host_session_id(id: &str) -> bool {
    id.strip_prefix("local_").is_some_and(|body| {
        (1..=64).contains(&body.len())
            && body.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
    })
}

/// `JSONLTailer.normalizedCursorChatText(from:)` for a string: transcript
/// wrappers (`<timestamp>`, `<user_query>`) stripped so hook and transcript
/// copies compare equal.
pub fn normalized_cursor_chat_text(content: &str) -> Option<String> {
    let mut text = extract_text(content)?;
    while let Some(start) = text.find("<timestamp>") {
        let after = start + "<timestamp>".len();
        let Some(end) = text[after..].find("</timestamp>") else {
            break;
        };
        text.replace_range(start..after + end + "</timestamp>".len(), "");
    }
    if let Some(start) = text.find("<user_query>") {
        let after = start + "<user_query>".len();
        if let Some(end) = text[after..].find("</user_query>") {
            text = text[after..after + end].to_owned();
        }
    }
    let trimmed = text.trim();
    (!trimmed.is_empty()).then(|| trimmed.to_owned())
}

/// `JSONLTailer.extractText(from:)` for a string.
fn extract_text(raw: &str) -> Option<String> {
    let text = strip_display_wrappers(raw);
    if is_thinking_blob(&text) {
        return None;
    }
    let trimmed = text.trim();
    (!trimmed.is_empty()).then(|| trimmed.to_owned())
}

/// `JSONLTailer.stripDisplayWrappers`: inside `<USER_REQUEST>`, without the
/// `<system-reminder>` spans that open the text.
fn strip_display_wrappers(raw: &str) -> String {
    let mut text = raw.to_owned();
    if let Some(start) = text.find("<USER_REQUEST>") {
        let after = start + "<USER_REQUEST>".len();
        if let Some(end) = text[after..].find("</USER_REQUEST>") {
            text = text[after..after + end].to_owned();
        }
    }
    while let Some(start) = text.find(|c: char| !c.is_whitespace()) {
        if !text[start..].starts_with("<system-reminder>") {
            break;
        }
        let Some(end) = text[start..].find("</system-reminder>") else {
            break;
        };
        text.replace_range(..start + end + "</system-reminder>".len(), "");
    }
    text
}

/// `JSONLTailer.isThinkingBlob`: a reasoning pass written as display text,
/// `{"type":"thinking","thinking":"…"}`.
fn is_thinking_blob(text: &str) -> bool {
    let trimmed = text.trim();
    if !(trimmed.starts_with('{') && trimmed.ends_with('}')) {
        return false;
    }
    let Ok(Value::Object(obj)) = serde_json::from_str::<Value>(trimmed) else {
        return false;
    };
    let type_is_thinking =
        json::string(obj.get("type")).is_some_and(|t| t.to_lowercase().contains("thinking"));
    (type_is_thinking || obj.contains_key("thinkingSignature"))
        && matches!(obj.get("thinking"), Some(Value::String(_)))
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;
    use crate::intake::SourceCatalog;

    #[test]
    fn content_parts_and_nested_containers() {
        let e = HookEvent::new(
            json!({"hook_event_name": "UserPromptSubmit",
                   "prompt": [{"type": "text", "text": "a"}, {"type": "image"}, {"text": "b"}],
                   "extra": {"user_message": "m"}})
            .as_object()
            .unwrap()
            .clone(),
            &SourceCatalog::default(),
        )
        .unwrap();
        assert_eq!(
            first_string_from_event(&e, &["prompt"], false).as_deref(),
            Some("ab")
        );
        assert_eq!(
            first_string_from_event(&e, &["user_message"], true).as_deref(),
            Some("m")
        );
        assert_eq!(first_string_from_event(&e, &["user_message"], false), None);
    }

    #[test]
    fn chat_text_loses_its_wrappers() {
        assert_eq!(
            normalized_cursor_chat_text("<timestamp>x</timestamp> <user_query>hi</user_query>")
                .as_deref(),
            Some("hi")
        );
        assert_eq!(
            normalized_cursor_chat_text(" <system-reminder>r</system-reminder>typed").as_deref(),
            Some("typed")
        );
        assert_eq!(
            normalized_cursor_chat_text(r#"{"type":"thinking","thinking":"t"}"#),
            None
        );
        assert!(is_valid_claude_desktop_host_session_id("local_ab-1"));
        assert!(!is_valid_claude_desktop_host_session_id("local_"));
        assert!(!is_valid_claude_desktop_host_session_id("local_a b"));
    }
}
