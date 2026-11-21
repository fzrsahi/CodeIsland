//! `AgentTaskList` against `Tests/MorrowCoreTests/AgentTaskListTests.swift`: the
//! state machine's own tests, plus the reducer and transcript wiring that feeds
//! it. The parsing half of the same file is `agent_task_parsing.rs`.
//!
//! Not ported: `testScanFileStopsAtTheTailerOffset` — reading a file belongs to
//! the shell, like the transcript tailer's DispatchSource tests.

use serde_json::{Map, Value, json};

use morrow_core::agent_tasks::parsing::scan;
use morrow_core::agent_tasks::{
    AgentTaskChange, AgentTaskDraft, AgentTaskEvent, AgentTaskItem, AgentTaskList, AgentTaskStatus,
};
use morrow_core::intake::SourceCatalog;
use morrow_core::reduce::{
    HookEvent, ReduceContext, SessionSnapshot, Sessions, Timestamp, reduce_hook_event,
};

const T0: Timestamp = Timestamp(1_000_000.0);

fn at(seconds: impl Into<f64>) -> Timestamp {
    Timestamp(T0.0 + seconds.into())
}

// MARK: - Hook payloads through the reducer

fn reduce(sessions: &mut Sessions, mut payload: Map<String, Value>) {
    payload
        .entry("session_id")
        .or_insert_with(|| Value::String("s1".into()));
    let sources = SourceCatalog::default();
    let event = HookEvent::new(payload.clone(), &sources)
        .unwrap_or_else(|| panic!("invalid hook payload {payload:?}"));
    let clock = || T0;
    let ctx = ReduceContext {
        clock: &clock,
        sources: &sources,
        home_directory: "/home/morrow-contract",
        max_history: 20,
        reply_complete_placeholder: "Reply complete",
    };
    reduce_hook_event(sessions, &event, &ctx);
}

fn pre_create(op_id: &str, subject: &str, active_form: Option<&str>) -> Map<String, Value> {
    let mut input = json!({"subject": subject, "description": "details"});
    if let Some(active_form) = active_form {
        input["activeForm"] = json!(active_form);
    }
    json!({
        "hook_event_name": "PreToolUse",
        "tool_name": "TaskCreate",
        "tool_use_id": op_id,
        "tool_input": input,
    })
    .as_object()
    .unwrap()
    .clone()
}

fn post_create(op_id: &str, subject: &str, id: &str) -> Map<String, Value> {
    json!({
        "hook_event_name": "PostToolUse",
        "tool_name": "TaskCreate",
        "tool_use_id": op_id,
        "tool_input": {"subject": subject},
        "tool_response": {"task": {"id": id, "subject": subject}},
    })
    .as_object()
    .unwrap()
    .clone()
}

fn pre_update(op_id: &str, task_id: &str, status: &str) -> Map<String, Value> {
    json!({
        "hook_event_name": "PreToolUse",
        "tool_name": "TaskUpdate",
        "tool_use_id": op_id,
        "tool_input": {"taskId": task_id, "status": status},
    })
    .as_object()
    .unwrap()
    .clone()
}

fn post_update(op_id: &str, task_id: &str, from: &str, to: &str) -> Map<String, Value> {
    json!({
        "hook_event_name": "PostToolUse",
        "tool_name": "TaskUpdate",
        "tool_use_id": op_id,
        "tool_input": {"taskId": task_id, "status": to},
        "tool_response": {
            "success": true,
            "taskId": task_id,
            "updatedFields": ["status"],
            "statusChange": {"from": from, "to": to},
        },
    })
    .as_object()
    .unwrap()
    .clone()
}

fn blocked_update(op_id: &str, task_id: &str) -> Map<String, Value> {
    json!({
        "hook_event_name": "PostToolUse",
        "tool_name": "TaskUpdate",
        "tool_use_id": op_id,
        "tool_input": {"taskId": task_id, "status": "completed"},
        "tool_response": {
            "success": false,
            "taskId": task_id,
            "updatedFields": [],
            "error": "blocked",
        },
    })
    .as_object()
    .unwrap()
    .clone()
}

fn todo_write(op_id: &str, todos: &[(&str, &str)]) -> Map<String, Value> {
    let todos: Vec<Value> = todos
        .iter()
        .map(|(content, status)| {
            json!({"content": content, "status": status, "activeForm": format!("{content}\u{2026}ing")})
        })
        .collect();
    json!({
        "hook_event_name": "PreToolUse",
        "tool_name": "TodoWrite",
        "tool_use_id": op_id,
        "tool_input": {"todos": todos},
    })
    .as_object()
    .unwrap()
    .clone()
}

fn cursor_todo_write(op_id: &str, merge: bool, todos: Value) -> Map<String, Value> {
    json!({
        "hook_event_name": "preToolUse",
        "tool_name": "todo_write",
        "tool_use_id": op_id,
        "tool_input": {"merge": merge, "todos": todos},
    })
    .as_object()
    .unwrap()
    .clone()
}

fn prompt(prompt: &str) -> Map<String, Value> {
    json!({"hook_event_name": "UserPromptSubmit", "prompt": prompt})
        .as_object()
        .unwrap()
        .clone()
}

fn session_start(source: &str) -> Map<String, Value> {
    json!({
        "hook_event_name": "SessionStart",
        "source": source,
        "cwd": "/tmp/p",
    })
    .as_object()
    .unwrap()
    .clone()
}

fn as_child(mut payload: Map<String, Value>) -> Map<String, Value> {
    payload.insert("agent_id".into(), json!("teammate-1"));
    payload.insert("agent_type".into(), json!("worker"));
    payload
}

fn as_agent(mut payload: Map<String, Value>, agent: &str) -> Map<String, Value> {
    payload.insert("agent_id".into(), json!(agent));
    payload.insert("agent_type".into(), json!("Explore"));
    payload
}

// MARK: - Transcript rows

