//! `JSONLTailerTests` and `JSONLTailerCursorQuestionTests` (`macos/Tests/MorrowCoreTests/`),
//! ported one test to one test as far as a pure core can carry them: the
//! parsing tests run as they are, and the attach/detach tests drive
//! [`TailState`] with the bytes a watcher would have read.
//!
//! Two Swift tests are the watcher's own and have no counterpart here —
//! `testDetachStopsFurtherCallbacks` and
//! `testDetachCancelsDelayedReattachAfterFileReplacement` (a `DispatchSource`
//! that stops firing, a delayed reopen after a rename). The lifecycle part of
//! `testFileReplacementReattachesWhenSessionRemainsDesired` is likewise the
//! watcher's; what the replacement delivers is here.

use serde_json::{Value, json};

use morrow_core::transcript::{
    ClaudeCommandEcho, ConversationTurnStatus as TurnStatus, CursorQuestionSignal, QuickTypeKind,
    TailState, claude_command_echo, cursor_question_prompt, extract_text,
    is_cursor_question_tool_name, latest_cursor_question, latest_turn_status,
    normalized_cursor_chat_text, quick_type_probe, scan_lines, scan_tail_for_attach,
    strip_display_wrappers,
};

// MARK: - Fixtures

fn assistant_line(text: &str) -> String {
    json!({
        "type": "assistant",
        "message": {"content": [{"type": "text", "text": text}]}
    })
    .to_string()
}

fn user_line(text: &str) -> String {
    json!({
        "type": "user",
        "message": {"content": text}
    })
    .to_string()
}

fn scan(text: &str) -> morrow_core::transcript::ScanResult {
    scan_lines(text.as_bytes())
}

fn cursor_user_line(text: &str) -> String {
    json!({
        "role": "user",
        "message": {"content": [{"type": "text", "text": text}]}
    })
    .to_string()
}

fn cursor_assistant_text_line(text: &str) -> String {
    json!({
        "role": "assistant",
        "message": {"content": [{"type": "text", "text": text}]}
    })
    .to_string()
}

/// An assistant entry whose content ends in a question `tool_use`.
/// `input_json` is raw JSON for the tool input object.
fn cursor_question_line(tool_name: &str, input_json: &str, leading_text: Option<&str>) -> String {
    let mut blocks: Vec<String> = Vec::new();
    if let Some(leading) = leading_text {
        blocks.push(json!({"type": "text", "text": leading}).to_string());
    }
    blocks.push(format!(
        r#"{{"type":"tool_use","name":"{tool_name}","input":{input_json}}}"#
    ));
    format!(
        r#"{{"role":"assistant","message":{{"content":[{}]}}}}"#,
        blocks.join(",")
    )
}

fn scan_lines_of(lines: &[String]) -> morrow_core::transcript::ScanResult {
    scan(&(lines.join("\n") + "\n"))
}

// MARK: - scanLines (pure)

#[test]
fn scan_lines_empty_input_produces_empty_delta_and_fragment() {
    let result = scan_lines(b"");
    assert!(result.delta.is_empty());
    assert_eq!(result.trailing_fragment, b"");
}

#[test]
fn scan_lines_extracts_assistant_text_from_single_line() {
    let result = scan(&(assistant_line("hello world") + "\n"));
    assert_eq!(
        result.delta.last_assistant_message.as_deref(),
        Some("hello world")
    );
    assert_eq!(result.delta.last_user_prompt, None);
    assert_eq!(result.trailing_fragment, b"");
}

#[test]
fn scan_lines_extracts_user_prompt_from_single_line() {
    let result = scan(&(user_line("what's the weather?") + "\n"));
    assert_eq!(
        result.delta.last_user_prompt.as_deref(),
        Some("what's the weather?")
    );
    assert_eq!(result.delta.last_assistant_message, None);
}

#[test]
fn scan_lines_latest_line_wins_for_each_role() {
    let text = [
        assistant_line("first reply"),
        user_line("first question"),
        assistant_line("second reply"),
        user_line("second question"),
    ]
    .join("\n")
        + "\n";
    let result = scan(&text);
    assert_eq!(
        result.delta.last_assistant_message.as_deref(),
        Some("second reply")
    );
    assert_eq!(
        result.delta.last_user_prompt.as_deref(),
        Some("second question")
    );
}

#[test]
fn scan_lines_trailing_partial_line_returns_as_fragment() {
    let complete_line = assistant_line("done") + "\n";
    let partial = r#"{"type":"assistant","message":{"content":[{"type":"text","text":"half"#;
    let result = scan(&(complete_line.clone() + partial));
    assert_eq!(result.delta.last_assistant_message.as_deref(), Some("done"));
    assert_eq!(result.trailing_fragment, partial.as_bytes());
}

