//! `SessionRecapTests` (`macos/Tests/MorrowCoreTests/SessionRecapTests.swift`), the
//! scan-level half: recap parsing and cleaning, the byte probe that lets only
//! `away_summary` system rows through, the supersede rule inside one chunk,
//! the model observation each line carries, and the 1M `/model` switch.
//!
//! Only `testLocalSlashCommandsStartNoChecklistTurn` has no counterpart here:
//! it asserts the checklist the transcript scanner does not carry yet (#136).

use serde_json::{Value, json};

use morrow_core::intake::SourceCatalog;
use morrow_core::model_label::ModelObservation;
use morrow_core::reduce::Timestamp;
use morrow_core::reduce::{
    AgentStatus, HookEvent, ReduceContext, SessionSnapshot, Sessions, SubagentState,
    reduce_hook_event,
};
use morrow_core::session_recap::SessionRecap;
use morrow_core::time::parse_iso8601;
use morrow_core::transcript::{
    ClaudeCommandEcho, QuickTypeKind, ScanDelta, claude_command_echo, quick_type_probe, scan_lines,
    scan_tail_for_attach,
};

// MARK: - Fixtures (shapes copied from real CLI 2.1.26x transcripts)

fn recap_line(content: &str, timestamp: &str, sidechain: bool) -> String {
    json!({
        "parentUuid": "p1",
        "isSidechain": sidechain,
        "type": "system",
        "subtype": "away_summary",
        "content": content,
        "timestamp": timestamp,
        "uuid": "u1",
        "isMeta": false,
        "userType": "external",
        "entrypoint": "cli",
        "cwd": "/repo",
        "sessionId": "s1",
        "version": "2.1.267",
        "gitBranch": "main",
    })
    .to_string()
}

fn system_line(subtype: &str) -> String {
    json!({
        "parentUuid": "p1",
        "isSidechain": false,
        "type": "system",
        "subtype": subtype,
        "durationMs": 1234,
        "timestamp": "2026-09-12T03:30:00.000Z",
        "uuid": "u2",
        "isMeta": false,
    })
    .to_string()
}

fn user_line(text: &str) -> String {
    json!({
        "parentUuid": "p1",
        "isSidechain": false,
        "type": "user",
        "message": {"role": "user", "content": text},
        "uuid": "u3",
        "timestamp": "2026-09-12T03:40:00.000Z",
    })
    .to_string()
}

fn assistant_line(
    model: &str,
    effort: Option<&str>,
    per_turn_effort: Option<&str>,
    sidechain: bool,
    text: &str,
) -> String {
    let mut line = json!({
        "parentUuid": "p1",
        "isSidechain": sidechain,
        "message": {
            "model": model,
            "id": "msg_1",
            "type": "message",
            "role": "assistant",
            "content": [{"type": "text", "text": text}],
        },
        "type": "assistant",
        "uuid": "u4",
    });
    if let Some(effort) = effort {
        line["effort"] = json!(effort);
    }
    if let Some(per_turn_effort) = per_turn_effort {
        line["perTurnEffort"] = json!(per_turn_effort);
    }
    line.to_string()
}

fn turn_context_line(model: &str, effort: &str) -> String {
    json!({
        "timestamp": "2026-09-24T09:05:19.777Z",
        "ordinal": 130,
        "type": "turn_context",
        "payload": {
            "turn_id": "t1",
            "cwd": "/repo",
            "approval_policy": "never",
            "model": model,
            "collaboration_mode": {
                "mode": "default",
                "settings": {"model": model, "reasoning_effort": effort},
            },
            "effort": effort,
            "summary": "auto",
        }
    })
    .to_string()
}

fn scan(lines: &[String]) -> ScanDelta {
    scan_lines((lines.join("\n") + "\n").as_bytes()).delta
}

