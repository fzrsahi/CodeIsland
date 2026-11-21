//! The parsing half of `AgentTaskListTests` (`macos/Tests/MorrowCoreTests/AgentTaskListTests.swift`):
//! reading checklist observations out of hook events and transcript rows, and
//! the backfill scan's byte prefilter. The list these events feed
//! (`AgentTaskList`) is `agent_task_list.rs`, so the tests that assert a built
//! list stay there.
//!
//! Ported 1:1: `testStatusVocabularies`, `testClaudeTranscriptRowShapes`,
//! `testSidechainTranscriptRowsAreIgnored`,
//! `testBackfillPrefilterMatchesOnlyRelevantRows`, and the scan expectations of
//! `testBackfillScanSkipsPartialHeadOversizedRowsAndUnterminatedTail`.

use serde_json::{Value, json};

use morrow_core::agent_tasks::parsing::{
    AgentTaskTool, created_task_id_from_result_text, events_from_line, hook_events,
    may_carry_task_event, scan,
};
use morrow_core::agent_tasks::{AgentTaskChange, AgentTaskDraft, AgentTaskEvent, AgentTaskStatus};
use morrow_core::intake::SourceCatalog;
use morrow_core::reduce::HookEvent;

fn object(line: &str) -> serde_json::Map<String, Value> {
    serde_json::from_str::<Value>(line)
        .expect("a transcript row")
        .as_object()
        .expect("an object")
        .clone()
}

fn events(line: &str) -> Vec<AgentTaskEvent> {
    events_from_line(&object(line))
}

fn claude_prompt_line(text: &str) -> String {
    json!({
        "parentUuid": null,
        "isSidechain": false,
        "type": "user",
        "message": {"role": "user", "content": text},
        "uuid": "p1",
    })
    .to_string()
}

fn claude_tool_use_line(id: &str, name: &str, input: &str, sidechain: bool) -> String {
    format!(
        r#"{{"parentUuid":"x","isSidechain":{sidechain},"message":{{"model":"claude","type":"message","role":"assistant","content":[{{"type":"tool_use","id":"{id}","name":"{name}","input":{input}}}]}},"type":"assistant","uuid":"a1"}}"#
    )
}

fn claude_result_line(tool_use_id: &str, text: &str, tool_use_result: &str) -> String {
    format!(
        r#"{{"parentUuid":"a1","isSidechain":false,"type":"user","message":{{"role":"user","content":[{{"tool_use_id":"{tool_use_id}","type":"tool_result","content":"{text}"}}]}},"uuid":"r1","toolUseResult":{tool_use_result}}}"#
    )
}

fn codex_plan_line(call_id: &str, steps: &[(&str, &str)]) -> String {
    // Codex keeps the arguments as a JSON *string*, not an object.
    let plan = Value::Array(
        steps
            .iter()
            .map(|(step, status)| json!({"step": step, "status": status}))
            .collect(),
    );
    json!({
        "timestamp": "2026-06-25T01:40:57.835Z",
        "ordinal": 1,
        "type": "response_item",
        "payload": {
            "type": "function_call",
            "id": "fc_1",
            "name": "update_plan",
            "arguments": json!({"plan": plan}).to_string(),
            "call_id": call_id,
        }
    })
    .to_string()
}

// MARK: - Vocabularies