#[test]
fn scan_lines_ignores_is_meta_lines() {
    let meta = r#"{"type":"assistant","isMeta":true,"message":{"content":[{"type":"text","text":"boot"}]}}"#;
    let result = scan(&format!("{meta}\n{}\n", assistant_line("real reply")));
    assert_eq!(
        result.delta.last_assistant_message.as_deref(),
        Some("real reply")
    );
}

#[test]
fn scan_lines_ignores_unknown_type() {
    let line = r#"{"type":"tool_use","message":{"content":[{"type":"text","text":"internal"}]}}"#;
    assert!(scan(&format!("{line}\n")).delta.is_empty());
}

#[test]
fn scan_lines_extracts_antigravity_user_input_with_tags() {
    let line = r#"{"type":"USER_INPUT","content":"<USER_REQUEST>\nhello world\n</USER_REQUEST>"}"#;
    let result = scan(&format!("{line}\n"));
    assert_eq!(
        result.delta.last_user_prompt.as_deref(),
        Some("hello world")
    );
    assert_eq!(result.delta.last_assistant_message, None);
}

#[test]
fn scan_lines_extracts_antigravity_user_input_without_tags() {
    let line = r#"{"type":"USER_INPUT","content":"hello world"}"#;
    let result = scan(&format!("{line}\n"));
    assert_eq!(
        result.delta.last_user_prompt.as_deref(),
        Some("hello world")
    );
    assert_eq!(result.delta.last_assistant_message, None);
}

#[test]
fn scan_lines_extracts_antigravity_planner_response_with_content() {
    let line =
        r#"{"type":"PLANNER_RESPONSE","content":"answer content","thinking":"thought process"}"#;
    let result = scan(&format!("{line}\n"));
    assert_eq!(
        result.delta.last_assistant_message.as_deref(),
        Some("answer content")
    );
    assert_eq!(result.delta.last_user_prompt, None);
}

#[test]
fn scan_lines_extracts_antigravity_planner_response_with_only_thinking() {
    let line = r#"{"type":"PLANNER_RESPONSE","thinking":"thought process"}"#;
    let result = scan(&format!("{line}\n"));
    assert_eq!(
        result.delta.last_assistant_message.as_deref(),
        Some("thought process")
    );
    assert_eq!(result.delta.last_user_prompt, None);
}

#[test]
fn scan_lines_extracts_codex_task_started_as_processing() {
    let line = r#"{"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}"#;
    let result = scan(&format!("{line}\n"));
    assert_eq!(result.delta.turn_status, Some(TurnStatus::Processing));
    assert!(!result.delta.is_empty());
}

#[test]
fn scan_lines_extracts_codex_terminal_turn_events_as_idle() {
    let lines = [
        r#"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1"}}"#,
        r#"{"type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}"#,
        r#"{"type":"event_msg","payload":{"type":"turn_failed","reason":"tool_error"}}"#,
    ]
    .join("\n");
    let result = scan(&(lines + "\n"));
    assert_eq!(result.delta.turn_status, Some(TurnStatus::Idle));
    assert!(!result.delta.is_empty());
}

#[test]
fn latest_turn_status_uses_most_recent_codex_turn_event() {
    let lines = [
        r#"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1"}}"#,
        r#"{"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-2"}}"#,
    ]
    .join("\n");
    assert_eq!(
        latest_turn_status((lines + "\n").as_bytes()),
        Some(TurnStatus::Processing)
    );
}

#[test]
fn scan_lines_treats_codex_event_messages_as_activity() {
    let line =
        r#"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{}}}}"#;
    let result = scan(&format!("{line}\n"));
    assert!(result.delta.has_activity);
    assert!(!result.delta.is_empty());
}

#[test]
fn scan_lines_extracts_codex_public_agent_message() {
    let line = r#"{"type":"event_msg","payload":{"type":"agent_message","message":"Checking the affected call sites now."}}"#;
    let result = scan(&format!("{line}\n"));
    assert_eq!(
        result.delta.last_assistant_message.as_deref(),
        Some("Checking the affected call sites now.")
    );
    assert!(result.delta.has_activity);
}

#[test]
fn scan_lines_extracts_codex_assistant_output_text() {
    let line = r#"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"The focused tests now pass."}]}}"#;
    let result = scan(&format!("{line}\n"));
    assert_eq!(
        result.delta.last_assistant_message.as_deref(),
        Some("The focused tests now pass.")
    );
    assert!(result.delta.has_activity);
}

