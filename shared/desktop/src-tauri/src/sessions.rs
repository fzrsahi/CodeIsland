//! Session reduction backed by `morrow-core::reduce` (`reduceHookEvent`),
//! projecting `SessionSnapshot` into the panel's `Session` rows.

use std::collections::HashMap;

use morrow_core::intake::SourceCatalog;
use morrow_core::reduce::{HookEvent, ReduceContext, SideEffect, Timestamp, reduce_hook_event};
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

#[derive(Debug, Default)]
pub struct Sessions {
    inner: morrow_core::reduce::Sessions,
    last_events: HashMap<String, String>,
    sources: SourceCatalog,
    home_directory: String,
}

impl Sessions {
    /// Creates a session store whose reducer ignores `home_directory` as a
    /// bare project `cwd`.
    pub fn with_home(home_directory: impl Into<String>) -> Self {
        Self {
            home_directory: home_directory.into(),
            ..Self::default()
        }
    }

    /// Reduces `payload` at `now_ms`, applying `RemoveSession` effects locally
    /// and returning all emitted `SideEffect`s for the shell.
    pub fn apply(&mut self, payload: &HookPayload, now_ms: u64) -> Vec<SideEffect> {
        let Some(event) = HookEvent::new(payload.as_object().clone(), &self.sources) else {
            return Vec::new();
        };
        let clock = || Timestamp(now_ms as f64 / 1000.0);
        let ctx = ReduceContext {
            clock: &clock,
            sources: &self.sources,
            home_directory: &self.home_directory,
            max_history: 50,
            reply_complete_placeholder: "Reply complete",
        };
        let reduction = reduce_hook_event(&mut self.inner, &event, &ctx);
        for effect in &reduction.effects {
            if let SideEffect::RemoveSession { session_id } = effect {
                self.inner.remove(session_id);
                self.last_events.remove(session_id);
            }
        }
        let card_id = event.session_id.as_deref().unwrap_or("default");
        if self.inner.contains_key(card_id) {
            self.last_events
                .insert(card_id.to_owned(), event.event_name);
        }
        reduction.effects
    }

    /// Newest first; ties by session id, so the order is stable.
    pub fn snapshot(&self) -> Vec<Session> {
        let mut sessions: Vec<Session> = self
            .inner
            .iter()
            .map(|(session_id, snap)| Session {
                session_id: session_id.clone(),
                source: snap.source.clone(),
                last_event: self
                    .last_events
                    .get(session_id)
                    .cloned()
                    .unwrap_or_default(),
                cwd_name: snap
                    .cwd
                    .as_deref()
                    .map(basename)
                    .unwrap_or_default()
                    .to_owned(),
                updated_at: (snap.last_activity.0 * 1000.0).round().max(0.0) as u64,
            })
            .collect();
        sessions.sort_by(|a, b| {
            b.updated_at
                .cmp(&a.updated_at)
                .then_with(|| a.session_id.cmp(&b.session_id))
        });
        sessions
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
    use morrow_core::reduce::AgentStatus;
    use morrow_protocol::decode_payload;

    fn hook(json: &str) -> HookPayload {
        decode_payload(json.as_bytes()).unwrap()
    }

    #[test]
    fn the_latest_hook_updates_the_session_and_preserves_prior_cwd() {
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
            sessions.snapshot(),
            vec![Session {
                session_id: "a".into(),
                source: "codex".into(),
                last_event: "PreToolUse".into(),
                cwd_name: "proj".into(),
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
    fn session_end_emits_remove_session_and_clears_the_card() {
        let mut sessions = Sessions::default();
        sessions.apply(
            &hook(r#"{"session_id":"a","hook_event_name":"SessionStart","cwd":"/srv/api"}"#),
            10,
        );
        let effects = sessions.apply(
            &hook(r#"{"session_id":"a","hook_event_name":"SessionEnd"}"#),
            20,
        );
        assert_eq!(
            effects,
            vec![SideEffect::RemoveSession {
                session_id: "a".into()
            }]
        );
        assert!(sessions.snapshot().is_empty());
    }

    #[test]
    fn permission_request_preserves_project_cwd_and_normalizes_source() {
        let mut sessions = Sessions::with_home("/home/u");
        sessions.apply(
            &hook(r#"{"session_id":"a","hook_event_name":"SessionStart","cwd":"/home/u/proj"}"#),
            10,
        );
        sessions.apply(
            &hook(
                r#"{"session_id":"a","hook_event_name":"PermissionRequest","cwd":"/home/u","_source":"anti-gravity"}"#,
            ),
            20,
        );
        let snap = sessions.inner.get("a").expect("session a");
        assert_eq!(snap.status, AgentStatus::Idle);
        assert_eq!(snap.source, "antigravity");
        assert_eq!(snap.cwd.as_deref(), Some("/home/u/proj"));

        // A permission_prompt notification moves status to WaitingApproval.
        sessions.apply(
            &hook(
                r#"{"session_id":"a","hook_event_name":"Notification","notification_type":"permission_prompt"}"#,
            ),
            30,
        );
        let snap = sessions.inner.get("a").expect("session a");
        assert_eq!(snap.status, AgentStatus::WaitingApproval);
    }

    #[test]
    fn basename_of_odd_paths() {
        assert_eq!(basename(""), "");
        assert_eq!(basename("/"), "");
        assert_eq!(basename("proj"), "proj");
        assert_eq!(basename("/a/b//"), "b");
    }
}