// Slash-command rows as CLI 2.1.2xx writes them: plain user rows, isMeta false.
const MODEL_COMMAND_LINE: &str = r#"{"parentUuid":"p1","isSidechain":false,"type":"user","message":{"role":"user","content":"<command-name>/model</command-name>\n            <command-message>model</command-message>\n            <command-args></command-args>"},"uuid":"u5","timestamp":"2026-09-12T03:41:00.000Z"}"#;
const MODEL_OUTPUT_LINE: &str = r#"{"parentUuid":"u5","isSidechain":false,"type":"user","message":{"role":"user","content":"<local-command-stdout>Set model to `Opus 5 (1M context) (default)` and saved as your default for new sessions</local-command-stdout>"},"uuid":"u6","timestamp":"2026-09-12T03:41:00.100Z"}"#;
const SKILL_COMMAND_LINE: &str = r#"{"parentUuid":"p1","isSidechain":false,"type":"user","message":{"role":"user","content":"<command-message>design</command-message>\n<command-name>/design</command-name>\n<command-args>tidy the settings layout</command-args>"},"uuid":"u7","timestamp":"2026-09-12T03:42:00.000Z"}"#;

// MARK: - SessionRecap parsing

#[test]
fn cleaned_text_drops_the_config_hint() {
    assert_eq!(
        SessionRecap::cleaned_text(Some(&json!(
            "Committed and deployed. Next: decide on backups. (disable recaps in /config)"
        )))
        .as_deref(),
        Some("Committed and deployed. Next: decide on backups.")
    );
}

#[test]
fn cleaned_text_keeps_ordinary_trailing_parentheticals() {
    assert_eq!(
        SessionRecap::cleaned_text(Some(&json!("  Fix shipped (commit 11be844)  "))).as_deref(),
        Some("Fix shipped (commit 11be844)")
    );
    assert_eq!(SessionRecap::cleaned_text(Some(&json!("   "))), None);
    assert_eq!(SessionRecap::cleaned_text(None), None);
    assert_eq!(
        SessionRecap::cleaned_text(Some(&json!("(disable recaps in /config)"))),
        None
    );
}

#[test]
fn recap_from_transcript_line_uses_its_timestamp() {
    let line: Value = serde_json::from_str(&recap_line(
        "All tests pass.",
        "2026-09-12T03:35:41.545Z",
        false,
    ))
    .unwrap();
    let recap = SessionRecap::from_transcript_line(line.as_object().unwrap(), Timestamp(0.0))
        .expect("a recap");
    assert_eq!(recap.text, "All tests pass.");
    assert_eq!(
        recap.created_at,
        parse_iso8601("2026-09-12T03:35:41.545Z").unwrap()
    );
}

#[test]
fn recap_ignores_other_subtypes_and_sidechains() {
    let other: Value = serde_json::from_str(&system_line("turn_duration")).unwrap();
    assert_eq!(
        SessionRecap::from_transcript_line(other.as_object().unwrap(), Timestamp(0.0)),
        None
    );
    let sidechain: Value =
        serde_json::from_str(&recap_line("x", "2026-09-12T03:35:41.545Z", true)).unwrap();
    assert_eq!(
        SessionRecap::from_transcript_line(sidechain.as_object().unwrap(), Timestamp(0.0)),
        None
    );
}

#[test]
fn prompt_at_or_after_the_recap_supersedes_it() {
    let recap = SessionRecap::new("r", Timestamp(100.0));
    assert!(recap.is_superseded(Timestamp(100.0)));
    assert!(recap.is_superseded(Timestamp(101.0)));
    assert!(!recap.is_superseded(Timestamp(99.0)));
}

// MARK: - Byte probe

#[test]
fn probe_lets_only_recap_system_rows_through() {
    assert_eq!(
        quick_type_probe(recap_line("r", "2026-09-12T03:35:41.545Z", false).as_bytes()),
        QuickTypeKind::ClaudeRecap
    );
    for subtype in [
        "turn_duration",
        "stop_hook_summary",
        "compact_boundary",
        "local_command",
    ] {
        assert_eq!(
            quick_type_probe(system_line(subtype).as_bytes()),
            QuickTypeKind::Irrelevant,
            "{subtype}"
        );
    }
}

#[test]
fn probe_lets_codex_turn_context_through() {
    assert_eq!(
        quick_type_probe(turn_context_line("gpt-5.6-sol", "max").as_bytes()),
        QuickTypeKind::CodexTurnContext
    );
}

