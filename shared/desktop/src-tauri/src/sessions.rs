//! The trivial reduction of Phase 1 (docs/plan-windows-linux.md §7): one
//! row per session id, overwritten by its latest hook. `TODO(#93)`: replaced
//! by morrow-core's `reduce`.

use std::collections::HashMap;

use morrow_protocol::HookPayload;
use serde::Serialize;

/// What the panel shows of one session.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Session {
    pub session_id: String,
    /// `_source`, or `claude` without one (Swift `SessionSnapshot.source`).
    pub source: String,
    /// `hook_event_name` of the latest hook.
    pub last_event: String,
    /// The last path component of `cwd`, or empty.
    pub cwd_name: String,
    /// Milliseconds since the Unix epoch, when the latest hook arrived.
    pub updated_at: u64,
}

/// What the frontend receives (`Snapshot` in `src/App.svelte`).
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Snapshot {
    /// Newest first; ties by session id, so the order is stable.
    pub sessions: Vec<Session>,
}

#[derive(Debug, Default)]
pub struct Sessions {
    by_id: HashMap<String, Session>,
}

impl Sessions {
    /// Records `payload` as its session's latest hook, arrived at `now_ms`.
    pub fn apply(&mut self, payload: &HookPayload, now_ms: u64) {
        let cwd = payload
            .get("cwd")
            .and_then(|v| v.as_str())
            .unwrap_or_default();
        let session = Session {
            session_id: payload.session_id().to_owned(),
            source: payload.source().unwrap_or("claude").to_owned(),
            last_event: payload.hook_event_name().to_owned(),
            cwd_name: basename(cwd).to_owned(),
            updated_at: now_ms,
        };
        self.by_id.insert(session.session_id.clone(), session);
    }

    pub fn snapshot(&self) -> Snapshot {
        let mut sessions: Vec<Session> = self.by_id.values().cloned().collect();
        sessions.sort_by(|a, b| {
            b.updated_at
                .cmp(&a.updated_at)
                .then_with(|| a.session_id.cmp(&b.session_id))
        });
        Snapshot { sessions }
    }
}

fn basename(path: &str) -> &str {
    path.trim_end_matches('/')
        .rsplit('/')
        .next()
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use morrow_protocol::decode_payload;

    fn hook(json: &str) -> HookPayload {
        decode_payload(json.as_bytes()).unwrap()
    }

    #[test]
    fn the_latest_hook_of_a_session_replaces_its_row() {
        let mut sessions = Sessions::default();
        sessions.apply(
            &hook(r#"{"session_id":"a","hook_event_name":"SessionStart","cwd":"/home/u/proj/"}"#),
            10,
        );
        sessions.apply(
            &hook(r#"{"session_id":"a","hook_event_name":"PreToolUse","_source":"codex"}"#),
            20,
        );
        assert_eq!(
            sessions.snapshot().sessions,
            vec![Session {
                session_id: "a".into(),
                source: "codex".into(),
                last_event: "PreToolUse".into(),
                cwd_name: String::new(),
                updated_at: 20,
            }]
        );
    }

    #[test]
    fn sessions_come_newest_first_and_default_to_claude() {
        let mut sessions = Sessions::default();
        sessions.apply(
            &hook(r#"{"session_id":"old","hook_event_name":"Stop","cwd":"/srv/api"}"#),
            1,
        );
        sessions.apply(
            &hook(r#"{"session_id":"new","hook_event_name":"PreToolUse","cwd":"/home/u/web/"}"#),
            2,
        );
        let snapshot = sessions.snapshot();
        let rows: Vec<_> = snapshot
            .sessions
            .iter()
            .map(|s| {
                (
                    s.session_id.as_str(),
                    s.source.as_str(),
                    s.cwd_name.as_str(),
                )
            })
            .collect();
        assert_eq!(rows, [("new", "claude", "web"), ("old", "claude", "api")]);
    }

    #[test]
    fn basename_of_odd_paths() {
        assert_eq!(basename(""), "");
        assert_eq!(basename("/"), "");
        assert_eq!(basename("proj"), "proj");
        assert_eq!(basename("/a/b//"), "b");
    }
}
