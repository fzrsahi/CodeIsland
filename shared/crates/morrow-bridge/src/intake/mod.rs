//! What one hook invocation means: the bridge's minimal port of `HookIntake`
//! (`Sources/MorrowCore/HookIntake.swift`), enough for Claude Code's hook on
//! Linux (`docs/hook-edge-protocol.md`, *What the island derives*).
//!
//! TODO(#93): moves to morrow-core HookIntake. Everything here is pure: it
//! reads only the [`Facts`] it is handed. Not ported yet (each one is a
//! source this ticket does not serve): Hermes' stdin trimming and
//! `_hermes_home`, Grok's runtime aliases and transcript path, Copilot and
//! Cline payload shapes, Google Antigravity's immediate stdout, Gemini's
//! `{"decision":…}` answer and delivery delay, Codex Desktop's `_term_bundle`,
//! ancestry inference for sources other than Claude, remote edges.

mod events;
pub mod sources;

use std::collections::HashMap;

use serde_json::{Map, Value};

use crate::digest::sha256_hex;

/// A JSON object, keys in arrival order.
pub type JsonObject = Map<String, Value>;

/// `HookIntake.environmentKeys`: the variables the interpretation reads.
/// The bridge hands over no others.
pub const ENVIRONMENT_KEYS: &[&str] = &[
    "MORROW_SKIP",
    "CODEISLAND_SKIP",
    "GROK_SESSION_ID",
    "GROK_HOOK_EVENT",
    "GROK_WORKSPACE_ROOT",
    "GROK_HOME",
    "HERMES_HOME",
    "TERM_PROGRAM",
    "__CFBundleIdentifier",
    "ITERM_SESSION_ID",
    "KITTY_WINDOW_ID",
    "TMUX",
    "TMUX_PANE",
    "CMUX_SURFACE_ID",
    "CMUX_WORKSPACE_ID",
    "ZELLIJ",
    "ZELLIJ_PANE_ID",
    "ZELLIJ_SESSION_NAME",
    "WEZTERM_PANE",
    "HERDR_ENV",
    "HERDR_PANE_ID",
    "HERDR_SOCKET_PATH",
    "HERDR_BIN_PATH",
    "SUPERSET_WORKSPACE_ID",
    "SUPERSET_PANE_ID",
    "SUPERSET_TERMINAL_ID",
    "ORCA_TERMINAL_HANDLE",
    "ORCA_WORKTREE_ID",
    "CLAUDE_CODE_HOST_SESSION_ID",
];

/// How many processes above the hook the bridge reads.
pub const MAX_ANCESTRY: usize = 6;

/// `TERM_PROGRAM` values of macOS terminals. On Linux they can only be a
/// variable forwarded from a Mac, so they name no terminal here (the linux
/// golden bundle's `omitted_values`).
const MACOS_TERM_APPS: &[&str] = &["iTerm.app", "Apple_Terminal"];

/// One process above the hook, nearest first.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Ancestor {
    pub pid: i32,
    /// The resolved executable (`/proc/<pid>/exe`), when readable.
    pub executable_path: Option<String>,
}

/// What the OS says about the hook's process, behind a trait so tests hand
/// in a fixture's process tree. The calls that cost something (a
/// subprocess) are asked only when the interpretation needs them.
pub trait ProcessFacts {
    /// The hook's parent process.
    fn parent_pid(&self) -> Option<i32>;
    /// Up to [`MAX_ANCESTRY`] processes, starting with the parent.
    fn ancestry(&self) -> Vec<Ancestor>;
    /// The directory the hook runs in.
    fn working_directory(&self) -> Option<String>;
    /// The tty of the tmux client showing `pane`.
    fn tmux_client_tty(&self, pane: &str) -> Option<String>;
}

/// The bridge's argv: `--source` and `--event`, each the word after the
/// first occurrence of the flag, as the Swift bridge reads them.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Args {
    pub source: Option<String>,
    pub event: Option<String>,
}

impl Args {
    /// Reads the arguments after argv\[0\].
    pub fn parse<I: IntoIterator<Item = String>>(args: I) -> Self {
        let args: Vec<String> = args.into_iter().collect();
        let after = |flag: &str| {
            let index = args.iter().position(|a| a == flag)?;
            args.get(index + 1).cloned()
        };
        Self {
            source: after("--source"),
            event: after("--event"),
        }
    }
}

/// What the bridge observed of one hook invocation.
pub struct Facts<'a> {
    pub source_tag: Option<String>,
    pub event_tag: Option<String>,
    /// Only [`ENVIRONMENT_KEYS`].
    pub environment: HashMap<String, String>,
    pub parent_pid: Option<i32>,
    pub ancestry: Vec<Ancestor>,
    pub process: &'a dyn ProcessFacts,
}

