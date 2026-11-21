//! Kimi Code CLI's hooks, in `config.toml` (`installKimiHooks` /
//! `removeKimiHooks`).
//!
//! Kimi reads an array of `[[hooks]]` tables. The file is the user's — it may
//! hold models, prompts and comments — so this never re-serialises it: our
//! blocks are appended, and on uninstall exactly those blocks are cut out and
//! the blank line they were given back. A legacy scalar `hooks = …` is
//! commented out rather than deleted, so uninstall can restore it.

/// The `--source` the bridge is told.
pub const SOURCE: &str = "kimi";

/// Every event Morrow registers, in order (`defaultEvents(for: .kimi)`). Kimi
/// caps a timeout at 600 and has no `PermissionRequest` event.
pub const EVENTS: &[(&str, i64)] = &[
    ("UserPromptSubmit", 5),
    ("PreToolUse", 5),
    ("PostToolUse", 5),
    ("PostToolUseFailure", 5),
    ("Stop", 5),
    ("SubagentStart", 5),
    ("SubagentStop", 5),
    ("SessionStart", 5),
    ("SessionEnd", 5),
    ("Notification", 600),
    ("PreCompact", 5),
];

/// The events whose table carries a matcher (a tool name, `.*` for all).
const MATCHED: &[&str] = &["PreToolUse", "PostToolUse", "PostToolUseFailure"];

/// What marks a `[[hooks]]` block as ours. The command names the script, and
/// the script's name is the app's (`codeisland`), which is also how the legacy
/// names are caught.
const MARKER: &str = "codeisland";

/// The comment we put in front of a legacy scalar `hooks = …`.
const LEGACY_COMMENT: &str =
    "# [CodeIsland] commented out legacy scalar hooks to avoid TOML conflict";

/// Whether the document already carries our blocks.
pub fn is_installed(existing: &str) -> bool {
    blocks(existing).iter().any(|block| block.contains(MARKER))
}

/// The document with our blocks appended, or the same text when they are
/// already all there.
pub fn install(existing: &str, command: &str) -> String {
    let command = if command.contains(char::is_whitespace) {
        format!("\"{command}\"")
    } else {
        command.to_owned()
    };
    let base = format!("{command} --source {SOURCE}");

    let wanted: Vec<String> = EVENTS
        .iter()
        .map(|(event, timeout)| {
            let mut block = format!(
                "[[hooks]]\nevent = \"{event}\"\ncommand = \"{base}\"\ntimeout = {timeout}"
            );
            if MATCHED.contains(event) {
                block.push_str("\nmatcher = \".*\"");
            }
            block
        })
        .collect();

    let cleaned = remove(existing);
    if blocks(&cleaned).iter().any(|block| block.contains(&base))
        && wanted.iter().all(|block| {
            blocks(&cleaned)
                .iter()
                .any(|existing| existing.trim() == block.trim())
        })
    {
        return cleaned;
    }
    // A legacy scalar `hooks = …` cannot live beside array-of-tables, but it is
    // the user's: comment it out, so uninstall can put it back.
    let cleaned = cleaned
        .split('\n')
        .map(|line| {
            if line.trim_start().starts_with("hooks =") {
                format!("{LEGACY_COMMENT}\n# {line}")
            } else {
                line.to_owned()
            }
        })
        .collect::<Vec<_>>()
        .join("\n");

    let mut text = cleaned;
    if !text.is_empty() && !text.ends_with('\n') {
        text.push('\n');
    }
    if !text.is_empty() {
        text.push('\n');
    }
    text + &wanted.join("\n\n") + "\n"
}

/// The document without our blocks, a legacy scalar restored.
pub fn remove(existing: &str) -> String {
    let lines: Vec<&str> = existing.split('\n').collect();
    let mut kept: Vec<String> = Vec::new();
    let mut i = 0;
    while i < lines.len() {
        let line = lines[i];
        if line.trim() == "[[hooks]]" {
            let mut block = vec![line];
            let mut j = i + 1;
            while j < lines.len() {
                let trimmed = lines[j].trim();
                if trimmed.starts_with("[[") || trimmed.starts_with('[') {
                    break;
                }
                block.push(lines[j]);
                j += 1;
            }
            let text = block.join("\n");
            if !text.contains(MARKER) {
                kept.extend(block.iter().map(|line| (*line).to_owned()));
            }
            i = j;
        } else {
            kept.push(line.to_owned());
            i += 1;
        }
    }

    // Our legacy comment goes, and the line it holds comes back uncommented.
    let mut restored: Vec<String> = Vec::new();
    let mut index = 0;
    while index < kept.len() {
        if kept[index].trim() == LEGACY_COMMENT {
            if let Some(next) = kept.get(index + 1) {
                restored.push(next.strip_prefix('#').unwrap_or(next).to_owned());
            }
            index += 2;
            continue;
        }
        restored.push(kept[index].clone());
        index += 1;
    }

    while restored.last().is_some_and(|line| line.trim().is_empty()) {
        restored.pop();
    }
    restored.join("\n")
}

/// The `[[hooks]]` blocks of a document, trimmed.
fn blocks(existing: &str) -> Vec<String> {
    let mut blocks: Vec<String> = Vec::new();
    let mut current: Option<Vec<&str>> = None;
    for line in existing.split('\n') {
        let trimmed = line.trim();
        if trimmed == "[[hooks]]" {
            if let Some(block) = current.take() {
                blocks.push(block.join("\n"));
            }
            current = Some(vec![line]);
            continue;
        }
        if trimmed.starts_with("[[") || trimmed.starts_with('[') {
            if let Some(block) = current.take() {
                blocks.push(block.join("\n"));
            }
            continue;
        }
        if let Some(block) = current.as_mut() {
            block.push(line);
        }
    }
    if let Some(block) = current {
        blocks.push(block.join("\n"));
    }
    blocks
}