// MARK: - scanLines: recap

#[test]
fn scan_picks_up_a_recap() {
    let delta = scan(&[
        user_line("ship it"),
        assistant_line("claude-opus-5-5", None, None, false, "done"),
        recap_line(
            "Shipped. (disable recaps in /config)",
            "2026-09-12T03:50:00.000Z",
            false,
        ),
    ]);
    assert_eq!(
        delta
            .session_recap
            .as_ref()
            .map(|recap| recap.text.as_str()),
        Some("Shipped.")
    );
    assert!(!delta.is_empty());
}

#[test]
fn recap_only_chunk_is_not_empty() {
    let delta = scan(&[recap_line("Idle recap", "2026-09-12T03:50:00.000Z", false)]);
    assert_eq!(
        delta
            .session_recap
            .as_ref()
            .map(|recap| recap.text.as_str()),
        Some("Idle recap")
    );
    assert!(!delta.is_empty());
    assert!(!delta.has_activity, "a recap is not agent activity");
}

#[test]
fn prompt_after_recap_in_the_same_chunk_supersedes_it() {
    let delta = scan(&[
        recap_line("old recap", "2026-09-12T03:50:00.000Z", false),
        user_line("next task"),
    ]);
    assert_eq!(delta.session_recap, None);
    assert_eq!(delta.last_user_prompt.as_deref(), Some("next task"));
}

#[test]
fn recap_after_prompt_in_the_same_chunk_survives() {
    let delta = scan(&[
        user_line("task"),
        assistant_line("claude-opus-5-5", None, None, false, "done"),
        recap_line("new recap", "2026-09-12T03:50:00.000Z", false),
    ]);
    assert_eq!(
        delta
            .session_recap
            .as_ref()
            .map(|recap| recap.text.as_str()),
        Some("new recap")
    );
    assert_eq!(delta.last_user_prompt.as_deref(), Some("task"));
}

#[test]
fn tool_result_user_rows_do_not_supersede_a_recap() {
    let tool_result = r#"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}"#;
    let delta = scan(&[
        recap_line("recap", "2026-09-12T03:50:00.000Z", false),
        tool_result.to_owned(),
    ]);
    assert_eq!(
        delta
            .session_recap
            .as_ref()
            .map(|recap| recap.text.as_str()),
        Some("recap")
    );
}

#[test]
fn local_slash_commands_neither_clear_the_recap_nor_become_the_prompt() {
    let delta = scan(&[
        recap_line("Shipped v2.", "2026-09-12T03:50:00.000Z", false),
        MODEL_COMMAND_LINE.to_owned(),
        MODEL_OUTPUT_LINE.to_owned(),
    ]);
    assert_eq!(
        delta
            .session_recap
            .as_ref()
            .map(|recap| recap.text.as_str()),
        Some("Shipped v2.")
    );
    assert_eq!(delta.last_user_prompt, None);
}

#[test]
fn a_prompt_command_starts_a_turn_and_reads_as_typed() {
    let delta = scan(&[
        recap_line("Shipped v2.", "2026-09-12T03:50:00.000Z", false),
        SKILL_COMMAND_LINE.to_owned(),
    ]);
    assert_eq!(delta.session_recap, None);
    assert_eq!(
        delta.last_user_prompt.as_deref(),
        Some("/design tidy the settings layout")
    );
}

