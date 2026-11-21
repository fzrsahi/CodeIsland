//! The reducer on every case of `fixtures/core/reducer.json` (exported from
//! Swift by `macos/Tests/MorrowCoreTests/CoreContractJSONExporter.swift`): after
//! each step, every session, the effects, the facts and the attention policy's
//! intents for those facts must be what Swift left, projected the way the
//! exporter projects them.
//!
//! The clock reads `$Tk` during step k (`Timestamp(k)` seconds); a case's
//! `custom_sources` are the catalog's custom sources, with no custom agent
//! commands, as the exporter pins them.

use std::collections::BTreeMap;
use std::path::PathBuf;

use serde_json::{Map, Value, json};

use morrow_core::attention::{AttentionMoment, AttentionSubject, intents};
use morrow_core::intake::SourceCatalog;
use morrow_core::reduce::{
    AgentStatus, ChatMessage, HookEvent, HookEventFacts, ReduceContext, SessionSnapshot, Sessions,
    SideEffect, SubagentState, SubsessionKind, Timestamp, ToolHistoryEntry, reduce_hook_event,
};

mod contracts;

/// Every case and step of the bundle; a change in the bundle shows here.
const CASES: usize = 80;
const STEPS: usize = 161;

/// A home no fixture's cwd sits in.
const HOME: &str = "/home/morrow-contract";

fn bundle() -> Value {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../../shared/contract/fixtures/core/reducer.json");
    let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
    serde_json::from_str(&text).expect("reducer.json")
}

// MARK: - Clock tokens

/// Seconds below this are `$Tk`; above, a fixed seeded instant.
const TOKEN_LIMIT: f64 = 1_000_000.0;

fn token(t: Timestamp) -> Value {
    if t.0 < TOKEN_LIMIT {
        return json!(format!("$T{}", t.0 as i64));
    }
    let secs = t.0 as i64;
    let (days, rem) = (secs.div_euclid(86_400), secs.rem_euclid(86_400));
    let (y, m, d) = civil_from_days(days);
    json!(format!(
        "{y:04}-{m:02}-{d:02}T{:02}:{:02}:{:02}Z",
        rem / 3600,
        rem % 3600 / 60,
        rem % 60
    ))
}

fn timestamp(value: &Value) -> Timestamp {
    let s = value.as_str().expect("a date token");
    if let Some(k) = s.strip_prefix("$T") {
        return Timestamp(k.parse::<f64>().expect("$Tk"));
    }
    let n = |range: std::ops::Range<usize>| s[range].parse::<i64>().expect("ISO 8601");
    let days = days_from_civil(n(0..4), n(5..7), n(8..10));
    Timestamp((days * 86_400 + n(11..13) * 3600 + n(14..16) * 60 + n(17..19)) as f64)
}