/// Shape copied from a real Codex 0.155 rollout: model output carries a
/// Responses API `id` between the payload `type` and `role`, plus trailing
/// `phase` / metadata keys.
#[test]
fn scan_lines_extracts_codex_assistant_output_text_with_response_id() {
    let line = r#"{"timestamp":"2026-09-22T10:30:08.122Z","ordinal":12,"type":"response_item","payload":{"type":"message","id":"msg_06d3529cdc545225016ab258ae4a9487d0b31be86b7c8d5a90","role":"assistant","content":[{"type":"output_text","text":"Checking the parser first."}],"phase":"commentary","internal_chat_message_metadata_passthrough":{"turn_id":"t1"}}}"#;
    let result = scan(&format!("{line}\n"));
    assert_eq!(
        result.delta.last_assistant_message.as_deref(),
        Some("Checking the parser first.")
    );
    assert!(result.delta.has_activity);
}

#[test]
fn scan_lines_ignores_codex_user_and_developer_messages_with_response_id() {
    let lines = [
        r#"{"type":"response_item","payload":{"type":"message","id":"msg_1","role":"developer","content":[{"type":"input_text","text":"<app-context>"}]}}"#,
        r#"{"type":"response_item","payload":{"type":"message","id":"msg_2","role":"user","content":[{"type":"input_text","text":"say \"role\":\"assistant\" and \"type\":\"output_text\""}]}}"#,
    ]
    .join("\n");
    let result = scan(&(lines + "\n"));
    assert_eq!(result.delta.last_assistant_message, None);
}

#[test]
fn scan_lines_ignores_paginated_codex_reasoning_items() {
    let line = r#"{"type":"event_msg","payload":{"type":"item_completed","thread_id":"t","turn_id":"u","item":{"type":"Reasoning","id":"rs_1","summary_text":["private summary"],"raw_content":["private reasoning"]}}}"#;
    let result = scan(&format!("{line}\n"));
    assert_eq!(result.delta.last_assistant_message, None);
}

#[test]
fn scan_lines_ignores_codex_reasoning_even_when_it_has_a_summary() {
    let line = r#"{"type":"response_item","payload":{"type":"reasoning","summary":[{"type":"summary_text","text":"Reviewing transcript parsing"}],"content":[{"type":"text","text":"hidden chain of thought"}],"encrypted_content":"secret"}}"#;
    let result = scan(&format!("{line}\n"));
    assert_eq!(result.delta.last_assistant_message, None);
}

#[test]
fn scan_lines_ignores_codex_response_item_agent_message_with_message_field() {
    let line = r#"{"type":"response_item","payload":{"type":"agent_message","message":"private delegation","author":"/root","recipient":"/root/worker"}}"#;
    let result = scan(&format!("{line}\n"));
    assert_eq!(result.delta.last_assistant_message, None);
    assert!(!result.delta.has_activity);
}

#[test]
fn scan_lines_ignores_codex_private_reasoning_and_inter_agent_messages() {
    let lines = [
        r#"{"type":"response_item","payload":{"type":"reasoning","summary":[],"content":[{"type":"text","text":"hidden chain of thought"}],"encrypted_content":"secret"}}"#,
        r#"{"type":"response_item","payload":{"type":"agent_message","author":"/root","recipient":"/root/worker","content":[{"type":"input_text","text":"private delegation"}]}}"#,
    ]
    .join("\n");
    let result = scan(&(lines + "\n"));
    assert_eq!(result.delta.last_assistant_message, None);
    assert!(!result.delta.has_activity);
}

#[test]
fn scan_lines_clears_previous_codex_output_at_new_turn_boundary() {
    let lines = [
        r#"{"type":"event_msg","payload":{"type":"agent_message","message":"Old answer"}}"#,
        r#"{"type":"event_msg","payload":{"type":"task_started"}}"#,
        r#"{"type":"event_msg","payload":{"type":"user_message","message":"New task"}}"#,
    ]
    .join("\n");
    let result = scan(&(lines + "\n"));
    assert_eq!(result.delta.last_assistant_message, None);
    assert_eq!(result.delta.last_user_prompt.as_deref(), Some("New task"));
    assert_eq!(result.delta.turn_status, Some(TurnStatus::Processing));
}

#[test]
fn scan_lines_extracts_grok_chat_history_rows() {
    let lines = [
        r#"{"type":"user","content":[{"type":"text","text":"build it"}]}"#,
        r#"{"type":"assistant","content":"done","model_id":"grok-code"}"#,
    ]
    .join("\n")
        + "\n";
    let result = scan(&lines);
    assert_eq!(result.delta.last_user_prompt.as_deref(), Some("build it"));
    assert_eq!(result.delta.last_assistant_message.as_deref(), Some("done"));
}

// MARK: - extractText

#[test]
fn extract_text_from_plain_string() {
    assert_eq!(extract_text(Some(&json!("hi"))).as_deref(), Some("hi"));
    assert_eq!(extract_text(Some(&json!("  hi  "))).as_deref(), Some("hi"));
    assert_eq!(extract_text(Some(&json!(""))), None);
    assert_eq!(extract_text(Some(&json!("   "))), None);
}

