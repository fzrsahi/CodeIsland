//! Installing and removing the Claude Code hooks (`ConfigInstaller.swift`'s
//! Claude slice: `installClaudeHooks`, `uninstallHooks`, `HookId`,
//! `containsOurHook`, `removeManagedHookEntries`, `hasStaleAsyncKey`).
//!
//! Pure: the caller reads `settings.json` (and its back-up) and writes what
//! comes back. The hook script and the bridge binary are the platform's.

use serde_json::{Map, Value, json};

use super::json_editor::{delete_top_level_key, set_top_level_value, strip_json_comments};

/// The top-level key Claude Code keeps hooks under.
pub const HOOKS_KEY: &str = "hooks";

/// The command those hooks run: the script `installHookScript` writes beside
/// the bridge. The platform names it, since macOS and Linux install the script
/// under the same path but keep their own binary naming.
pub const HOOK_COMMAND: &str = "~/.codeisland/codeisland-hook.sh";

/// One hook event to register.
///
/// `min_version` gates an event the CLI only grew later: an older build must
/// never be handed a key it does not know.
///
/// `async_` is planning data, as in Swift's `(name, timeout, async)` table; the
/// entry written carries only `type`, `command` and `timeout`. An install that
/// *does* carry `async` is a stale one, and `has_stale_async_key` is why it
/// gets repaired.
pub struct ClaudeHookEvent {
    pub name: &'static str,
    pub timeout: i64,
    pub async_: bool,
    pub min_version: Option<&'static str>,
}

const fn event(
    name: &'static str,
    timeout: i64,
    async_: bool,
    min_version: Option<&'static str>,
) -> ClaudeHookEvent {
    ClaudeHookEvent {
        name,
        timeout,
        async_,
        min_version,
    }
}

/// Every event Morrow registers, in the order they are appended
/// (`builtInCLIs`' Claude Code entry).
pub const CLAUDE_EVENTS: &[ClaudeHookEvent] = &[
    event("UserPromptSubmit", 5, true, None),
    event("PreToolUse", 5, false, None),
    event("PostToolUse", 5, true, None),
    event("PostToolUseFailure", 5, true, Some("2.1.89")),
    // Waits on the card until the user answers, hence the day-long timeout.
    event("PermissionRequest", 86_400, false, None),
    event("Stop", 5, true, None),
    // Fires *instead of* Stop when the turn ends on an API error (rate limit,
    // overload, auth, billing) — the only turn-level failure signal, so it owns
    // the error sound.
    event("StopFailure", 5, true, Some("2.1.78")),
    event("SubagentStart", 5, true, None),
    event("SubagentStop", 5, true, None),
    event("SessionStart", 5, false, None),
    event("SessionEnd", 5, true, None),
    event("Notification", 86_400, false, None),
    event("PreCompact", 5, true, None),
];

/// `versionAtLeast`: component-wise, missing parts as zero.
pub fn version_at_least(installed: &str, required: &str) -> bool {
    let parse = |text: &str| -> Vec<i64> {
        text.split('.')
            .map_while(|part| part.parse::<i64>().ok())
            .collect()
    };
    let have = parse(installed);
    let want = parse(required);
    for index in 0..have.len().max(want.len()) {
        let have_part = have.get(index).copied().unwrap_or(0);
        let want_part = want.get(index).copied().unwrap_or(0);
        if have_part > want_part {
            return true;
        }
        if have_part < want_part {
            return false;
        }
    }
    true
}

/// The events this CLI build understands (`compatibleEvents`).
///
/// An event with a minimum version is skipped when the version could not be
/// read at all — the risky ones stay out rather than in.
pub fn events_for_version(version: Option<&str>) -> Vec<&'static ClaudeHookEvent> {
    CLAUDE_EVENTS
        .iter()
        .filter(|event| match event.min_version {
            None => true,
            Some(minimum) => version.is_some_and(|installed| version_at_least(installed, minimum)),
        })
        .collect()
}

/// `HookId.isOurs`: any command naming this app, including the names it had
/// before (`vibenotch`, `vibe-island`, `vibeisland`).
pub fn is_ours(command: &str) -> bool {
    let lower = command.to_lowercase();
    lower.contains("codeisland")
        || ["vibenotch", "vibe-island", "vibeisland"]
            .iter()
            .any(|legacy| lower.contains(legacy))
}

/// `containsOurHook`: Claude and nested formats name it in `hooks[].command`,
/// the flat format in `command`, Copilot's in `bash`.
pub fn contains_our_hook(entry: &Value) -> bool {
    let Some(map) = entry.as_object() else {
        return false;
    };
    if let Some(hooks) = map.get("hooks").and_then(Value::as_array) {
        return hooks.iter().any(|hook| {
            hook.get("command")
                .and_then(Value::as_str)
                .is_some_and(is_ours)
        });
    }
    if let Some(command) = map.get("command").and_then(Value::as_str) {
        if is_ours(command) {
            return true;
        }
    }
    map.get("bash").and_then(Value::as_str).is_some_and(is_ours)
}

/// `removeManagedHookEntries`: drop every entry of ours, and an event whose
/// entries were all ours.
pub fn remove_managed_entries(hooks: &Map<String, Value>) -> Map<String, Value> {
    let mut cleaned = Map::new();
    for (event, value) in hooks {
        let Some(entries) = value.as_array() else {
            cleaned.insert(event.clone(), value.clone());
            continue;
        };
        let kept: Vec<Value> = entries
            .iter()
            .filter(|entry| !contains_our_hook(entry))
            .cloned()
            .collect();
        if !kept.is_empty() {
            cleaned.insert(event.clone(), Value::Array(kept));
        }
    }
    cleaned
}

