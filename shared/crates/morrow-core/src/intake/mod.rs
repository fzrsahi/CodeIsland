//! One hook delivery, interpreted (`HookIntake`,
//! `macos/Sources/MorrowCore/HookIntake.swift`): the event the island gets,
//! whether the hook waits for the island's answer, and how that answer
//! reaches its agent (`shared/contract/hook-edge-protocol.md`, *What the island
//! derives*).
//!
//! It reads nothing but the [`Facts`] it is handed. The ones that cost a
//! process lookup or a subprocess (an ancestor's argv, the tmux client)
//! are closures, asked only when the interpretation needs them.
//!
//! Two steps, so a bridge can arm its deadline in between:
//! [`HookIntake::new`] decides what the event is (source, session, event
//! name, whether it is held) and may drop it;
//! [`HookIntake::add_terminal_context`] then records where it runs.
//!
//! The submodules are the Swift types HookIntake calls, one file each,
//! named after them.

pub mod antigravity_hook_contract;
pub mod cli_process_resolver;
pub mod cursor_hook_payload;
pub mod custom_agent_command;
pub mod event_normalizer;
pub mod grok;
pub mod hermes_hook_payload;
pub mod hook_edge_facts;
pub mod host_harness;
pub mod session_snapshot;

use std::collections::HashMap;
use std::fmt;
use std::time::Duration;

use serde_json::Value;

use crate::JsonObject;
pub use custom_agent_command::CustomAgentCommand;
pub use session_snapshot::{SourceCatalog, normalized_supported_source};

/// `HookIntake.environmentKeys`: the variables the interpretation reads.
/// An edge sends no others, and a bridge hands over no others.
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
    // ClaudeDesktopCodeSession.hostSessionEnvKey
    "CLAUDE_CODE_HOST_SESSION_ID",
];

/// How many processes above the hook an edge reads (`Facts.ancestry`).
pub const MAX_ANCESTRY: usize = 6;

/// A fact asked for only when needed.
pub type Lazy<'a, T> = Box<dyn Fn() -> T + 'a>;

/// A fact about a path or a pane, asked for only when needed.
pub type Lookup<'a, T> = Box<dyn Fn(&str) -> T + 'a>;

/// `HookIntake.Ancestor`: one process above the hook, nearest first.
pub struct Ancestor<'a> {
    pub pid: i32,
    /// The resolved executable, symlinks already followed.
    pub executable_path: Option<String>,
    /// argv, including argv\[0\]. Read only for Codex Desktop detection.
    pub arguments: Lazy<'a, Vec<String>>,
    /// The bundle id of the outermost `.app` containing
    /// `executable_path`. Read only for Codex Desktop detection.
    pub bundle_identifier: Lazy<'a, Option<String>>,
}

impl<'a> Ancestor<'a> {
    /// A process with no argv and no bundle to report.
    pub fn new(pid: i32, executable_path: Option<String>) -> Self {
        Self {
            pid,
            executable_path,
            arguments: Box::new(Vec::new),
            bundle_identifier: Box::new(|| None),
        }
    }

    pub fn with_arguments(mut self, arguments: impl Fn() -> Vec<String> + 'a) -> Self {
        self.arguments = Box::new(arguments);
        self
    }

    pub fn with_bundle_identifier(
        mut self,
        bundle_identifier: impl Fn() -> Option<String> + 'a,
    ) -> Self {
        self.bundle_identifier = Box::new(bundle_identifier);
        self
    }
}

impl fmt::Debug for Ancestor<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Ancestor")
            .field("pid", &self.pid)
            .field("executable_path", &self.executable_path)
            .finish_non_exhaustive()
    }
}

/// `HookIntake.EdgeHost`: the machine an edge runs on when that is not the
/// island's.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct EdgeHost {
    pub id: String,
    pub name: String,
}