#[test]
fn extract_text_from_mixed_blocks() {
    let blocks = json!([
        {"type": "text", "text": "part one"},
        {"type": "tool_use", "name": "Bash", "input": {"command": "ls"}},
        {"type": "text", "text": "part two"}
    ]);
    assert_eq!(
        extract_text(Some(&blocks)).as_deref(),
        Some("part one\npart two")
    );
}

#[test]
fn extract_text_from_empty_array_returns_nothing() {
    assert_eq!(extract_text(Some(&json!([]))), None);
}

#[test]
fn extract_text_from_unknown_shape_returns_nothing() {
    assert_eq!(extract_text(Some(&json!(42))), None);
    assert_eq!(extract_text(None), None);
}

// MARK: - Integration: tail a real file

#[test]
fn attach_and_detect_appended_line() {
    let mut state = TailState::at_end(0);
    let line = assistant_line("ping") + "\n";
    let delta = state.receive(line.as_bytes()).expect("a delta");
    assert_eq!(delta.delta.last_assistant_message.as_deref(), Some("ping"));
    assert!(!delta.replays_whole_file);
}

#[test]
fn attach_ignores_preexisting_content_by_default() {
    let pre = assistant_line("already written") + "\n";
    let mut state = TailState::at_end(pre.len() as u64);
    let delta = state
        .receive((assistant_line("fresh") + "\n").as_bytes())
        .expect("a delta for the new append only");
    assert_eq!(delta.delta.last_assistant_message.as_deref(), Some("fresh"));
    assert_eq!(delta.delta.last_user_prompt, None);
}

#[test]
fn file_replacement_delivers_the_new_files_live_write() {
    // The reopen after a rename is the watcher's; what the replacement
    // delivers is not.
    let mut state = TailState::at_end(0);
    state.replaced(0);
    let delta = state
        .receive((assistant_line("after-rotate") + "\n").as_bytes())
        .expect("a delta");
    assert_eq!(
        delta.delta.last_assistant_message.as_deref(),
        Some("after-rotate")
    );
    // The replacement was empty when it was reopened: its first write is news.
    assert!(!delta.replays_whole_file);
}

// MARK: - Offset accounting across partial writes

/// A JSONL line flushed in two chunks (no newline in the first) must be joined
/// from the in-memory fragment plus the second chunk exactly once.
#[test]
fn partial_line_split_across_writes_delivers_joined_message() {
    let full = assistant_line("split-reply") + "\n";
    let cut = full.len() / 2;
    let mut state = TailState::at_end(0);
    // First chunk carries no newline — the tailer stashes it as a fragment.
    assert_eq!(state.receive(&full.as_bytes()[..cut]), None);
    let delta = state
        .receive(&full.as_bytes()[cut..])
        .expect("the joined line");
    assert_eq!(
        delta.delta.last_assistant_message.as_deref(),
        Some("split-reply")
    );
}

/// After a fragment episode the read offset must keep pointing inside the
/// file: a drifted offset makes the next small append look like a truncation
/// and re-scans the whole file from 0 (#278).
#[test]
fn small_append_after_fragment_does_not_rescan_whole_file() {
    let pre = user_line("old-question") + "\n";
    let mut state = TailState::at_end(pre.len() as u64);

    let full = assistant_line(&"x".repeat(200)) + "\n";
    let cut = full.len() - 20;
    assert_eq!(state.receive(&full.as_bytes()[..cut]), None);
    assert!(state.receive(&full.as_bytes()[cut..]).is_some());

    let delta = state
        .receive((assistant_line("wrap") + "\n").as_bytes())
        .expect("a delta for the final small append");
    assert_eq!(delta.delta.last_assistant_message.as_deref(), Some("wrap"));
    assert_eq!(
        delta.delta.last_user_prompt, None,
        "pre-attach content resurfaced — the tailer re-scanned the file from offset 0"
    );
}

/// Real truncation (size genuinely shrinks) must still rewind and pick up the
/// fresh content.
#[test]
fn real_truncation_rewinds_and_picks_up_fresh_content() {
    let pre = assistant_line("long original content that will be truncated away") + "\n";
    let mut state = TailState::at_end(pre.len() as u64);
    state.truncated();
    let delta = state
        .receive((assistant_line("fresh-after-truncate") + "\n").as_bytes())
        .expect("a delta after truncation");
    assert_eq!(
        delta.delta.last_assistant_message.as_deref(),
        Some("fresh-after-truncate")
    );
}

