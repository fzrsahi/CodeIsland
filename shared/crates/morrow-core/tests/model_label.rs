//! `ModelLabelTests` (`macos/Tests/MorrowCoreTests/ModelLabelTests.swift`), ported
//! one test to one test: the friendly model tag, the merge rules a transcript
//! line obeys, and the two backward searches over transcript rows (fed bytes
//! here, where Swift reads a file).

use serde_json::{Value, json};

use morrow_core::model_label::{
    ModelObservation, display_name, label, latest_codex_turn_context, latest_in_claude_transcript,
    long_context_switch, merged_model_id, with_long_context,
};
use morrow_core::time::parse_iso8601;

fn name(raw: &str) -> Option<String> {
    display_name(Some(raw))
}

// MARK: - displayName: Claude ids

#[test]
fn claude_family_first_ids_become_friendly_names() {
    assert_eq!(name("claude-opus-5-5").as_deref(), Some("Opus 5.5"));
    assert_eq!(name("claude-sonnet-5").as_deref(), Some("Sonnet 5"));
    assert_eq!(
        name("claude-haiku-4-5-20251001").as_deref(),
        Some("Haiku 4.5")
    );
    assert_eq!(name("claude-fable-5-1").as_deref(), Some("Fable 5.1"));
    assert_eq!(name("claude-opus-4-8").as_deref(), Some("Opus 4.8"));
    assert_eq!(name("claude-opus-5").as_deref(), Some("Opus 5"));
}

#[test]
fn long_context_suffix_appends_1m() {
    assert_eq!(name("claude-opus-5-5[1m]").as_deref(), Some("Opus 5.5 1M"));
    assert_eq!(name("claude-sonnet-5[1M]").as_deref(), Some("Sonnet 5 1M"));
    assert_eq!(name("opus[1m]").as_deref(), Some("Opus 1M"));
}

#[test]
fn legacy_version_first_claude_ids() {
    assert_eq!(
        name("claude-3-5-sonnet-20241022").as_deref(),
        Some("Sonnet 3.5")
    );
    assert_eq!(name("claude-3-opus-20240229").as_deref(), Some("Opus 3"));
}

#[test]
fn claude_aliases_are_capitalized() {
    assert_eq!(name("opus").as_deref(), Some("Opus"));
    assert_eq!(name("sonnet").as_deref(), Some("Sonnet"));
}

#[test]
fn provider_routing_decoration_is_stripped() {
    assert_eq!(
        name("anthropic/claude-sonnet-4").as_deref(),
        Some("Sonnet 4")
    );
    assert_eq!(
        name("us.anthropic.claude-sonnet-4-5-20250929-v1:0").as_deref(),
        Some("Sonnet 4.5")
    );
    assert_eq!(
        name("claude-sonnet-4-5@20250929").as_deref(),
        Some("Sonnet 4.5")
    );
}

// MARK: - displayName: everything else

#[test]
fn non_claude_ids_keep_their_spelling_minus_dates() {
    assert_eq!(name("gpt-5.6-sol").as_deref(), Some("gpt-5.6-sol"));
    assert_eq!(name("gpt-6-astra").as_deref(), Some("gpt-6-astra"));
    assert_eq!(name("gpt-4o-2024-08-06").as_deref(), Some("gpt-4o"));
    assert_eq!(name("some-model-20250514").as_deref(), Some("some-model"));
    assert_eq!(name("github-copilot/gpt-5.4").as_deref(), Some("gpt-5.4"));
}

#[test]
fn names_that_merely_end_in_a_version_are_not_mangled() {
    assert_eq!(name("deepseek-v3").as_deref(), Some("deepseek-v3"));
    assert_eq!(
        name("gemini-2.5-pro-preview-05-06").as_deref(),
        Some("gemini-2.5-pro-preview-05-06")
    );
    assert_eq!(name("kimi-k2").as_deref(), Some("kimi-k2"));
}

#[test]
fn unknown_claude_shapes_fall_back_to_the_raw_id() {
    assert_eq!(
        name("claude-opus-5-5-thinking").as_deref(),
        Some("claude-opus-5-5-thinking")
    );
    assert_eq!(name("claude-2.1").as_deref(), Some("claude-2.1"));
    assert_eq!(
        name("claude-opus-5-5-1-2").as_deref(),
        Some("claude-opus-5-5-1-2")
    );
}

