//! Events of a session's subagents: `handleSubagentEvent` and the helpers
//! around it (`ensureSubagent`, `recordSubagentModel`,
//! `recordFoldedSubsession`, `shouldReopenSubagentOnPrompt`,
//! `shouldSurfaceCursorSubagentChat`) in
//! `macos/Sources/MorrowCore/SessionSnapshot.swift`.

use super::hook_event::HookEvent;
use super::metadata::is_codex_subagent_event;
use super::session_snapshot::{
    AgentStatus, ChatMessage, SessionSnapshot, SubagentState, SubsessionKind,
};
use super::subsession::{folded_kind, is_cursor_family_source};
use super::text::{first_string_from_event, has_question, subagent_type};
use super::{ReduceContext, SideEffect, json};
use crate::intake::normalized_supported_source;

fn is_waiting(status: AgentStatus) -> bool {
    matches!(
        status,
        AgentStatus::WaitingApproval | AgentStatus::WaitingQuestion
    )
}

/// `shouldReopenSubagentOnPrompt`: a folded child's prompt, or a Cursor
/// Task's, starts a new turn of a closed agent id.
fn should_reopen_subagent_on_prompt(
    event: &HookEvent,
    s: &SessionSnapshot,
    ctx: &ReduceContext,
) -> bool {
    if folded_kind(event).is_some() {
        return true;
    }
    let source = normalized_supported_source(json::string(event.raw("_source")), ctx.sources)
        .or_else(|| normalized_supported_source(json::string(event.raw("source")), ctx.sources))
        .unwrap_or_else(|| s.source.clone());
    source == "cursor" || source == "cursor-cli"
}

/// `shouldSurfaceCursorSubagentChat`: a folded Cursor Task's prompt and
/// reply show on the parent card; a Codex or plugin child's never do.
fn should_surface_cursor_subagent_chat(
    event: &HookEvent,
    s: &SessionSnapshot,
    ctx: &ReduceContext,
) -> bool {
    if folded_kind(event) == Some(SubsessionKind::CursorTask) {
        return true;
    }
    let source = json::string(event.raw("_source"))
        .or_else(|| json::string(event.raw("source")))
        .unwrap_or(&s.source);
    is_cursor_family_source(Some(source), ctx.sources)
}

/// `ensureSubagent`: the agent's row, made if missing; `false` when the id
/// is closed (only SubagentStart/SessionStart, or a Cursor prompt, reopen it).
fn ensure_subagent(
    s: &mut SessionSnapshot,
    agent_id: &str,
    event: &HookEvent,
    ctx: &ReduceContext,
) -> bool {
    if s.has_closed_subagent_id(agent_id) {
        return false;
    }
    if !s.subagents.contains_key(agent_id) {
        let state = SubagentState::new(agent_id, &subagent_type(event), (ctx.clock)());
        s.subagents.insert(agent_id.to_owned(), state);
    }
    true
}

/// `recordSubagentModel`: a child's own model on its row.
pub fn record_subagent_model(s: &mut SessionSnapshot, agent_id: &str, event: &HookEvent) {
    let Some(sub) = s.subagents.get_mut(agent_id) else {
        return;
    };
    if let Some(model) = json::string(event.raw("model"))
        .map(str::trim)
        .filter(|m| !m.is_empty())
    {
        sub.model = Some(model.to_owned());
    }
}

/// `recordFoldedSubsession`: mark the row of a folded child session.
pub fn record_folded_subsession(s: &mut SessionSnapshot, agent_id: &str, event: &HookEvent) {
    let Some(kind) = folded_kind(event) else {
        return;
    };
    if let Some(sub) = s.subagents.get_mut(agent_id) {
        sub.subsession_kind = Some(kind);
    }
}