/// `HookIntake.Facts`: what an edge observed of one hook invocation. Facts
/// only: nothing in here is derived from anything else in here.
/// [`Facts::default`] knows nothing (every closure answers `None`, `false`,
/// or the path unchanged).
pub struct Facts<'a> {
    /// `--source`: the agent the hook was installed for.
    pub source_tag: Option<String>,
    /// `--event`: for agents whose stdin does not name the event.
    pub event_tag: Option<String>,
    /// The source to stamp when nothing declares or infers one and the
    /// payload has no `_source` of its own. A bridge has none; see
    /// [`hook_edge_facts::facts`] for an edge's.
    pub default_source: Option<String>,
    /// The hook's environment. Only [`ENVIRONMENT_KEYS`] are read.
    pub environment: HashMap<String, String>,
    /// The hook's parent process. `None` for an edge on another machine,
    /// whose processes are not the island's to track.
    pub parent_pid: Option<i32>,
    /// Up to [`MAX_ANCESTRY`] processes above the hook, nearest first.
    pub ancestry: Vec<Ancestor<'a>>,
    /// The directory the hook runs in. Read only when the payload names none.
    pub working_directory: Lazy<'a, Option<String>>,
    /// The hook's controlling terminal.
    pub tty: Lazy<'a, Option<String>>,
    /// The home directory, for `~` in GROK_HOME. `None` for an edge on
    /// another machine.
    pub home_directory: Lazy<'a, Option<String>>,
    /// `~` in a path expanded (HERMES_HOME).
    pub expanding_tilde_in_path: Lookup<'a, String>,
    /// Where an edge on another machine runs; `None` on the island's.
    pub remote_host: Option<EdgeHost>,
    /// SHA-256 of the hook's stdin exactly as the agent wrote it
    /// ([`cursor_hook_payload::delivery_digest`]).
    pub stdin_digest: Lazy<'a, Option<String>>,
    /// Whether the edge waits for the island's answer, when it decided that
    /// on its own. `None`: it waits whenever HookIntake says so, as a
    /// bridge does. A hook nobody waits on is never held.
    pub edge_waits: Option<bool>,
    /// The tty of the tmux client showing a pane (`tmux display-message`).
    pub tmux_client_tty: Lookup<'a, Option<String>>,
    /// Whether a file exists.
    pub file_exists: Lookup<'a, bool>,
    /// What Swift reads from `UserDefaults`: custom sources and commands.
    pub catalog: SourceCatalog,
}

impl Default for Facts<'_> {
    fn default() -> Self {
        Self {
            source_tag: None,
            event_tag: None,
            default_source: None,
            environment: HashMap::new(),
            parent_pid: None,
            ancestry: Vec::new(),
            working_directory: Box::new(|| None),
            tty: Box::new(|| None),
            home_directory: Box::new(|| None),
            expanding_tilde_in_path: Box::new(str::to_owned),
            remote_host: None,
            stdin_digest: Box::new(|| None),
            edge_waits: None,
            tmux_client_tty: Box::new(|_| None),
            file_exists: Box::new(|_| false),
            catalog: SourceCatalog::default(),
        }
    }
}

impl fmt::Debug for Facts<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Facts")
            .field("source_tag", &self.source_tag)
            .field("event_tag", &self.event_tag)
            .field("default_source", &self.default_source)
            .field("parent_pid", &self.parent_pid)
            .field("ancestry", &self.ancestry)
            .field("remote_host", &self.remote_host)
            .field("edge_waits", &self.edge_waits)
            .finish_non_exhaustive()
    }
}

/// `HookIntake.AnswerFormat`: how the hook hands the island's answer to
/// its agent.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AnswerFormat {
    /// As the island wrote it: Claude Code's `hookSpecificOutput`, which the
    /// other agents read too.
    Verbatim,
    /// Gemini CLI and Google Antigravity read `{"decision":"allow"|"deny"}`.
    GeminiDecision,
}

/// One hook delivery, interpreted.
#[derive(Debug)]
pub struct HookIntake<'a> {
    payload: JsonObject,
    /// The facts it was read from.
    pub facts: Facts<'a>,
    /// The event as the agent named it.
    pub event_name: String,
    /// [`Self::event_name`] in the island's terms ([`event_normalizer`]).
    pub normalized_event_name: String,
    pub session_id: String,
    /// The session id was made up from the agent's process: it sent none.
    pub session_id_is_fallback: bool,
    /// The source stamped as `_source`.
    pub source: Option<String>,
    pub is_permission: bool,
    pub is_question: bool,
    /// Whether the hook waits for the island's answer and hands it on.
    pub waits_for_answer: bool,
    pub answer_format: AnswerFormat,
    /// How long the bridge holds the event before delivering it.
    pub delivery_delay: Duration,
}

