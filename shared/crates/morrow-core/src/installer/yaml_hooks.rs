//! The YAML sources — Hermes and TraeCli — as a managed block (#151).
//!
//! macOS round-trips these two files through `Yams`: `load` and `dump` again,
//! which is guaranteed valid YAML and guaranteed to lose the user's comments.
//! A port that does the same would fail L-002 on the very files this module is
//! for, so this takes the other road: Morrow owns **one region**, fenced by
//! comment lines, and writes nothing outside it.
//!
//! ```yaml
//! # >>> morrow hooks (managed by Morrow; edits inside are overwritten)
//! pre_tool_call:
//!   - command: '~/.codeisland/codeisland-hook.sh --source hermes'
//!     timeout: 5
//! # <<< morrow hooks
//! ```
//!
//! Everything else — the user's keys, order, comments, quoting, indentation —
//! is never parsed, never re-rendered, never touched. A layout this module
//! cannot vouch for is refused rather than guessed at, which is the one thing
//! worth being strict about: it is someone's config file.

/// How a CLI wants its hooks laid out under `hooks:`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Shape {
    /// A map of event name to a list of `{command, timeout}` — Hermes.
    EventMap,
    /// One list item carrying every event as a matcher — TraeCli.
    MatchList,
}

/// A YAML source.
pub struct Source {
    /// The `--source` the bridge is told.
    pub source: &'static str,
    pub name: &'static str,
    /// Relative to the user's home.
    pub path: &'static str,
    /// The directory whose presence means the CLI is installed.
    pub directory: &'static str,
    pub shape: Shape,
    /// Event names with their timeouts, in the order they are written.
    pub events: &'static [(&'static str, i64)],
}

/// Hermes: a map of snake_case events to a list of hooks, timeouts in seconds.
const HERMES: Source = Source {
    source: "hermes",
    name: "Hermes",
    path: ".hermes/config.yaml",
    directory: ".hermes",
    shape: Shape::EventMap,
    events: &[
        ("pre_tool_call", 5),
        ("post_tool_call", 5),
        // The prompt, so the card shows what is being worked on before the
        // first tool call.
        ("pre_llm_call", 5),
        ("post_llm_call", 5),
        ("on_session_start", 5),
        ("on_session_end", 5),
        ("on_session_finalize", 5),
        ("subagent_stop", 5),
    ],
};

/// TraeCli: one list item whose `matchers` name every event. The longest
/// timeout of the set is the item's own (`86400s`, the permission request).
const TRAECLI: Source = Source {
    source: "traecli",
    name: "Trae CLI",
    path: ".trae/traecli.yaml",
    directory: ".trae",
    shape: Shape::MatchList,
    events: &[
        ("session_start", 5),
        ("session_end", 5),
        ("user_prompt_submit", 5),
        ("pre_tool_use", 5),
        ("post_tool_use", 5),
        ("post_tool_use_failure", 5),
        ("permission_request", 86_400),
        ("notification", 86_400),
        ("subagent_start", 5),
        ("subagent_stop", 5),
        ("stop", 5),
        ("pre_compact", 5),
        ("post_compact", 5),
    ],
};

pub const SOURCES: &[Source] = &[HERMES, TRAECLI];

/// The first fence line of our region.
pub const FENCE_OPEN: &str = "# >>> morrow hooks (managed by Morrow; edits inside are overwritten)";
/// The closing fence.
pub const FENCE_CLOSE: &str = "# <<< morrow hooks";

pub fn source_for(source: &str) -> Option<&'static Source> {
    SOURCES.iter().find(|target| target.source == source)
}

/// Why a file was not written.
#[derive(Debug, PartialEq, Eq)]
pub enum Refusal {
    /// `hooks:` carries an inline value we would have to rewrite: a user's
    /// `{}` or `[]` is easy, anything else is a layout to leave alone.
    InlineHooks(String),
    /// Indentation by tab. YAML forbids it; a file like that is not one we can
    /// append to safely.
    TabIndentation,
    /// `hooks:` is nested (not at the top level), so ours would not be read.
    NestedHooks,
}

/// Whether our region is already there.
pub fn is_installed(source: &Source, existing: &str) -> bool {
    existing.lines().any(|line| line.trim() == FENCE_OPEN)
        && existing
            .lines()
            .any(|line| line.trim().contains(&marker(source)))
}

/// The document with our region in it, or the refusal that kept it out.
pub fn install(source: &Source, existing: &str, bridge: &str) -> Result<String, Refusal> {
    let cleaned = strip_region(existing);
    let mut lines: Vec<String> = cleaned.split('\n').map(str::to_owned).collect();
    if has_tab_indentation(&lines) {
        return Err(Refusal::TabIndentation);
    }

    let block = render(source, bridge);
    match find_hooks(&lines)? {
        Hooks::Line(index, indent) => {
            if indent > 0 {
                return Err(Refusal::NestedHooks);
            }
            // An empty `hooks:` on its own line takes our block beneath it.
            lines.splice(index + 1..index + 1, block);
        }
        Hooks::EmptyInline(index) => {
            lines[index] = "hooks:".to_owned();
            lines.splice(index + 1..index + 1, block);
        }
        Hooks::Absent => {
            while lines.last().is_some_and(|line| line.is_empty()) {
                lines.pop();
            }
            if !lines.is_empty() && !lines.last().is_some_and(|line| line.trim().is_empty()) {
                lines.push(String::new());
            }
            lines.push("hooks:".to_owned());
            lines.extend(block);
        }
    }

    let mut text = lines.join("\n");
    if !text.ends_with('\n') {
        text.push('\n');
    }
    Ok(text)
}

