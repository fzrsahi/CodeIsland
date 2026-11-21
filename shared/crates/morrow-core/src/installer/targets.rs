//! The hook targets besides Claude Code, and the shape each one's file takes
//! (`ConfigInstaller.swift`'s `builtInCLIs` for Codex, Gemini, Cursor, Qoder,
//! Factory/Droid, CodeBuddy and Copilot CLI).
//!
//! A plan over text, like [`super::claude_hooks`]: the platform names the
//! command, reads the file and writes the result.

use serde_json::{Map, Value, json};

use super::claude_hooks::{contains_our_hook, remove_managed_entries};
use super::json_editor::{delete_top_level_key, set_top_level_value};
use super::settings::{object, same_document};

/// How one CLI's file holds its hooks.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Format {
    /// `{matcher, hooks: [{type, command, timeout}]}` — Claude forks.
    Claude,
    /// `{hooks: [{type, command, timeout}]}` — Codex, Gemini.
    Nested,
    /// `{command}` — Cursor.
    Flat,
    /// `{type, bash, timeoutSec}` in a file of its own — Copilot CLI.
    Copilot,
}

/// One hook event to register, with the timeout the CLI expects (seconds,
/// except Gemini, which counts milliseconds).
pub struct TargetEvent {
    pub name: &'static str,
    pub timeout: i64,
    pub async_: bool,
}

const fn event(name: &'static str, timeout: i64, async_: bool) -> TargetEvent {
    TargetEvent {
        name,
        timeout,
        async_,
    }
}

/// A CLI Morrow can hook, and where its file is.
pub struct Target {
    /// The `--source` the bridge is told.
    pub source: &'static str,
    pub name: &'static str,
    /// Relative to the user's home.
    pub path: &'static str,
    /// The top-level key the hooks live under.
    pub key: &'static str,
    pub format: Format,
    pub events: &'static [TargetEvent],
    /// Some CLIs are reported under another source (`--source` in the entry).
    pub bridge_source: Option<&'static str>,
    /// A file Copilot reads needs `version: 1` at the top level.
    pub seeds_version: bool,
}

impl Target {
    pub fn bridge_source(&self) -> &'static str {
        self.bridge_source.unwrap_or(self.source)
    }
}

/// `defaultEvents(for: .claude)`: the same list Claude Code gets, for the forks
/// that share its schema.
const CLAUDE_EVENTS: &[TargetEvent] = &[
    event("UserPromptSubmit", 5, true),
    event("PreToolUse", 5, false),
    event("PostToolUse", 5, true),
    event("SessionStart", 5, false),
    event("SessionEnd", 5, true),
    event("Stop", 5, true),
    event("SubagentStart", 5, true),
    event("SubagentStop", 5, true),
    event("Notification", 86_400, false),
    event("PreCompact", 5, true),
];

/// Every target this module can install. Claude Code is not here: it has its
/// own installer, because its events and its script came first.
pub const TARGETS: &[Target] = &[
    Target {
        source: "codex",
        name: "Codex",
        path: ".codex/hooks.json",
        key: "hooks",
        format: Format::Nested,
        events: &[
            event("SessionStart", 5, false),
            event("SessionEnd", 3, true),
            event("UserPromptSubmit", 5, false),
            event("PreToolUse", 5, false),
            event("PostToolUse", 5, false),
            // Codex fires PermissionRequest before shell escalation; without it
            // the panel stays on "running" and the approval sound never plays.
            event("PermissionRequest", 86_400, false),
            event("PreCompact", 5, false),
            event("PostCompact", 5, false),
            event("SubagentStart", 5, false),
            event("SubagentStop", 5, false),
            event("Stop", 5, false),
            event("Interrupt", 3, false),
        ],
        bridge_source: None,
        seeds_version: false,
    },
    // Gemini counts milliseconds, and its hook names are its own.
    Target {
        source: "gemini",
        name: "Gemini",
        path: ".gemini/settings.json",
        key: "hooks",
        format: Format::Nested,
        events: &[
            event("SessionStart", 10_000, false),
            event("SessionEnd", 10_000, false),
            event("BeforeTool", 86_400_000, false),
            event("AfterTool", 10_000, false),
            event("BeforeAgent", 10_000, false),
            event("AfterAgent", 10_000, false),
        ],
        bridge_source: None,
        seeds_version: false,
    },
    Target {
        source: "cursor",
        name: "Cursor",
        path: ".cursor/hooks.json",
        key: "hooks",
        format: Format::Flat,
        events: &[
            event("beforeSubmitPrompt", 5, false),
            event("beforeShellExecution", 5, false),
            event("afterShellExecution", 5, false),
            event("beforeReadFile", 5, false),
            event("afterFileEdit", 5, false),
            event("beforeMCPExecution", 5, false),
            event("afterMCPExecution", 5, false),
            event("afterAgentThought", 5, false),
            event("afterAgentResponse", 5, false),
            event("stop", 5, false),
        ],
        bridge_source: None,
        seeds_version: false,
    },
    // A Claude Code fork with its own PermissionRequest hook.
    Target {
        source: "qoder",
        name: "Qoder",
        path: ".qoder/settings.json",
        key: "hooks",
        format: Format::Claude,
        events: &[
            event("UserPromptSubmit", 5, true),
            event("PreToolUse", 5, false),
            event("PostToolUse", 5, true),
            event("PostToolUseFailure", 5, true),
            event("PermissionRequest", 86_400, false),
            event("Stop", 5, true),
            event("SubagentStart", 5, true),
            event("SubagentStop", 5, true),
            event("SessionStart", 5, false),
            event("SessionEnd", 5, true),
            event("Notification", 86_400, false),
            event("PreCompact", 5, true),
        ],
        bridge_source: None,
        seeds_version: false,
    },
    // Factory's Droid and CodeBuddy both speak Claude Code's schema.
    Target {
        source: "droid",
        name: "Factory",
        path: ".factory/settings.json",
        key: "hooks",
        format: Format::Claude,
        events: CLAUDE_EVENTS,
        bridge_source: None,
        seeds_version: false,
    },
    Target {
        source: "codebuddy",
        name: "CodeBuddy",
        path: ".codebuddy/settings.json",
        key: "hooks",
        format: Format::Claude,
        events: CLAUDE_EVENTS,
        bridge_source: None,
        seeds_version: false,
    },
    // Copilot CLI's stdin carries no session or event name, so the event is a
    // flag, and the file must say which schema it is.
    Target {
        source: "copilot",
        name: "Copilot",
        path: ".copilot/hooks/codeisland.json",
        key: "hooks",
        format: Format::Copilot,
        events: &[
            event("sessionStart", 5, false),
            event("sessionEnd", 5, true),
            event("userPromptSubmitted", 5, false),
            event("preToolUse", 5, false),
            event("postToolUse", 5, true),
            event("errorOccurred", 5, true),
        ],
        bridge_source: None,
        seeds_version: true,
    },
];