fn claude_task_transcript() -> Vec<String> {
    vec![
        claude_prompt_line("Refactor the parser"),
        claude_tool_use_line(
            "toolu_c1",
            "TaskCreate",
            r#"{"subject":"Write parser","description":"d","activeForm":"Writing parser"}"#,
        ),
        claude_result_line(
            "toolu_c1",
            "Task #1 created successfully: Write parser",
            r#"{"task":{"id":"1","subject":"Write parser"}}"#,
        ),
        claude_tool_use_line(
            "toolu_c2",
            "TaskCreate",
            r#"{"subject":"Add tests","description":"d"}"#,
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
        ),
        claude_result_line(
            "toolu_u1",
            "Updated task #1 status",
            r#"{"success":true,"taskId":"1","updatedFields":["status"],"statusChange":{"from":"pending","to":"in_progress"}}"#,
        ),
    ]
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

fn claude_tool_use_line(id: &str, name: &str, input: &str) -> String {
    format!(
        r#"{{"parentUuid":"x","isSidechain":false,"message":{{"model":"claude","type":"message","role":"assistant","content":[{{"type":"tool_use","id":"{id}","name":"{name}","input":{input}}}]}},"type":"assistant","uuid":"a1"}}"#
    )
}

fn claude_result_line(tool_use_id: &str, text: &str, tool_use_result: &str) -> String {
    format!(
        r#"{{"parentUuid":"a1","isSidechain":false,"type":"user","message":{{"role":"user","content":[{{"tool_use_id":"{tool_use_id}","type":"tool_result","content":"{text}"}}]}},"uuid":"r1","toolUseResult":{tool_use_result}}}"#
    )
}

fn codex_plan_line(call_id: &str, steps: &[(&str, &str)]) -> String {
    let plan = steps
        .iter()
        .map(|(step, status)| format!(r#"{{\"step\":\"{step}\",\"status\":\"{status}\"}}"#))
        .collect::<Vec<_>>()
        .join(",");
    format!(
        r#"{{"timestamp":"2026-06-25T01:40:57.835Z","ordinal":1,"type":"response_item","payload":{{"type":"function_call","id":"fc_1","name":"update_plan","arguments":"{{\"plan\":[{plan}]}}","call_id":"{call_id}"}}}}"#
    )
}

fn transcript_events(lines: &[String]) -> Vec<AgentTaskEvent> {
    let blob = format!("{}\n", lines.join("\n"));
    scan(blob.as_bytes(), true, 8 * 1024 * 1024)
}

// MARK: - Small readers

fn titles(list: &AgentTaskList) -> Vec<&str> {
    list.items.iter().map(|item| item.title.as_str()).collect()
}

fn statuses(list: &AgentTaskList) -> Vec<AgentTaskStatus> {
    list.items.iter().map(|item| item.status).collect()
}

fn task_ids(list: &AgentTaskList) -> Vec<Option<&str>> {
    list.items
        .iter()
        .map(|item| item.task_id.as_deref())
        .collect()
}

fn draft(title: &str, status: AgentTaskStatus) -> AgentTaskDraft {
    AgentTaskDraft {
        title: title.into(),
        active_form: None,
        status,
        row_id: None,
    }
}

fn item(id: &str, title: &str, status: AgentTaskStatus) -> AgentTaskItem {
    AgentTaskItem {
        id: id.into(),
        task_id: None,
        create_op_id: None,
        title: title.into(),
        active_form: None,
        status,
    }
}

fn finished_plan(op_id: &str) -> AgentTaskEvent {
    AgentTaskEvent::Replace {
        op_id: Some(op_id.into()),
        items: vec![
            draft("Read", AgentTaskStatus::Completed),
            draft("Patch", AgentTaskStatus::InProgress),
            draft("Test", AgentTaskStatus::Pending),
        ],
    }
}

// MARK: - Claude Task tools via hooks

#[test]
fn claude_task_tools_via_hooks_build_progress() {
    let mut sessions = Sessions::new();
    reduce(
        &mut sessions,
        pre_create("toolu_c1", "Write parser", Some("Writing parser")),
    );
    reduce(&mut sessions, post_create("toolu_c1", "Write parser", "1"));
    reduce(&mut sessions, pre_create("toolu_c2", "Add tests", None));
    reduce(&mut sessions, post_create("toolu_c2", "Add tests", "2"));
    reduce(&mut sessions, pre_update("toolu_u1", "1", "in_progress"));
    reduce(
        &mut sessions,
        post_update("toolu_u1", "1", "pending", "in_progress"),
    );

    let tasks = &sessions["s1"].agent_tasks;
    assert_eq!(task_ids(tasks), [Some("1"), Some("2")]);
    assert_eq!(titles(tasks), ["Write parser", "Add tests"]);
    assert_eq!(
        tasks.current().map(|row| row.progress_label()),
        Some("Writing parser")
    );
    assert_eq!(tasks.completed_count(), 0);

    reduce(&mut sessions, pre_update("toolu_u2", "1", "completed"));
    reduce(&mut sessions, pre_update("toolu_u3", "2", "in_progress"));
    let tasks = &sessions["s1"].agent_tasks;
    assert_eq!(tasks.completed_count(), 1);
    assert_eq!(
        tasks.current().map(|row| row.progress_label()),
        Some("Add tests")
    );
    assert!(!tasks.is_all_completed());
}

#[test]
fn update_before_create_result_is_parked_until_the_id_arrives() {
    // Claude's PostToolUse hooks run async: the next TaskUpdate's PreToolUse
    // can land before the TaskCreate result names the id.
    let mut sessions = Sessions::new();
    reduce(&mut sessions, pre_create("toolu_c1", "Write parser", None));
    reduce(&mut sessions, pre_update("toolu_u1", "1", "in_progress"));
    assert_eq!(
        statuses(&sessions["s1"].agent_tasks),
        [AgentTaskStatus::Pending]
    );

    reduce(&mut sessions, post_create("toolu_c1", "Write parser", "1"));
    assert_eq!(
        statuses(&sessions["s1"].agent_tasks),
        [AgentTaskStatus::InProgress]
    );
    assert_eq!(task_ids(&sessions["s1"].agent_tasks), [Some("1")]);
}

#[test]
fn update_arriving_before_any_create_lands_once_the_row_exists() {
    let mut list = AgentTaskList::new();
    list.apply_all(
        &[
            AgentTaskEvent::Update {
                op_id: Some("u1".into()),
                task_id: "3".into(),
                change: AgentTaskChange::with_status(AgentTaskStatus::Completed),
                expected_from: None,
            },
            AgentTaskEvent::Created {
                op_id: Some("c3".into()),
                task_id: "3".into(),
                title: Some("Ship it".into()),
                active_form: None,
            },
        ],
        T0,
    );
    assert_eq!(titles(&list), ["Ship it"]);
    assert_eq!(statuses(&list), [AgentTaskStatus::Completed]);
}

#[test]
fn late_async_result_cannot_roll_status_back() {
    let mut list = AgentTaskList::new();
    list.apply_all(
        &[
            AgentTaskEvent::Created {
                op_id: Some("c1".into()),
                task_id: "1".into(),
                title: Some("A".into()),
                active_form: None,
            },
            AgentTaskEvent::Update {
                op_id: Some("u2".into()),
                task_id: "1".into(),
                change: AgentTaskChange::with_status(AgentTaskStatus::Completed),
                expected_from: None,
            },
            // Result of an earlier update whose call we never saw.
            AgentTaskEvent::Update {
                op_id: Some("u1".into()),
                task_id: "1".into(),
                change: AgentTaskChange::with_status(AgentTaskStatus::InProgress),
                expected_from: Some(AgentTaskStatus::Pending),
            },
        ],
        T0,
    );
    assert_eq!(statuses(&list), [AgentTaskStatus::Completed]);
}

#[test]
fn duplicate_hook_events_apply_once() {
    let mut sessions = Sessions::new();
    for _ in 0..2 {
        reduce(&mut sessions, pre_create("toolu_c1", "Write parser", None));
        reduce(&mut sessions, post_create("toolu_c1", "Write parser", "1"));
        reduce(&mut sessions, pre_update("toolu_u1", "1", "completed"));
    }
    let tasks = &sessions["s1"].agent_tasks;
    assert_eq!(tasks.items.len(), 1);
    assert_eq!(tasks.completed_count(), 1);
}

#[test]
fn deleted_task_leaves_the_list() {
    let mut list = AgentTaskList::new();
    list.apply_all(
        &[
            AgentTaskEvent::Created {
                op_id: Some("c1".into()),
                task_id: "1".into(),
                title: Some("Keep".into()),
                active_form: None,
            },
            AgentTaskEvent::Created {
                op_id: Some("c2".into()),
                task_id: "2".into(),
                title: Some("Drop".into()),
                active_form: None,
            },
            AgentTaskEvent::Update {
                op_id: Some("u1".into()),
                task_id: "2".into(),
                change: AgentTaskChange {
                    is_deletion: true,
                    ..AgentTaskChange::default()
                },
                expected_from: None,
            },
        ],
        T0,
    );
    assert_eq!(titles(&list), ["Keep"]);

    // A deletion that overtakes the create result is parked, then applied.
    list.apply_all(
        &[
            AgentTaskEvent::Create {
                op_id: "c3".into(),
                title: "Gone".into(),
                active_form: None,
            },
            AgentTaskEvent::Update {
                op_id: Some("u3".into()),
                task_id: "3".into(),
                change: AgentTaskChange {
                    is_deletion: true,
                    ..AgentTaskChange::default()
                },
                expected_from: None,
            },
            AgentTaskEvent::Created {
                op_id: Some("c3".into()),
                task_id: "3".into(),
                title: Some("Gone".into()),
                active_form: None,
            },
        ],
        T0,
    );
    assert_eq!(titles(&list), ["Keep"]);
}

#[test]
fn deleted_status_from_hook_removes_row() {
    let mut sessions = Sessions::new();
    reduce(&mut sessions, pre_create("toolu_c1", "A", None));
    reduce(&mut sessions, post_create("toolu_c1", "A", "1"));
    reduce(&mut sessions, pre_create("toolu_c2", "B", None));
    reduce(&mut sessions, post_create("toolu_c2", "B", "2"));
    reduce(&mut sessions, pre_update("toolu_u1", "1", "deleted"));
    assert_eq!(titles(&sessions["s1"].agent_tasks), ["B"]);
}

#[test]
fn failed_update_is_undone() {
    let mut sessions = Sessions::new();
    reduce(&mut sessions, pre_create("toolu_c1", "A", None));
    reduce(&mut sessions, post_create("toolu_c1", "A", "1"));
    reduce(&mut sessions, pre_update("toolu_u1", "1", "in_progress"));
    reduce(&mut sessions, pre_update("toolu_u2", "1", "completed"));
    // A TaskCompleted hook blocked the completion.
    reduce(&mut sessions, blocked_update("toolu_u2", "1"));
    assert_eq!(
        statuses(&sessions["s1"].agent_tasks),
        [AgentTaskStatus::InProgress]
    );
}

#[test]
fn failed_create_drops_the_draft() {
    let mut sessions = Sessions::new();
    reduce(&mut sessions, pre_create("toolu_c1", "A", None));
    reduce(
        &mut sessions,
        json!({
            "hook_event_name": "PostToolUseFailure",
            "tool_name": "TaskCreate",
            "tool_use_id": "toolu_c1",
            "tool_input": {"subject": "A"},
        })
        .as_object()
        .unwrap()
        .clone(),
    );
    assert!(sessions["s1"].agent_tasks.is_empty());
}

// MARK: - Snapshot lists

#[test]
fn todo_write_snapshot_replaces_the_list() {
    let mut sessions = Sessions::new();
    reduce(
        &mut sessions,
        todo_write(
            "toolu_w1",
            &[
                ("Read code", "completed"),
                ("Fix bug", "in_progress"),
                ("Run tests", "pending"),
            ],
        ),
    );
    let tasks = &sessions["s1"].agent_tasks;
    assert_eq!(titles(tasks), ["Read code", "Fix bug", "Run tests"]);
    assert_eq!(
        tasks.current().map(|row| row.progress_label()),
        Some("Fix bug…ing")
    );
    assert_eq!(tasks.completed_count(), 1);

    reduce(
        &mut sessions,
        todo_write(
            "toolu_w2",
            &[
                ("Read code", "completed"),
                ("Fix bug", "completed"),
                ("Run tests", "in_progress"),
            ],
        ),
    );
    // PostToolUse repeats the same call — applied once.
    let mut post = todo_write("toolu_w2", &[("Read code", "completed")]);
    post.insert("hook_event_name".into(), json!("PostToolUse"));
    reduce(&mut sessions, post);
    let tasks = &sessions["s1"].agent_tasks;
    assert_eq!(tasks.items.len(), 3);
    assert_eq!(tasks.completed_count(), 2);

    reduce(&mut sessions, todo_write("toolu_w3", &[]));
    assert!(sessions["s1"].agent_tasks.is_empty());
}

#[test]
fn cursor_todo_write_merge_updates_rows_by_id_instead_of_replacing_the_list() {
    let mut sessions = Sessions::new();
    reduce(
        &mut sessions,
        cursor_todo_write(
            "w1",
            false,
            json!([
                {"id": "1", "content": "Scan the repo", "status": "in_progress"},
                {"id": "2", "content": "Fix the bug", "status": "pending"},
                {"id": "3", "content": "Run tests", "status": "pending"},
            ]),
        ),
    );
    assert_eq!(
        task_ids(&sessions["s1"].agent_tasks),
        [Some("1"), Some("2"), Some("3")]
    );

    // Cursor's partial update: only ids and statuses.
    reduce(
        &mut sessions,
        cursor_todo_write(
            "w2",
            true,
            json!([
                {"id": "1", "status": "completed"},
                {"id": "2", "status": "in_progress"},
            ]),
        ),
    );
    let tasks = &sessions["s1"].agent_tasks;
    assert_eq!(titles(tasks), ["Scan the repo", "Fix the bug", "Run tests"]);
    assert_eq!(
        statuses(tasks),
        [
            AgentTaskStatus::Completed,
            AgentTaskStatus::InProgress,
            AgentTaskStatus::Pending
        ]
    );

    // A merge can rename a row, add one, and cancel one.
    reduce(
        &mut sessions,
        cursor_todo_write(
            "w3",
            true,
            json!([
                {"id": "2", "content": "Fix the parser bug"},
                {"id": "4", "content": "Update docs", "status": "pending"},
                {"id": "3", "status": "cancelled"},
                {"id": "99", "status": "completed"},
            ]),
        ),
    );
    let tasks = &sessions["s1"].agent_tasks;
    assert_eq!(
        titles(tasks),
        ["Scan the repo", "Fix the parser bug", "Update docs"]
    );
    assert_eq!(
        statuses(tasks),
        [
            AgentTaskStatus::Completed,
            AgentTaskStatus::InProgress,
            AgentTaskStatus::Pending
        ]
    );
    let ids: std::collections::BTreeSet<&str> = tasks.items.iter().map(|i| i.id.as_str()).collect();
    assert_eq!(ids.len(), 3, "row identities stay unique");

    // merge:false is still a whole-list replacement.
    reduce(
        &mut sessions,
        cursor_todo_write(
            "w4",
            false,
            json!([{"id": "9", "content": "Fresh", "status": "pending"}]),
        ),
    );
    assert_eq!(titles(&sessions["s1"].agent_tasks), ["Fresh"]);
}

#[test]
fn merge_of_id_only_rows_into_an_empty_list_shows_nothing() {
    let mut list = AgentTaskList::new();
    list.apply(
        &AgentTaskEvent::Merge {
            op_id: Some("w1".into()),
            rows: vec![morrow_core::agent_tasks::AgentTaskRowPatch {
                row_id: Some("1".into()),
                change: AgentTaskChange::with_status(AgentTaskStatus::Completed),
            }],
        },
        T0,
    );
    assert!(list.is_empty());
}

#[test]
fn codex_update_plan_from_rollout_line() {
    let line = codex_plan_line(
        "call_p1",
        &[
            ("Inspect intro", "completed"),
            ("Rewrite framing", "in_progress"),
            ("Compile", "pending"),
        ],
    );
    let mut list = AgentTaskList::new();
    list.apply_all(&transcript_events(&[line]), T0);
    assert_eq!(
        titles(&list),
        ["Inspect intro", "Rewrite framing", "Compile"]
    );
    assert_eq!(
        statuses(&list),
        [
            AgentTaskStatus::Completed,
            AgentTaskStatus::InProgress,
            AgentTaskStatus::Pending
        ]
    );
}

#[test]
fn codex_turn_start_is_a_new_turn() {
    let started = r#"{"type":"event_msg","payload":{"type":"task_started","turn_id":"t2"}}"#;
    assert_eq!(
        transcript_events(&[started.to_owned()]),
        [AgentTaskEvent::NewTurn]
    );
    let complete = r#"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"t2"}}"#;
    assert_eq!(
        transcript_events(&[complete.to_owned()]),
        [AgentTaskEvent::TurnEnded]
    );
}

// MARK: - Turn boundaries

#[test]
fn new_turn_clears_only_a_finished_list() {
    let mut sessions = Sessions::new();
    reduce(
        &mut sessions,
        todo_write("toolu_w1", &[("A", "completed"), ("B", "in_progress")]),
    );
    reduce(&mut sessions, prompt("keep going"));
    assert_eq!(
        sessions["s1"].agent_tasks.items.len(),
        2,
        "an unfinished plan survives a new prompt"
    );

    reduce(
        &mut sessions,
        todo_write("toolu_w2", &[("A", "completed"), ("B", "completed")]),
    );
    assert!(sessions["s1"].agent_tasks.is_all_completed());
    reduce(&mut sessions, prompt("next thing"));
    assert!(sessions["s1"].agent_tasks.is_empty());
}

// MARK: - Abandoned snapshot plans

#[test]
fn snapshot_plan_retires_after_a_whole_turn_without_updates() {
    let mut list = AgentTaskList::new();
    list.apply_all(&[AgentTaskEvent::NewTurn, finished_plan("p1")], T0);
    list.apply(&AgentTaskEvent::TurnEnded, at(60));

    // Next turn: the plan is still the agent's until a turn ignores it.
    list.apply(&AgentTaskEvent::NewTurn, at(100));
    assert_eq!(list.items.len(), 3);
    list.apply(&AgentTaskEvent::TurnEnded, at(160));

    list.apply(&AgentTaskEvent::NewTurn, at(200));
    assert!(
        list.is_empty(),
        "a plan a whole turn went by without is abandoned"
    );
}

#[test]
fn a_plan_updated_during_the_turn_survives() {
    let mut list = AgentTaskList::new();
    list.apply_all(&[AgentTaskEvent::NewTurn, finished_plan("p1")], T0);
    list.apply(&AgentTaskEvent::TurnEnded, at(60));
    list.apply(&AgentTaskEvent::NewTurn, at(100));
    list.apply(&finished_plan("p2"), at(120));
    list.apply(&AgentTaskEvent::TurnEnded, at(160));
    list.apply(&AgentTaskEvent::NewTurn, at(200));
    assert_eq!(list.items.len(), 3);

    // An unrelated failing tool is not an update of the plan.
    list.apply(
        &AgentTaskEvent::OpFailed {
            op_id: "toolu_bash".into(),
        },
        at(210),
    );
    list.apply(&AgentTaskEvent::TurnEnded, at(260));
    list.apply(&AgentTaskEvent::NewTurn, at(300));
    assert!(list.is_empty());
}

#[test]
fn boundaries_from_both_channels_do_not_retire_a_plan_in_use() {
    // A queued Codex prompt runs right after the previous turn: the hooks
    // (Stop, UserPromptSubmit) and the rollout (task_complete, task_started,
    // user_message) report the same two boundaries, the rollout's late.
    let mut list = AgentTaskList::new();
    list.apply_all(&[AgentTaskEvent::NewTurn, finished_plan("p1")], T0);
    let end = 60.0;
    list.apply(&AgentTaskEvent::TurnEnded, at(end)); // hook Stop
    list.apply(&AgentTaskEvent::NewTurn, at(end + 0.1)); // hook UserPromptSubmit
    list.apply(&AgentTaskEvent::TurnEnded, at(end + 0.2)); // rollout task_complete
    list.apply(&AgentTaskEvent::NewTurn, at(end + 0.3)); // rollout task_started
    list.apply(&AgentTaskEvent::NewTurn, at(end + 0.3)); // rollout user_message
    assert_eq!(list.items.len(), 3);
    list.apply(&AgentTaskEvent::NewTurn, at(end + 1.0));
    assert_eq!(
        list.items.len(),
        3,
        "repeated starts of one turn change nothing"
    );
}

#[test]
fn task_create_lists_are_not_retired_for_an_untouched_turn() {
    // Claude's tasks live on in the CLI's own task store.
    let mut list = AgentTaskList::new();
    list.apply_all(
        &[
            AgentTaskEvent::NewTurn,
            AgentTaskEvent::Created {
                op_id: Some("c1".into()),
                task_id: "1".into(),
                title: Some("A".into()),
                active_form: None,
            },
        ],
        T0,
    );
    for turn in 1..=3 {
        list.apply(&AgentTaskEvent::TurnEnded, at(turn as f64 * 100.0 - 50.0));
        list.apply(&AgentTaskEvent::NewTurn, at(turn as f64 * 100.0));
    }
    assert_eq!(titles(&list), ["A"]);
}

#[test]
fn restored_plan_needs_a_whole_observed_turn_before_retiring() {
    let mut list = AgentTaskList::restored(
        vec![item("step:0", "Patch", AgentTaskStatus::InProgress)],
        None,
    );
    list.apply(&AgentTaskEvent::TurnEnded, T0); // end of a turn we never saw start
    list.apply(&AgentTaskEvent::NewTurn, at(10));
    assert_eq!(list.items.len(), 1);
    list.apply(&AgentTaskEvent::TurnEnded, at(70));
    list.apply(&AgentTaskEvent::NewTurn, at(100));
    assert!(list.is_empty());
}

#[test]
fn replayed_rollout_retires_a_plan_later_turns_abandoned() {
    let lines = vec![
        r#"{"type":"event_msg","payload":{"type":"task_started","turn_id":"t1"}}"#.to_owned(),
        r#"{"type":"event_msg","payload":{"type":"user_message","message":"fix it"}}"#.to_owned(),
        codex_plan_line(
            "call_p1",
            &[("Read", "completed"), ("Patch", "in_progress")],
        ),
        r#"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"t1"}}"#.to_owned(),
        r#"{"type":"event_msg","payload":{"type":"task_started","turn_id":"t2"}}"#.to_owned(),
        r#"{"type":"event_msg","payload":{"type":"user_message","message":"what does X do?"}}"#
            .to_owned(),
        r#"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"t2"}}"#.to_owned(),
    ];
    let events = transcript_events(&lines);
    assert_eq!(
        events
            .iter()
            .filter(|event| **event == AgentTaskEvent::TurnEnded)
            .count(),
        2
    );
    let mut rebuilt = AgentTaskList::rebuilt(&events, true, AgentTaskList::new());
    assert_eq!(
        rebuilt.items.len(),
        2,
        "still shown until the next turn starts"
    );
    rebuilt.apply(&AgentTaskEvent::NewTurn, T0);
    assert!(rebuilt.is_empty());
}

#[test]
fn stop_hook_ends_the_turn() {
    let mut sessions = Sessions::new();
    reduce(&mut sessions, prompt("go"));
    reduce(
        &mut sessions,
        todo_write("toolu_w1", &[("A", "completed"), ("B", "in_progress")]),
    );
    reduce(
        &mut sessions,
        json!({"hook_event_name": "Stop"})
            .as_object()
            .unwrap()
            .clone(),
    );
    reduce(&mut sessions, prompt("unrelated question"));
    assert_eq!(sessions["s1"].agent_tasks.items.len(), 2);
    // The reducer's clock stands still here; age the turn past the minimum.
    sessions
        .get_mut("s1")
        .unwrap()
        .agent_tasks
        .apply(&AgentTaskEvent::TurnEnded, at(60));
    reduce(&mut sessions, prompt("another"));
    assert!(sessions["s1"].agent_tasks.is_empty());
}

#[test]
fn session_start_keeps_the_checklist() {
    // /compact and resume re-fire SessionStart for the same session.
    let mut sessions = Sessions::new();
    reduce(
        &mut sessions,
        todo_write("toolu_w1", &[("A", "in_progress")]),
    );
    reduce(&mut sessions, session_start("compact"));
    assert_eq!(titles(&sessions["s1"].agent_tasks), ["A"]);
    reduce(&mut sessions, session_start("resume"));
    assert_eq!(titles(&sessions["s1"].agent_tasks), ["A"]);
}

#[test]
fn session_start_after_clear_drops_the_checklist() {
    // /clear can keep the session id; the conversation (and its plan) is gone.
    let mut sessions = Sessions::new();
    reduce(
        &mut sessions,
        todo_write("toolu_w1", &[("A", "in_progress"), ("B", "pending")]),
    );
    reduce(&mut sessions, session_start("clear"));
    assert!(sessions["s1"].agent_tasks.is_empty());
}

// MARK: - Subagents

#[test]
fn subagent_task_events_stay_off_the_parent_card() {
    let mut sessions = Sessions::new();
    reduce(
        &mut sessions,
        as_agent(pre_create("toolu_c1", "Child task", None), "agent-1"),
    );
    reduce(
        &mut sessions,
        as_agent(post_create("toolu_c1", "Child task", "9"), "agent-1"),
    );
    reduce(
        &mut sessions,
        as_agent(
            todo_write("toolu_w1", &[("Child todo", "pending")]),
            "agent-1",
        ),
    );

    assert!(sessions["s1"].agent_tasks.is_empty());
    assert!(
        sessions["s1"].subagents.contains_key("agent-1"),
        "the subagent itself is still tracked"
    );
}

#[test]
fn subagent_updates_to_the_parents_shared_tasks_land_on_the_parent_card() {
    let mut sessions = Sessions::new();
    reduce(&mut sessions, pre_create("toolu_c1", "Write parser", None));
    reduce(&mut sessions, post_create("toolu_c1", "Write parser", "1"));
    reduce(&mut sessions, pre_create("toolu_c2", "Add tests", None));
    reduce(&mut sessions, post_create("toolu_c2", "Add tests", "2"));

    // The teammate picks up task 1 and finishes it.
    reduce(
        &mut sessions,
        as_child(pre_update("toolu_s1", "1", "in_progress")),
    );
    reduce(
        &mut sessions,
        as_child(post_update("toolu_s1", "1", "pending", "in_progress")),
    );
    reduce(
        &mut sessions,
        as_child(pre_update("toolu_s2", "1", "completed")),
    );
    assert_eq!(
        statuses(&sessions["s1"].agent_tasks),
        [AgentTaskStatus::Completed, AgentTaskStatus::Pending]
    );

    // Its completion of task 2 is blocked by a TaskCompleted hook: undone.
    reduce(
        &mut sessions,
        as_child(pre_update("toolu_s3", "2", "completed")),
    );
    reduce(&mut sessions, as_child(blocked_update("toolu_s3", "2")));
    assert_eq!(
        statuses(&sessions["s1"].agent_tasks),
        [AgentTaskStatus::Completed, AgentTaskStatus::Pending]
    );

    // Its own task and updates to it stay off the parent card.
    reduce(
        &mut sessions,
        as_child(pre_create("toolu_s4", "Child-only step", None)),
    );
    reduce(
        &mut sessions,
        as_child(post_create("toolu_s4", "Child-only step", "7")),
    );
    reduce(
        &mut sessions,
        as_child(pre_update("toolu_s5", "7", "in_progress")),
    );
    assert_eq!(
        titles(&sessions["s1"].agent_tasks),
        ["Write parser", "Add tests"]
    );
    assert!(sessions["s1"].subagents.contains_key("teammate-1"));
}

// MARK: - Hook + transcript double delivery

#[test]
fn hook_and_transcript_delivering_same_calls_do_not_double_count() {
    let transcript = claude_task_transcript();

    // Hooks first, then the tail catches up.
    let mut sessions = Sessions::new();
    reduce(
        &mut sessions,
        pre_create("toolu_c1", "Write parser", Some("Writing parser")),
    );
    reduce(&mut sessions, post_create("toolu_c1", "Write parser", "1"));
    reduce(&mut sessions, pre_create("toolu_c2", "Add tests", None));
    reduce(&mut sessions, post_create("toolu_c2", "Add tests", "2"));
    reduce(&mut sessions, pre_update("toolu_u1", "1", "in_progress"));
    let via_hooks = sessions["s1"].agent_tasks.clone();
    sessions
        .get_mut("s1")
        .unwrap()
        .agent_tasks
        .apply_all(&transcript_events(&transcript), T0);
    assert_eq!(sessions["s1"].agent_tasks.items, via_hooks.items);

    // Tail first, then (late, async) hooks for the same calls.
    let mut list = AgentTaskList::new();
    list.apply_all(&transcript_events(&transcript), T0);
    let via_transcript = list.items.clone();
    let mut late_sessions = Sessions::new();
    late_sessions.insert("s1".into(), SessionSnapshot::new(T0));
    late_sessions.get_mut("s1").unwrap().agent_tasks = list;
    reduce(
        &mut late_sessions,
        post_create("toolu_c1", "Write parser", "1"),
    );
    reduce(
        &mut late_sessions,
        pre_create("toolu_c2", "Add tests", None),
    );
    reduce(
        &mut late_sessions,
        post_update("toolu_u1", "1", "pending", "in_progress"),
    );
    let late = &late_sessions["s1"].agent_tasks;
    assert_eq!(late.items.len(), 2);
    assert_eq!(
        statuses(late),
        via_transcript.iter().map(|i| i.status).collect::<Vec<_>>()
    );
    assert_eq!(
        via_transcript.iter().map(|i| i.status).collect::<Vec<_>>(),
        [AgentTaskStatus::InProgress, AgentTaskStatus::Pending]
    );
}

// MARK: - Text-only results

#[test]
fn text_only_create_result_completes_a_draft_but_never_adds_a_row() {
    let mcp_result = r#"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_mcp","type":"tool_result","content":[{"type":"text","text":"Task #42 created successfully: sync tickets"}]}]}}"#;
    let mut list = AgentTaskList::new();
    list.apply(
        &AgentTaskEvent::Replace {
            op_id: Some("w1".into()),
            items: vec![draft("A", AgentTaskStatus::Completed)],
        },
        T0,
    );
    list.apply_all(&transcript_events(&[mcp_result.to_owned()]), T0);
    assert_eq!(
        titles(&list),
        ["A"],
        "no ghost row from someone else's text"
    );
    list.apply(&AgentTaskEvent::NewTurn, T0);
    assert!(
        list.is_empty(),
        "and nothing pending keeps a finished list from retiring"
    );

    // A real TaskCreate answered in a multi-result row: its draft gets the id.
    let call = claude_tool_use_line("toolu_a", "TaskCreate", r#"{"subject":"Five"}"#);
    let multi = r#"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_a","type":"tool_result","content":"Task #5 created successfully: Five"},{"tool_use_id":"toolu_b","type":"tool_result","content":"ok"}]}}"#;
    let mut events = transcript_events(&[call]);
    events.extend(transcript_events(&[multi.to_owned()]));
    list.apply_all(&events, T0);
    list.apply(
        &AgentTaskEvent::Update {
            op_id: Some("u5".into()),
            task_id: "5".into(),
            change: AgentTaskChange::with_status(AgentTaskStatus::InProgress),
            expected_from: None,
        },
        T0,
    );
    assert_eq!(task_ids(&list), [Some("5")]);
    assert_eq!(statuses(&list), [AgentTaskStatus::InProgress]);
}

#[test]
fn ignored_text_result_leaves_the_structured_result_free() {
    // The text row came first with no draft to complete; the call's own
    // structured result (a late hook) must still apply.
    let mut list = AgentTaskList::new();
    list.apply(
        &AgentTaskEvent::CreatedPerText {
            op_id: "c1".into(),
            task_id: "1".into(),
            title: Some("A".into()),
        },
        T0,
    );
    list.apply(
        &AgentTaskEvent::Created {
            op_id: Some("c1".into()),
            task_id: "1".into(),
            title: Some("A".into()),
            active_form: None,
        },
        T0,
    );
    assert_eq!(titles(&list), ["A"]);
}

// MARK: - Completion linger

#[test]
fn completion_linger_then_hides() {
    let mut list = AgentTaskList::new();
    list.apply(
        &AgentTaskEvent::Replace {
            op_id: Some("w1".into()),
            items: vec![draft("A", AgentTaskStatus::InProgress)],
        },
        T0,
    );
    assert_eq!(list.completed_at(), None);
    assert!(
        list.is_visible(at(3_600.0), 8.0),
        "open lists never time out"
    );

    let done = at(10.0);
    list.apply(
        &AgentTaskEvent::Replace {
            op_id: Some("w2".into()),
            items: vec![draft("A", AgentTaskStatus::Completed)],
        },
        done,
    );
    assert_eq!(list.completed_at(), Some(done));
    assert!(list.is_visible(at(11.0), 8.0));
    assert!(!list.is_visible(at(10.0 + 8.0), 8.0));

    // A duplicate all-done snapshot must not restart the linger.
    list.apply(
        &AgentTaskEvent::Replace {
            op_id: Some("w3".into()),
            items: vec![draft("A", AgentTaskStatus::Completed)],
        },
        at(15.0),
    );
    assert_eq!(list.completed_at(), Some(done));

    list.apply(
        &AgentTaskEvent::Replace {
            op_id: Some("w4".into()),
            items: vec![draft("B", AgentTaskStatus::Pending)],
        },
        done,
    );
    assert_eq!(list.completed_at(), None);
}

// MARK: - Attach-time rebuild

#[test]
fn rebuild_from_whole_transcript_replaces_stale_rows() {
    let stale = AgentTaskList::restored(
        vec![item("step:0", "Old", AgentTaskStatus::InProgress)],
        None,
    );
    let events = transcript_events(&claude_task_transcript());
    let rebuilt = AgentTaskList::rebuilt(&events, true, stale);
    assert_eq!(titles(&rebuilt), ["Write parser", "Add tests"]);
}

#[test]
fn rebuild_from_tail_window_keeps_rows_created_before_it() {
    let live = AgentTaskList::restored(
        vec![AgentTaskItem {
            id: "task:1".into(),
            task_id: Some("1".into()),
            create_op_id: Some("toolu_c1".into()),
            title: "Early".into(),
            active_form: None,
            status: AgentTaskStatus::InProgress,
        }],
        None,
    );
    let window = [
        AgentTaskEvent::Update {
            op_id: Some("u9".into()),
            task_id: "1".into(),
            change: AgentTaskChange::with_status(AgentTaskStatus::Completed),
            expected_from: None,
        },
        AgentTaskEvent::Create {
            op_id: "toolu_c2".into(),
            title: "Late".into(),
            active_form: None,
        },
        AgentTaskEvent::Created {
            op_id: Some("toolu_c2".into()),
            task_id: "2".into(),
            title: Some("Late".into()),
            active_form: None,
        },
    ];
    let rebuilt = AgentTaskList::rebuilt(&window, false, live);
    assert_eq!(titles(&rebuilt), ["Early", "Late"]);
    assert_eq!(
        statuses(&rebuilt),
        [AgentTaskStatus::Completed, AgentTaskStatus::Pending]
    );
}

#[test]
fn rebuild_without_operations_keeps_live_and_replayed_completion_does_not_flash() {
    let live =
        AgentTaskList::restored(vec![item("step:0", "A", AgentTaskStatus::InProgress)], None);
    assert_eq!(
        AgentTaskList::rebuilt(&[AgentTaskEvent::NewTurn], true, live.clone()),
        live
    );

    let finished = AgentTaskList::rebuilt(
        &[AgentTaskEvent::Replace {
            op_id: Some("w1".into()),
            items: vec![draft("A", AgentTaskStatus::Completed)],
        }],
        true,
        AgentTaskList::new(),
    );
    assert!(finished.is_all_completed());
    assert!(
        !finished.is_visible(T0, 8.0),
        "a list finished before attach must not show 'all done'"
    );
}

// MARK: - Backfill scanner

#[test]
fn backfill_scan_skips_partial_head_oversized_rows_and_unterminated_tail() {
    let lines = claude_task_transcript();
    let oversized = claude_tool_use_line(
        "toolu_big",
        "TaskCreate",
        &format!(
            r#"{{"subject":"Huge","description":"{}"}}"#,
            "x".repeat(2_000)
        ),
    );
    // Window cut mid-row, an oversized row, the real rows, then a row still
    // being written.
    let blob = format!(
        "ated successfully\"}}]}}\n{oversized}\n{}\n{{\"type\":\"user\",\"mess",
        lines.join("\n")
    );
    let events = scan(blob.as_bytes(), false, 1_024);
    let mut list = AgentTaskList::new();
    list.apply_all(&events, T0);
    assert_eq!(titles(&list), ["Write parser", "Add tests"]);
    assert_eq!(
        statuses(&list),
        [AgentTaskStatus::InProgress, AgentTaskStatus::Pending]
    );
}

#[test]
fn backfill_replays_a_fork_transcript_that_spells_the_tool_differently() {
    let lines = vec![
        claude_prompt_line("plan it"),
        claude_tool_use_line(
            "toolu_w1",
            "write_todos",
            r#"{"todos":[{"description":"Scan","status":"completed"},{"description":"Fix","status":"in_progress"}]}"#,
        ),
    ];
    let events = transcript_events(&lines);
    let rebuilt = AgentTaskList::rebuilt(
        &events,
        true,
        AgentTaskList::restored(
            vec![item("step:0", "Stale", AgentTaskStatus::Pending)],
            None,
        ),
    );
    assert_eq!(titles(&rebuilt), ["Scan", "Fix"]);
}

#[test]
fn transcript_of_only_prompts_and_unrelated_failures_keeps_the_live_list() {
    // A Bash call failed (is_error) and a prompt was typed: nothing in there
    // can build a checklist, so what hooks built must survive.
    let live =
        AgentTaskList::restored(vec![item("step:0", "A", AgentTaskStatus::InProgress)], None);
    let events = [
        AgentTaskEvent::NewTurn,
        AgentTaskEvent::OpFailed {
            op_id: "toolu_bash".into(),
        },
        AgentTaskEvent::CreatedPerText {
            op_id: "toolu_mcp".into(),
            task_id: "9".into(),
            title: None,
        },
    ];
    assert!(!events.iter().any(AgentTaskEvent::builds_list));
    assert_eq!(AgentTaskList::rebuilt(&events, true, live.clone()), live);
}

// MARK: - Persistence

#[test]
fn persisted_round_trip_keeps_items_and_completion() {
    let mut list = AgentTaskList::new();
    list.apply_all(
        &[
            AgentTaskEvent::Created {
                op_id: Some("c1".into()),
                task_id: "1".into(),
                title: Some("A".into()),
                active_form: Some("Doing A".into()),
            },
            AgentTaskEvent::Update {
                op_id: Some("u1".into()),
                task_id: "1".into(),
                change: AgentTaskChange::with_status(AgentTaskStatus::Completed),
                expected_from: None,
            },
        ],
        T0,
    );
    let decoded = AgentTaskList::from_json(&list.to_json());
    assert_eq!(decoded, list);
    assert_eq!(decoded.items[0].active_form.as_deref(), Some("Doing A"));
    assert_eq!(decoded.completed_at(), Some(T0));
}

#[test]
fn unknown_persisted_status_decodes_as_pending() {
    let json: Value = serde_json::from_str(
        r#"{"items":[{"id":"a","title":"A","status":"in_progress"},{"id":"b","title":"B","status":"awaiting_review"},{"id":"c","title":"C","status":"done"}]}"#,
    )
    .unwrap();
    let decoded = AgentTaskList::from_json(&json);
    assert_eq!(
        statuses(&decoded),
        [
            AgentTaskStatus::InProgress,
            AgentTaskStatus::Pending,
            AgentTaskStatus::Completed
        ]
    );
    // Encoding still writes the canonical raw values.
    let reencoded = decoded.to_json().to_string();
    assert!(reencoded.contains(r#""status":"in_progress""#));
    assert!(reencoded.contains(r#""status":"completed""#));
}