// MARK: - Before stdin

/// `HookIntake.admits`: whether the hook is forwarded at all: not with
/// MORROW_SKIP / CODEISLAND_SKIP set (to anything), and inside Grok only
/// its own `--source grok` hook.
pub fn admits(source_tag: Option<&str>, environment: &HashMap<String, String>) -> bool {
    if environment.contains_key("MORROW_SKIP") || environment.contains_key("CODEISLAND_SKIP") {
        return false;
    }
    grok::should_forward(source_tag, environment)
}

/// `HookIntake.immediateStdout(sourceTag:eventName:)`: what the hook must
/// print before anything else can end it, whatever the island does (Google
/// Antigravity's PreToolUse, #339).
pub fn immediate_stdout(
    source_tag: Option<&str>,
    event_name: Option<&str>,
    catalog: &SourceCatalog,
) -> Option<&'static str> {
    antigravity_hook_contract::hook_stdout(source_tag, event_name, catalog)
}

/// `HookIntake.stdinObject(_:sourceTag:)`: the stdin as an object, without
/// what is never forwarded (Hermes' copy of the conversation). `None` when
/// stdin is not a JSON object.
pub fn stdin_object(stdin: &[u8], source_tag: Option<&str>) -> Option<JsonObject> {
    let Ok(Value::Object(parsed)) = serde_json::from_slice(stdin) else {
        return None;
    };
    Some(if drops_parts_of_stdin(source_tag) {
        hermes_hook_payload::trimmed_for_forwarding(parsed)
    } else {
        parsed
    })
}

/// `HookIntake.dropsPartsOfStdin(sourceTag:)`: whether [`stdin_object`]
/// leaves parts of the stdin out, which must then stay out of logs too.
pub fn drops_parts_of_stdin(source_tag: Option<&str>) -> bool {
    source_tag == Some("hermes")
}

// MARK: - Interpretation

