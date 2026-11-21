//! `AttentionPolicy.intents` on every case of `fixtures/core/attention.json`
//! (exported from Swift by `macos/Tests/MorrowCoreTests/CoreContractJSONExporter.swift`
//! out of `AttentionPolicyTests`): the intents Swift returns for a moment and
//! a subject must be the ones morrow-core returns.
//!
//! `settle(_:context:)` is not part of the bundle: it reads the user's
//! settings and the room, which arrive with the platform adapters.

use std::collections::BTreeMap;
use std::path::PathBuf;

use serde_json::Value;

use contracts::intents_document;
use morrow_core::attention::{
    AttentionMoment, AttentionSubject, FollowUpReminderKind, TurnEnd, TurnHost, intents,
};
use morrow_core::reduce::{HookEventFacts, PushSessionError};

mod contracts;

/// Every case of the bundle; a change in the bundle shows here.
const CASES: usize = 56;

fn bundle() -> Value {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../../shared/contract/fixtures/core/attention.json");
    let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
    serde_json::from_str(&text).expect("attention.json")
}

// MARK: - Reading a case

fn facts(value: &Value) -> HookEventFacts {
    let turn_error = value["turn_error"].as_object().map(|e| PushSessionError {
        r#type: e.get("type").and_then(Value::as_str).map(str::to_owned),
        detail: e.get("detail").and_then(Value::as_str).map(str::to_owned),
    });
    HookEventFacts {
        raw_event_name: value["raw_event_name"].as_str().unwrap().to_owned(),
        event_name: value["event_name"].as_str().unwrap().to_owned(),
        applied_to_session: value["applied_to_session"] == true,
        ended_turn: value["ended_turn"] == true,
        held_elsewhere: value["held_elsewhere"] == true,
        turn_error,
        subagent_turn: value["subagent_turn"] == true,
    }
}

fn kind(value: &Value) -> FollowUpReminderKind {
    FollowUpReminderKind::from_raw_value(value.as_str().expect("a reminder kind"))
        .unwrap_or_else(|| panic!("reminder kind {value}"))
}

fn moment(value: &Value) -> AttentionMoment {
    match value["type"].as_str().expect("a moment type") {
        "hookEvent" => AttentionMoment::HookEvent(facts(&value["facts"])),
        "approvalQueued" => AttentionMoment::ApprovalQueued {
            first_of_burst: value["first_of_burst"] == true,
        },
        "questionQueued" => AttentionMoment::QuestionQueued {
            first_of_burst: value["first_of_burst"] == true,
            smart_suppressible: value["smart_suppressible"] == true,
        },
        "requestRaisedElsewhere" => AttentionMoment::RequestRaisedElsewhere,
        "displayOnlyWaitBegan" => AttentionMoment::DisplayOnlyWaitBegan {
            kind: kind(&value["kind"]),
            announce: value["announce"] == true,
        },
        "turnStarted" => AttentionMoment::TurnStarted {
            new_session: value["new_session"] == true,
        },
        "turnEnded" => AttentionMoment::TurnEnded {
            end: match value["end"].as_str().expect("a turn end") {
                "completed" => TurnEnd::Completed,
                "failed" => TurnEnd::Failed,
                "stopped" => TurnEnd::Stopped,
                other => panic!("turn end {other}"),
            },
            host: match value["host"].as_str().expect("a turn host") {
                "claudeDesktop" => TurnHost::ClaudeDesktop,
                "aiwork" => TurnHost::Aiwork,
                other => panic!("turn host {other}"),
            },
        },
        "reminderDue" => AttentionMoment::ReminderDue {
            kind: kind(&value["kind"]),
            turn_failed: value["turn_failed"] == true,
        },
        "appLaunched" => AttentionMoment::AppLaunched,
        other => panic!("moment type {other}"),
    }
}

fn subject(value: &Value) -> AttentionSubject {
    AttentionSubject {
        is_child: value["is_child"] == true,
        interrupted: value["interrupted"] == true,
    }
}

// MARK: - Running the bundle

#[test]
fn every_attention_case_matches_swift() {
    let bundle = bundle();
    assert_eq!(bundle["contract"], "attention");
    let cases = bundle["cases"].as_array().unwrap();
    let mut by_category: BTreeMap<&str, (usize, usize)> = BTreeMap::new();
    let mut failures = Vec::new();
    for case in cases {
        let name = case["name"].as_str().unwrap();
        let category = name.split('/').next().unwrap();
        let entry = by_category.entry(category).or_default();
        entry.1 += 1;
        let got = intents_document(&intents(
            &moment(&case["moment"]),
            subject(&case["subject"]),
        ));
        if got == case["intents"] {
            entry.0 += 1;
        } else {
            failures.push(format!(
                "{name}:\n  rust:  {got}\n  swift: {}",
                case["intents"]
            ));
        }
    }
    for (category, (passed, total)) in &by_category {
        println!("attention {category}: {passed}/{total} cases");
    }
    println!(
        "attention: {}/{} cases",
        cases.len() - failures.len(),
        cases.len()
    );
    assert!(
        failures.is_empty(),
        "{} of {} cases differ from Swift:\n{}",
        failures.len(),
        cases.len(),
        failures.join("\n")
    );
    assert_eq!(cases.len(), CASES);
}