impl<'a> Facts<'a> {
    /// Gathers the facts: the environment filtered to [`ENVIRONMENT_KEYS`],
    /// the parent and the ancestry, once.
    pub fn gather(
        args: &Args,
        environment: &HashMap<String, String>,
        process: &'a dyn ProcessFacts,
    ) -> Self {
        Self {
            source_tag: args.source.clone(),
            event_tag: args.event.clone(),
            environment: environment
                .iter()
                .filter(|(key, _)| ENVIRONMENT_KEYS.contains(&key.as_str()))
                .map(|(key, value)| (key.clone(), value.clone()))
                .collect(),
            parent_pid: process.parent_pid(),
            ancestry: process.ancestry(),
            process,
        }
    }

    fn env(&self, key: &str) -> Option<&str> {
        self.environment.get(key).map(String::as_str)
    }

    /// A variable that is set and not empty.
    fn env_non_empty(&self, key: &str) -> Option<&str> {
        self.env(key).filter(|value| !value.is_empty())
    }
}

/// `HookIntake.admits`: not with `MORROW_SKIP` / `CODEISLAND_SKIP` set
/// (to anything), and inside Grok only Grok's own `--source grok` hook.
pub fn admits(source_tag: Option<&str>, environment: &HashMap<String, String>) -> bool {
    if environment.contains_key("MORROW_SKIP") || environment.contains_key("CODEISLAND_SKIP") {
        return false;
    }
    let set = |key: &str| environment.get(key).is_some_and(|v| !v.trim().is_empty());
    let in_grok = set("GROK_SESSION_ID") || set("GROK_HOOK_EVENT");
    !in_grok || source_tag == Some("grok")
}

/// The stdin as a JSON object; `None` when it is not one (empty, invalid,
/// an array, …).
pub fn stdin_object(stdin: &[u8]) -> Option<JsonObject> {
    match serde_json::from_slice(stdin) {
        Ok(Value::Object(object)) => Some(object),
        _ => None,
    }
}

/// One hook delivery, interpreted.
#[derive(Clone, Debug)]
pub struct Intake {
    payload: JsonObject,
    /// The event as the agent named it.
    pub event_name: String,
    /// [`Self::event_name`] in the island's terms.
    pub normalized_event_name: String,
    pub session_id: String,
    /// The session id was made up from the agent's process: it sent none.
    pub session_id_is_fallback: bool,
    /// The source stamped as `_source`.
    pub source: Option<String>,
    /// Whether the hook waits for the island's answer and prints it.
    pub waits_for_answer: bool,
}