impl<'a> HookIntake<'a> {
    /// `HookIntake.init?(stdin:facts:)`: what the event is, from the agent's
    /// stdin object and the edge's facts. `None` when it names no session
    /// and none can be made up: it is dropped.
    pub fn new(stdin: JsonObject, facts: Facts<'a>) -> Option<Self> {
        let source_tag = facts.source_tag.as_deref();
        let mut json = if drops_parts_of_stdin(source_tag) {
            hermes_hook_payload::trimmed_for_forwarding(stdin)
        } else {
            stdin
        };
        // Facts are not part of the event. A bridge reads its own and drops
        // any piped in with the stdin, so nothing interprets a hook twice.
        json.remove(hook_edge_facts::KEY);
        let env = &facts.environment;
        let event_tag = facts.event_tag.as_deref();
        let catalog = &facts.catalog;

        // Cursor also runs Morrow's Claude Code hook with its own payload,
        // so a source-less event may be Cursor's (#377). Its digest lets the
        // island keep one of the two deliveries of a step wired in both.
        let is_cursor_payload = cursor_hook_payload::is_cursor_hook(&json);
        if is_cursor_payload {
            if let Some(digest) = (facts.stdin_digest)() {
                json.insert(cursor_hook_payload::DIGEST_KEY.into(), digest.into());
            }
        }

        // Hermes runs each hook with the firing profile's HERMES_HOME; only
        // on the island's machine (a remote edge sends `_hermes_store`).
        if source_tag == Some("hermes") && facts.remote_host.is_none() {
            if let Some(hermes_home) = non_empty_str(env.get("HERMES_HOME")) {
                json.insert(
                    "_hermes_home".into(),
                    (facts.expanding_tilde_in_path)(&hermes_home).into(),
                );
            }
        }

        // Grok normally sends these camelCase fields; the environment covers
        // hook variants and truncated passive payloads.
        let is_grok_runtime = grok::is_grok_runtime(env);
        if is_grok_runtime {
            if !json.contains_key("hookEventName") {
                if let Some(event) = non_empty_str(env.get("GROK_HOOK_EVENT")) {
                    json.insert("hookEventName".into(), event.into());
                }
            }
            if !json.contains_key("sessionId") {
                if let Some(session_id) = non_empty_str(env.get("GROK_SESSION_ID")) {
                    json.insert("sessionId".into(), session_id.into());
                }
            }
            if !json.contains_key("cwd") {
                let workspace_root = non_empty_string(json.get("workspaceRoot"))
                    .or_else(|| non_empty_str(env.get("GROK_WORKSPACE_ROOT")));
                if let Some(workspace_root) = workspace_root {
                    json.insert("cwd".into(), workspace_root.into());
                }
            }
        }

        // Generic compatibility: common camelCase aliases of forks.
        if names_no_event(&json) {
            let event = ["hookEventName", "eventName", "event"]
                .iter()
                .find_map(|key| non_empty_string(json.get(*key)))
                .or_else(|| event_tag.map(str::to_owned));
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
            // Google Antigravity sends `conversationId` and no session id (#215).
            let session_id = non_empty_string(json.get("sessionId"))
                .or_else(|| nested("payload"))
                .or_else(|| nested("data"))
                .or_else(|| non_empty_string(json.get("conversationId")));
            if let Some(session_id) = session_id {
                json.insert("session_id".into(), session_id.into());
            }
        }

        // Google Antigravity's camelCase `transcriptPath`.
        if !json.contains_key("transcript_path") {
            if let Some(path) = non_empty_string(json.get("transcriptPath")) {
                json.insert("transcript_path".into(), path.into());
            }
        }

        // Grok sends no transcript path; its session layout is fixed, and
        // the path is forwarded once the file exists.
        if is_grok_runtime && !json.contains_key("transcript_path") {
            let session_id = non_empty_string(json.get("session_id"));
            let cwd = non_empty_string(json.get("cwd"));
            if let (Some(session_id), Some(cwd), Some(home)) =
                (session_id, cwd, (facts.home_directory)())
            {
                let grok_home = match non_empty_str(env.get("GROK_HOME")) {
                    Some(raw) if raw == "~" => home.clone(),
                    Some(raw) if raw.starts_with("~/") => format!("{home}/{}", &raw[2..]),
                    Some(raw) => raw,
                    None => appending_path_component(&home, ".grok"),
                };
                if let Some(path) = grok::existing_chat_history_path(
                    &grok_home,
                    &cwd,
                    &session_id,
                    &*facts.file_exists,
                ) {
                    json.insert("transcript_path".into(), path.into());
                }
            }
        }

        // Copilot CLI: no session_id or hook_event_name on stdin, and its
        // own names for the tool fields.
        if source_tag == Some("copilot") {
            if names_no_event(&json) {
                if let Some(event) = event_tag {
                    json.insert("hook_event_name".into(), event.into());
                }
            }
            if !json.contains_key("session_id") {
                if let Some(session_id) = non_empty_string(json.get("sessionId")) {
                    json.insert("session_id".into(), session_id.into());
                }
            }
            if let Some(tool_name) = json.get("toolName").and_then(Value::as_str) {
                let tool_name = tool_name.to_owned();
                json.insert("tool_name".into(), tool_name.into());
            }
            let tool_args = json
                .get("toolArgs")
                .and_then(Value::as_str)
                .and_then(|args| serde_json::from_str::<Value>(args).ok())
                .filter(Value::is_object);
            if let Some(tool_args) = tool_args {
                json.insert("tool_input".into(), tool_args);
            }
        }

        // Cline: `hookName` and `taskId`, and the tool inside
        // `preToolUse` / `postToolUse`.
        if source_tag == Some("cline") {
            if names_no_event(&json) {
                if let Some(name) = non_empty_string(json.get("hookName")) {
                    json.insert("hook_event_name".into(), name.into());
                }
            }
            if !json.contains_key("session_id") {
                if let Some(task_id) = non_empty_string(json.get("taskId")) {
                    json.insert("session_id".into(), task_id.into());
                }
            }
            if !json.contains_key("tool_name") {
                let tool = |key: &str| {
                    let step = json.get(key)?.as_object()?;
                    let tool_name = non_empty_string(step.get("toolName"))?;
                    Some((
                        tool_name,
                        step.get("parameters").filter(|p| p.is_object()).cloned(),
                    ))
                };
                if let Some((tool_name, parameters)) = tool("preToolUse") {
                    json.insert("tool_name".into(), tool_name.into());
                    if !json.contains_key("tool_input") {
                        if let Some(parameters) = parameters {
                            json.insert("tool_input".into(), parameters);
                        }
                    }
                } else if let Some((tool_name, _)) = tool("postToolUse") {
                    json.insert("tool_name".into(), tool_name.into());
                }
            }
        }

        // The source: declared, a direct plugin's own `_source`, Cursor's
        // payload, else the ancestry (an agent firing Claude Code's hook,
        // marked `_via_plugin`, #95 #123 #134 #377).
        let ancestry = &facts.ancestry;
        let bridge_source = cli_process_resolver::bridge_source(
            source_tag,
            json.get("_source").and_then(Value::as_str),
            is_cursor_payload,
            ancestry,
            catalog,
        );
        // A `_source` the payload names but the island does not support
        // stays, and the island drops the event.
        let effective_source = bridge_source.source.or_else(|| {
            (!json.contains_key("_source"))
                .then(|| facts.default_source.clone())
                .flatten()
        });
        if let Some(source) = &effective_source {
            json.insert("_source".into(), source.clone().into());
        }
        if bridge_source.via_plugin {
            json.insert("_via_plugin".into(), true.into());
        }

        // The process the island tracks. Some CLIs run hooks through
        // `sh -c`: the parent is a throwaway shell, not the CLI.
        if let Some(immediate_parent_pid) = facts.parent_pid {
            let resolved_tracked_pid = cli_process_resolver::resolved_tracked_pid(
                immediate_parent_pid,
                effective_source.as_deref(),
                ancestry,
                catalog,
            );
            json.insert("_ppid".into(), resolved_tracked_pid.into());
            if resolved_tracked_pid != immediate_parent_pid {
                json.insert("_hook_ppid".into(), immediate_parent_pid.into());
            }
            // Cline's hooks are throwaway shells of a VS Code extension.
            if effective_source.as_deref() == Some("cline") {
                json.insert("_ppid".into(), 0.into());
            }
            // A caller whose process is not the agent's lifetime opts out
            // (OpenCode 2's shared background service, #332).
            if json.get("_untracked_process").and_then(swift_bool) == Some(true) {
                json.insert("_ppid".into(), 0.into());
                json.remove("_hook_ppid");
            }
        } else if facts.remote_host.is_some() {
            // Nor is a pid an edge there forwards one of the island's.
            json.remove("_ppid");
            json.remove("_hook_ppid");
        }

        // A declared source with no session id gets `<source>-ppid-<pid>`,
        // from the farthest same-source ancestor (#148).
        let mut session_id_is_fallback = false;
        if !json.contains_key("session_id") {
            if let (Some(source), Some(immediate_parent_pid)) = (source_tag, facts.parent_pid) {
                if !source.trim().is_empty() {
                    let session_pid = cli_process_resolver::resolved_session_pid(
                        immediate_parent_pid,
                        effective_source.as_deref().or(Some(source)),
                        ancestry,
                        catalog,
                    );
                    json.insert(
                        "session_id".into(),
                        format!("{source}-ppid-{session_pid}").into(),
                    );
                    session_id_is_fallback = true;
                }
            }
        }
        let session_id = json
            .get("session_id")
            .and_then(Value::as_str)
            .filter(|id| !id.is_empty())?
            .to_owned();

        // Event type.
        let event_name = json
            .get("hook_event_name")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned();
        let normalized_event_name = event_normalizer::normalize(&event_name).to_owned();
        let gemini_based = |s: Option<&str>| matches!(s, Some("google-antigravity" | "gemini"));
        let is_gemini_based_source =
            gemini_based(source_tag) || gemini_based(effective_source.as_deref());
        let is_permission = normalized_event_name == "PermissionRequest";
        let is_question = (normalized_event_name == "Notification"
            || event_name == "afterAgentThought")
            && json.get("question").is_some_and(Value::is_string);
        // A hook Cursor runs never waits on the island: Cursor reads its
        // stdout against its own schema, and an answer it cannot use blocks
        // the tool. Nor does a hook whose edge does not wait.
        let waits_for_answer =
            (is_permission || is_question) && !is_cursor_payload && facts.edge_waits != Some(false);

        Some(Self {
            payload: json,
            event_name,
            normalized_event_name,
            session_id,
            session_id_is_fallback,
            source: effective_source,
            is_permission,
            is_question,
            waits_for_answer,
            answer_format: if is_gemini_based_source {
                AnswerFormat::GeminiDecision
            } else {
                AnswerFormat::Verbatim
            },
            // Gemini prints its own approval prompt in the terminal; give it
            // a moment to show before the island's card does.
            delivery_delay: if is_gemini_based_source && is_permission {
                Duration::from_millis(250)
            } else {
                Duration::ZERO
            },
            facts,
        })
    }

