//! What a hook says about where its session runs: `extractMetadata`,
//! `fillMissingParentMetadataFromSubagentEvent` and the private helpers they
//! share (`applyEnvMetadata`, `applyHerdrRoute`, `applyHookProcessId`, …) of
//! `macos/Sources/MorrowCore/SessionSnapshot.swift`.

use super::ReduceContext;
use super::hermes;
use super::hook_event::HookEvent;
use super::json;
use super::session_snapshot::{SessionSnapshot, is_unhelpful_hook_cwd};
use super::subsession::{is_cursor_agent_transcript_path, parent_card_id, remote_host_id};
use super::text::is_valid_claude_desktop_host_session_id;
use crate::intake::normalized_supported_source;

/// `CLAUDE_CODE_HOST_SESSION_ID` (`ClaudeDesktopCodeSession.hostSessionEnvKey`).
const CLAUDE_DESKTOP_HOST_SESSION_ENV_KEY: &str = "CLAUDE_CODE_HOST_SESSION_ID";

fn owned(value: &str) -> Option<String> {
    Some(value.to_owned())
}

/// `extractMetadata(into:sessionId:event:)`: a parent event's metadata,
/// over what the card had.
pub fn extract_metadata(s: &mut SessionSnapshot, event: &HookEvent, ctx: &ReduceContext) {
    let home = ctx.home_directory;
    let event_cwd = json::non_empty(event.raw("cwd"));
    if let Some(cwd) = event_cwd.filter(|c| !is_unhelpful_hook_cwd(c, home)) {
        s.cwd = owned(cwd);
    }
    let cwd_missing = s
        .cwd
        .as_deref()
        .is_none_or(|c| is_unhelpful_hook_cwd(c, home));
    let first_root = json::strings(event.raw("workspace_roots"))
        .and_then(|roots| roots.first().copied())
        .filter(|r| !r.is_empty());
    let cursor_project = json::string(event.raw("transcript_path"))
        .filter(|tp| tp.contains("/.cursor/projects/"))
        .map(cursor_project_dir);
    if let (true, Some(root)) = (cwd_missing, first_root) {
        s.cwd = owned(root);
    } else if let (true, Some(project)) = (cwd_missing, cursor_project) {
        // Cursor: ~/.cursor/projects/<project>/agent-transcripts/… →
        // ~/.cursor/projects/<project>.
        if let Some(project) = project {
            s.cwd = Some(project);
        }
    } else if let (None, Some(cwd)) = (&s.cwd, event_cwd) {
        // Last resort: an unhelpful cwd still beats none.
        s.cwd = owned(cwd);
    }
    if let Some(model) = hook_reported_model(event) {
        s.model = owned(model);
        s.model_reported_at = Some((ctx.clock)());
    }
    if let Some(mode) = json::string(event.raw("permission_mode")) {
        s.permission_mode = owned(mode);
    }
    if let Some(path) = json::non_empty(event.raw("transcript_path")) {
        s.transcript_path = owned(path);
    }
    if let Some(app) = json::non_empty(event.raw("_term_app")).filter(|a| *a != "unknown") {
        s.term_app = owned(app);
    }
    let set = |field: &mut Option<String>, key: &str| {
        if let Some(value) = json::non_empty(event.raw(key)) {
            *field = owned(value);
        }
    };
    set(&mut s.iterm_session_id, "_iterm_session");
    set(&mut s.tty_path, "_tty");
    set(&mut s.kitty_window_id, "_kitty_window");
    set(&mut s.tmux_pane, "_tmux_pane");
    set(&mut s.tmux_client_tty, "_tmux_client_tty");
    set(&mut s.tmux_env, "_tmux");
    set(&mut s.term_bundle_id, "_term_bundle");
    if let Some(env) = json::string_map(event.raw("_env")) {
        apply_env_metadata(s, &env);
    }
    apply_hook_process_id(s, event, false);
    if let Some(source) =
        normalized_supported_source(json::string(event.raw("_source")), ctx.sources)
    {
        s.source = source;
    } else if s.source == "claude" {
        let path = json::string(event.raw("transcript_path"))
            .or_else(|| json::string(event.raw("transcriptPath")));
        if path.is_some() && is_cursor_agent_transcript_path(path) {
            // Untagged Cursor Agent Task hooks inherit the default "claude".
            s.source = "cursor".to_owned();
        }
    }
    set(&mut s.cmux_surface_id, "_cmux_surface_id");
    set(&mut s.cmux_workspace_id, "_cmux_workspace_id");
    set(&mut s.zellij_pane_id, "_zellij_pane_id");
    set(&mut s.zellij_session_name, "_zellij_session_name");
    set(&mut s.wezterm_pane_id, "_wezterm_pane");
    apply_herdr_route(s, event, false);
    set(&mut s.superset_workspace_id, "_superset_workspace_id");
    set(&mut s.superset_pane_id, "_superset_pane_id");
    set(&mut s.orca_terminal_handle, "_orca_terminal_handle");
    set(&mut s.orca_worktree_id, "_orca_worktree_id");
    if let Some(host_id) = claude_desktop_session_id(event) {
        s.claude_desktop_session_id = owned(host_id);
    }
    set(&mut s.remote_host_id, "_remote_host_id");
    set(&mut s.remote_host_name, "_remote_host_name");
    apply_provider_session_id(s, event);
    apply_session_title(s, event);
    if let Some(parent) = parent_card_id(&event.raw_json) {
        s.parent_session_id = Some(parent);
    }
}