// Howard Hinnant's civil-date algorithms.
fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * (m + if m > 2 { -3 } else { 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

fn civil_from_days(z: i64) -> (i64, i64, i64) {
    let z = z + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    (
        if m <= 2 {
            yoe + era * 400 + 1
        } else {
            yoe + era * 400
        },
        m,
        d,
    )
}

// MARK: - Projection (CoreContractJSONExporter.sessionDocument)

type Field = fn(&mut SessionSnapshot) -> &mut Option<String>;

/// The optional strings of the projection, but `current_tool` (a setter).
const STRINGS: &[(&str, Field)] = &[
    ("current_tool_use_id", |s| &mut s.current_tool_use_id),
    ("tool_description", |s| &mut s.tool_description),
    ("cwd", |s| &mut s.cwd),
    ("model", |s| &mut s.model),
    ("permission_mode", |s| &mut s.permission_mode),
    ("transcript_path", |s| &mut s.transcript_path),
    ("last_user_prompt", |s| &mut s.last_user_prompt),
    ("last_assistant_message", |s| &mut s.last_assistant_message),
    ("live_codex_output", |s| &mut s.live_codex_output),
    ("session_title", |s| &mut s.session_title),
    ("provider_session_id", |s| &mut s.provider_session_id),
    ("parent_session_id", |s| &mut s.parent_session_id),
    ("remote_host_id", |s| &mut s.remote_host_id),
    ("remote_host_name", |s| &mut s.remote_host_name),
    ("term_app", |s| &mut s.term_app),
    ("iterm_session_id", |s| &mut s.iterm_session_id),
    ("tty_path", |s| &mut s.tty_path),
    ("kitty_window_id", |s| &mut s.kitty_window_id),
    ("tmux_pane", |s| &mut s.tmux_pane),
    ("tmux_client_tty", |s| &mut s.tmux_client_tty),
    ("tmux_env", |s| &mut s.tmux_env),
    ("term_bundle_id", |s| &mut s.term_bundle_id),
    ("cmux_surface_id", |s| &mut s.cmux_surface_id),
    ("cmux_workspace_id", |s| &mut s.cmux_workspace_id),
    ("zellij_pane_id", |s| &mut s.zellij_pane_id),
    ("zellij_session_name", |s| &mut s.zellij_session_name),
    ("wezterm_pane_id", |s| &mut s.wezterm_pane_id),
    ("herdr_pane_id", |s| &mut s.herdr_pane_id),
    ("herdr_socket_path", |s| &mut s.herdr_socket_path),
    ("herdr_binary_path", |s| &mut s.herdr_binary_path),
    ("superset_workspace_id", |s| &mut s.superset_workspace_id),
    ("superset_pane_id", |s| &mut s.superset_pane_id),
    ("orca_terminal_handle", |s| &mut s.orca_terminal_handle),
    ("orca_worktree_id", |s| &mut s.orca_worktree_id),
    ("claude_desktop_session_id", |s| {
        &mut s.claude_desktop_session_id
    }),
];

type Flag = fn(&mut SessionSnapshot) -> &mut bool;

const FLAGS: &[(&str, Flag)] = &[
    ("interrupted", |s| &mut s.interrupted),
    ("last_turn_failed", |s| &mut s.last_turn_failed),
    ("task_round_ended", |s| &mut s.task_round_ended),
    ("hermes_hooks_report_prompts", |s| {
        &mut s.hermes_hooks_report_prompts
    }),
    ("hermes_hooks_report_replies", |s| {
        &mut s.hermes_hooks_report_replies
    }),
    ("hermes_chat_elsewhere", |s| &mut s.hermes_chat_elsewhere),
];

const STATUSES: &[(AgentStatus, &str)] = &[
    (AgentStatus::Idle, "idle"),
    (AgentStatus::Processing, "processing"),
    (AgentStatus::Running, "running"),
    (AgentStatus::WaitingApproval, "waitingApproval"),
    (AgentStatus::WaitingQuestion, "waitingQuestion"),
];

fn status_name(status: AgentStatus) -> Value {
    json!(STATUSES.iter().find(|(s, _)| *s == status).unwrap().1)
}

fn status(value: &Value) -> AgentStatus {
    STATUSES
        .iter()
        .find(|(_, name)| Some(*name) == value.as_str())
        .unwrap_or_else(|| panic!("status {value}"))
        .0
}

fn session_document(s: &SessionSnapshot) -> Value {
    let mut s = s.clone();
    let mut doc = Map::new();
    doc.insert("status".into(), status_name(s.status));
    doc.insert("source".into(), json!(s.source));
    doc.insert("start_time".into(), token(s.start_time));
    doc.insert("last_activity".into(), token(s.last_activity));
    if let Some(tool) = s.current_tool() {
        doc.insert("current_tool".into(), json!(tool));
    }
    for (key, field) in STRINGS {
        if let Some(value) = field(&mut s) {
            doc.insert((*key).into(), json!(value));
        }
    }
    for (key, flag) in FLAGS {
        if *flag(&mut s) {
            doc.insert((*key).into(), json!(true));
        }
    }
    let mut put = |key: &str, value: Option<Value>| {
        if let Some(value) = value {
            doc.insert(key.into(), value);
        }
    };
    put("cli_pid", s.cli_pid.map(|p| json!(p)));
    put("remote_pid", s.remote_pid.map(|p| json!(p)));
    put("cli_start_time", s.cli_start_time.map(token));
    put("model_reported_at", s.model_reported_at.map(token));
    put(
        "total_tool_call_count",
        (s.total_tool_call_count != 0).then(|| json!(s.total_tool_call_count)),
    );
    put(
        "recent_messages",
        (!s.recent_messages.is_empty()).then(|| {
            json!(
                s.recent_messages
                    .iter()
                    .map(|m| json!({"is_user": m.is_user, "text": m.text}))
                    .collect::<Vec<_>>()
            )
        }),
    );
    put(
        "tool_history",
        (!s.tool_history.is_empty()).then(|| {
            json!(s.tool_history.iter().map(|e| {
                let mut item = json!({"tool": e.tool, "success": e.success, "timestamp": token(e.timestamp)});
                if let Some(d) = &e.description { item["description"] = json!(d); }
                if let Some(a) = &e.agent_type { item["agent_type"] = json!(a); }
                item
            }).collect::<Vec<_>>())
        }),
    );
    put(
        "subagents",
        (!s.subagents.is_empty()).then(|| {
            Value::Object(
                s.subagents
                    .iter()
                    .map(|(id, sub)| {
                        let mut item = json!({
                            "agent_type": sub.agent_type,
                            "status": status_name(sub.status),
                            "start_time": token(sub.start_time),
                            "last_activity": token(sub.last_activity),
                        });
                        if let Some(v) = sub.current_tool() {
                            item["current_tool"] = json!(v);
                        }
                        if let Some(v) = &sub.current_tool_use_id {
                            item["current_tool_use_id"] = json!(v);
                        }
                        if let Some(v) = &sub.tool_description {
                            item["tool_description"] = json!(v);
                        }
                        if let Some(v) = &sub.model {
                            item["model"] = json!(v);
                        }
                        if let Some(v) = sub.subsession_kind {
                            item["subsession_kind"] = json!(v.raw_value());
                        }
                        (id.clone(), item)
                    })
                    .collect(),
            )
        }),
    );
    put(
        "closed_subagent_ids",
        (!s.closed_subagent_ids().is_empty()).then(|| json!(s.closed_subagent_ids())),
    );
    Value::Object(doc)
}

fn sessions_document(sessions: &Sessions) -> Value {
    Value::Object(
        sessions
            .iter()
            .map(|(id, s)| (id.clone(), session_document(s)))
            .collect(),
    )
}

/// A case's initial session from its projection: every projected field.
fn seed(doc: &Value) -> SessionSnapshot {
    let doc = doc.as_object().expect("a session");
    let mut s = SessionSnapshot::new(timestamp(&doc["start_time"]));
    s.last_activity = timestamp(&doc["last_activity"]);
    s.status = status(&doc["status"]);
    s.source = doc["source"].as_str().unwrap().to_owned();
    s.set_current_tool(
        doc.get("current_tool")
            .map(|v| v.as_str().unwrap().to_owned()),
    );
    for (key, field) in STRINGS {
        *field(&mut s) = doc.get(*key).map(|v| v.as_str().unwrap().to_owned());
    }
    for (key, flag) in FLAGS {
        *flag(&mut s) = doc.get(*key).is_some_and(|v| v == true);
    }
    let pid = |key: &str| doc.get(key).map(|v| v.as_i64().unwrap() as i32);
    s.cli_pid = pid("cli_pid");
    s.remote_pid = pid("remote_pid");
    s.cli_start_time = doc.get("cli_start_time").map(timestamp);
    s.model_reported_at = doc.get("model_reported_at").map(timestamp);
    s.total_tool_call_count = doc
        .get("total_tool_call_count")
        .map_or(0, |v| v.as_i64().unwrap());
    for m in doc
        .get("recent_messages")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        s.recent_messages.push(ChatMessage::new(
            m["is_user"] == true,
            m["text"].as_str().unwrap(),
        ));
    }
    for e in doc
        .get("tool_history")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        s.tool_history.push(ToolHistoryEntry {
            tool: e["tool"].as_str().unwrap().to_owned(),
            description: e.get("description").map(|v| v.as_str().unwrap().to_owned()),
            timestamp: timestamp(&e["timestamp"]),
            success: e["success"] == true,
            agent_type: e.get("agent_type").map(|v| v.as_str().unwrap().to_owned()),
        });
    }
    for (id, sub) in doc
        .get("subagents")
        .and_then(Value::as_object)
        .into_iter()
        .flatten()
    {
        let text = |key: &str| sub.get(key).map(|v| v.as_str().unwrap().to_owned());
        let mut state = SubagentState::new(
            id,
            sub["agent_type"].as_str().unwrap(),
            timestamp(&sub["start_time"]),
        );
        state.last_activity = timestamp(&sub["last_activity"]);
        state.status = status(&sub["status"]);
        state.set_current_tool(text("current_tool"));
        state.current_tool_use_id = text("current_tool_use_id");
        state.tool_description = text("tool_description");
        state.model = text("model");
        state.subsession_kind =
            text("subsession_kind").map(|k| SubsessionKind::from_raw_value(&k).unwrap());
        s.subagents.insert(id.clone(), state);
    }
    let closed: Vec<String> = doc
        .get("closed_subagent_ids")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .map(|v| v.as_str().unwrap().to_owned())
        .collect();
    s.restore_closed_subagent_ids(&closed);
    s
}

