//! What a routed hook says about its card's family: `SubsessionRouter`'s
//! reading half (`macos/Sources/MorrowCore/SubsessionRouter.swift`),
//! `DeclaredSubsession.parentSessionId`, and `CursorSessionFolding` /
//! `CursorSubsessionRouter` (`CursorSessionFolding.swift`).

use super::hook_event::{HookEvent, card_session_id};
use super::json;
use super::session_snapshot::SubsessionKind;
use crate::JsonObject;
use crate::intake::{SourceCatalog, normalized_supported_source};

/// `SubsessionRouter.linkedParentKey`.
const LINKED_PARENT_KEY: &str = "_subsession_parent";
/// `SubsessionRouter.foldedKey`.
const FOLDED_KEY: &str = "_subsession_folded";
/// `DeclaredSubsession.parentKey`.
const DECLARED_PARENT_KEY: &str = "_parent_session_id";

/// `SubsessionRouter.parentCardId(in:)`: the card the hook's session works
/// for, as the router linked it or the child declared it.
pub fn parent_card_id(raw: &JsonObject) -> Option<String> {
    json::trimmed(raw.get(LINKED_PARENT_KEY))
        .map(str::to_owned)
        .or_else(|| declared_parent_session_id(raw))
}

/// `DeclaredSubsession.parentSessionId(in:)`, filed like `session_id`.
fn declared_parent_session_id(raw: &JsonObject) -> Option<String> {
    let parent = json::trimmed(raw.get(DECLARED_PARENT_KEY))?;
    if Some(parent) == session_id(raw) {
        return None;
    }
    Some(card_session_id(parent, raw))
}

/// `SubsessionRouter.sessionId(in:)`.
fn session_id(raw: &JsonObject) -> Option<&str> {
    json::trimmed(raw.get("session_id")).or_else(|| json::trimmed(raw.get("sessionId")))
}

/// `SubsessionRouter.foldedKind(of:)`.
pub fn folded_kind(event: &HookEvent) -> Option<SubsessionKind> {
    json::string(event.raw(FOLDED_KEY)).and_then(SubsessionKind::from_raw_value)
}

/// `SubsessionRouter.remoteHostId(in:)`: `None` for this machine.
pub fn remote_host_id(raw: &JsonObject) -> Option<&str> {
    json::string(raw.get("_remote_host_id")).filter(|h| !h.trim().is_empty())
}

/// `CursorSessionFolding.isCursorAgentTranscriptPath`.
pub fn is_cursor_agent_transcript_path(path: Option<&str>) -> bool {
    let Some(path) = path.map(str::trim).filter(|p| !p.is_empty()) else {
        return false;
    };
    path.contains("/agent-transcripts/")
        && (path.contains("/.cursor/") || path.contains("/cursor/projects/"))
}

/// `CursorSessionFolding.parentConversationId(fromTranscriptPath:)`: the
/// UUID directory right under `agent-transcripts/`.
fn parent_conversation_id(path: &str) -> Option<&str> {
    let parts: Vec<&str> = path.trim().split('/').filter(|p| !p.is_empty()).collect();
    let index = parts.iter().rposition(|p| *p == "agent-transcripts")?;
    let candidate = *parts.get(index + 1)?;
    is_uuid(candidate).then_some(candidate)
}

/// `^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`.
fn is_uuid(s: &str) -> bool {
    let groups: Vec<&str> = s.split('-').collect();
    groups.len() == 5
        && groups
            .iter()
            .zip([8, 4, 4, 4, 12])
            .all(|(g, n)| g.len() == n && g.bytes().all(|b| b.is_ascii_hexdigit()))
}

/// `CursorSessionFolding.foldTarget(childSessionId:transcriptPath:)`: the
/// chat a Task of it runs for, when the transcript names another one.
pub fn fold_target(child_session_id: &str, transcript_path: Option<&str>) -> Option<String> {
    let child = child_session_id.trim();
    if child.is_empty() {
        return None;
    }
    let parent = parent_conversation_id(transcript_path?)?;
    (parent != child).then(|| parent.to_owned())
}

/// `CursorSubsessionRouter.isCursorFamilySource`.
pub fn is_cursor_family_source(source: Option<&str>, sources: &SourceCatalog) -> bool {
    matches!(
        normalized_supported_source(source, sources).as_deref(),
        Some("cursor" | "cursor-cli")
    )
}

/// `CursorSubsessionRouter.isLikelyCursorTaskCard`.
pub fn is_likely_cursor_task_card(
    session_id: &str,
    provider_session_id: Option<&str>,
    transcript_path: Option<&str>,
) -> bool {
    fold_target(session_id, transcript_path).is_some()
        || provider_session_id.is_some_and(|provider| {
            provider != session_id && fold_target(provider, transcript_path).is_some()
        })
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    const PARENT: &str = "e1247fd5-d9a0-48ef-8457-0304606b1833";

    #[test]
    fn a_task_folds_onto_the_chat_its_transcript_names() {
        let path = format!("/h/.cursor/projects/p/agent-transcripts/{PARENT}/subagents/c.jsonl");
        assert!(is_cursor_agent_transcript_path(Some(&path)));
        assert_eq!(fold_target("child", Some(&path)).as_deref(), Some(PARENT));
        assert_eq!(fold_target(PARENT, Some(&path)), None);
        assert_eq!(
            fold_target("child", Some("/h/agent-transcripts/not-a-uuid/x")),
            None
        );
    }

    #[test]
    fn a_declared_parent_is_filed_like_the_session() {
        let raw = json!({"session_id": "c", "_parent_session_id": "p", "_remote_host_id": "h"});
        assert_eq!(
            parent_card_id(raw.as_object().unwrap()).as_deref(),
            Some("remote:h:p")
        );
        let own = json!({"session_id": "c", "_parent_session_id": " c "});
        assert_eq!(parent_card_id(own.as_object().unwrap()), None);
    }
}