#[test]
fn replaced_file_history_is_delivered_once_as_a_replay_then_live_again() {
    let history = assistant_line("history") + "\n";
    let mut state = TailState::at_end(0);
    // Replaced by a file that already has history; no further write.
    state.replaced(history.len() as u64);
    let replay = state.receive(history.as_bytes()).expect("the history");
    assert_eq!(
        replay.delta.last_assistant_message.as_deref(),
        Some("history")
    );

    let live = state
        .receive((assistant_line("news") + "\n").as_bytes())
        .expect("the next append");
    assert_eq!(live.delta.last_assistant_message.as_deref(), Some("news"));

    let replays: Vec<bool> = [replay.replays_whole_file, live.replays_whole_file].to_vec();
    assert_eq!(replays, [true, false]);
}

// MARK: - Attach offset shared with the backfill

/// Lines written after the caller's backfill stopped but before the watch was
/// armed must be read at once — no later write may ever come.
#[test]
fn attach_at_an_offset_reads_what_follows_it_without_waiting_for_a_write() {
    let seen = user_line("already backfilled") + "\n";
    let missed = assistant_line("written in the gap") + "\n";
    let mut state = TailState::at_offset(seen.len() as u64);
    let delta = state.receive(missed.as_bytes()).expect("the gap line");
    assert_eq!(
        delta.delta.last_assistant_message.as_deref(),
        Some("written in the gap")
    );
    assert_eq!(
        delta.delta.last_user_prompt, None,
        "bytes before the offset belong to the backfill"
    );
}

#[test]
fn attach_at_an_offset_completes_a_row_that_was_still_being_written() {
    let full = assistant_line("finished later") + "\n";
    let cut = full.len() / 2;
    let head = user_line("q") + "\n";
    let file = format!("{head}{}", &full[..cut]);

    let scan = scan_tail_for_attach(file.as_bytes(), 0, file.len() as u64);
    assert_eq!(
        scan.end_offset,
        head.len() as u64,
        "the tailer starts at the row being written"
    );
    assert_eq!(scan.delta.last_user_prompt.as_deref(), Some("q"));
    assert_eq!(scan.delta.last_assistant_message, None);

    let mut state = TailState::at_offset(scan.end_offset);
    // What is already on disk from the offset is the row's first half: no
    // newline yet, so it is stashed as a fragment.
    assert_eq!(
        state.receive(&file.as_bytes()[scan.end_offset as usize..]),
        None
    );
    let delta = state
        .receive(&full.as_bytes()[cut..])
        .expect("the completed row");
    assert_eq!(
        delta.delta.last_assistant_message.as_deref(),
        Some("finished later")
    );
}

#[test]
fn scan_tail_for_attach_skips_the_cut_first_row_and_reads_an_unterminated_last_row() {
    let early = user_line(&"e".repeat(400)) + "\n";
    let prompt = user_line("in window") + "\n";
    // Cursor never ends its last row with a newline.
    let last =
        r#"{"role":"assistant","message":{"content":[{"type":"text","text":"cursor reply"}]}}"#;
    let file = format!("{early}{prompt}{last}");
    let size = file.len() as u64;

    // The platform reads one byte before the window, so a cut first row is
    // recognisable.
    let max_bytes = prompt.len() + last.len() + 10;
    let start = size - max_bytes as u64 - 1;
    let scan = scan_tail_for_attach(&file.as_bytes()[start as usize..], start, size);
    assert_eq!(
        scan.delta.last_user_prompt.as_deref(),
        Some("in window"),
        "the cut first row is dropped, not misparsed"
    );
    assert_eq!(
        scan.delta.last_assistant_message.as_deref(),
        Some("cursor reply")
    );
    assert_eq!(scan.end_offset, (early.len() + prompt.len()) as u64);

    // A window that starts exactly on a row boundary keeps that row.
    let max_bytes = prompt.len() + last.len();
    let start = size - max_bytes as u64 - 1;
    let exact = scan_tail_for_attach(&file.as_bytes()[start as usize..], start, size);
    assert_eq!(exact.delta.last_user_prompt.as_deref(), Some("in window"));
}

// MARK: - Minimax compatible-transcript shapes

#[test]
fn scan_lines_strips_minimax_system_reminder_from_user_prompt() {
    // mcode prepends its agent-context boilerplate to the prompt inside the
    // SAME text block of the compatible transcript's user row.
    let wrapped = "<system-reminder>\n<agent-context>\n  agent: Mavis\n</agent-context>\n</system-reminder>\n\n你好";
    let line = json!({
        "type": "user",
        "message": {"content": [{"type": "text", "text": wrapped}]}
    })
    .to_string();
    let result = scan(&format!("{line}\n"));
    assert_eq!(result.delta.last_user_prompt.as_deref(), Some("你好"));
}

#[test]
fn scan_lines_skips_minimax_thinking_blob_text_block() {
    let blob = r#"{"type":"thinking","thinking":"The user greeted me in Chinese","thinkingSignature":"b1f92541"}"#;
    let line = json!({
        "type": "assistant",
        "message": {"content": [
            {"type": "text", "text": blob},
            {"type": "text", "text": "你好！有什么我可以帮你的吗？"}
        ]}
    })
    .to_string();
    let result = scan(&format!("{line}\n"));
    assert_eq!(
        result.delta.last_assistant_message.as_deref(),
        Some("你好！有什么我可以帮你的吗？")
    );
}