#[test]
fn command_echo_classification() {
    assert_eq!(
        claude_command_echo(
            "<command-name>/effort</command-name>\n<command-message>effort</command-message>\n<command-args>high</command-args>"
        ),
        Some(ClaudeCommandEcho::Local)
    );
    assert_eq!(
        claude_command_echo("<local-command-stderr>Error: nope</local-command-stderr>"),
        Some(ClaudeCommandEcho::Local)
    );
    assert_eq!(
        claude_command_echo(
            "<command-message>review</command-message>\n<command-name>review</command-name>"
        ),
        Some(ClaudeCommandEcho::Prompt("/review".into()))
    );
    assert_eq!(
        claude_command_echo(r#"<pasted_content id="1">x</pasted_content> what is this?"#),
        None
    );
    assert_eq!(claude_command_echo("fix the <command-name> parser"), None);
}

// MARK: - scanLines: model observation

#[test]
fn claude_assistant_line_yields_model_and_effort() {
    let delta = scan(&[assistant_line(
        "claude-opus-5-5",
        Some("xhigh"),
        None,
        false,
        "done",
    )]);
    assert_eq!(
        delta.model_observation,
        Some(ModelObservation::new(
            "claude-opus-5-5",
            Some("xhigh".into())
        ))
    );
}

#[test]
fn per_turn_effort_wins_over_session_effort() {
    let delta = scan(&[assistant_line(
        "claude-opus-5-5",
        Some("xhigh"),
        Some("max"),
        false,
        "done",
    )]);
    assert_eq!(
        delta
            .model_observation
            .as_ref()
            .and_then(|observation| observation.effort.clone()),
        Some("max".into())
    );
}

#[test]
fn newest_assistant_line_wins_and_clears_stale_effort() {
    let delta = scan(&[
        assistant_line("claude-opus-5-5", Some("xhigh"), None, false, "done"),
        assistant_line("claude-haiku-4-5-20251001", None, None, false, "done"),
    ]);
    assert_eq!(
        delta.model_observation,
        Some(ModelObservation::new("claude-haiku-4-5-20251001", None))
    );
}

#[test]
fn sidechain_and_synthetic_lines_do_not_relabel_the_session() {
    let delta = scan(&[
        assistant_line("claude-opus-5-5", Some("xhigh"), None, false, "done"),
        assistant_line("claude-haiku-4-5-20251001", Some("low"), None, true, "done"),
        assistant_line("<synthetic>", None, None, false, "API Error"),
    ]);
    assert_eq!(
        delta.model_observation,
        Some(ModelObservation::new(
            "claude-opus-5-5",
            Some("xhigh".into())
        ))
    );
}

#[test]
fn codex_turn_context_yields_model_and_effort() {
    let delta = scan(&[turn_context_line("gpt-5.6-sol", "max")]);
    assert_eq!(
        delta.model_observation,
        Some(ModelObservation::new("gpt-5.6-sol", Some("max".into())))
    );
    assert!(!delta.has_activity);
    assert_eq!(delta.turn_status, None);
}

#[test]
fn codex_turn_context_falls_back_to_collaboration_settings() {
    let line = r#"{"timestamp":"t","type":"turn_context","payload":{"cwd":"/r","collaboration_mode":{"mode":"default","settings":{"model":"gpt-6-astra","reasoning_effort":"high"}}}}"#;
    assert_eq!(
        scan(&[line.to_owned()]).model_observation,
        Some(ModelObservation::new("gpt-6-astra", Some("high".into())))
    );
}

#[test]
fn model_switch_output_sets_the_1m_variant() {
    let on = scan(&[
        assistant_line("claude-opus-5-5", Some("xhigh"), None, false, "done"),
        MODEL_COMMAND_LINE.to_owned(),
        MODEL_OUTPUT_LINE.to_owned(),
    ]);
    assert_eq!(on.configured_long_context, Some(true));
    assert_eq!(
        on.model_observation, None,
        "a model seen before the switch is out of date"
    );

    let off_output = r#"{"type":"user","message":{"role":"user","content":"<local-command-stdout>Set model to \u001b[1mOpus 5.5\u001b[22m and saved as your default for new sessions</local-command-stdout>"}}"#;
    assert_eq!(
        scan(&[off_output.to_owned()]).configured_long_context,
        Some(false),
        "ANSI bold is not a [1m] tag"
    );
    let effort_output = r#"{"type":"user","message":{"role":"user","content":"<local-command-stdout>Set effort level to high</local-command-stdout>"}}"#;
    assert_eq!(
        scan(&[effort_output.to_owned()]).configured_long_context,
        None
    );
}

// MARK: - Attach-time backfill window

#[test]
fn scan_tail_for_attach_reads_only_the_window_and_survives_a_cut_first_line() {
    let padding = assistant_line("claude-opus-4-8", None, None, false, &"x".repeat(4_000));
    let body = [
        padding,
        user_line("go"),
        assistant_line("claude-opus-5-5", Some("high"), None, false, "done"),
        recap_line("Tail recap", "2026-09-12T03:50:00.000Z", false),
    ]
    .join("\n")
        + "\n";
    let size = body.len() as u64;
    let max_bytes = 1_500u64;
    let start = size - max_bytes - 1;

    let tail = scan_tail_for_attach(&body.as_bytes()[start as usize..], start, size);
    assert_eq!(
        tail.delta
            .session_recap
            .as_ref()
            .map(|recap| recap.text.as_str()),
        Some("Tail recap")
    );
    assert_eq!(
        tail.delta.model_observation,
        Some(ModelObservation::new(
            "claude-opus-5-5",
            Some("high".into())
        ))
    );
    assert_eq!(scan_tail_for_attach(b"", 0, 0).delta, ScanDelta::default());
}

// MARK: - Snapshot: live tail semantics

fn session() -> SessionSnapshot {
    SessionSnapshot::new(Timestamp(0.0))
}

fn live_delta(
    prompt: Option<&str>,
    recap: Option<SessionRecap>,
    model: Option<ModelObservation>,
) -> ScanDelta {
    ScanDelta {
        last_user_prompt: prompt.map(str::to_owned),
        session_recap: recap,
        model_observation: model,
        ..ScanDelta::default()
    }
}

#[test]
fn live_recap_is_adopted_without_touching_last_activity() {
    let mut session = session();
    session.last_activity = Timestamp(1_000.0);
    let recap = SessionRecap::new("r", Timestamp(2_000.0));

    assert!(session.apply_transcript_delta(&live_delta(None, Some(recap.clone()), None)));
    assert_eq!(session.recap, Some(recap.clone()));
    assert_eq!(session.last_activity, Timestamp(1_000.0));
    assert!(
        !session.apply_transcript_delta(&live_delta(None, Some(recap), None)),
        "unchanged recap is a no-op"
    );
}

#[test]
fn live_prompt_clears_the_recap() {
    let mut session = session();
    session.recap = Some(SessionRecap::new("r", Timestamp(2_000.0)));
    assert!(session.apply_transcript_delta(&live_delta(Some("next"), None, None)));
    assert_eq!(session.recap, None);
}

#[test]
fn live_chunk_without_prompt_or_recap_keeps_the_recap() {
    let mut session = session();
    let recap = SessionRecap::new("r", Timestamp(2_000.0));
    session.recap = Some(recap.clone());
    assert!(!session.apply_transcript_delta(&live_delta(None, None, None)));
    assert_eq!(session.recap, Some(recap));
}

#[test]
fn live_model_keeps_the_context_variant_and_tracks_effort() {
    let mut session = session();
    session.model = Some("claude-opus-5-5[1m]".into());
    assert!(session.apply_transcript_delta(&live_delta(
        None,
        None,
        Some(ModelObservation::new(
            "claude-opus-5-5",
            Some("xhigh".into())
        ))
    )));
    assert_eq!(session.model.as_deref(), Some("claude-opus-5-5[1m]"));
    assert_eq!(session.reasoning_effort.as_deref(), Some("xhigh"));
    assert_eq!(
        session.model_label().as_deref(),
        Some("Opus 5.5 1M \u{b7} xhigh")
    );

    assert!(session.apply_transcript_delta(&live_delta(
        None,
        None,
        Some(ModelObservation::new("claude-sonnet-5", None))
    )));
    assert_eq!(session.model.as_deref(), Some("claude-sonnet-5"));
    assert_eq!(
        session.reasoning_effort, None,
        "a model without effort must not inherit the old one"
    );
}

// MARK: - Snapshot: attach-time backfill

#[test]
fn backfill_is_authoritative_for_the_recap() {
    let mut session = session();
    session.recap = Some(SessionRecap::new("persisted", Timestamp(1.0)));

    let superseded = scan(&[
        recap_line("persisted", "2026-09-12T03:50:00.000Z", false),
        user_line("typed while Morrow was closed"),
    ]);
    assert!(session.apply_transcript_backfill(&superseded));
    assert_eq!(session.recap, None);

    let fresh = scan(&[
        user_line("task"),
        recap_line("fresh", "2026-09-12T03:50:00.000Z", false),
    ]);
    assert!(session.apply_transcript_backfill(&fresh));
    assert_eq!(
        session.recap.as_ref().map(|recap| recap.text.as_str()),
        Some("fresh")
    );

    assert!(session.apply_transcript_backfill(&scan(&[assistant_line(
        "claude-opus-5-5",
        None,
        None,
        false,
        "done"
    )])));
    assert_eq!(
        session.recap, None,
        "no recap in the tail means none is current"
    );
}

fn timed_assistant_line(model: &str, effort: &str, at: &str) -> String {
    json!({
        "parentUuid": "p1",
        "isSidechain": false,
        "message": {
            "model": model,
            "id": "msg_1",
            "type": "message",
            "role": "assistant",
            "content": [{"type": "text", "text": "ok"}],
        },
        "type": "assistant",
        "uuid": "u4",
        "timestamp": at,
        "effort": effort,
    })
    .to_string()
}

#[test]
fn backfill_keeps_a_model_a_hook_reported_after_the_scanned_lines() {
    // `claude --resume --model sonnet` over a transcript that ran on Opus:
    // SessionStart reported the new model before the attach scan.
    let mut session = session();
    session.model = Some("claude-sonnet-5".into());
    session.model_reported_at = parse_iso8601("2026-09-12T04:00:00.000Z");

    let older = scan(&[timed_assistant_line(
        "claude-opus-5-5",
        "xhigh",
        "2026-09-12T03:59:00.000Z",
    )]);
    assert!(!session.apply_transcript_backfill(&older));
    assert_eq!(session.model.as_deref(), Some("claude-sonnet-5"));
    assert_eq!(
        session.reasoning_effort, None,
        "Opus's effort does not describe Sonnet"
    );

    // An older line on the same model still lends its effort.
    let same_model = scan(&[timed_assistant_line(
        "claude-sonnet-5",
        "high",
        "2026-09-12T03:58:00.000Z",
    )]);
    assert!(session.apply_transcript_backfill(&same_model));
    assert_eq!(
        session.model_label().as_deref(),
        Some("Sonnet 5 \u{b7} high")
    );

    // A line written after the report is newer than it.
    let newer = scan(&[timed_assistant_line(
        "claude-opus-5-5",
        "max",
        "2026-09-12T04:01:00.000Z",
    )]);
    assert!(session.apply_transcript_backfill(&newer));
    assert_eq!(
        session.model_label().as_deref(),
        Some("Opus 5.5 \u{b7} max")
    );
}

#[test]
fn backfill_of_a_restored_session_takes_the_transcript_model() {
    let mut session = session();
    session.model = Some("claude-sonnet-5".into());
    let delta = scan(&[timed_assistant_line(
        "claude-opus-5-5",
        "xhigh",
        "2026-09-12T03:59:00.000Z",
    )]);
    assert!(session.apply_transcript_backfill(&delta));
    assert_eq!(
        session.model_label().as_deref(),
        Some("Opus 5.5 \u{b7} xhigh")
    );
}

#[test]
fn session_start_hook_records_when_it_reported_the_model() {
    let sources = SourceCatalog::default();
    let clock = || Timestamp(1_000.0);
    let ctx = ReduceContext {
        clock: &clock,
        sources: &sources,
        home_directory: "/home/morrow",
        max_history: 10,
        reply_complete_placeholder: "Reply complete",
    };
    let event: serde_json::Value = serde_json::from_str(
        r#"{"hook_event_name":"SessionStart","session_id":"s1","source":"resume","model":"claude-sonnet-5","cwd":"/repo"}"#,
    )
    .unwrap();
    let event = HookEvent::new(event.as_object().unwrap().clone(), &sources).expect("a hook event");

    let mut sessions = Sessions::new();
    reduce_hook_event(&mut sessions, &event, &ctx);
    let session = sessions.get("s1").expect("the session");
    assert_eq!(session.model.as_deref(), Some("claude-sonnet-5"));
    assert_eq!(session.model_reported_at, Some(Timestamp(1_000.0)));
}

#[test]
fn switching_to_and_from_the_1m_variant_relabels_the_session() {
    let mut session = session();
    session.model = Some("claude-opus-5-5".into());
    let live = |long_context: Option<bool>, model: Option<&str>| ScanDelta {
        configured_long_context: long_context,
        model_observation: model.map(|model| ModelObservation::new(model, Some("xhigh".into()))),
        ..ScanDelta::default()
    };

    assert!(session.apply_transcript_delta(&live(Some(true), None)));
    assert_eq!(session.model_label().as_deref(), Some("Opus 5.5 1M"));
    session.apply_transcript_delta(&live(None, Some("claude-opus-5-5")));
    assert_eq!(
        session.model_label().as_deref(),
        Some("Opus 5.5 1M \u{b7} xhigh"),
        "the bare API id keeps the 1M variant"
    );

    assert!(session.apply_transcript_delta(&live(Some(false), None)));
    assert_eq!(
        session.model_label().as_deref(),
        Some("Opus 5.5 \u{b7} xhigh")
    );
    session.apply_transcript_delta(&live(None, Some("claude-opus-5-5")));
    assert_eq!(
        session.model_label().as_deref(),
        Some("Opus 5.5 \u{b7} xhigh"),
        "and loses it once switched off"
    );

    // Switching model and variant at once: the next line names the model.
    session.model = Some("claude-sonnet-5".into());
    session.apply_transcript_delta(&live(Some(true), None));
    session.apply_transcript_delta(&live(None, Some("claude-opus-5")));
    assert_eq!(session.model.as_deref(), Some("claude-opus-5[1m]"));
}

// MARK: - Reducer and card state

fn hook_event(payload: Value, sources: &SourceCatalog) -> HookEvent {
    HookEvent::new(payload.as_object().unwrap().clone(), sources).expect("a hook event")
}

#[test]
fn user_prompt_submit_hook_clears_the_recap_but_other_events_keep_it() {
    let sources = SourceCatalog::default();
    let clock = || Timestamp(2_000.0);
    let ctx = ReduceContext {
        clock: &clock,
        sources: &sources,
        home_directory: "/home/morrow",
        max_history: 10,
        reply_complete_placeholder: "Reply complete",
    };
    let mut first = session();
    first.recap = Some(SessionRecap::new("r", Timestamp(1_000.0)));
    let mut sessions: Sessions = [("s1".to_owned(), first)].into_iter().collect();

    let notification = hook_event(
        json!({"hook_event_name": "Notification", "session_id": "s1", "message": "idle"}),
        &sources,
    );
    reduce_hook_event(&mut sessions, &notification, &ctx);
    assert!(sessions["s1"].recap.is_some());

    let prompt = hook_event(
        json!({"hook_event_name": "UserPromptSubmit", "session_id": "s1", "prompt": "next"}),
        &sources,
    );
    reduce_hook_event(&mut sessions, &prompt, &ctx);
    assert_eq!(sessions["s1"].recap, None);
}

#[test]
fn visible_recap_only_while_idle() {
    let mut session = session();
    session.recap = Some(SessionRecap::new("r", Timestamp(2_000.0)));
    session.status = AgentStatus::Idle;
    assert!(session.visible_recap().is_some());
    for status in [
        AgentStatus::Processing,
        AgentStatus::Running,
        AgentStatus::WaitingApproval,
        AgentStatus::WaitingQuestion,
    ] {
        session.status = status;
        assert!(session.visible_recap().is_none(), "{status:?}");
    }
}

// MARK: - Subagent models

#[test]
fn codex_child_keeps_its_own_model_and_never_the_parents() {
    let sources = SourceCatalog::default();
    let clock = || Timestamp(1_000.0);
    let ctx = ReduceContext {
        clock: &clock,
        sources: &sources,
        home_directory: "/home/morrow",
        max_history: 10,
        reply_complete_placeholder: "Reply complete",
    };
    let mut parent = session();
    parent.source = "codex".into();
    parent.model = Some("gpt-5.6-sol".into());
    let mut sessions: Sessions = [("parent".to_owned(), parent)].into_iter().collect();

    let start = hook_event(
        json!({
            "hook_event_name": "SessionStart", "session_id": "parent", "_source": "codex",
            "agent_id": "child", "agent_type": "worker", "model": "gpt-5.4-mini",
        }),
        &sources,
    );
    reduce_hook_event(&mut sessions, &start, &ctx);
    assert_eq!(
        sessions["parent"].subagents["child"].model.as_deref(),
        Some("gpt-5.4-mini")
    );
    assert_eq!(sessions["parent"].model.as_deref(), Some("gpt-5.6-sol"));

    // Later child hooks without a model leave it alone.
    let step = hook_event(
        json!({
            "hook_event_name": "PreToolUse", "session_id": "parent", "_source": "codex",
            "agent_id": "child", "tool_name": "Bash", "tool_input": {"command": "ls"},
        }),
        &sources,
    );
    reduce_hook_event(&mut sessions, &step, &ctx);
    assert_eq!(
        sessions["parent"].subagents["child"].model.as_deref(),
        Some("gpt-5.4-mini")
    );
}

#[test]
fn claude_subagent_without_model_stays_unlabeled() {
    let sources = SourceCatalog::default();
    let clock = || Timestamp(1_000.0);
    let ctx = ReduceContext {
        clock: &clock,
        sources: &sources,
        home_directory: "/home/morrow",
        max_history: 10,
        reply_complete_placeholder: "Reply complete",
    };
    let mut parent = session();
    parent.model = Some("claude-opus-5-5".into());
    parent.reasoning_effort = Some("xhigh".into());
    let mut sessions: Sessions = [("parent".to_owned(), parent)].into_iter().collect();

    let start = hook_event(
        json!({
            "hook_event_name": "SubagentStart", "session_id": "parent",
            "agent_id": "a1", "agent_type": "Explore",
        }),
        &sources,
    );
    reduce_hook_event(&mut sessions, &start, &ctx);
    let subagent = &sessions["parent"].subagents["a1"];
    assert_eq!(subagent.model, None);
    assert_eq!(subagent.model_label(), None);
}

#[test]
fn claude_subagent_transcript_path_derivation() {
    assert_eq!(
        SubagentState::claude_transcript_path(
            "/u/.claude/projects/-repo/3fdc50ad.jsonl",
            "a6914a36aae8b67eb"
        )
        .as_deref(),
        Some("/u/.claude/projects/-repo/3fdc50ad/subagents/agent-a6914a36aae8b67eb.jsonl")
    );
    assert_eq!(
        SubagentState::claude_transcript_path("/u/x.json", "a1"),
        None
    );
    assert_eq!(
        SubagentState::claude_transcript_path("/u/x.jsonl", "../a1"),
        None
    );
    assert_eq!(
        SubagentState::claude_transcript_path("/u/x.jsonl", ""),
        None
    );
}

// MARK: - The probe keeps the realistic mix fast

#[test]
fn recap_aware_probe_keeps_the_realistic_mix_fast() {
    // Every Claude turn ends with turn_duration + stop_hook_summary rows; they
    // must stay on the no-parse path now that `system` is a probe case.
    let mix = [
        user_line("q"),
        assistant_line("claude-opus-5-5", Some("xhigh"), None, false, "done"),
        system_line("turn_duration"),
        system_line("stop_hook_summary"),
        format!(
            r#"{{"type":"user","message":{{"role":"user","content":[{{"type":"tool_result","tool_use_id":"t1","content":"{}"}}]}}}}"#,
            "y".repeat(800)
        ),
        recap_line("r", "2026-09-12T03:50:00.000Z", false),
    ];
    let mut blob = String::new();
    while blob.len() < 1_000_000 {
        for line in &mix {
            blob.push_str(line);
            blob.push('\n');
        }
    }
    let start = std::time::Instant::now();
    let delta = scan_lines(blob.as_bytes()).delta;
    let elapsed_ms = start.elapsed().as_secs_f64() * 1000.0;
    assert_eq!(
        delta
            .session_recap
            .as_ref()
            .map(|recap| recap.text.as_str()),
        Some("r")
    );
    assert!(elapsed_ms < 5_000.0, "took {elapsed_ms} ms");
}
