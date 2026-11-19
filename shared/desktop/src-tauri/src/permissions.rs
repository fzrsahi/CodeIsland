//! Permission requests the panel holds until the user answers (plan §3):
//! one card per held hook, answered with the bytes the macOS island sends
//! Claude Code (`AppState.approvePermission` / `denyPermission`), which the
//! bridge prints verbatim.

use std::collections::BTreeMap;
use std::sync::mpsc::Sender;

use morrow_protocol::HookPayload;
use serde::{Deserialize, Serialize};
use serde_json::Value;

/// The longest tool summary a card shows, in characters.
const SUMMARY_CHARS: usize = 120;

/// Whether the island holds `payload` for an answer. `TODO(#93)`: HookIntake
/// in morrow-core decides (aliases, questions); E2E-1 serves Claude Code's
/// `PermissionRequest`. A hook Cursor ran is never held: Cursor reads its
/// stdout against its own schema (docs/hook-edge-protocol.md).
pub fn waits(payload: &HookPayload) -> bool {
    let cursor = payload
        .get("cursor_version")
        .and_then(Value::as_str)
        .is_some_and(|v| !v.trim().is_empty());
    payload.hook_event_name() == "PermissionRequest" && !cursor
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Decision {
    Allow,
    Deny,
}

impl Decision {
    /// The reply, byte for byte as Swift writes it.
    pub fn reply(self) -> &'static [u8] {
        match self {
            Self::Allow => {
                br#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#
            }
            Self::Deny => {
                br#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}"#
            }
        }
    }
}

/// What the panel shows of one held request (`Card` in `src/App.svelte`).
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Card {
    pub id: u64,
    pub session_id: String,
    pub source: String,
    pub tool_name: String,
    /// One line of the tool input: the command, the file, or its JSON.
    pub summary: String,
}

#[derive(Debug, Default)]
pub struct Permissions {
    next_id: u64,
    /// Oldest first; each with the way to its hook's connection.
    held: BTreeMap<u64, (Card, Sender<Decision>)>,
}

impl Permissions {
    /// Holds `payload` until [`Self::answer`] sends the decision to
    /// `answer`, or [`Self::drop_request`]. Returns the card's id.
    pub fn hold(&mut self, payload: &HookPayload, answer: Sender<Decision>) -> u64 {
        self.next_id += 1;
        let id = self.next_id;
        let text = |key| payload.get(key).and_then(Value::as_str).unwrap_or_default();
        let card = Card {
            id,
            session_id: payload.session_id().to_owned(),
            source: payload.source().unwrap_or("claude").to_owned(),
            tool_name: text("tool_name").to_owned(),
            summary: summary(payload.get("tool_input")),
        };
        self.held.insert(id, (card, answer));
        id
    }

    /// The user's answer: sent to the request's hook, and its card gone.
    /// False for a request no longer held (answered, or its hook gone).
    pub fn answer(&mut self, id: u64, decision: Decision) -> bool {
        match self.held.remove(&id) {
            Some((_, answer)) => answer.send(decision).is_ok(),
            None => false,
        }
    }

    /// Its hook is gone: the card goes, unanswered.
    pub fn drop_request(&mut self, id: u64) -> bool {
        self.held.remove(&id).is_some()
    }

    /// Its session ended: every pending card for `session_id` goes, unanswered.
    pub fn drop_session(&mut self, session_id: &str) {
        self.held
            .retain(|_, (card, _)| card.session_id != session_id);
    }

    /// Oldest first.
    pub fn cards(&self) -> Vec<Card> {
        self.held.values().map(|(card, _)| card.clone()).collect()
    }
}

/// The first of `command`, `file_path`, `path`, `url`, `pattern` that is a
/// string, else the input's JSON; one line, at most [`SUMMARY_CHARS`].
fn summary(input: Option<&Value>) -> String {
    let Some(input) = input else {
        return String::new();
    };
    let text = ["command", "file_path", "path", "url", "pattern"]
        .iter()
        .find_map(|key| input.get(key).and_then(Value::as_str))
        .map_or_else(|| input.to_string(), str::to_owned);
    let line = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if line.chars().count() <= SUMMARY_CHARS {
        return line;
    }
    let mut cut: String = line.chars().take(SUMMARY_CHARS - 1).collect();
    cut.push('…');
    cut
}

#[cfg(test)]
mod tests {
    use super::*;
    use morrow_protocol::decode_payload;
    use std::sync::mpsc::{self, TryRecvError};

    fn hook(json: &str) -> HookPayload {
        decode_payload(json.as_bytes()).unwrap()
    }

    const BASH: &str = r#"{"session_id":"s1","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf build\n  && make"}}"#;