/// The `session_id` a remote or Codex Desktop card keeps as its provider's
/// (the block shared by `extractMetadata` and SessionStart).
pub fn apply_provider_session_id(s: &mut SessionSnapshot, event: &HookEvent) {
    let Some(provider) = json::non_empty(event.raw("session_id")) else {
        return;
    };
    let is_codex_desktop =
        s.source == "codex" && s.term_bundle_id.as_deref() == Some("com.openai.codex");
    if s.is_remote() || is_codex_desktop {
        s.provider_session_id = Some(if is_codex_desktop {
            normalized_codex_desktop_provider_session_id(provider).to_owned()
        } else {
            provider.to_owned()
        });
    }
}

/// `session_title`, when not blank (shared by `extractMetadata` and
/// SessionStart).
pub fn apply_session_title(s: &mut SessionSnapshot, event: &HookEvent) {
    if let Some(title) = json::string(event.raw("session_title")).filter(|t| !t.trim().is_empty()) {
        s.session_title = owned(title);
    }
}

/// `fillMissingParentMetadataFromSubagentEvent`: identity fields a merged
/// Task/subagent hook fills on its parent's card, never overwriting.
pub fn fill_missing_parent_metadata_from_subagent_event(
    s: &mut SessionSnapshot,
    event: &HookEvent,
    ctx: &ReduceContext,
) {
    let home = ctx.home_directory;
    if s.remote_host_id.is_none() {
        s.remote_host_id = remote_host_id(&event.raw_json).map(str::to_owned);
    }
    if s.remote_host_name.is_none() {
        s.remote_host_name = json::non_empty(event.raw("_remote_host_name")).map(str::to_owned);
    }
    if s.source == "claude" {
        let source = normalized_supported_source(json::string(event.raw("_source")), ctx.sources)
            .or_else(|| {
                normalized_supported_source(json::string(event.raw("source")), ctx.sources)
            });
        if let Some(source) = source.filter(|s| s != "claude") {
            s.source = source;
        }
    }
    if s.source == "claude" {
        let path = json::string(event.raw("transcript_path"));
        if path.is_some() && is_cursor_agent_transcript_path(path) {
            s.source = "cursor".to_owned();
        }
    }

    let cwd_missing = s
        .cwd
        .as_deref()
        .is_none_or(|c| is_unhelpful_hook_cwd(c, home));
    if cwd_missing {
        let first_root = json::strings(event.raw("workspace_roots"))
            .and_then(|roots| roots.first().copied())
            .filter(|r| !r.is_empty());
        if let Some(cwd) =
            json::non_empty(event.raw("cwd")).filter(|c| !is_unhelpful_hook_cwd(c, home))
        {
            s.cwd = owned(cwd);
        } else if let Some(root) = first_root {
            s.cwd = owned(root);
        } else if let Some(tp) = json::string(event.raw("transcript_path"))
            .filter(|tp| tp.contains("/.cursor/projects/"))
        {
            if let Some(project) = cursor_project_dir(tp) {
                s.cwd = Some(project);
            }
        }
    }

    // A Codex child's transcript is its own rollout, not the parent's.
    if s.transcript_path.is_none() && !is_codex_subagent_event(event, Some(s), ctx) {
        s.transcript_path = json::non_empty(event.raw("transcript_path")).map(str::to_owned);
    }
    apply_hook_process_id(s, event, true);
    apply_herdr_route(s, event, true);
    if s.claude_desktop_session_id.is_none() {
        s.claude_desktop_session_id = claude_desktop_session_id(event).map(str::to_owned);
    }
    if s.parent_session_id.is_none() {
        s.parent_session_id = parent_card_id(&event.raw_json);
    }
}

/// The project directory of a Cursor `…/.cursor/projects/<project>/…`
/// transcript path.
fn cursor_project_dir(transcript_path: &str) -> Option<String> {
    let parts: Vec<&str> = transcript_path
        .split('/')
        .filter(|p| !p.is_empty())
        .collect();
    let index = parts.iter().position(|p| *p == "projects")?;
    let project = parts.get(index + 1)?;
    Some(format!("/{}/{project}", parts[..=index].join("/")))
}