impl Intake {
    /// What the event is. `None` when it names no session and none can be
    /// made up: it is dropped.
    pub fn new(stdin: JsonObject, stdin_bytes: &[u8], facts: &Facts<'_>) -> Option<Self> {
        let mut json = stdin;
        // Facts are not part of the event: the bridge reads its own.
        json.remove("_edge");

        // Rule 2: a non-blank `cursor_version` marks a hook Cursor ran,
        // through Claude Code's hook too (#377). Its digest lets the island
        // keep one of the two deliveries of a step wired in both configs.
        let is_cursor_payload = json
            .get("cursor_version")
            .and_then(Value::as_str)
            .is_some_and(|version| !version.trim().is_empty());
        if is_cursor_payload {
            json.insert(
                "_cursor_payload_digest".into(),
                sha256_hex(stdin_bytes).into(),
            );
        }

        // Rule 3: aliases.
        if names_no_event(&json) {
            let event = ["hookEventName", "eventName", "event"]
                .iter()
                .find_map(|key| non_empty_string(json.get(*key)))
                .or_else(|| facts.event_tag.clone());
            if let Some(event) = event {
                json.insert("hook_event_name".into(), event.into());
            }
        }
        if !json.contains_key("session_id") {
            let nested = |key: &str| {
                let object = json.get(key)?.as_object()?;
                non_empty_string(object.get("session_id"))
                    .or_else(|| non_empty_string(object.get("sessionId")))
            };
            let session = non_empty_string(json.get("sessionId"))
                .or_else(|| nested("payload"))
                .or_else(|| nested("data"))
                .or_else(|| non_empty_string(json.get("conversationId")));
            if let Some(session) = session {
                json.insert("session_id".into(), session.into());
            }
        }
        if !json.contains_key("transcript_path") {
            if let Some(path) = non_empty_string(json.get("transcriptPath")) {
                json.insert("transcript_path".into(), path.into());
            }
        }

        // Rule 4: the declared source, else a supported `_source`, else
        // Cursor's payload, else the ancestry. An unsupported `_source` with
        // nothing else to go on is left for the island to drop.
        let ancestry = &facts.ancestry;
        let source_tag = facts.source_tag.as_deref();
        let declared: Option<String> = source_tag
            .map(str::to_owned)
            .or_else(|| {
                sources::normalized_supported_source(json.get("_source").and_then(Value::as_str))
                    .map(str::to_owned)
            })
            .or_else(|| is_cursor_payload.then(|| "cursor".to_owned()));
        let inferred = declared
            .clone()
            .or_else(|| sources::infer_source(ancestry).map(str::to_owned));
        let source = sources::cli_variant_override(inferred.as_deref(), ancestry)
            .map(str::to_owned)
            .or(inferred);
        let via_plugin = declared.is_none() && source.as_deref().is_some_and(|s| s != "claude");
        if let Some(source) = &source {
            json.insert("_source".into(), source.clone().into());
        }
        if via_plugin {
            json.insert("_via_plugin".into(), true.into());
        }

        // Rule 5: the process the island tracks.
        if let Some(parent) = facts.parent_pid {
            let tracked = sources::resolved_tracked_pid(parent, source.as_deref(), ancestry);
            json.insert("_ppid".into(), tracked.into());
            if tracked != parent {
                json.insert("_hook_ppid".into(), parent.into());
            }
            // Cline's hooks are throwaway shells of a VS Code extension.
            if source.as_deref() == Some("cline") {
                json.insert("_ppid".into(), 0.into());
            }
            if json.get("_untracked_process") == Some(&Value::Bool(true)) {
                json.insert("_ppid".into(), 0.into());
                json.remove("_hook_ppid");
            }
        }

        // A declared source with no session id gets `<source>-ppid-<pid>`,
        // from the farthest same-source ancestor (#148). Claude Code's hook
        // declares none, so a Claude event without one is dropped.
        let mut session_id_is_fallback = false;
        if !json.contains_key("session_id") {
            if let (Some(tag), Some(parent)) = (source_tag, facts.parent_pid) {
                if !tag.trim().is_empty() {
                    let pid = sources::resolved_session_pid(
                        parent,
                        source.as_deref().or(Some(tag)),
                        ancestry,
                    );
                    json.insert("session_id".into(), format!("{tag}-ppid-{pid}").into());
                    session_id_is_fallback = true;
                }
            }
        }
        let session_id = json
            .get("session_id")
            .and_then(Value::as_str)
            .filter(|id| !id.is_empty())?
            .to_owned();

        // Waiting for the answer (protocol, *Waiting for the answer*).
        let event_name = json
            .get("hook_event_name")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned();
        let normalized_event_name = events::normalize(&event_name).to_owned();
        let is_permission = normalized_event_name == "PermissionRequest";
        let is_question = (normalized_event_name == "Notification"
            || event_name == "afterAgentThought")
            && json.get("question").is_some_and(Value::is_string);
        // Cursor reads a hook's stdout against its own schema: never held.
        let waits_for_answer = (is_permission || is_question) && !is_cursor_payload;

        Some(Self {
            payload: json,
            event_name,
            normalized_event_name,
            session_id,
            session_id_is_fallback,
            source,
            waits_for_answer,
        })
    }

    /// The payload to forward.
    pub fn payload(&self) -> &JsonObject {
        &self.payload
    }