#[test]
fn empty_and_placeholder_ids_have_no_name() {
    assert_eq!(display_name(None), None);
    assert_eq!(display_name(Some("")), None);
    assert_eq!(display_name(Some("   ")), None);
    assert_eq!(display_name(Some("<synthetic>")), None);
}

// MARK: - label

#[test]
fn label_appends_normalized_effort() {
    assert_eq!(
        label(Some("claude-opus-5-5"), Some("xhigh")).as_deref(),
        Some("Opus 5.5 \u{b7} xhigh")
    );
    assert_eq!(
        label(Some("gpt-5.6-sol"), Some(" MAX ")).as_deref(),
        Some("gpt-5.6-sol \u{b7} max")
    );
    assert_eq!(
        label(Some("claude-opus-5-5[1m]"), Some("high")).as_deref(),
        Some("Opus 5.5 1M \u{b7} high")
    );
}

#[test]
fn label_without_effort_is_just_the_name() {
    assert_eq!(
        label(Some("claude-sonnet-5"), None).as_deref(),
        Some("Sonnet 5")
    );
    assert_eq!(
        label(Some("claude-sonnet-5"), Some("  ")).as_deref(),
        Some("Sonnet 5")
    );
}

#[test]
fn effort_alone_produces_no_label() {
    assert_eq!(label(None, Some("xhigh")), None);
}

// MARK: - mergedModelId

#[test]
fn transcript_id_does_not_strip_the_configured_context_variant() {
    assert_eq!(
        merged_model_id(Some("claude-opus-5-5[1m]"), "claude-opus-5-5"),
        "claude-opus-5-5[1m]"
    );
}

#[test]
fn a_real_model_switch_replaces_the_current_id() {
    assert_eq!(
        merged_model_id(Some("claude-opus-5-5[1m]"), "claude-sonnet-5"),
        "claude-sonnet-5"
    );
    assert_eq!(
        merged_model_id(Some("opus"), "claude-opus-5-5"),
        "claude-opus-5-5"
    );
    assert_eq!(merged_model_id(None, "gpt-5.6-sol"), "gpt-5.6-sol");
}

// MARK: - ModelObservation

#[test]
fn observation_rejects_placeholders_and_normalizes_effort() {
    assert_eq!(
        ModelObservation::from_values(Some(&json!("<synthetic>")), Some(&json!("xhigh")), None),
        None
    );
    assert_eq!(
        ModelObservation::from_values(None, Some(&json!("xhigh")), None),
        None
    );
    assert_eq!(
        ModelObservation::from_values(Some(&json!(42)), None, None),
        None
    );
    assert_eq!(
        ModelObservation::from_values(
            Some(&json!(" claude-opus-5-5 ")),
            Some(&json!("XHigh")),
            None
        ),
        Some(ModelObservation::new(
            "claude-opus-5-5",
            Some("xhigh".into())
        ))
    );
}

#[test]
fn latest_in_claude_transcript_reads_sidechain_lines_newest_first() {
    let lines = [
        r#"{"isSidechain":true,"type":"user","message":{"role":"user","content":"find the bug"}}"#,
        r#"{"isSidechain":true,"message":{"model":"claude-haiku-4-5-20251001","role":"assistant","content":[{"type":"text","text":"a"}]},"type":"assistant","effort":"low"}"#,
        r#"{"isSidechain":true,"message":{"model":"claude-sonnet-5","role":"assistant","content":[{"type":"text","text":"b"}]},"type":"assistant","effort":"high"}"#,
        r#"{"isSidechain":true,"message":{"model":"<synthetic>","role":"assistant","content":[{"type":"text","text":"API Error"}]},"type":"assistant"}"#,
    ]
    .join("\n");

    assert_eq!(
        latest_in_claude_transcript(lines.as_bytes()),
        Some(ModelObservation::new(
            "claude-sonnet-5",
            Some("high".into())
        ))
    );
    assert_eq!(latest_in_claude_transcript(b""), None);
}

