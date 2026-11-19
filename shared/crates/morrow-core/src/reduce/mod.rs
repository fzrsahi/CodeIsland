//! The reducer (`reduceHookEvent`, `Sources/MorrowCore/SessionSnapshot.swift`):
//! one hook event applied to the sessions, the lifecycle effects for the
//! shell to run, and what the event did ([`HookEventFacts`]) for the
//! attention policy to read.
//!
//! The clock, the custom sources and the home directory come in through
//! [`ReduceContext`]; the reducer reads no clock, configuration or file.
//! The submodules are the Swift functions and types it calls, named after
//! them.

pub mod facts;
pub mod hermes;
pub mod hook_event;
mod json;
pub mod metadata;
pub mod session_snapshot;
pub mod subagent;
pub mod subsession;
pub mod text;

pub use facts::{HookEventFacts, PushSessionError};
pub use hook_event::HookEvent;
pub use session_snapshot::{
    AgentStatus, ChatMessage, SessionSnapshot, Sessions, SubagentState, SubsessionKind, Timestamp,
    ToolHistoryEntry,
};

use crate::intake::event_normalizer::normalize;
use crate::intake::{SourceCatalog, normalized_supported_source};
use hermes::StoreSnapshot;
use metadata::{
    apply_env_metadata, apply_herdr_route, apply_hook_process_id, apply_provider_session_id,
    apply_session_title, claude_desktop_session_id, extract_metadata,
    fill_missing_parent_metadata_from_subagent_event, hook_reported_model,
};
use session_snapshot::IDE_COMPLETION_SOURCES;
use subagent::{handle_subagent_event, record_folded_subsession, record_subagent_model};
use subsession::{fold_target, parent_card_id};
use text::{first_string_from_event, has_question, normalized_cursor_chat_text, notification_kind};

/// What the reducer is handed besides the sessions and the event: what
/// Swift reads from `Date()`, `UserDefaults` and `FileManager`.
pub struct ReduceContext<'a> {
    /// Now. Every timestamp the reducer stamps comes from here.
    pub clock: &'a dyn Fn() -> Timestamp,
    /// The custom CLI sources and agent commands
    /// (`normalizedSupportedSource`'s `UserDefaults`).
    pub sources: &'a SourceCatalog,
    /// The user's home directory, which as a hook's cwd names no project
    /// (`isUnhelpfulHookCwd`).
    pub home_directory: &'a str,
    /// How many tools a session's history keeps.
    pub max_history: usize,
    /// The chat row a turn that ended without reply text gets.
    pub reply_complete_placeholder: &'a str,
}

/// `SideEffect`: what the shell does after a reduction. The reducer never
/// returns `PlaySound` or `EnqueueCompletion`; those are the attention
/// policy's intents.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SideEffect {
    PlaySound(String),
    TryMonitorSession { session_id: String },
    StopMonitor { session_id: String },
    RemoveSession { session_id: String },
    EnqueueCompletion { session_id: String },
    SetActiveSession { session_id: Option<String> },
}

/// `AttentionEffectSlots`: where in the effects the turn ended (a
/// completion goes in there) and where the event finished moving its
/// session (a sound goes in there), for putting the policy's intents back
/// in the order the reducer once returned them.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct AttentionEffectSlots {
    pub completion: Option<usize>,
    pub sound: Option<usize>,
}

/// `HookEventReduction`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HookEventReduction {
    pub effects: Vec<SideEffect>,
    pub facts: HookEventFacts,
    pub slots: AttentionEffectSlots,
}

/// `reduceHookEvent(sessions:event:maxHistory:replyCompletePlaceholder:)`:
/// applies `event` to `sessions` and reports what happened. Whether that
/// rings, pops a card or pushes is the attention policy's call.
pub fn reduce_hook_event(
    sessions: &mut Sessions,
    event: &HookEvent,
    ctx: &ReduceContext,
) -> HookEventReduction {
    let mut facts = HookEventFacts::new(event);
    let mut slots = AttentionEffectSlots::default();
    let effects = apply_hook_event(sessions, event, ctx, &mut facts, &mut slots);
    if facts.ended_turn {
        let session_id = event.session_id.as_deref().unwrap_or("default");
        facts.subagent_turn = facts::is_subagent_completion(
            event.agent_id.as_deref(),
            session_id,
            sessions.get(session_id),
            ctx.sources,
        );
    }
    HookEventReduction {
        effects,
        facts,
        slots,
    }
}