    /// The payload to forward.
    pub fn payload(&self) -> &JsonObject {
        &self.payload
    }

    /// The payload to forward, owned.
    pub fn into_payload(self) -> JsonObject {
        self.payload
    }

    /// `immediateStdout`: what the hook must print now that its event is
    /// known. Antigravity wired through Gemini-style hooks names the event
    /// on stdin, not in `--event`.
    pub fn immediate_stdout(&self) -> Option<&'static str> {
        immediate_stdout(
            self.facts.source_tag.as_deref(),
            Some(self.event_name.as_str()),
            &self.facts.catalog,
        )
    }

    // MARK: - Terminal context

    /// `addTerminalContext()`: records where the hook runs: terminal app,
    /// multiplexer panes, tty, working directory and, for an edge on
    /// another machine, which one.
    pub fn add_terminal_context(&mut self) {
        let facts = &self.facts;
        let env = &facts.environment;
        let json = &mut self.payload;
        let set = |key: &str| env.get(key).map(String::as_str).filter(|v| !v.is_empty());
        let mut put = |key: &str, value: &str| {
            json.insert(key.into(), value.into());
        };

        if let Some(term_app) = set("TERM_PROGRAM") {
            put("_term_app", term_app);
        }
        if let Some(term_bundle) = set("__CFBundleIdentifier") {
            put("_term_bundle", term_bundle);
        }
        // ChatGPT starts Codex Desktop's app-server without
        // __CFBundleIdentifier: without a bundle its hooks were keyed as a
        // CLI thread next to the `codexapp:` card of the same thread.
        if non_empty_string(json.get("_term_bundle")).is_none()
            && self.source.as_deref() == Some("codex")
        {
            if let Some(desktop_bundle) =
                cli_process_resolver::codex_desktop_term_bundle(&facts.ancestry, &facts.catalog)
            {
                json.insert("_term_bundle".into(), desktop_bundle.into());
            }
        }
        let mut put = |key: &str, value: &str| {
            json.insert(key.into(), value.into());
        };

        // iTerm2: the GUID after the "w0t0p0:" prefix, for AppleScript.
        if let Some(iterm) = set("ITERM_SESSION_ID") {
            let session = iterm.split_once(':').map_or(iterm, |(_, guid)| guid);
            put("_iterm_session", session);
        }
        if let Some(kitty) = set("KITTY_WINDOW_ID") {
            put("_kitty_window", kitty);
        }
        if let Some(tmux) = set("TMUX") {
            put("_tmux", tmux);
            if let Some(pane) = set("TMUX_PANE") {
                put("_tmux_pane", pane);
                // The client tty tells which terminal window shows the pane.
                if let Some(client_tty) = (facts.tmux_client_tty)(pane) {
                    put("_tmux_client_tty", &client_tty);
                }
            }
        }
        if let Some(tty) = (facts.tty)().filter(|tty| !tty.is_empty()) {
            put("_tty", &tty);
        }
        if let Some(surface) = set("CMUX_SURFACE_ID") {
            put("_cmux_surface_id", surface);
        }
        if let Some(workspace) = set("CMUX_WORKSPACE_ID") {
            put("_cmux_workspace_id", workspace);
        }
        if let Some(zellij) = set("ZELLIJ") {
            put("_zellij", zellij);
            if let Some(pane) = set("ZELLIJ_PANE_ID") {
                put("_zellij_pane_id", pane);
            }
            if let Some(session) = set("ZELLIJ_SESSION_NAME") {
                put("_zellij_session_name", session);
            }
        }
        if let Some(pane) = set("WEZTERM_PANE") {
            put("_wezterm_pane", pane);
        }
        // Herdr: the pane only with the server socket that owns it.
        let trimmed = |key: &str| env.get(key).map(|v| v.trim()).filter(|v| !v.is_empty());
        if env.get("HERDR_ENV").map(String::as_str) == Some("1") {
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
        // Superset spoofs TERM_PROGRAM and strips the bundle id: its own
        // variables are the only sign of it (#213).
        if let Some(workspace) = set("SUPERSET_WORKSPACE_ID") {
            put("_superset_workspace_id", workspace);
        }
        // `SUPERSET_PANE_ID ?? SUPERSET_TERMINAL_ID`: a set but empty pane
        // id hides the terminal id.
        let superset_pane = env
            .get("SUPERSET_PANE_ID")
            .or_else(|| env.get("SUPERSET_TERMINAL_ID"))
            .filter(|v| !v.is_empty());
        if let Some(pane) = superset_pane {
            put("_superset_pane_id", pane);
        }
        // Orca: the handle `orca terminal switch --terminal` takes (#302).
        if let Some(handle) = set("ORCA_TERMINAL_HANDLE") {
            put("_orca_terminal_handle", handle);
        }
        if let Some(worktree) = set("ORCA_WORKTREE_ID") {
            put("_orca_worktree_id", worktree);
        }
        // Claude Desktop's Code tab: its own id for the session.
        if let Some(host) = set("CLAUDE_CODE_HOST_SESSION_ID") {
            put("_claude_desktop_session", host);
        }

        // Gemini CLI and Google Antigravity send no `cwd`.
        if !json.contains_key("cwd") {
            if let Some(working_directory) = (facts.working_directory)() {
                json.insert("cwd".into(), working_directory.into());
            }
        }

        // An edge on another machine: which one. A payload that names its
        // host already (the remote OpenCode plugin's) keeps it.
        if let Some(host) = &facts.remote_host {
            if non_empty_string(json.get("_remote_host_id")).is_none() && !host.id.trim().is_empty()
            {
                json.insert("_remote_host_id".into(), host.id.clone().into());
            }
            if non_empty_string(json.get("_remote_host_name")).is_none()
                && !host.name.trim().is_empty()
            {
                json.insert("_remote_host_name".into(), host.name.clone().into());
            }
        }
    }

    // MARK: - The answer

    /// `stdout(forAnswer:)`: what the hook prints for the island's
    /// `response`; `None` when it prints nothing (it does not wait for an
    /// answer, or there is none).
    pub fn stdout_for_answer(&self, response: &[u8]) -> Option<Vec<u8>> {
        if !self.waits_for_answer || response.is_empty() {
            return None;
        }
        match self.answer_format {
            AnswerFormat::Verbatim => Some(response.to_vec()),
            AnswerFormat::GeminiDecision => Some(gemini_decision(response)),
        }
    }
}

