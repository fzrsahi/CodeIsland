//! What an edge that cannot run HookIntake sends instead: the facts it
//! observed, in its payload's `_edge` object, next to the agent's stdin
//! object (`HookEdgeFacts`, `Sources/MorrowCore/HookEdgeFacts.swift`;
//! `docs/hook-edge-protocol.md`). The island runs HookIntake on them as a
//! bridge does on its own side.
//!
//! Every edge that sends facts runs on another machine: a bridge reads its
//! own and drops an `_edge` piped into it. So no fact is taken for the
//! island's machine: no pid is tracked, no home or file consulted,
//! whatever `host` says, or if it says nothing. The facts are read
//! leniently, as Swift reads them: a field of the wrong type is absent.
//! (Schema checks are `morrow-protocol`'s.)

use std::collections::HashMap;

use serde_json::Value;

use super::session_snapshot::{SourceCatalog, normalized_supported_source};
use super::{ENVIRONMENT_KEYS, EdgeHost, Facts, HookIntake, admits};
use crate::JsonObject;

/// The payload key the facts travel under.
pub const KEY: &str = "_edge";

/// The facts version this island reads. Fields are added without changing
/// it; facts naming another version are read for the fields this one knows.
pub const VERSION: u64 = 1;

/// What an `_edge` payload delivers.
#[derive(Debug)]
pub enum Delivery {
    /// Nothing to forward: the facts rule it out (MORROW_SKIP, a hook Grok
    /// imported) or it names no session. The edge gets no answer.
    Dropped,
    Interpreted(Box<HookIntake<'static>>),
}

/// `mayCarryFacts`: a cheap probe on the raw bytes, so a payload that
/// cannot carry facts is never parsed for them.
pub fn may_carry_facts(data: &[u8]) -> bool {
    let key = br#""_edge""#;
    data.windows(key.len()).any(|window| window == key)
}

/// `delivery(in:)`: what `payload` delivers, or `None` when it carries no
/// `_edge` facts.
pub fn delivery(payload: &JsonObject, catalog: &SourceCatalog) -> Option<Delivery> {
    let edge = payload.get(KEY)?.as_object()?;
    let facts = facts(edge, catalog);
    if !admits(facts.source_tag.as_deref(), &facts.environment) {
        return Some(Delivery::Dropped);
    }
    // A blank cwd is no cwd: the edge's own (or Grok's workspace) stands in.
    let mut stdin = payload.clone();
    if stdin
        .get("cwd")
        .and_then(Value::as_str)
        .is_some_and(|cwd| cwd.trim().is_empty())
    {
        stdin.remove("cwd");
    }
    let Some(mut intake) = HookIntake::new(stdin, facts) else {
        return Some(Delivery::Dropped);
    };
    intake.add_terminal_context();
    Some(Delivery::Interpreted(Box::new(intake)))
}

/// `facts(from:)`: HookIntake's facts from an `_edge` object, those of
/// another machine.
pub fn facts(edge: &JsonObject, catalog: &SourceCatalog) -> Facts<'static> {
    let source = string(edge.get("source"));
    // Claude Code's hook is the one other agents run too (Cursor imports
    // it, omo fires it), so on the island's machine it carries no
    // `--source`. An edge's `claude` is that same hook: read as no tag, with
    // Claude what is left when nothing else names the agent.
    let is_claudes_own_hook =
        normalized_supported_source(source.as_deref(), catalog).as_deref() == Some("claude");
    let environment: HashMap<String, String> = edge
        .get("env")
        .and_then(Value::as_object)
        .map(|env| {
            env.iter()
                .filter(|(key, _)| ENVIRONMENT_KEYS.contains(&key.as_str()))
                .filter_map(|(key, value)| Some((key.clone(), value.as_str()?.to_owned())))
                .collect()
        })
        .unwrap_or_default();
    let working_directory = string(edge.get("cwd"));
    let tty = string(edge.get("tty"));
    let digest = string(edge.get("stdin_sha256"));
    let tmux_client_tty = string(edge.get("tmux_client_tty"));
    // Another machine, even when `host` is missing or malformed.
    let host = edge.get("host").and_then(Value::as_object);
    let host_field = |key: &str| {
        host.and_then(|h| h.get(key))
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned()
    };

    Facts {
        source_tag: if is_claudes_own_hook { None } else { source },
        event_tag: string(edge.get("event")),
        default_source: is_claudes_own_hook.then(|| "claude".to_owned()),
        environment,
        working_directory: Box::new(move || working_directory.clone()),
        tty: Box::new(move || tty.clone()),
        remote_host: Some(EdgeHost {
            id: host_field("id"),
            name: host_field("name"),
        }),
        stdin_digest: Box::new(move || digest.clone()),
        edge_waits: edge.get("waits").and_then(super::swift_bool),
        tmux_client_tty: Box::new(move |_| tmux_client_tty.clone()),
        catalog: catalog.clone(),
        ..Facts::default()
    }
}