/// `applyEnvMetadata`: terminal fields from the `_env` object, only where
/// the card has none.
pub fn apply_env_metadata(s: &mut SessionSnapshot, env: &[(&str, &str)]) {
    let get = |key: &str| {
        env.iter()
            .find(|(k, _)| *k == key)
            .map(|(_, v)| *v)
            .filter(|v| !v.is_empty())
    };
    let fill = |field: &mut Option<String>, value: Option<&str>| {
        if field.is_none() {
            if let Some(value) = value {
                *field = owned(value);
            }
        }
    };
    fill(&mut s.term_app, get("TERM_PROGRAM"));
    fill(&mut s.term_bundle_id, get("__CFBundleIdentifier"));
    fill(
        &mut s.iterm_session_id,
        get("ITERM_SESSION_ID").map(|ses| ses.split_once(':').map_or(ses, |(_, after)| after)),
    );
    fill(&mut s.kitty_window_id, get("KITTY_WINDOW_ID"));
    fill(&mut s.tmux_env, get("TMUX"));
    fill(&mut s.tmux_pane, get("TMUX_PANE"));
    fill(&mut s.cmux_surface_id, get("CMUX_SURFACE_ID"));
    fill(&mut s.cmux_workspace_id, get("CMUX_WORKSPACE_ID"));
    fill(&mut s.zellij_pane_id, get("ZELLIJ_PANE_ID"));
    fill(&mut s.zellij_session_name, get("ZELLIJ_SESSION_NAME"));
    fill(&mut s.wezterm_pane_id, get("WEZTERM_PANE"));
    fill(&mut s.superset_workspace_id, get("SUPERSET_WORKSPACE_ID"));
    // `env["SUPERSET_PANE_ID"] ?? env["SUPERSET_TERMINAL_ID"]`, then the
    // emptiness check: an empty pane id does not fall back.
    let superset_pane = env
        .iter()
        .find(|(k, _)| *k == "SUPERSET_PANE_ID")
        .or_else(|| env.iter().find(|(k, _)| *k == "SUPERSET_TERMINAL_ID"))
        .map(|(_, v)| *v)
        .filter(|v| !v.is_empty());
    fill(&mut s.superset_pane_id, superset_pane);
    fill(&mut s.orca_terminal_handle, get("ORCA_TERMINAL_HANDLE"));
    fill(&mut s.orca_worktree_id, get("ORCA_WORKTREE_ID"));
    fill(
        &mut s.claude_desktop_session_id,
        env.iter()
            .find(|(k, _)| *k == CLAUDE_DESKTOP_HOST_SESSION_ENV_KEY)
            .map(|(_, v)| *v)
            .filter(|v| is_valid_claude_desktop_host_session_id(v)),
    );
}

/// `applyHerdrRoute`: the Herdr pane of a local hook. `filling_only` keeps
/// what the card already has.
pub fn apply_herdr_route(s: &mut SessionSnapshot, event: &HookEvent, filling_only: bool) {
    if remote_host_id(&event.raw_json).is_some() {
        return;
    }
    let route = |field: &mut Option<String>, key: &str| {
        if let Some(value) = json::non_empty(event.raw(key)) {
            if !filling_only || field.is_none() {
                *field = owned(value);
            }
        }
    };
    route(&mut s.herdr_pane_id, "_herdr_pane_id");
    route(&mut s.herdr_socket_path, "_herdr_socket_path");
    route(&mut s.herdr_binary_path, "_herdr_bin_path");
}

/// `applyHookProcessId`: the agent's process (`_ppid`), as `cli_pid` on
/// this machine and `remote_pid` for a remote host's.
pub fn apply_hook_process_id(s: &mut SessionSnapshot, event: &HookEvent, filling_only: bool) {
    let Some(pid) = hook_process_id(event) else {
        return;
    };
    if remote_host_id(&event.raw_json).is_some() {
        if !filling_only || s.remote_pid.is_none() {
            s.remote_pid = Some(pid);
        }
    } else if filling_only {
        if s.cli_pid.is_none() {
            s.cli_pid = Some(pid);
        }
    } else if s.cli_pid != Some(pid) {
        s.cli_pid = Some(pid);
        s.cli_start_time = None;
    }
}

/// `hookProcessId`: a positive `_ppid` within `pid_t`'s range.
fn hook_process_id(event: &HookEvent) -> Option<i32> {
    let ppid = json::int(event.raw("_ppid")).filter(|p| *p > 0)?;
    i32::try_from(ppid).ok()
}

/// `claudeDesktopSessionId(in:)`: a well-formed `_claude_desktop_session`.
pub fn claude_desktop_session_id(event: &HookEvent) -> Option<&str> {
    json::string(event.raw("_claude_desktop_session"))
        .filter(|id| is_valid_claude_desktop_host_session_id(id))
}

/// `hookReportedModel`: top-level `model`, or Hermes's `extra.model`.
pub fn hook_reported_model(event: &HookEvent) -> Option<&str> {
    json::non_empty(event.raw("model")).or_else(|| hermes::model(&event.raw_json))
}

/// `normalizedCodexDesktopProviderSessionId`.
fn normalized_codex_desktop_provider_session_id(session_id: &str) -> &str {
    session_id.strip_prefix("codexapp:").unwrap_or(session_id)
}

/// `isCodexSubagentEvent`: a subagent-routed event from Codex.
pub fn is_codex_subagent_event(
    event: &HookEvent,
    session: Option<&SessionSnapshot>,
    ctx: &ReduceContext,
) -> bool {
    let source = normalized_supported_source(json::string(event.raw("_source")), ctx.sources)
        .or_else(|| session.map(|s| s.source.clone()));
    source.as_deref() == Some("codex")
}