fn is_waiting(status: AgentStatus) -> bool {
    matches!(
        status,
        AgentStatus::WaitingApproval | AgentStatus::WaitingQuestion
    )
}

/// Drop the tool chrome: no tool, no description.
fn clear_tool(s: &mut SessionSnapshot) {
    s.set_current_tool(None);
    s.tool_description = None;
}

/// A prompt the card has not shown yet: it replaces a trailing prompt row.
fn record_prompt(s: &mut SessionSnapshot, prompt: &str) {
    s.last_user_prompt = Some(prompt.to_owned());
    if s.last_message_is_user() {
        s.recent_messages.pop();
    }
    s.add_recent_message(ChatMessage::new(true, prompt));
}

/// `applyHookEvent`.
fn apply_hook_event(
    sessions: &mut Sessions,
    event: &HookEvent,
    ctx: &ReduceContext,
    facts: &mut HookEventFacts,
    slots: &mut AttentionEffectSlots,
) -> Vec<SideEffect> {
    let session_id = event.session_id.as_deref().unwrap_or("default");
    let event_name = normalize(&event.event_name);
    let now = || (ctx.clock)();
    let mut effects = Vec::new();

    let s = sessions
        .entry(session_id.to_owned())
        .or_insert_with(|| SessionSnapshot::new(now()));

    // A subagent event is routed through its parent's id: only fill what
    // the parent card is missing.
    if event.agent_id.is_none() {
        extract_metadata(s, event, ctx);
    } else {
        fill_missing_parent_metadata_from_subagent_event(s, event, ctx);
    }
    let is_remote = s.is_remote();

    // Cline's hooks race in after a finished task round: drop them until
    // the next TaskStart / TaskResume.
    if s.source == "cline"
        && s.task_round_ended
        && event_name != "SessionStart"
        && event_name != "UserPromptSubmit"
    {
        return effects;
    }

    // Codex flushes queued tool hooks after an Interrupt: keep the turn
    // latched until a new prompt or session. SubagentStop still passes.
    if s.source == "codex"
        && s.interrupted
        && !matches!(
            event_name,
            "SessionStart" | "UserPromptSubmit" | "SessionEnd" | "SubagentStop" | "Interrupt"
        )
    {
        return effects;
    }

    if let Some(agent_id) = event.agent_id.as_deref() {
        // Not ported: the shared task list (`AgentTaskHookParser`,
        // `AgentTaskList.applySharedUpdates`).
        let handled = handle_subagent_event(
            s,
            session_id,
            agent_id,
            event_name,
            event,
            ctx,
            &mut effects,
        );
        record_subagent_model(s, agent_id, event);
        record_folded_subsession(s, agent_id, event);
        if handled {
            return effects;
        }
    }

    // A remote Codex hook carries the latest public assistant text.
    if s.source == "codex" && event_name != "UserPromptSubmit" && event_name != "SessionStart" {
        if let Some(output) = json::string(event.raw("last_assistant_message")) {
            let trimmed = output.trim();
            if !trimmed.is_empty() {
                s.live_codex_output = Some(trimmed.to_owned());
            }
        }
    }

    // Activity never overwrites a waiting state.
    let was_waiting = is_waiting(s.status);

    // Not ported: the agent's checklist (`AgentTaskHookParser.events`,
    // `AgentTaskList.apply`) and its restore after SessionStart below.

    match event_name {
        "UserPromptSubmit" => {
            s.interrupted = false;
            s.last_turn_failed = false;
            s.task_round_ended = false;
            // Not ported: `clearRecapIfSuperseded` (the recap is not kept).
            if s.source == "codex" {
                s.live_codex_output = None;
            }
            s.status = AgentStatus::Processing;
            clear_tool(s);
            // A separate Cursor Task's Stop tombstoned its own id; a new
            // prompt is a relaunch.
            if s.source == "cursor" || s.source == "cursor-cli" {
                s.clear_closed_subagent_id(session_id);
            }
            let prompt = first_string_from_event(
                event,
                &[
                    "prompt",
                    "user_prompt",
                    "userPrompt",
                    "user_message",
                    "message",
                    "input",
                    "content",
                    "text",
                ],
                true,
            );
            if let Some(prompt) = prompt {
                if s.source == "hermes" {
                    s.hermes_hooks_report_prompts = true;
                }
                record_prompt(s, &prompt);
            }
        }
        "PreToolUse" => {
            if !was_waiting {
                s.status = AgentStatus::Running;
                s.set_current_tool(event.activity_label());
                s.current_tool_use_id = event.tool_use_id.clone();
                s.tool_description = event.tool_description();
            }
        }
        "PostToolUse" | "PostToolUseFailure" => {
            let success = event_name == "PostToolUse";
            if s.finishes_another_tool_use(event) {
                // An earlier tool's step, overtaken by the next tool's
                // start: recorded from its own payload, the running tool
                // stays up.
                if let Some(tool) = event.activity_label() {
                    let description = event.tool_description();
                    s.record_tool(
                        &tool,
                        description.as_deref(),
                        success,
                        None,
                        ctx.max_history,
                        now(),
                    );
                }
            } else {
                if let Some(tool) = s.current_tool().map(str::to_owned) {
                    let description = s.tool_description.clone();
                    s.record_tool(
                        &tool,
                        description.as_deref(),
                        success,
                        None,
                        ctx.max_history,
                        now(),
                    );
                }
                if !was_waiting {
                    s.status = AgentStatus::Processing;
                    clear_tool(s);
                }
            }
        }
        "PermissionDenied" | "SubagentStop" | "PostCompact" => {
            if !was_waiting {
                s.status = AgentStatus::Processing;
                clear_tool(s);
            }
        }
        "SubagentStart" => {
            if !was_waiting {
                s.status = AgentStatus::Running;
                s.set_current_tool(Some("Agent".to_owned()));
                s.tool_description = json::string(event.raw("agent_type")).map(str::to_owned);
            }
        }
        "AfterAgentResponse" => {
            // Cursor's reply arrives here, not in Stop.
            if let Some(text) =
                first_string_from_event(event, &["text", "message"], true).filter(|t| !t.is_empty())
            {
                s.last_assistant_message = Some(text.clone());
                s.add_recent_message(ChatMessage::new(false, &text));
            }
            if IDE_COMPLETION_SOURCES.contains(&s.source.as_str()) {
                if s.has_active_subagents() {
                    // The chat's turn ended while folded Tasks still work:
                    // the card stays active, no completion yet.
                    if !was_waiting {
                        s.status = AgentStatus::Running;
                        if s.current_tool().is_none() {
                            s.set_current_tool(Some("Agent".to_owned()));
                        }
                    }
                } else {
                    s.status = AgentStatus::Idle;
                    clear_tool(s);
                    facts.ended_turn = true;
                    slots.completion = Some(effects.len());
                }
            } else {
                s.status = AgentStatus::Processing;
            }
        }
        "AgentTurnSettled" => {
            // Hermes's post_llm_call: the turn's final reply, before the
            // Stop (on_session_end) that ends the turn.
            clear_tool(s);
            if let Some(prompt) = first_string_from_event(event, &["user_message"], true) {
                if Some(&prompt) != s.last_user_prompt.as_ref() {
                    record_prompt(s, &prompt);
                }
            }
            if let Some(message) = first_string_from_event(
                event,
                &[
                    "assistant_response",
                    "last_assistant_message",
                    "text",
                    "message",
                ],
                true,
            )
            .filter(|m| !m.trim().is_empty())
            {
                s.hermes_hooks_report_replies = true;
                s.last_assistant_message = Some(message.clone());
                let already_shown = s
                    .recent_messages
                    .last()
                    .is_some_and(|m| !m.is_user && m.text == message);
                if !already_shown {
                    s.add_recent_message(ChatMessage::new(false, &message));
                }
            }
            if !was_waiting {
                s.status = AgentStatus::Processing;
            }
        }
        "TaskRoundComplete" => {
            let is_task_cancel = event.event_name == "TaskCancel"
                || json::is_true(event.raw("interrupted"))
                || json::is_true(event.raw("cancelled"));
            s.interrupted = is_task_cancel;
            s.status = if is_task_cancel {
                AgentStatus::Idle
            } else {
                AgentStatus::Processing
            };
            clear_tool(s);
            let message = first_string_from_event(
                event,
                &["last_assistant_message", "text", "message", "summary"],
                true,
            );
            if let Some(message) = message {
                s.last_assistant_message = Some(message.clone());
                s.add_recent_message(ChatMessage::new(false, &message));
            } else if s.last_assistant_message.is_none() && s.last_message_is_user() {
                s.add_recent_message(ChatMessage::new(false, ctx.reply_complete_placeholder));
            }
            // A Cline task is a single round: its end is the session's, and
            // late tool hooks must not revive it.
            if s.source == "cline" || is_task_cancel {
                s.status = AgentStatus::Idle;
                s.task_round_ended = true;
            }
            facts.ended_turn = true;
            slots.completion = Some(effects.len());
        }
        "Stop" => {
            // A Hermes one-shot run's only turn ending is its card ending.
            if hermes::ends_one_shot_run(event) {
                effects.push(SideEffect::RemoveSession {
                    session_id: session_id.to_owned(),
                });
                return effects;
            }
            apply_stop(
                s,
                session_id,
                event,
                ctx,
                was_waiting,
                facts,
                slots,
                effects.len(),
            );
        }
        "SessionStart" => {
            // A link an AppState pass made is on the card, not in the hook:
            // the rebuild keeps it unless the hook names a parent itself.
            let linked_parent_id = s.parent_session_id.take();
            effects.push(SideEffect::StopMonitor {
                session_id: session_id.to_owned(),
            });
            *s = SessionSnapshot::new(now());
            apply_session_start(s, event, ctx);
            s.parent_session_id = parent_card_id(&event.raw_json).or(linked_parent_id);
            if !is_remote {
                effects.push(SideEffect::TryMonitorSession {
                    session_id: session_id.to_owned(),
                });
            }
        }
        "SessionEnd" => {
            // The shell drops the session's pending requests, then the card.
            effects.push(SideEffect::RemoveSession {
                session_id: session_id.to_owned(),
            });
            return effects;
        }
        "Notification" => apply_notification(s, event),
        "PreCompact" => {
            s.status = AgentStatus::Processing;
            if s.source == "codex" {
                s.set_current_tool(Some("Compacting".to_owned()));
            }
            s.tool_description = Some("Compacting context\u{2026}".to_owned());
        }
        "Interrupt" => {
            s.interrupted = true;
            s.status = AgentStatus::Idle;
            clear_tool(s);
            facts.ended_turn = true;
            slots.completion = Some(effects.len());
        }
        _ => {}
    }

    // A remote Hermes hook attaches its host's store; after the event, so a
    // prompt this very hook reported wins.
    if let Some(store) = StoreSnapshot::from_payload(event.raw("_hermes_store")) {
        s.apply_hermes_store(&store);
    }
    // After the switch: SessionStart rebuilt the snapshot.
    if hermes::platform(event).is_some() {
        s.hermes_chat_elsewhere = hermes::is_quiet(event);
    }

    s.last_activity = now();

    // Sessions created implicitly get their process monitor too.
    if s.cwd.is_some() && !is_remote {
        effects.push(SideEffect::TryMonitorSession {
            session_id: session_id.to_owned(),
        });
    }

    // The event reached this session's own state.
    facts.applied_to_session = true;
    slots.sound = Some(effects.len());

    // Show the session that just had activity; a Stop keeps the display
    // where its completion card puts it.
    if event_name != "Stop" && s.status != AgentStatus::Idle {
        effects.push(SideEffect::SetActiveSession {
            session_id: Some(session_id.to_owned()),
        });
    }
    effects
}