#[test]
fn status_vocabularies() {
    assert_eq!(
        AgentTaskStatus::parse(Some(&json!("in-progress"))),
        morrow_core::agent_tasks::ParsedStatus::Status(AgentTaskStatus::InProgress)
    );
    assert_eq!(
        AgentTaskStatus::parse(Some(&json!("DONE"))),
        morrow_core::agent_tasks::ParsedStatus::Status(AgentTaskStatus::Completed)
    );
    assert_eq!(
        AgentTaskStatus::parse(Some(&json!("cancelled"))),
        morrow_core::agent_tasks::ParsedStatus::Removed
    );
    assert_eq!(
        AgentTaskStatus::parse(Some(&json!("weird"))),
        morrow_core::agent_tasks::ParsedStatus::Unknown
    );
    assert_eq!(
        AgentTaskStatus::parse(None),
        morrow_core::agent_tasks::ParsedStatus::Unknown
    );
    assert_eq!(
        AgentTaskTool::from_tool_name(Some("write_todos")),
        Some(AgentTaskTool::TodoSnapshot)
    );
    assert_eq!(
        AgentTaskTool::from_tool_name(Some("todo_write")),
        Some(AgentTaskTool::TodoSnapshot)
    );
    assert_eq!(AgentTaskTool::from_tool_name(Some("TaskGet")), None);
    assert_eq!(
        AgentTaskTool::from_tool_name(Some("mcp__x__task_create")),
        None
    );
    // A status a newer build wrote decodes as pending, never fails.
    assert_eq!(
        AgentTaskStatus::from_raw_value("some-future-status"),
        AgentTaskStatus::Pending
    );
    assert_eq!(
        AgentTaskStatus::from_raw_value("in_progress"),
        AgentTaskStatus::InProgress
    );
}

// MARK: - Claude transcript rows

#[test]
fn claude_transcript_row_shapes() {
    assert_eq!(
        events(&claude_prompt_line("Refactor the parser")),
        [AgentTaskEvent::NewTurn]
    );
    assert_eq!(
        events(
            r#"{"type":"user","isMeta":true,"message":{"role":"user","content":"<system-reminder>x</system-reminder>"}}"#
        ),
        []
    );
    assert_eq!(
        events(
            r#"{"type":"user","isCompactSummary":true,"message":{"role":"user","content":"Summary of the conversation"}}"#
        ),
        []
    );
    assert_eq!(
        events(&claude_result_line(
            "toolu_c1",
            "Task #1 created successfully: A",
            r#"{"task":{"id":"1","subject":"A"}}"#
        )),
        [AgentTaskEvent::Created {
            op_id: Some("toolu_c1".into()),
            task_id: "1".into(),
            title: Some("A".into()),
            active_form: None,
        }]
    );
    // TaskGet echoes a task *with* status — a read, not a create.
    assert_eq!(
        events(&claude_result_line(
            "toolu_g1",
            "Task #1: A",
            r#"{"task":{"id":"1","subject":"A","status":"pending","blocks":[]}}"#
        )),
        []
    );
    assert_eq!(
        events(&claude_result_line(
            "toolu_u9",
            "blocked",
            r#"{"success":false,"taskId":"1","updatedFields":[],"error":"blocked"}"#
        )),
        [AgentTaskEvent::OpFailed {
            op_id: "toolu_u9".into()
        }]
    );
    assert_eq!(
        events(&claude_result_line(
            "toolu_u1",
            "Updated task #1 status",
            r#"{"success":true,"taskId":"1","updatedFields":["status"],"statusChange":{"from":"pending","to":"completed"}}"#
        )),
        [AgentTaskEvent::Update {
            op_id: Some("toolu_u1".into()),
            task_id: "1".into(),
            change: AgentTaskChange::with_status(AgentTaskStatus::Completed),
            expected_from: Some(AgentTaskStatus::Pending),
        }]
    );
    // Several results in one row: toolUseResult is ambiguous, the text is not.
    let multi = r#"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_a","type":"tool_result","content":"Task #5 created successfully: Five"},{"tool_use_id":"toolu_b","type":"tool_result","content":"ok","is_error":true}]},"toolUseResult":{"task":{"id":"4","subject":"wrong"}}}"#;
    assert_eq!(
        events(multi),
        [
            AgentTaskEvent::CreatedPerText {
                op_id: "toolu_a".into(),
                task_id: "5".into(),
                title: Some("Five".into()),
            },
            AgentTaskEvent::OpFailed {
                op_id: "toolu_b".into()
            },
        ]
    );
}