/// `hasStaleAsyncKey`: an install from before the flag was dropped carries an
/// `async` key in one of our hook entries.
pub fn has_stale_async_key(hooks: &Map<String, Value>) -> bool {
    hooks
        .values()
        .filter_map(Value::as_array)
        .flatten()
        .filter(|entry| contains_our_hook(entry))
        .filter_map(|entry| entry.get("hooks").and_then(Value::as_array))
        .flatten()
        .any(|hook| hook.get("async").is_some())
}

/// What an install came to.
pub struct InstallOutcome {
    /// Whether the text differs from what was read.
    pub changed: bool,
    pub text: String,
}

/// Install or repair the hooks in one `settings.json`
/// (`installClaudeHooks` + `writeJSONWithKey`).
///
/// `None` when the file exists and does not parse as a JSON object: the caller
/// writes nothing (#89). `existing` is `None` for a file that is not there yet.
pub fn install(
    existing: Option<&str>,
    command: &str,
    version: Option<&str>,
) -> Option<InstallOutcome> {
    let original = existing.filter(|text| !text.is_empty());
    let source = original.unwrap_or("{}");

    let settings = settings_object(source)?;
    let mut hooks = settings
        .get(HOOKS_KEY)
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    let events = events_for_version(version);

    let already_installed = events.iter().all(|expected| {
        hooks
            .get(expected.name)
            .and_then(Value::as_array)
            .is_some_and(|entries| {
                entries.iter().any(|entry| {
                    entry
                        .get("hooks")
                        .and_then(Value::as_array)
                        .is_some_and(|hooks| {
                            hooks.iter().any(|hook| {
                                hook.get("command").and_then(Value::as_str) == Some(command)
                            })
                        })
                })
            })
    });
    if already_installed && !has_stale_async_key(&hooks) {
        return Some(InstallOutcome {
            changed: false,
            text: source.to_owned(),
        });
    }

    // Every entry of ours goes first, legacy naming included, so a repair
    // replaces rather than accumulates.
    hooks = remove_managed_entries(&hooks);
    for expected in events {
        let entry = json!({
            "matcher": "",
            "hooks": [{
                "type": "command",
                "command": command,
                "timeout": expected.timeout,
            }],
        });
        hooks
            .entry(expected.name.to_owned())
            .or_insert_with(|| Value::Array(Vec::new()))
            .as_array_mut()?
            .push(entry);
    }

    let text = set_top_level_value(source, HOOKS_KEY, &Value::Object(hooks))?;
    Some(InstallOutcome {
        changed: !same_document(source, &text),
        text,
    })
}

/// Whether every event of this build already carries `command`, with no stale
/// `async` key left behind (`isHooksInstalled`).
pub fn is_installed(existing: &str, command: &str, version: Option<&str>) -> bool {
    let Some(settings) = settings_object(existing) else {
        return false;
    };
    let hooks = settings
        .get(HOOKS_KEY)
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    let all_present = events_for_version(version).iter().all(|expected| {
        hooks
            .get(expected.name)
            .and_then(Value::as_array)
            .is_some_and(|entries| {
                entries.iter().any(|entry| {
                    entry
                        .get("hooks")
                        .and_then(Value::as_array)
                        .is_some_and(|hooks| {
                            hooks.iter().any(|hook| {
                                hook.get("command").and_then(Value::as_str) == Some(command)
                            })
                        })
                })
            })
    });
    all_present && !has_stale_async_key(&hooks)
}

/// What an uninstall came to.
pub struct UninstallOutcome {
    pub changed: bool,
    pub text: String,
}

/// Take the hooks back out (`uninstallHooks`). `None` when the file does not
/// hold a JSON object — there is nothing we could have written there.
pub fn uninstall(existing: &str) -> Option<UninstallOutcome> {
    let settings = settings_object(existing)?;
    let hooks = settings
        .get(HOOKS_KEY)
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    let cleaned = remove_managed_entries(&hooks);

    // An empty `hooks` key goes altogether, so a file that held nothing but our
    // entries comes back byte for byte.
    let text = if cleaned.is_empty() {
        delete_top_level_key(existing, HOOKS_KEY)?
    } else {
        set_top_level_value(existing, HOOKS_KEY, &Value::Object(cleaned))?
    };
    Some(UninstallOutcome {
        changed: text != existing,
        text,
    })
}

/// The back-up name to create before the first write to `path`: a timestamped
/// `.codeisland.bak` beside it, skipped once any such back-up exists in the
/// same directory (`backupOpencodeConfig`).
pub fn backup_path(path: &str, stamp: &str, names_in_dir: &[String]) -> Option<String> {
    let name = path.rsplit('/').next().unwrap_or(path);
    let prefix = format!("{name}.codeisland.bak.");
    if names_in_dir
        .iter()
        .any(|existing| existing.starts_with(&prefix))
    {
        return None;
    }
    Some(format!("{path}.codeisland.bak.{stamp}"))
}

fn settings_object(source: &str) -> Option<Map<String, Value>> {
    let value: Value = serde_json::from_str(&strip_json_comments(source)).ok()?;
    value.as_object().cloned()
}

/// `isSameJSONDocument`: same document, whatever the key order, spacing or
/// comments.
fn same_document(left: &str, right: &str) -> bool {
    let parse = |text: &str| serde_json::from_str::<Value>(&strip_json_comments(text));
    match (parse(left), parse(right)) {
        (Ok(left), Ok(right)) => left == right,
        _ => false,
    }
}