/// The `Stop` case of `applyHookEvent`.
#[allow(clippy::too_many_arguments)]
fn apply_stop(
    s: &mut SessionSnapshot,
    session_id: &str,
    event: &HookEvent,
    ctx: &ReduceContext,
    was_waiting: bool,
    facts: &mut HookEventFacts,
    slots: &mut AttentionEffectSlots,
    effect_count: usize,
) {
    // ESC / Ctrl+C.
    let stop_reason = json::string(event.raw("stop_reason"))
        .unwrap_or("")
        .to_lowercase();
    let is_cursor = s.source == "cursor" || s.source == "cursor-cli";
    let was_interrupted = (!is_cursor && stop_reason == "user")
        || matches!(
            stop_reason.as_str(),
            "interrupted" | "cancel" | "cancelled" | "abort" | "aborted"
        )
        || stop_reason.contains("interrupt")
        || stop_reason.contains("cancel")
        || json::is_true(event.raw("interrupted"))
        || json::is_true(event.raw("cancelled"))
        || hermes::ends_interrupted_turn(event);
    let has_active_subagents = s.has_active_subagents();
    // A separate Cursor Task card (its transcript names another chat)
    // tombstones itself and drops its process, so a still-open IDE `_ppid`
    // does not bring it back. Never the chat itself.
    if !has_active_subagents
        && (s.source == "cursor" || s.source == "cursor-cli")
        && fold_target(session_id, s.transcript_path.as_deref()).is_some()
    {
        s.record_closed_subagent_id(session_id);
        s.cli_pid = None;
        s.cli_start_time = None;
    }

    let message = first_string_from_event(
        event,
        &["last_assistant_message", "text", "message", "summary"],
        true,
    );
    if let Some(message) = message {
        s.last_assistant_message = Some(message.clone());
        // Often the reply the transcript tailer already appended: skip it
        // only when it is the newest row.
        let normalized = normalized_cursor_chat_text(&message).unwrap_or_else(|| message.clone());
        let already_shown = s.recent_messages.last().is_some_and(|m| {
            !m.is_user
                && normalized_cursor_chat_text(&m.text).unwrap_or_else(|| m.text.clone())
                    == normalized
        });
        if !already_shown {
            s.add_recent_message(ChatMessage::new(false, &message));
        }
    } else if s.last_assistant_message.is_none() && s.last_message_is_user() {
        // No reply text from the hook (CodeBuddy): the placeholder.
        s.add_recent_message(ChatMessage::new(false, ctx.reply_complete_placeholder));
    }
    if s.last_user_prompt.is_none() {
        if let Some(prompt) = json::string(event.raw("last_user_message")) {
            s.last_user_prompt = Some(prompt.to_owned());
            let at = s.recent_messages.len().saturating_sub(1);
            s.insert_recent_message(ChatMessage::new(true, prompt), at);
        }
    }

    if has_active_subagents && !was_interrupted {
        // The chat stopped while folded Tasks still work: the card stays
        // active, no completion, no `interrupted` latch.
        if !was_waiting {
            s.status = AgentStatus::Running;
            if s.current_tool().is_none() {
                s.set_current_tool(Some("Agent".to_owned()));
            }
        }
    } else {
        s.interrupted = was_interrupted;
        s.status = AgentStatus::Idle;
        clear_tool(s);
        if was_interrupted {
            for sub in s.subagents.values_mut() {
                sub.status = AgentStatus::Idle;
            }
        }
        facts.ended_turn = true;
        slots.completion = Some(effect_count);
    }
}