fn effect_document(effect: &SideEffect) -> Value {
    match effect {
        SideEffect::PlaySound(sound) => json!({"type": "playSound", "sound": sound}),
        SideEffect::TryMonitorSession { session_id } => {
            json!({"type": "tryMonitorSession", "session_id": session_id})
        }
        SideEffect::StopMonitor { session_id } => {
            json!({"type": "stopMonitor", "session_id": session_id})
        }
        SideEffect::RemoveSession { session_id } => {
            json!({"type": "removeSession", "session_id": session_id})
        }
        SideEffect::EnqueueCompletion { session_id } => {
            json!({"type": "enqueueCompletion", "session_id": session_id})
        }
        SideEffect::SetActiveSession { session_id } => {
            json!({"type": "setActiveSession", "session_id": session_id})
        }
    }
}

fn facts_document(f: &HookEventFacts) -> Value {
    json!({
        "raw_event_name": f.raw_event_name,
        "event_name": f.event_name,
        "applied_to_session": f.applied_to_session,
        "ended_turn": f.ended_turn,
        "held_elsewhere": f.held_elsewhere,
        "turn_error": f.turn_error.as_ref().map(|e| json!({"type": e.r#type, "detail": e.detail})),
        "subagent_turn": f.subagent_turn,
    })
}

// MARK: - Running the bundle

/// The first step of `case` whose sessions, effects or facts differ from
/// Swift's, described; `None` when every step matches.
fn run_case(case: &Value) -> Result<usize, String> {
    let sources = SourceCatalog {
        custom_sources: case["custom_sources"]
            .as_array()
            .unwrap()
            .iter()
            .map(|s| s.as_str().unwrap().to_owned())
            .collect(),
        custom_commands: Vec::new(),
    };
    let mut sessions: Sessions = case["sessions"]
        .as_object()
        .unwrap()
        .iter()
        .map(|(id, doc)| (id.clone(), seed(doc)))
        .collect();
    if sessions_document(&sessions) != case["sessions"] {
        return Err(format!(
            "seed does not round-trip:\n  rust:  {}\n  swift: {}",
            sessions_document(&sessions),
            case["sessions"]
        ));
    }
    let steps = case["steps"].as_array().unwrap();
    for (index, step) in steps.iter().enumerate() {
        let k = (index + 1) as f64;
        let clock = move || Timestamp(k);
        let ctx = ReduceContext {
            clock: &clock,
            sources: &sources,
            home_directory: HOME,
            max_history: case["max_history"].as_u64().unwrap() as usize,
            reply_complete_placeholder: case["reply_complete_placeholder"].as_str().unwrap(),
        };
        let event = HookEvent::new(step["event"].as_object().unwrap().clone(), &sources)
            .ok_or_else(|| format!("step {}: not a hook event", index + 1))?;
        let reduction = reduce_hook_event(&mut sessions, &event, &ctx);
        let step_subject = AttentionSubject {
            is_child: step["subject"]["is_child"] == true,
            interrupted: step["subject"]["interrupted"] == true,
        };
        let got = [
            ("sessions", sessions_document(&sessions)),
            (
                "effects",
                Value::Array(reduction.effects.iter().map(effect_document).collect()),
            ),
            ("facts", facts_document(&reduction.facts)),
            (
                "intents",
                contracts::intents_document(&intents(
                    &AttentionMoment::HookEvent(reduction.facts),
                    step_subject,
                )),
            ),
        ];
        for (key, value) in got {
            if value != step[key] {
                return Err(format!(
                    "step {} {key}:\n  rust:  {value}\n  swift: {}",
                    index + 1,
                    step[key]
                ));
            }
        }
    }
    Ok(steps.len())
}

#[test]
fn every_reducer_case_matches_swift() {
    let bundle = bundle();
    assert_eq!(bundle["contract"], "reducer");
    let cases = bundle["cases"].as_array().unwrap();
    let mut by_category: BTreeMap<&str, (usize, usize)> = BTreeMap::new();
    let (mut steps, mut failures) = (0, Vec::new());
    for case in cases {
        let name = case["name"].as_str().unwrap();
        let category = name.split('/').next().unwrap();
        let entry = by_category.entry(category).or_default();
        entry.1 += 1;
        match run_case(case) {
            Ok(n) => {
                entry.0 += 1;
                steps += n;
            }
            Err(diff) => failures.push(format!("{name}: {diff}")),
        }
    }
    for (category, (passed, total)) in &by_category {
        println!("reducer {category}: {passed}/{total} cases");
    }
    println!(
        "reducer: {}/{} cases, {steps} steps",
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
    assert_eq!((cases.len(), steps), (CASES, STEPS));
}

#[test]
fn the_clock_tokens_round_trip() {
    for token_text in ["$T0", "$T7", "2023-11-14T22:13:20Z"] {
        assert_eq!(token(timestamp(&json!(token_text))), json!(token_text));
    }
}