/// A string with something besides whitespace, as it was sent.
fn string(value: Option<&Value>) -> Option<String> {
    value?
        .as_str()
        .filter(|raw| !raw.trim().is_empty())
        .map(str::to_owned)
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    fn interpret(payload: Value) -> HookIntake<'static> {
        let payload = payload.as_object().unwrap().clone();
        match delivery(&payload, &SourceCatalog::default()) {
            Some(Delivery::Interpreted(intake)) => *intake,
            other => panic!("not interpreted: {other:?}"),
        }
    }

    fn remote_edge(source: &str, extra: Value) -> Value {
        let mut edge = json!({
            "v": 1,
            "source": source,
            "host": {"id": "devbox", "name": "Dev Box"},
            "cwd": "/home/dev/project",
            "stdin_sha256": "abc123",
        });
        for (k, v) in extra.as_object().unwrap() {
            edge[k] = v.clone();
        }
        edge
    }

    #[test]
    fn remote_claude_hook_is_claude_on_its_host() {
        let intake = interpret(json!({
            "hook_event_name": "Stop",
            "session_id": "sess-1",
            "cwd": "/home/dev/project",
            "_edge": remote_edge("claude", json!({"tty": "/dev/pts/3"})),
        }));
        let p = intake.payload();
        assert_eq!(p["_source"], "claude");
        assert!(p.get("_via_plugin").is_none());
        assert_eq!(p["_remote_host_id"], "devbox");
        assert_eq!(p["_remote_host_name"], "Dev Box");
        assert_eq!(p["_tty"], "/dev/pts/3");
        assert!(p.get("_edge").is_none(), "facts are not part of the event");
        assert!(p.get("_ppid").is_none() && p.get("_hook_ppid").is_none());
        assert!(p.get("_cursor_payload_digest").is_none());
        assert!(!intake.waits_for_answer);
    }

    /// #377 over Remote-SSH: Cursor runs the remote Claude Code hook.
    #[test]
    fn cursor_running_the_remote_claude_hook_is_cursor_and_never_held() {
        let intake = interpret(json!({
            "hook_event_name": "PermissionRequest",
            "session_id": "conv-1",
            "cursor_version": "3.25.9",
            "_edge": remote_edge("claude", json!({"waits": true})),
        }));
        assert_eq!(intake.payload()["_source"], "cursor");
        assert_eq!(intake.payload()["_cursor_payload_digest"], "abc123");
        assert!(!intake.waits_for_answer);
        assert_eq!(intake.stdout_for_answer(b"{\"x\":1}"), None);
    }

    #[test]
    fn a_hook_its_edge_does_not_wait_on_is_never_held() {
        let event = |waits: Value| {
            interpret(json!({
                "hook_event_name": "PermissionRequest",
                "session_id": "s",
                "_edge": remote_edge("codex", json!({"waits": waits})),
            }))
            .waits_for_answer
        };
        assert!(!event(json!(false)));
        assert!(event(json!(true)));
    }

    #[test]
    fn remote_gemini_answer_is_put_as_gemini_reads_it() {
        let intake = interpret(json!({
            "hook_event_name": "BeforeTool",
            "session_id": "g",
            "_edge": remote_edge("gemini", json!({"waits": true})),
        }));
        let answer = br#"{"hookSpecificOutput":{"decision":{"behavior":"allow"}}}"#;
        assert_eq!(
            intake.stdout_for_answer(answer).unwrap(),
            br#"{"decision":"allow"}"#
        );
    }

    #[test]
    fn remote_hermes_never_points_at_the_islands_machine() {
        let intake = interpret(json!({
            "hook_event_name": "pre_llm_call",
            "session_id": "h",
            "_edge": remote_edge("hermes", json!({"env": {"HERMES_HOME": "~/.hermes", "PATH": "/x"}})),
        }));
        assert!(intake.payload().get("_hermes_home").is_none());
    }

    #[test]
    fn a_blank_cwd_is_no_cwd_and_the_session_is_never_made_up() {
        let intake = interpret(json!({
            "hook_event_name": "Stop",
            "session_id": "s",
            "cwd": "  ",
            "_edge": remote_edge("codex", json!({})),
        }));
        assert_eq!(intake.payload()["cwd"], "/home/dev/project");

        let payload = json!({"hook_event_name": "Stop", "_edge": remote_edge("codex", json!({}))});
        let delivered = delivery(payload.as_object().unwrap(), &SourceCatalog::default());
        assert!(matches!(delivered, Some(Delivery::Dropped)));
    }

    #[test]
    fn skip_and_grok_imports_are_dropped_and_plain_payloads_not_read() {
        let skip = json!({
            "session_id": "s",
            "_edge": remote_edge("codex", json!({"env": {"MORROW_SKIP": "1"}})),
        });
        let grok = json!({
            "session_id": "s",
            "_edge": remote_edge("claude", json!({"env": {"GROK_SESSION_ID": "g"}})),
        });
        for payload in [skip, grok] {
            let delivered = delivery(payload.as_object().unwrap(), &SourceCatalog::default());
            assert!(matches!(delivered, Some(Delivery::Dropped)));
        }
        let plain = json!({"session_id": "s"});
        assert!(delivery(plain.as_object().unwrap(), &SourceCatalog::default()).is_none());
        assert!(!may_carry_facts(br#"{"session_id":"s"}"#));
        assert!(may_carry_facts(br#"{"_edge":{}}"#));
    }

    #[test]
    fn an_edge_with_a_malformed_host_is_still_another_machine() {
        let intake = interpret(json!({
            "hook_event_name": "Stop",
            "session_id": "s",
            "_ppid": 42,
            "_edge": {"v": 1, "source": "codex", "host": "devbox"},
        }));
        assert!(intake.payload().get("_ppid").is_none());
        assert!(intake.payload().get("_remote_host_id").is_none());
    }
}