/// The metadata the `SessionStart` case re-applies to the rebuilt card.
fn apply_session_start(s: &mut SessionSnapshot, event: &HookEvent, ctx: &ReduceContext) {
    if let Some(cwd) = json::non_empty(event.raw("cwd")) {
        s.cwd = Some(cwd.to_owned());
    }
    if let Some(model) = hook_reported_model(event) {
        s.model = Some(model.to_owned());
        s.model_reported_at = Some((ctx.clock)());
    }
    apply_hook_process_id(s, event, false);
    if let Some(source) =
        normalized_supported_source(json::string(event.raw("_source")), ctx.sources)
    {
        s.source = source;
    }
    let set = |field: &mut Option<String>, key: &str| {
        if let Some(value) = json::non_empty(event.raw(key)) {
            *field = Some(value.to_owned());
        }
    };
    set(&mut s.term_app, "_term_app");
    set(&mut s.term_bundle_id, "_term_bundle");
    set(&mut s.iterm_session_id, "_iterm_session");
    set(&mut s.tty_path, "_tty");
    set(&mut s.kitty_window_id, "_kitty_window");
    set(&mut s.tmux_pane, "_tmux_pane");
    set(&mut s.tmux_client_tty, "_tmux_client_tty");
    set(&mut s.tmux_env, "_tmux");
    if let Some(mode) = json::string(event.raw("permission_mode")) {
        s.permission_mode = Some(mode.to_owned());
    }
    if let Some(root) = json::strings(event.raw("workspace_roots"))
        .and_then(|roots| roots.first().copied())
        .filter(|r| !r.is_empty())
    {
        s.cwd = Some(root.to_owned());
    }
    set(&mut s.cmux_surface_id, "_cmux_surface_id");
    set(&mut s.cmux_workspace_id, "_cmux_workspace_id");
    set(&mut s.zellij_pane_id, "_zellij_pane_id");
    set(&mut s.zellij_session_name, "_zellij_session_name");
    set(&mut s.wezterm_pane_id, "_wezterm_pane");
    apply_herdr_route(s, event, false);
    set(&mut s.superset_workspace_id, "_superset_workspace_id");
    set(&mut s.superset_pane_id, "_superset_pane_id");
    if let Some(host_id) = claude_desktop_session_id(event) {
        s.claude_desktop_session_id = Some(host_id.to_owned());
    }
    if let Some(env) = json::string_map(event.raw("_env")) {
        apply_env_metadata(s, &env);
    }
    set(&mut s.remote_host_id, "_remote_host_id");
    set(&mut s.remote_host_name, "_remote_host_name");
    apply_provider_session_id(s, event);
    apply_session_title(s, event);
}