/// The island's `hookSpecificOutput.decision.behavior` as Gemini reads it.
fn gemini_decision(response: &[u8]) -> Vec<u8> {
    let behavior = serde_json::from_slice::<Value>(response)
        .ok()
        .and_then(|reply| {
            let decision = reply.get("hookSpecificOutput")?.get("decision")?;
            decision.as_object()?;
            decision.get("behavior")?.as_str().map(str::to_owned)
        });
    if let Some(behavior) = behavior {
        let translated = if behavior == "allow" || behavior == "always" {
            "allow"
        } else {
            "deny"
        };
        return serde_json::to_vec(&serde_json::json!({ "decision": translated }))
            .unwrap_or_else(|_| response.to_vec());
    }
    // Fallback: the raw text, to be resilient.
    let text = std::str::from_utf8(response).unwrap_or("");
    if text.contains(r#""behavior":"allow""#) || text.contains(r#""behavior":"always""#) {
        br#"{"decision":"allow"}"#.to_vec()
    } else if text.contains(r#""behavior":"deny""#) {
        br#"{"decision":"deny"}"#.to_vec()
    } else {
        response.to_vec()
    }
}

// MARK: - Helpers

/// `namesNoEvent`: no `hook_event_name`, or an empty one (a `null` one
/// names an event, as in Swift).
pub fn names_no_event(json: &JsonObject) -> bool {
    match json.get("hook_event_name") {
        None => true,
        Some(Value::String(name)) => name.is_empty(),
        Some(_) => false,
    }
}