#[test]
fn scan_lines_thinking_blob_only_assistant_row_yields_no_reply() {
    let blob = r#"{"type":"thinking","thinking":"mid-reasoning"}"#;
    let line = json!({
        "type": "assistant",
        "message": {"content": [{"type": "text", "text": blob}]}
    })
    .to_string();
    assert_eq!(
        scan(&format!("{line}\n")).delta.last_assistant_message,
        None
    );
}

#[test]
fn extract_text_drops_thinking_blob_string_content() {
    let blob = r#"{"type":"thinking","thinking":"not display text"}"#;
    assert_eq!(extract_text(Some(&json!(blob))), None);
    assert_eq!(extract_text(Some(&json!(format!("  {blob}  ")))), None);
    assert_eq!(
        extract_text(Some(&json!("plain reply"))).as_deref(),
        Some("plain reply")
    );
}

#[test]
fn extract_text_keeps_a_system_reminder_tag_quoted_inside_the_message() {
    let reply = "Claude Code wraps hook output in <system-reminder>like this</system-reminder> before the model sees it.";
    assert_eq!(extract_text(Some(&json!(reply))).as_deref(), Some(reply));
    assert_eq!(
        extract_text(Some(&json!([{"type": "text", "text": reply}]))).as_deref(),
        Some(reply)
    );

    // Several leading spans all go; the typed text after them stays.
    let wrapped = "<system-reminder>a</system-reminder>\n<system-reminder>b</system-reminder>\nwhat is <system-reminder>?";
    assert_eq!(
        extract_text(Some(&json!(wrapped))).as_deref(),
        Some("what is <system-reminder>?")
    );
    // An unclosed leading tag is not a wrapper we can bound — leave it.
    let unclosed = "<system-reminder> what is this tag";
    assert_eq!(
        extract_text(Some(&json!(unclosed))).as_deref(),
        Some(unclosed)
    );
}

// MARK: - Cursor question signals

#[test]
fn cursor_user_line_clears_question_and_extracts_chat_text() {
    let result = scan_lines_of(&[cursor_user_line("fix the bug")]);
    assert_eq!(
        result.delta.last_user_prompt.as_deref(),
        Some("fix the bug")
    );
    assert_eq!(result.delta.last_assistant_message, None);
    assert_eq!(
        result.delta.cursor_question,
        Some(CursorQuestionSignal::Cleared)
    );
}

#[test]
fn cursor_assistant_text_line_clears_question_and_extracts_chat_text() {
    let result = scan_lines_of(&[cursor_assistant_text_line("done, deployed")]);
    assert_eq!(
        result.delta.last_assistant_message.as_deref(),
        Some("done, deployed")
    );
    assert_eq!(
        result.delta.cursor_question,
        Some(CursorQuestionSignal::Cleared)
    );
}

#[test]
fn cursor_user_line_strips_timestamp_and_user_query_wrappers() {
    let line = r#"{"role":"user","message":{"content":[{"type":"text","text":"<timestamp>Thursday, Jul 30, 2026, 3:51 PM (UTC+8)</timestamp>\n<user_query>\n## 根因分析\n</user_query>"}]}}"#;
    let result = scan(&format!("{line}\n"));
    assert_eq!(
        result.delta.last_user_prompt.as_deref(),
        Some("## 根因分析")
    );
    assert_eq!(
        result.delta.cursor_question,
        Some(CursorQuestionSignal::Cleared)
    );
}

#[test]
fn ask_question_tool_use_marks_pending() {
    let input = r#"{"title":"Clarifying Questions","questions":[{"id":"db","prompt":"Which database should we target?","options":[{"id":"pg","label":"PostgreSQL"}],"allow_multiple":false}]}"#;
    let result = scan_lines_of(&[cursor_question_line(
        "AskQuestion",
        input,
        Some("I need one detail."),
    )]);
    assert_eq!(
        result.delta.cursor_question,
        Some(CursorQuestionSignal::Pending {
            prompt: "Which database should we target?".into()
        })
    );
    // Leading assistant prose before AskQuestion still refreshes chat text.
    assert_eq!(
        result.delta.last_assistant_message.as_deref(),
        Some("I need one detail.")
    );
}

#[test]
fn ask_question_multiple_prompts_get_numeric_suffix() {
    let input = r#"{"title":"Clarifying Questions","questions":[{"id":"a","prompt":"Which DB?"},{"id":"b","prompt":"Which tests?"},{"id":"c","prompt":"Which CI?"}]}"#;
    let result = scan_lines_of(&[cursor_question_line("AskQuestion", input, None)]);
    assert_eq!(
        result.delta.cursor_question,
        Some(CursorQuestionSignal::Pending {
            prompt: "Which DB? (+2)".into()
        })
    );
}