    /// Records where the hook runs (rule 6), the keys a Linux edge can
    /// honestly give: no `_tty`, `_term_bundle` or `_iterm_session`, and no
    /// `_term_app` naming a macOS terminal (the linux golden bundle's
    /// `omitted_keys` / `omitted_values`). `_env` is a plugin's, passed on
    /// from stdin as it came.
    pub fn add_terminal_context(&mut self, facts: &Facts<'_>) {
        let json = &mut self.payload;
        let mut put = |key: &str, value: &str| {
            json.insert(key.into(), value.into());
        };

        if let Some(app) = facts.env_non_empty("TERM_PROGRAM") {
            if !MACOS_TERM_APPS.contains(&app) {
                put("_term_app", app);
            }
        }
        if let Some(kitty) = facts.env_non_empty("KITTY_WINDOW_ID") {
            put("_kitty_window", kitty);
        }
        if let Some(tmux) = facts.env_non_empty("TMUX") {
            put("_tmux", tmux);
            if let Some(pane) = facts.env_non_empty("TMUX_PANE") {
                put("_tmux_pane", pane);
                if let Some(client_tty) = facts.process.tmux_client_tty(pane) {
                    put("_tmux_client_tty", &client_tty);
                }
            }
        }
        if let Some(surface) = facts.env_non_empty("CMUX_SURFACE_ID") {
            put("_cmux_surface_id", surface);
        }
        if let Some(workspace) = facts.env_non_empty("CMUX_WORKSPACE_ID") {
            put("_cmux_workspace_id", workspace);
        }
        if let Some(zellij) = facts.env_non_empty("ZELLIJ") {
            put("_zellij", zellij);
            if let Some(pane) = facts.env_non_empty("ZELLIJ_PANE_ID") {
                put("_zellij_pane_id", pane);
            }
            if let Some(session) = facts.env_non_empty("ZELLIJ_SESSION_NAME") {
                put("_zellij_session_name", session);
            }
        }
        if let Some(pane) = facts.env_non_empty("WEZTERM_PANE") {
            put("_wezterm_pane", pane);
        }
        // Herdr: the pane only with the server socket that owns it.
        let trimmed = |key: &str| facts.env(key).map(str::trim).filter(|v| !v.is_empty());
        if facts.env("HERDR_ENV") == Some("1") {
            if let (Some(pane), Some(socket)) =
                (trimmed("HERDR_PANE_ID"), trimmed("HERDR_SOCKET_PATH"))
            {
                put("_herdr_pane_id", pane);
                put("_herdr_socket_path", socket);
                if let Some(binary) = trimmed("HERDR_BIN_PATH") {
                    put("_herdr_bin_path", binary);
                }
            }
        }
        if let Some(workspace) = facts.env_non_empty("SUPERSET_WORKSPACE_ID") {
            put("_superset_workspace_id", workspace);
        }
        // Swift's `SUPERSET_PANE_ID ?? SUPERSET_TERMINAL_ID`: a set but empty
        // pane id hides the terminal id.
        let superset_pane = facts
            .env("SUPERSET_PANE_ID")
            .or_else(|| facts.env("SUPERSET_TERMINAL_ID"));
        if let Some(pane) = superset_pane.filter(|v| !v.is_empty()) {
            put("_superset_pane_id", pane);
        }
        if let Some(handle) = facts.env_non_empty("ORCA_TERMINAL_HANDLE") {
            put("_orca_terminal_handle", handle);
        }
        if let Some(worktree) = facts.env_non_empty("ORCA_WORKTREE_ID") {
            put("_orca_worktree_id", worktree);
        }
        if let Some(host) = facts.env_non_empty("CLAUDE_CODE_HOST_SESSION_ID") {
            put("_claude_desktop_session", host);
        }
        if !json.contains_key("cwd") {
            if let Some(cwd) = facts.process.working_directory() {
                json.insert("cwd".into(), cwd.into());
            }
        }
    }

    /// What the hook prints for the island's `reply`: nothing unless it
    /// waits for an answer and there is one; Claude Code reads the island's
    /// `hookSpecificOutput` as it is.
    pub fn stdout_for_answer<'r>(&self, reply: &'r [u8]) -> Option<&'r [u8]> {
        (self.waits_for_answer && !reply.is_empty()).then_some(reply)
    }
}

/// No `hook_event_name`, or an empty one (a `null` one names an event, as
/// in Swift).
fn names_no_event(json: &JsonObject) -> bool {
    match json.get("hook_event_name") {
        None => true,
        Some(Value::String(name)) => name.is_empty(),
        Some(_) => false,
    }
}

/// A string with something besides whitespace, trimmed.
fn non_empty_string(value: Option<&Value>) -> Option<String> {
    let trimmed = value?.as_str()?.trim();
    (!trimmed.is_empty()).then(|| trimmed.to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn args_take_the_word_after_the_first_flag() {
        let args = Args::parse(
            ["--source", "codex", "--event", "Stop", "--source", "x"].map(String::from),
        );
        assert_eq!(args.source.as_deref(), Some("codex"));
        assert_eq!(args.event.as_deref(), Some("Stop"));
        assert_eq!(Args::parse(["--source".to_owned()]), Args::default());
    }

    #[test]
    fn skip_and_grok_runtime_are_not_admitted() {
        let env = |pairs: &[(&str, &str)]| -> HashMap<String, String> {
            pairs
                .iter()
                .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
                .collect()
        };
        assert!(admits(None, &env(&[])));
        assert!(!admits(None, &env(&[("MORROW_SKIP", "")])));
        assert!(!admits(None, &env(&[("CODEISLAND_SKIP", "1")])));
        assert!(!admits(None, &env(&[("GROK_SESSION_ID", "g")])));
        assert!(admits(None, &env(&[("GROK_SESSION_ID", "  ")])));
        assert!(admits(Some("grok"), &env(&[("GROK_HOOK_EVENT", "Stop")])));
    }

    #[test]
    fn stdin_must_be_an_object() {
        assert!(stdin_object(b"{}").is_some());
        for bad in [&b""[..], b"[]", b"not json", b"\"s\"", b"{"] {
            assert!(stdin_object(bad).is_none(), "{bad:?}");
        }
    }
}