/// The target Morrow installs for `--source`, if it has one.
pub fn target_for(source: &str) -> Option<&'static Target> {
    TARGETS.iter().find(|target| target.source == source)
}

/// What an install came to.
pub struct Outcome {
    pub changed: bool,
    pub text: String,
}

/// The command one event's entry carries.
///
/// `bridge` is the hook script with no arguments (e.g.
/// `~/.codeisland/codeisland-hook.sh`); a path with a space is quoted, as the
/// Swift installer does.
pub fn command_for(target: &Target, bridge: &str, event: &str) -> String {
    let bridge = if bridge.contains(' ') {
        format!("\"{bridge}\"")
    } else {
        bridge.to_owned()
    };
    let base = format!("{bridge} --source {}", target.bridge_source());
    match target.format {
        // Gemini and Copilot do not report their event on stdin.
        Format::Nested if target.source == "gemini" => format!("{base} --event {event}"),
        Format::Flat | Format::Copilot => format!("{base} --event {event}"),
        _ => base,
    }
}

fn entry_for(target: &Target, bridge: &str, event: &'static TargetEvent) -> Value {
    let command = command_for(target, bridge, event.name);
    match target.format {
        Format::Claude => json!({
            "matcher": "*",
            "hooks": [{
                "type": "command",
                "command": command,
                "timeout": event.timeout,
            }],
        }),
        Format::Nested => json!({
            "hooks": [{
                "type": "command",
                "command": command,
                "timeout": event.timeout,
            }],
        }),
        Format::Flat => json!({"command": command}),
        Format::Copilot => json!({
            "type": "command",
            "bash": command,
            "timeoutSec": event.timeout,
        }),
    }
}

/// Whether every event of the target carries our hook (`isHooksInstalled`).
pub fn is_installed(target: &Target, existing: &str) -> bool {
    let Some(settings) = object(existing) else {
        return false;
    };
    let hooks = settings
        .get(target.key)
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    target.events.iter().all(|expected| {
        hooks
            .get(expected.name)
            .and_then(Value::as_array)
            .is_some_and(|entries| entries.iter().any(contains_our_hook))
    })
}

/// Install or repair one target. `None` when the file does not parse as a JSON
/// object: the caller writes nothing (#89).
pub fn install(target: &Target, existing: Option<&str>, bridge: &str) -> Option<Outcome> {
    let source = existing.filter(|text| !text.is_empty()).unwrap_or("{}");
    let settings = object(source)?;
    let mut hooks = settings
        .get(target.key)
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();

    for expected in target.events {
        let mut entries = hooks
            .get(expected.name)
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        // Ours goes first, so a reinstall replaces rather than accumulates.
        entries.retain(|entry| !contains_our_hook(entry));
        entries.push(entry_for(target, bridge, expected));
        hooks.insert(expected.name.to_owned(), Value::Array(entries));
    }

    let mut text = set_top_level_value(source, target.key, &Value::Object(hooks))?;
    // Copilot reads a schema version; only insert one the user has not set.
    if target.seeds_version {
        text = seed_version(&text, &settings)?;
    }
    Some(Outcome {
        changed: !same_document(source, &text),
        text,
    })
}

/// Take our entries back out; an emptied key goes altogether, so a file that
/// held only ours comes back byte for byte.
pub fn uninstall(target: &Target, existing: &str) -> Option<Outcome> {
    let settings = object(existing)?;
    let hooks = settings
        .get(target.key)
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    let cleaned = remove_managed_entries(&hooks);
    let text = if cleaned.is_empty() {
        delete_top_level_key(existing, target.key)?
    } else {
        set_top_level_value(existing, target.key, &Value::Object(cleaned))?
    };
    Some(Outcome {
        changed: text != existing,
        text,
    })
}

/// Copilot reads a schema version. One the user set themselves — a future
/// v2 — is left alone (`installExternalHooks`).
fn seed_version(installed: &str, before: &Map<String, Value>) -> Option<String> {
    if before.contains_key("version") || object(installed)?.contains_key("version") {
        return Some(installed.to_owned());
    }
    set_top_level_value(installed, "version", &json!(1))
}