#[test]
fn ask_question_falls_back_to_title_when_prompts_missing() {
    let input = r#"{"title":"Pick a rollout strategy","questions":[]}"#;
    let result = scan_lines_of(&[cursor_question_line("AskQuestion", input, None)]);
    assert_eq!(
        result.delta.cursor_question,
        Some(CursorQuestionSignal::Pending {
            prompt: "Pick a rollout strategy".into()
        })
    );
}

#[test]
fn ask_question_with_unparseable_args_still_signals_pending_with_empty_prompt() {
    let result = scan_lines_of(&[cursor_question_line(
        "AskQuestion",
        r#"{"unexpected":"shape"}"#,
        None,
    )]);
    assert_eq!(
        result.delta.cursor_question,
        Some(CursorQuestionSignal::Pending {
            prompt: String::new()
        })
    );
}

#[test]
fn ask_question_accepts_flat_question_field() {
    let result = scan_lines_of(&[cursor_question_line(
        "AskQuestion",
        r#"{"question":"Deploy to staging first?"}"#,
        None,
    )]);
    assert_eq!(
        result.delta.cursor_question,
        Some(CursorQuestionSignal::Pending {
            prompt: "Deploy to staging first?".into()
        })
    );
}

#[test]
fn question_tool_name_matching_is_separator_and_case_insensitive() {
    for name in [
        "AskQuestion",
        "ask_question",
        "askQuestion",
        "AskUserQuestion",
        "ask-followup-question",
    ] {
        assert!(is_cursor_question_tool_name(name), "{name}");
    }
    for name in ["Shell", "QuestionnaireImport", ""] {
        assert!(!is_cursor_question_tool_name(name), "{name}");
    }
}

#[test]
fn run_async_snake_case_question_is_not_pending() {
    let input = r#"{"title":"Optional","questions":[{"id":"a","prompt":"Any preference?"}],"run_async":true}"#;
    let result = scan_lines_of(&[cursor_question_line("AskQuestion", input, None)]);
    assert_eq!(
        result.delta.cursor_question,
        Some(CursorQuestionSignal::Cleared)
    );
}

#[test]
fn run_async_camel_case_question_is_not_pending() {
    let input = r#"{"title":"Optional","questions":[{"id":"a","prompt":"Any preference?"}],"runAsync":true}"#;
    let result = scan_lines_of(&[cursor_question_line("AskQuestion", input, None)]);
    assert_eq!(
        result.delta.cursor_question,
        Some(CursorQuestionSignal::Cleared)
    );
}

#[test]
fn question_followed_by_user_entry_clears() {
    let question = cursor_question_line(
        "AskQuestion",
        r#"{"questions":[{"id":"a","prompt":"Which DB?"}]}"#,
        None,
    );
    let result = scan_lines_of(&[question, cursor_user_line("PostgreSQL please")]);
    assert_eq!(
        result.delta.cursor_question,
        Some(CursorQuestionSignal::Cleared)
    );
}

#[test]
fn question_followed_by_assistant_entry_clears() {
    let question = cursor_question_line(
        "AskQuestion",
        r#"{"questions":[{"id":"a","prompt":"Which DB?"}]}"#,
        None,
    );
    let result = scan_lines_of(&[
        question,
        cursor_assistant_text_line("Great, using PostgreSQL."),
    ]);
    assert_eq!(
        result.delta.cursor_question,
        Some(CursorQuestionSignal::Cleared)
    );
}

#[test]
fn answered_question_mid_transcript_does_not_resurface() {
    let lines = [
        cursor_user_line("set up the db layer"),
        cursor_question_line(
            "AskQuestion",
            r#"{"questions":[{"id":"a","prompt":"Which DB?"}]}"#,
            None,
        ),
        cursor_user_line("PostgreSQL"),
        cursor_assistant_text_line("Done."),
    ];
    assert_eq!(
        scan_lines_of(&lines).delta.cursor_question,
        Some(CursorQuestionSignal::Cleared)
    );
    assert_eq!(
        latest_cursor_question((lines.join("\n") + "\n").as_bytes()),
        Some(CursorQuestionSignal::Cleared)
    );
}

#[test]
fn latest_cursor_question_pending_when_question_is_trailing_entry() {
    let lines = [
        cursor_user_line("set up the db layer"),
        cursor_assistant_text_line("Looking at the schema."),
        cursor_question_line(
            "AskQuestion",
            r#"{"questions":[{"id":"a","prompt":"Which DB?"}]}"#,
            None,
        ),
    ];
    assert_eq!(
        latest_cursor_question((lines.join("\n") + "\n").as_bytes()),
        Some(CursorQuestionSignal::Pending {
            prompt: "Which DB?".into()
        })
    );
}