    #[test]
    fn only_a_permission_request_outside_cursor_waits() {
        assert!(waits(&hook(BASH)));
        assert!(!waits(&hook(
            r#"{"session_id":"s","hook_event_name":"PreToolUse"}"#
        )));
        assert!(!waits(&hook(
            r#"{"session_id":"s","hook_event_name":"PermissionRequest","cursor_version":"1.2"}"#
        )));
        assert!(waits(&hook(
            r#"{"session_id":"s","hook_event_name":"PermissionRequest","cursor_version":" "}"#
        )));
    }

    #[test]
    fn a_held_request_is_a_card_until_approved() {
        let mut permissions = Permissions::default();
        let (tx, rx) = mpsc::channel();
        let id = permissions.hold(&hook(BASH), tx);
        assert_eq!(
            permissions.cards(),
            vec![Card {
                id,
                session_id: "s1".into(),
                source: "claude".into(),
                tool_name: "Bash".into(),
                summary: "rm -rf build && make".into(),
            }]
        );
        assert_eq!(rx.try_recv(), Err(TryRecvError::Empty));

        assert!(permissions.answer(id, Decision::Allow));
        assert_eq!(rx.try_recv(), Ok(Decision::Allow));
        assert!(permissions.cards().is_empty());
        assert!(!permissions.answer(id, Decision::Deny), "answered once");
    }

    #[test]
    fn deny_reaches_only_its_own_request() {
        let mut permissions = Permissions::default();
        let (tx1, rx1) = mpsc::channel();
        let (tx2, rx2) = mpsc::channel();
        let first = permissions.hold(&hook(BASH), tx1);
        let second = permissions.hold(&hook(BASH), tx2);
        assert_ne!(first, second);

        assert!(permissions.answer(second, Decision::Deny));
        assert_eq!(rx2.try_recv(), Ok(Decision::Deny));
        assert_eq!(rx1.try_recv(), Err(TryRecvError::Empty));
        let ids: Vec<u64> = permissions.cards().iter().map(|c| c.id).collect();
        assert_eq!(ids, [first]);
    }

    #[test]
    fn a_gone_hook_drops_its_card_unanswered() {
        let mut permissions = Permissions::default();
        let (tx, rx) = mpsc::channel();
        let id = permissions.hold(&hook(BASH), tx);
        assert!(permissions.drop_request(id));
        assert!(permissions.cards().is_empty());
        assert_eq!(rx.try_recv(), Err(TryRecvError::Disconnected));
        assert!(!permissions.answer(id, Decision::Allow));
        assert!(!permissions.drop_request(id));
    }

    #[test]
    fn dropping_a_session_drops_only_its_cards() {
        let mut permissions = Permissions::default();
        let (tx1, rx1) = mpsc::channel();
        let (tx2, rx2) = mpsc::channel();
        let other =
            hook(r#"{"session_id":"s2","hook_event_name":"PermissionRequest","tool_name":"Bash"}"#);
        permissions.hold(&hook(BASH), tx1);
        let kept = permissions.hold(&other, tx2);

        permissions.drop_session("s1");
        assert_eq!(rx1.try_recv(), Err(TryRecvError::Disconnected));
        assert_eq!(rx2.try_recv(), Err(TryRecvError::Empty));
        assert_eq!(
            permissions.cards().iter().map(|c| c.id).collect::<Vec<_>>(),
            [kept]
        );
    }

    /// The replies as the macOS island writes them, read from its source:
    /// a change on either side fails here. `TODO(#86)`: the path moves with
    /// the monorepo layout.
    #[test]
    fn replies_are_the_macos_islands_bytes() {
        let swift = include_str!("../../../../Sources/Morrow/AppState.swift");
        for decision in [Decision::Allow, Decision::Deny] {
            let reply = std::str::from_utf8(decision.reply()).unwrap();
            assert!(swift.contains(&format!("#\"{reply}\"#")), "{reply}");
        }
        assert_eq!(
            serde_json::from_str::<Decision>(r#""deny""#).unwrap(),
            Decision::Deny
        );
    }

    #[test]
    fn summaries_are_one_short_line() {
        let input = |json: &str| serde_json::from_str::<Value>(json).unwrap();
        assert_eq!(summary(None), "");
        assert_eq!(
            summary(Some(&input(r#"{"file_path":"/a/b.rs","content":"x"}"#))),
            "/a/b.rs"
        );
        assert_eq!(
            summary(Some(&input(r#"{"query":"q"}"#))),
            r#"{"query":"q"}"#
        );
        let long = summary(Some(&input(&format!(
            r#"{{"command":"{}"}}"#,
            "x".repeat(300)
        ))));
        assert_eq!(long.chars().count(), SUMMARY_CHARS);
        assert!(long.ends_with('…'));
    }
}
