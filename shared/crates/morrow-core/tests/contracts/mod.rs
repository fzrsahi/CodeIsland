//! The core contract's projections, as `macos/Tests/MorrowCoreTests/CoreContractJSONExporter.swift`
//! writes them: what the policy's intents look like in
//! `fixtures/core/attention.json` and in a reducer step of
//! `fixtures/core/reducer.json`.
//!
//! Shared by `attention_conformance.rs` and `reducer_conformance.rs`.
#![allow(dead_code)]

use serde_json::{Map, Value, json};

use morrow_core::attention::{AttentionIntents, AttentionPushKind, FollowUpIntent};

fn push_kind(kind: AttentionPushKind) -> Value {
    match kind {
        AttentionPushKind::Error => json!({"type": "error"}),
        AttentionPushKind::Completion {
            is_subagent,
            interrupted,
        } => json!({
            "type": "completion",
            "is_subagent": is_subagent,
            "interrupted": interrupted,
        }),
        AttentionPushKind::Approval => json!({"type": "approval"}),
        AttentionPushKind::Question => json!({"type": "question"}),
        AttentionPushKind::DisplayOnlyWait => json!({"type": "displayOnlyWait"}),
    }
}

/// `CoreContractJSONExporter`'s `intents` document.
pub fn intents_document(intents: &AttentionIntents) -> Value {
    let mut doc = Map::new();
    doc.insert("sound".into(), json!(intents.sound));
    doc.insert(
        "completion".into(),
        match intents.completion {
            Some(completion) => json!({"turn_failed": completion.turn_failed}),
            None => Value::Null,
        },
    );
    doc.insert(
        "push".into(),
        match intents.push {
            Some(push) => json!({
                "kind": push_kind(push.kind),
                "smart_suppressible": push.smart_suppressible,
            }),
            None => Value::Null,
        },
    );
    doc.insert(
        "follow_up".into(),
        match intents.follow_up {
            Some(FollowUpIntent::TrackCompletion { turn_failed }) => {
                json!({"type": "trackCompletion", "turn_failed": turn_failed})
            }
            Some(FollowUpIntent::RestartWait(kind)) => {
                json!({"type": "restartWait", "kind": kind.raw_value()})
            }
            None => Value::Null,
        },
    );
    Value::Object(doc)
}