#[test]
fn latest_cursor_question_none_for_non_cursor_transcript() {
    let claude = r#"{"type":"assistant","message":{"content":[{"type":"text","text":"hi"}]}}"#;
    assert_eq!(
        latest_cursor_question(format!("{claude}\n").as_bytes()),
        None
    );
}

#[test]
fn claude_style_ask_user_question_tool_use_produces_no_cursor_signal() {
    // Claude's own question tool is handled by the hook flow — the transcript
    // tail must not double-report it.
    let line = r#"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"AskUserQuestion","input":{"questions":[{"question":"Pick one"}]}}]}}"#;
    assert_eq!(scan(&format!("{line}\n")).delta.cursor_question, None);
}

#[test]
fn code_buddy_style_role_with_type_key_produces_no_cursor_signal() {
    let line =
        r#"{"type":"message","role":"assistant","content":[{"type":"text","text":"hello"}]}"#;
    assert_eq!(scan(&format!("{line}\n")).delta.cursor_question, None);
}

#[test]
fn quick_type_probe_classifies_cursor_role_lines() {
    assert_eq!(
        quick_type_probe(cursor_user_line("hi").as_bytes()),
        QuickTypeKind::CursorRole
    );
    assert_eq!(
        quick_type_probe(cursor_assistant_text_line("hi").as_bytes()),
        QuickTypeKind::CursorRole
    );
}

#[test]
fn quick_type_probe_still_classifies_claude_lines() {
    let claude = r#"{"type":"assistant","message":{"role":"assistant","content":[]}}"#;
    assert_eq!(
        quick_type_probe(claude.as_bytes()),
        QuickTypeKind::Assistant
    );
}

#[test]
fn quick_type_probe_classifies_public_codex_response_item() {
    let with_output = r#"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"ok"}]}}"#;
    assert_eq!(
        quick_type_probe(with_output.as_bytes()),
        QuickTypeKind::CodexResponseItem
    );
}

#[test]
fn quick_type_probe_keeps_large_codex_tool_output_on_fast_irrelevant_path() {
    let huge = "x".repeat(200_000);
    let codex = format!(
        r#"{{"type":"response_item","payload":{{"type":"function_call_output","output":"{huge}"}}}}"#
    );
    assert_eq!(
        quick_type_probe(codex.as_bytes()),
        QuickTypeKind::Irrelevant
    );
}

#[test]
fn trailing_partial_cursor_question_line_stays_buffered() {
    let complete = cursor_assistant_text_line("checking") + "\n";
    let partial =
        r#"{"role":"assistant","message":{"content":[{"type":"tool_use","name":"AskQuestion","#;
    let result = scan(&(complete.clone() + partial));
    assert_eq!(
        result.delta.cursor_question,
        Some(CursorQuestionSignal::Cleared)
    );
    assert_eq!(result.trailing_fragment, partial.as_bytes());
}

#[test]
fn delta_is_empty_accounts_for_cursor_question() {
    let mut delta = morrow_core::transcript::ScanDelta::default();
    assert!(delta.is_empty());
    delta.cursor_question = Some(CursorQuestionSignal::Cleared);
    assert!(!delta.is_empty());
}

// MARK: - Command echoes and text helpers (used by the port, not by the suite)

#[test]
fn slash_command_echoes_are_not_prompts() {
    assert_eq!(
        claude_command_echo("<command-name>/model</command-name>"),
        Some(ClaudeCommandEcho::Local)
    );
    assert_eq!(
        claude_command_echo("<local-command-stdout>done</local-command-stdout>"),
        Some(ClaudeCommandEcho::Local)
    );
    let prompt = "<command-message>run</command-message>\n<command-name>/design</command-name>\n<command-args>tidy the layout</command-args>";
    assert_eq!(
        claude_command_echo(prompt),
        Some(ClaudeCommandEcho::Prompt("/design tidy the layout".into()))
    );
    assert_eq!(claude_command_echo("just a prompt"), None);
}

#[test]
fn text_helpers_are_exported_for_the_watcher() {
    let content = json!({"content": [{"type": "text", "text": "<timestamp>x</timestamp><user_query>hi</user_query>"}]});
    assert_eq!(
        normalized_cursor_chat_text(content.get("content")).as_deref(),
        Some("hi")
    );
    let question = json!([
        {"type": "tool_use", "name": "ask_question", "input": {"question": "Which?"}}
    ]);
    assert_eq!(
        cursor_question_prompt(Some(&question)).as_deref(),
        Some("Which?")
    );
    assert_eq!(strip_display_wrappers("  plain  "), "  plain  ");
    let _ = Value::Null;
}