/// `handleSubagentEvent`: `true` when the event was the subagent's alone.
pub fn handle_subagent_event(
    s: &mut SessionSnapshot,
    session_id: &str,
    agent_id: &str,
    event_name: &str,
    event: &HookEvent,
    ctx: &ReduceContext,
    effects: &mut Vec<SideEffect>,
) -> bool {
    let now = || (ctx.clock)();
    let set_active = |effects: &mut Vec<SideEffect>| {
        effects.push(SideEffect::SetActiveSession {
            session_id: Some(session_id.to_owned()),
        });
    };
    match event_name {
        "SubagentStart" | "SessionStart" => {
            let agent_type = subagent_type(event);
            s.clear_closed_subagent_id(agent_id);
            s.subagents.insert(
                agent_id.to_owned(),
                SubagentState::new(agent_id, &agent_type, now()),
            );
            if matches!(s.status, AgentStatus::Idle | AgentStatus::Processing) {
                s.status = AgentStatus::Running;
                s.set_current_tool(Some("Agent".to_owned()));
                s.tool_description = Some(agent_type);
            }
            s.last_activity = now();
            set_active(effects);
            true
        }
        "UserPromptSubmit" => {
            // Cursor has no SessionStart for Tasks: a prompt relaunches one.
            if should_reopen_subagent_on_prompt(event, s, ctx) {
                s.clear_closed_subagent_id(agent_id);
            }
            if !ensure_subagent(s, agent_id, event, ctx) {
                return true;
            }
            if let Some(sub) = s.subagents.get_mut(agent_id) {
                sub.status = AgentStatus::Processing;
                sub.last_activity = now();
            }
            if should_surface_cursor_subagent_chat(event, s, ctx) {
                if let Some(prompt) =
                    first_string_from_event(event, &["prompt", "user_prompt", "userPrompt"], true)
                {
                    s.last_user_prompt = Some(prompt.clone());
                    if s.last_message_is_user() {
                        s.recent_messages.pop();
                    }
                    s.add_recent_message(ChatMessage::new(true, &prompt));
                }
            }
            if !is_waiting(s.status) {
                let agent_type = s.subagents.get(agent_id).map(|sub| sub.agent_type.clone());
                s.status = AgentStatus::Running;
                s.set_current_tool(Some("Agent".to_owned()));
                s.tool_description = agent_type;
            }
            s.last_activity = now();
            set_active(effects);
            true
        }
        "SubagentStop" | "Stop" | "SessionEnd" => {
            s.subagents.remove(agent_id);
            // Codex reuses a child's thread id for its follow-up turns: no
            // tombstone for its per-turn SubagentStop.
            if !(event_name == "SubagentStop" && is_codex_subagent_event(event, Some(s), ctx)) {
                s.record_closed_subagent_id(agent_id);
            }
            if s.subagents.is_empty()
                && s.status == AgentStatus::Running
                && s.current_tool() == Some("Agent")
            {
                s.status = AgentStatus::Processing;
                s.set_current_tool(None);
                s.tool_description = None;
            }
            s.last_activity = now();
            true
        }
        "PreToolUse" => {
            if !ensure_subagent(s, agent_id, event, ctx) {
                return true;
            }
            if let Some(sub) = s.subagents.get_mut(agent_id) {
                sub.status = AgentStatus::Running;
                sub.set_current_tool(event.activity_label());
                sub.current_tool_use_id = event.tool_use_id.clone();
                sub.tool_description = event.tool_description();
                sub.last_activity = now();
            }
            if !is_waiting(s.status) {
                s.status = AgentStatus::Running;
            }
            s.last_activity = now();
            true
        }
        "PostToolUse" | "PostToolUseFailure" => {
            let success = event_name == "PostToolUse";
            if !ensure_subagent(s, agent_id, event, ctx) {
                return true;
            }
            let Some(sub) = s.subagents.get(agent_id) else {
                return true;
            };
            let agent_type = sub.agent_type.clone();
            if sub.finishes_another_tool_use(event) {
                // An earlier tool's step, overtaken by the next tool's start.
                if let Some(tool) = event.activity_label() {
                    let description = event.tool_description();
                    s.record_tool(
                        &tool,
                        description.as_deref(),
                        success,
                        Some(&agent_type),
                        ctx.max_history,
                        now(),
                    );
                }
                if success {
                    if let Some(sub) = s.subagents.get_mut(agent_id) {
                        sub.last_activity = now();
                    }
                }
                s.last_activity = now();
                return true;
            }
            if let Some(tool) = sub.current_tool().map(str::to_owned) {
                let description = sub.tool_description.clone();
                s.record_tool(
                    &tool,
                    description.as_deref(),
                    success,
                    Some(&agent_type),
                    ctx.max_history,
                    now(),
                );
            }
            if let Some(sub) = s.subagents.get_mut(agent_id) {
                sub.status = AgentStatus::Processing;
                sub.set_current_tool(None);
                sub.tool_description = None;
                if success {
                    sub.last_activity = now();
                }
            }
            s.last_activity = now();
            true
        }
        "AfterAgentResponse" => {
            if !ensure_subagent(s, agent_id, event, ctx) {
                return true;
            }
            // A folded Cursor Task's reply shows on the parent card, but
            // never completes the parent's turn.
            if should_surface_cursor_subagent_chat(event, s, ctx) {
                if let Some(text) = first_string_from_event(event, &["text", "message"], true)
                    .filter(|t| !t.is_empty())
                {
                    s.last_assistant_message = Some(text.clone());
                    s.add_recent_message(ChatMessage::new(false, &text));
                }
            }
            if let Some(sub) = s.subagents.get_mut(agent_id) {
                sub.status = AgentStatus::Processing;
                sub.last_activity = now();
            }
            s.last_activity = now();
            if !is_waiting(s.status) && s.status != AgentStatus::Running {
                s.status = AgentStatus::Processing;
            }
            true
        }
        "Notification" => {
            // A folded Task's question stays on the parent card.
            if !ensure_subagent(s, agent_id, event, ctx) {
                return true;
            }
            if let Some(sub) = s.subagents.get_mut(agent_id) {
                sub.last_activity = now();
            }
            s.last_activity = now();
            let notification = first_string_from_event(
                event,
                &["message", "text", "summary", "status", "detail"],
                true,
            );
            if let Some(message) = notification.filter(|m| !m.trim().is_empty()) {
                s.tool_description = Some(message.clone());
                if let Some(sub) = s.subagents.get_mut(agent_id) {
                    sub.tool_description = Some(message);
                }
            }
            if has_question(event) {
                s.status = AgentStatus::WaitingQuestion;
                if let Some(sub) = s.subagents.get_mut(agent_id) {
                    sub.status = AgentStatus::WaitingQuestion;
                }
                set_active(effects);
            } else if !is_waiting(s.status) && s.status != AgentStatus::Running {
                s.status = AgentStatus::Processing;
                if let Some(sub) = s.subagents.get_mut(agent_id) {
                    sub.status = AgentStatus::Processing;
                }
            }
            true
        }
        "PreCompact" | "PostCompact" => {
            // A subagent compacts its own context, not the parent's.
            if let Some(sub) = s.subagents.get_mut(agent_id) {
                sub.last_activity = now();
                s.last_activity = now();
            }
            true
        }
        _ => false,
    }
}