/// The document without our region. A `hooks:` line we introduced goes too;
/// one the user wrote stays, even when it ends up empty.
pub fn remove(existing: &str) -> String {
    let cleaned = strip_region(existing);
    let mut lines: Vec<String> = cleaned.split('\n').map(str::to_owned).collect();

    // `hooks:` followed by nothing is a key we created: YAML reads it as null,
    // which is not what the user had before we touched the file.
    if let Some(index) = lines.iter().position(|line| line.trim() == "hooks:") {
        let rest = lines[index + 1..]
            .iter()
            .filter(|line| !line.trim().is_empty())
            .count();
        if rest == 0 {
            lines.remove(index);
            while lines.last().is_some_and(|line| line.is_empty()) {
                lines.pop();
            }
        }
    }
    let mut text = lines.join("\n");
    // Give back the file's own final newline, if it had one.
    if existing.ends_with('\n') && !text.ends_with('\n') {
        text.push('\n');
    }
    text
}

// MARK: - Looking for `hooks:`

enum Hooks {
    /// A top-level `hooks:` with nothing after the colon.
    Line(usize, usize),
    /// `hooks: {}`, `hooks: []`, `hooks: null` or `hooks: ~`.
    EmptyInline(usize),
    Absent,
}

fn find_hooks(lines: &[String]) -> Result<Hooks, Refusal> {
    for (index, line) in lines.iter().enumerate() {
        let trimmed = line.trim_end();
        if trimmed.trim().is_empty() || trimmed.trim_start().starts_with('#') {
            continue;
        }
        let indent = trimmed.len() - trimmed.trim_start().len();
        let body = trimmed.trim_start();
        let Some(rest) = body.strip_prefix("hooks:") else {
            continue;
        };
        // `hookstore:` and friends are not the key.
        if !(rest.is_empty() || rest.starts_with(' ') || rest.starts_with('\t')) {
            continue;
        }
        let value = strip_comment(rest).trim().to_owned();
        if indent > 0 {
            return Err(Refusal::NestedHooks);
        }
        if value.is_empty() {
            return Ok(Hooks::Line(index, indent));
        }
        return match value.as_str() {
            "{}" | "[]" | "null" | "~" => Ok(Hooks::EmptyInline(index)),
            _ => Err(Refusal::InlineHooks(value)),
        };
    }
    Ok(Hooks::Absent)
}

fn strip_comment(text: &str) -> &str {
    match text.find('#') {
        Some(index) if index == 0 || text[..index].ends_with(' ') => &text[..index],
        _ => text,
    }
}

fn has_tab_indentation(lines: &[String]) -> bool {
    lines
        .iter()
        .any(|line| line.starts_with('\t') || line.trim_start_matches(' ').starts_with('\t'))
}

// MARK: - Our region

fn marker(source: &Source) -> String {
    format!("--source {}", source.source)
}

fn render(source: &Source, bridge: &str) -> Vec<String> {
    let bridge = if bridge.contains(char::is_whitespace) {
        format!("\"{bridge}\"")
    } else {
        bridge.to_owned()
    };
    let mut lines = vec![FENCE_OPEN.to_owned()];
    match source.shape {
        Shape::EventMap => {
            for (event, timeout) in source.events {
                lines.push(format!("{event}:"));
                lines.push(format!(
                    "  - command: '{bridge} --source {}'",
                    source.source
                ));
                lines.push(format!("    timeout: {timeout}"));
            }
        }
        Shape::MatchList => {
            let timeout = source
                .events
                .iter()
                .map(|(_, timeout)| *timeout)
                .max()
                .unwrap_or(5);
            lines.push("  - type: command".to_owned());
            lines.push(format!(
                "    command: '{bridge} --source {}'",
                source.source
            ));
            lines.push(format!("    timeout: '{timeout}s'"));
            lines.push("    matchers:".to_owned());
            for (event, _) in source.events {
                lines.push(format!("      - event: {event}"));
            }
        }
    }
    lines.push(FENCE_CLOSE.to_owned());
    lines
}

/// Drop our fenced region, fences included. The fence lines are ours by
/// construction: no other tool writes that comment, and we are the only writer
/// of the block between them.
fn strip_region(existing: &str) -> String {
    let mut kept: Vec<&str> = Vec::new();
    let mut inside = false;
    for line in existing.split('\n') {
        let trimmed = line.trim();
        if trimmed == FENCE_OPEN {
            inside = true;
            continue;
        }
        if trimmed == FENCE_CLOSE {
            inside = false;
            continue;
        }
        if !inside {
            kept.push(line);
        }
    }
    let mut text = kept.join("\n");
    while text.ends_with("\n\n") {
        text.pop();
    }
    text
}
