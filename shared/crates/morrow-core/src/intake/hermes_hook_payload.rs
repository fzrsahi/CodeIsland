//! Hermes Agent's shell-hook payload (`Sources/MorrowCore/HermesHookPayload.swift`):
//! the part the bridge needs.

use serde_json::Value;

use crate::JsonObject;

/// `extra` keys nothing reads that grow with the conversation:
/// `conversation_history` is the whole transcript, sent with every
/// pre/post_llm_call.
const UNFORWARDED_EXTRA_KEYS: &[&str] = &["conversation_history"];

/// `trimmedForForwarding`: the payload without the transcript copy.
pub fn trimmed_for_forwarding(mut json: JsonObject) -> JsonObject {
    if let Some(Value::Object(extra)) = json.get_mut("extra") {
        for key in UNFORWARDED_EXTRA_KEYS {
            extra.remove(*key);
        }
    }
    json
}