/// The `Notification` case of `applyHookEvent`.
fn apply_notification(s: &mut SessionSnapshot, event: &HookEvent) {
    let text = first_string_from_event(
        event,
        &["message", "text", "summary", "status", "detail"],
        true,
    );
    if let Some(message) = text.as_deref().filter(|m| !m.trim().is_empty()) {
        s.tool_description = Some(message.to_owned());
    }
    if has_question(event) {
        s.status = AgentStatus::WaitingQuestion;
        return;
    }
    // A Notification cannot block: what it says the agent waits for is a
    // display-only wait, cleared by the next PostToolUse / Stop (#290).
    let interrupt = |s: &mut SessionSnapshot| {
        s.interrupted = true;
        s.status = AgentStatus::Idle;
        clear_tool(s);
    };
    match notification_kind(event).as_deref() {
        Some("permission_prompt") => s.status = AgentStatus::WaitingApproval,
        // "Waiting for your input after 60s idle": the turn is over.
        Some("idle_prompt") => s.status = AgentStatus::Idle,
        Some("interrupt" | "interrupted" | "user_interrupted" | "cancelled" | "aborted") => {
            interrupt(s);
        }
        _ => {
            let lower = text.map(|t| t.to_lowercase()).unwrap_or_default();
            if lower.contains("interrupted")
                || lower.contains("request interrupted")
                || lower.contains("cancelled by user")
                || lower.contains("aborted")
            {
                interrupt(s);
            }
        }
    }
}