#[test]
fn observation_keeps_the_lines_timestamp_without_changing_equality() {
    let timed = ModelObservation::from_values(
        Some(&json!("gpt-5.6-sol")),
        Some(&json!("max")),
        Some(&json!("2026-09-24T09:05:19.777Z")),
    );
    assert_eq!(
        timed.as_ref().and_then(ModelObservation::observed_at),
        parse_iso8601("2026-09-24T09:05:19.777Z")
    );
    assert_eq!(
        timed,
        Some(ModelObservation::new("gpt-5.6-sol", Some("max".into())))
    );
    assert_eq!(
        ModelObservation::from_values(Some(&json!("gpt-5.6-sol")), None, Some(&json!("t")))
            .and_then(|observation| observation.observed_at()),
        None
    );
}

// MARK: - Codex turn_context search

fn turn_context_line(effort: &str, turn: &str) -> String {
    json!({
        "timestamp": "2026-09-24T09:05:19.777Z",
        "ordinal": 1,
        "type": "turn_context",
        "payload": {
            "turn_id": turn,
            "cwd": "/repo",
            "model": "gpt-5.6-sol",
            "effort": effort,
            "summary": "auto",
        }
    })
    .to_string()
}

fn tool_output_line(bytes: usize) -> String {
    json!({
        "timestamp": "2026-09-24T09:05:20.000Z",
        "type": "response_item",
        "payload": {
            "type": "function_call_output",
            "call_id": "c",
            "output": "o".repeat(bytes),
        }
    })
    .to_string()
}

const MAX_BYTES: u64 = 2 * 1024 * 1024;

#[test]
fn latest_codex_turn_context_searches_back_past_the_tail_window() {
    let mut lines = vec![
        turn_context_line("low", "t1"),
        turn_context_line("max", "t2"),
    ];
    lines.extend(std::iter::repeat_n(tool_output_line(3_000), 60));
    let data = lines.join("\n") + "\n";

    // Small chunks, so the row straddles chunk boundaries on the way back.
    let found = latest_codex_turn_context(data.as_bytes(), None, MAX_BYTES, 1_000);
    assert_eq!(
        found,
        Some(ModelObservation::new("gpt-5.6-sol", Some("max".into())))
    );
    assert!(
        found
            .and_then(|observation| observation.observed_at())
            .is_some()
    );
    assert_eq!(
        latest_codex_turn_context(data.as_bytes(), None, MAX_BYTES, 128 * 1024),
        latest_codex_turn_context(data.as_bytes(), None, MAX_BYTES, 1_000)
    );
}

#[test]
fn latest_codex_turn_context_honours_the_end_offset_and_the_search_bound() {
    let head = [turn_context_line("low", "t1"), tool_output_line(500)].join("\n") + "\n";
    let data = [
        turn_context_line("low", "t1"),
        tool_output_line(500),
        turn_context_line("max", "t2"),
        tool_output_line(20_000),
    ]
    .join("\n")
        + "\n";

    let bounded =
        latest_codex_turn_context(data.as_bytes(), Some(head.len() as u64), MAX_BYTES, 256);
    assert_eq!(
        bounded.and_then(|observation| observation.effort),
        Some("low".into()),
        "rows past the tailer's start offset are the tailer's"
    );
    assert_eq!(
        latest_codex_turn_context(data.as_bytes(), None, 10_000, 4_096),
        None,
        "the search stops at its bound"
    );
    assert_eq!(latest_codex_turn_context(b"", None, MAX_BYTES, 4_096), None);
}

// MARK: - The 1M switch and the context variant

#[test]
fn long_context_switches_are_read_from_the_models_command_output() {
    assert_eq!(
        long_context_switch("Set model to `Opus 5 (1M context) (default)` and saved"),
        Some(true)
    );
    assert_eq!(
        long_context_switch("Set model to Fable 5 and saved as your default"),
        Some(false)
    );
    assert_eq!(long_context_switch("Set effort level to high"), None);
}

#[test]
fn with_long_context_sets_or_clears_the_bracket_suffix() {
    assert_eq!(
        with_long_context("claude-opus-5-5", true),
        "claude-opus-5-5[1m]"
    );
    assert_eq!(
        with_long_context("claude-opus-5-5[1m]", false),
        "claude-opus-5-5"
    );
    assert_eq!(
        with_long_context("claude-opus-5-5[1m]", true),
        "claude-opus-5-5[1m]"
    );
}

#[test]
fn placeholders_never_become_observations() {
    let placeholder = json!("<synthetic>");
    assert_eq!(
        ModelObservation::from_values(Some(&placeholder), Some(&Value::Null), None),
        None
    );
}