#[test]
fn sidechain_transcript_rows_are_ignored() {
    let line = claude_tool_use_line("toolu_c1", "TaskCreate", r#"{"subject":"Child"}"#, true);
    assert!(events(&line).is_empty());
}

// MARK: - The byte prefilter

fn matches(line: &str) -> bool {
    may_carry_task_event(line.as_bytes())
}

#[test]
fn backfill_prefilter_matches_only_relevant_rows() {
    assert!(matches(&claude_prompt_line("hi")));
    assert!(matches(&claude_tool_use_line(
        "t",
        "TodoWrite",
        r#"{"todos":[]}"#,
        false
    )));
    assert!(matches(&codex_plan_line("c", &[("A", "pending")])));
    assert!(!matches(&claude_tool_use_line(
        "t",
        "Bash",
        r#"{"command":"ls"}"#,
        false
    )));
    assert!(!matches(&claude_result_line(
        "t",
        "file contents",
        r#"{"stdout":"x"}"#
    )));
    // Every spelling the live parser accepts (forks rename the tool).
    for name in [
        "todo_write",
        "write_todos",
        "todowrite",
        "WriteTodos",
        "task_create",
        "TASKUPDATE",
        "update-plan",
    ] {
        assert!(
            matches(&claude_tool_use_line("t", name, r#"{"todos":[]}"#, false)),
            "{name}"
        );
    }
    assert!(!matches(&claude_tool_use_line(
        "t",
        "todo_read",
        "{}",
        false
    )));
    assert!(!matches(&claude_tool_use_line(
        "t",
        "TaskCreateAndRun",
        "{}",
        false
    )));
}

// MARK: - Backfill scan

#[test]
fn backfill_scan_skips_partial_head_oversized_rows_and_unterminated_tail() {
    let lines = [
        claude_tool_use_line(
            "toolu_c1",
            "TaskCreate",
            r#"{"subject":"Write parser"}"#,
            false,
        ),
        claude_result_line(
            "toolu_c1",
            "Task #1 created successfully: Write parser",
            r#"{"task":{"id":"1","subject":"Write parser"}}"#,
        ),
        claude_tool_use_line(
            "toolu_c2",
            "TaskCreate",
            r#"{"subject":"Add tests"}"#,
            false,
        ),
        claude_result_line(
            "toolu_c2",
            "Task #2 created successfully: Add tests",
            r#"{"task":{"id":"2","subject":"Add tests"}}"#,
        ),
        claude_tool_use_line(
            "toolu_u1",
            "TaskUpdate",
            r#"{"taskId":"1","status":"in_progress"}"#,
            false,
        ),
    ];
    let oversized = claude_tool_use_line(
        "toolu_big",
        "TaskCreate",
        &format!(
            r#"{{"subject":"Huge","description":"{}"}}"#,
            "x".repeat(2_000)
        ),
        false,
    );
    // Window cut mid-row, an oversized row, the real rows, then a row still
    // being written.
    let blob = format!(
        "ated successfully\"}}]}}\n{oversized}\n{}\n{{\"type\":\"user\",\"mess",
        lines.join("\n")
    );

    let events = scan(blob.as_bytes(), false, 1_024);
    assert_eq!(
        events,
        [
            AgentTaskEvent::Create {
                op_id: "toolu_c1".into(),
                title: "Write parser".into(),
                active_form: None,
            },
            AgentTaskEvent::Created {
                op_id: Some("toolu_c1".into()),
                task_id: "1".into(),
                title: Some("Write parser".into()),
                active_form: None,
            },
            AgentTaskEvent::Create {
                op_id: "toolu_c2".into(),
                title: "Add tests".into(),
                active_form: None,
            },
            AgentTaskEvent::Created {
                op_id: Some("toolu_c2".into()),
                task_id: "2".into(),
                title: Some("Add tests".into()),
                active_form: None,
            },
            AgentTaskEvent::Update {
                op_id: Some("toolu_u1".into()),
                task_id: "1".into(),
                change: AgentTaskChange::with_status(AgentTaskStatus::InProgress),
                expected_from: None,
            },
        ]
    );
}

// MARK: - Hook events

fn hook(payload: Value) -> HookEvent {
    HookEvent::new(
        payload.as_object().expect("an object").clone(),
        &SourceCatalog::default(),
    )
    .expect("a hook event")
}

#[test]
fn hook_events_read_calls_results_and_boundaries() {
    let create = hook(json!({
        "hook_event_name": "PreToolUse",
        "tool_name": "TaskCreate",
        "tool_use_id": "toolu_c1",
        "tool_input": {"subject": "Write parser", "description": "details", "activeForm": "Writing parser"},
    }));
    assert_eq!(
        hook_events(&create, "PreToolUse"),
        [AgentTaskEvent::Create {
            op_id: "toolu_c1".into(),
            title: "Write parser".into(),
            active_form: Some("Writing parser".into()),
        }]
    );

    let result = hook(json!({
        "hook_event_name": "PostToolUse",
        "tool_name": "TaskCreate",
        "tool_use_id": "toolu_c1",
        "tool_input": {"subject": "Write parser"},
        "tool_response": {"task": {"id": "1", "subject": "Write parser"}},
    }));
    assert_eq!(
        hook_events(&result, "PostToolUse"),
        [AgentTaskEvent::Created {
            op_id: Some("toolu_c1".into()),
            task_id: "1".into(),
            title: Some("Write parser".into()),
            active_form: None,
        }]
    );

    let turn = hook(json!({"hook_event_name": "Stop", "session_id": "s1"}));
    assert_eq!(hook_events(&turn, "Stop"), [AgentTaskEvent::TurnEnded]);
    let prompt = hook(json!({
        "hook_event_name": "UserPromptSubmit", "session_id": "s1", "prompt": "next",
    }));
    assert_eq!(
        hook_events(&prompt, "UserPromptSubmit"),
        [AgentTaskEvent::NewTurn]
    );

    // A failed or denied call undoes whatever its PreToolUse applied.
    let denied = hook(json!({
        "hook_event_name": "PermissionDenied",
        "tool_name": "TaskCreate",
        "tool_use_id": "toolu_c9",
        "tool_input": {"subject": "Nope"},
    }));
    assert_eq!(
        hook_events(&denied, "PermissionDenied"),
        [AgentTaskEvent::OpFailed {
            op_id: "toolu_c9".into()
        }]
    );

    // An unrelated tool carries nothing.
    let bash = hook(json!({
        "hook_event_name": "PreToolUse", "tool_name": "Bash",
        "tool_use_id": "toolu_x", "tool_input": {"command": "ls"},
    }));
    assert_eq!(hook_events(&bash, "PreToolUse"), []);
}

#[test]
fn plan_snapshots_become_replace_events() {
    let line = codex_plan_line("call_1", &[("A", "pending"), ("B", "completed")]);
    assert_eq!(
        events(&line),
        [AgentTaskEvent::Replace {
            op_id: Some("call_1".into()),
            items: vec![
                AgentTaskDraft {
                    title: "A".into(),
                    active_form: None,
                    status: AgentTaskStatus::Pending,
                    row_id: None,
                },
                AgentTaskDraft {
                    title: "B".into(),
                    active_form: None,
                    status: AgentTaskStatus::Completed,
                    row_id: None,
                },
            ],
        }]
    );
}

#[test]
fn cursor_merge_updates_carry_only_what_changed() {
    let line = claude_tool_use_line(
        "toolu_m",
        "todo_write",
        r#"{"merge":true,"todos":[{"id":"7","status":"completed"},{"content":"No id"}]}"#,
        false,
    );
    let events = events(&line);
    assert_eq!(events.len(), 1, "{events:?}");
    let AgentTaskEvent::Merge { rows, .. } = &events[0] else {
        panic!("expected a merge, got {events:?}");
    };
    // Both rows carry something: one an id + status, the other a title only.
    assert_eq!(rows.len(), 2);
    assert_eq!(rows[0].row_id.as_deref(), Some("7"));
    assert_eq!(rows[0].change.status, Some(AgentTaskStatus::Completed));
    assert_eq!(rows[1].row_id, None);
    assert_eq!(rows[1].change.title.as_deref(), Some("No id"));
}

#[test]
fn task_create_text_results_name_the_new_id() {
    assert_eq!(
        created_task_id_from_result_text(Some("Task #7 created successfully: A")).as_deref(),
        Some("7")
    );
    assert_eq!(
        created_task_id_from_result_text(Some("Task # created successfully: A")),
        None
    );
    assert_eq!(
        created_task_id_from_result_text(Some("Task #1 created successfully: A")),
        Some("1".into())
    );
    assert_eq!(created_task_id_from_result_text(Some("nothing here")), None);
    assert_eq!(created_task_id_from_result_text(None), None);
}