/// `nonEmptyString`: a string with something besides whitespace, trimmed.
pub fn non_empty_string(value: Option<&Value>) -> Option<String> {
    non_empty_str(value?.as_str())
}

fn non_empty_str<S: AsRef<str>>(value: Option<S>) -> Option<String> {
    let value = value?;
    let trimmed = value.as_ref().trim();
    (!trimmed.is_empty()).then(|| trimmed.to_owned())
}

/// `value as? Bool` on a `JSONSerialization` value: a JSON boolean, or a
/// number that is exactly 0 or 1 (NSNumber bridges to Bool then).
fn swift_bool(value: &Value) -> Option<bool> {
    match value {
        Value::Bool(b) => Some(*b),
        Value::Number(n) => match n.as_f64() {
            Some(0.0) => Some(false),
            Some(1.0) => Some(true),
            _ => None,
        },
        _ => None,
    }
}

/// `(path as NSString).appendingPathComponent(component)`.
fn appending_path_component(path: &str, component: &str) -> String {
    if path.is_empty() {
        component.to_owned()
    } else if path.ends_with('/') {
        format!("{path}{component}")
    } else {
        format!("{path}/{component}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn env(pairs: &[(&str, &str)]) -> HashMap<String, String> {
        pairs
            .iter()
            .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
            .collect()
    }

    #[test]
    fn skip_and_grok_runtime_are_not_admitted() {
        assert!(admits(None, &env(&[])));
        assert!(!admits(None, &env(&[("MORROW_SKIP", "")])));
        assert!(!admits(None, &env(&[("CODEISLAND_SKIP", "1")])));
        assert!(!admits(None, &env(&[("GROK_SESSION_ID", "g")])));
        assert!(admits(None, &env(&[("GROK_SESSION_ID", "  ")])));
        assert!(admits(Some("grok"), &env(&[("GROK_HOOK_EVENT", "Stop")])));
    }

    #[test]
    fn stdin_must_be_an_object() {
        assert!(stdin_object(b"{}", None).is_some());
        for bad in [&b""[..], b"[]", b"not json", b"\"s\"", b"{"] {
            assert!(stdin_object(bad, None).is_none(), "{bad:?}");
        }
        let hermes = br#"{"extra":{"conversation_history":[1],"model":"m"}}"#;
        let trimmed = stdin_object(hermes, Some("hermes")).unwrap();
        assert_eq!(trimmed["extra"], serde_json::json!({"model": "m"}));
    }

    #[test]
    fn swift_bridges_only_0_and_1_to_bool() {
        assert_eq!(swift_bool(&serde_json::json!(1)), Some(true));
        assert_eq!(swift_bool(&serde_json::json!(0)), Some(false));
        assert_eq!(swift_bool(&serde_json::json!(2)), None);
        assert_eq!(swift_bool(&serde_json::json!("true")), None);
    }

    #[test]
    fn gemini_decision_from_the_islands_answer() {
        let allow = br#"{"hookSpecificOutput":{"decision":{"behavior":"always"}}}"#;
        assert_eq!(gemini_decision(allow), br#"{"decision":"allow"}"#);
        let deny = br#"{"hookSpecificOutput":{"decision":{"behavior":"ask"}}}"#;
        assert_eq!(gemini_decision(deny), br#"{"decision":"deny"}"#);
        assert_eq!(gemini_decision(b"{}"), b"{}");
    }
}
