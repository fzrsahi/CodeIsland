//! The Claude Code slice of `ConfigInstallerTests`
//! (`macos/Tests/MorrowTests/ConfigInstallerTests.swift`), and the install/repair/
//! uninstall properties #98 asks for, checked over text instead of a file
//! system.

use serde_json::{Value, json};

use morrow_core::installer::claude_hooks::{
    CLAUDE_EVENTS, HOOK_COMMAND, HOOKS_KEY, InstallOutcome, UninstallOutcome, backup_path,
    events_for_version, has_stale_async_key, install, is_ours, remove_managed_entries, uninstall,
    version_at_least,
};
use morrow_core::installer::json_editor::strip_json_comments;

/// The file is JSONC: comments are the user's, and they stay.
fn parsed(text: &str) -> Value {
    serde_json::from_str(&strip_json_comments(text)).expect("valid JSON")
}

fn hooks_of(text: &str) -> Value {
    parsed(text)[HOOKS_KEY].clone()
}

fn event_names(text: &str) -> Vec<String> {
    hooks_of(text)
        .as_object()
        .map(|hooks| hooks.keys().cloned().collect())
        .unwrap_or_default()
}

fn installed(version: Option<&str>) -> InstallOutcome {
    install(None, HOOK_COMMAND, version).expect("a fresh file installs")
}

// MARK: - The table

#[test]
fn the_table_is_the_claude_entry_of_built_in_clis() {
    let names: Vec<&str> = CLAUDE_EVENTS.iter().map(|event| event.name).collect();
    assert_eq!(
        names,
        [
            "UserPromptSubmit",
            "PreToolUse",
            "PostToolUse",
            "PostToolUseFailure",
            "PermissionRequest",
            "Stop",
            "StopFailure",
            "SubagentStart",
            "SubagentStop",
            "SessionStart",
            "SessionEnd",
            "Notification",
            "PreCompact",
        ]
    );
    // The events that wait on the user keep their day-long timeout.
    let permission = CLAUDE_EVENTS
        .iter()
        .find(|event| event.name == "PermissionRequest")
        .expect("PermissionRequest");
    assert_eq!(permission.timeout, 86_400);
}

#[test]
fn a_version_gate_skips_events_the_build_does_not_know() {
    // No version at all: both gated events stay out.
    let unknown: Vec<&str> = events_for_version(None)
        .iter()
        .map(|event| event.name)
        .collect();
    assert!(!unknown.contains(&"PostToolUseFailure"));
    assert!(!unknown.contains(&"StopFailure"));
    assert!(unknown.contains(&"PreToolUse"));

    // 2.1.80 knows StopFailure (2.1.78) but not PostToolUseFailure (2.1.89).
    let old: Vec<&str> = events_for_version(Some("2.1.80"))
        .iter()
        .map(|event| event.name)
        .collect();
    assert!(old.contains(&"StopFailure"));
    assert!(!old.contains(&"PostToolUseFailure"));

    let current: Vec<&str> = events_for_version(Some("2.1.89"))
        .iter()
        .map(|event| event.name)
        .collect();
    assert!(current.contains(&"PostToolUseFailure"));
    assert_eq!(current.len(), CLAUDE_EVENTS.len());
}

#[test]
fn version_comparison_is_component_wise() {
    assert!(version_at_least("2.1.89", "2.1.89"));
    assert!(version_at_least("2.2", "2.1.89"));
    assert!(version_at_least("3", "2.9.9"));
    assert!(!version_at_least("2.1.88", "2.1.89"));
    assert!(!version_at_least("2.0.99", "2.1"));
    assert!(version_at_least("1.0", "1"));
}

// MARK: - Recognition

#[test]
fn our_own_names_are_recognised_legacy_ones_included() {
    assert!(is_ours("~/.codeisland/codeisland-hook.sh"));
    assert!(is_ours(
        "/Applications/CodeIsland.app/Contents/MacOS/codeisland-bridge"
    ));
    assert!(is_ours(
        "~/.vibe-island/bin/vibe-island-bridge --source claude"
    ));
    assert!(is_ours("~/.vibenotch/bin/bridge"));
    assert!(is_ours("VibeIsland"));
    assert!(!is_ours("~/.claude/hooks/bark-notify.sh"));
    assert!(!is_ours("notify-send done"));
}

#[test]
fn remove_managed_hook_entries_also_prunes_legacy_vibe_island_hooks() {
    let hooks = json!({
        "SessionEnd": [
            {
                "hooks": [{
                    "command": "/Users/test/.vibe-island/bin/vibe-island-bridge --source claude",
                    "type": "command",
                }],
            },
            {
                "matcher": "",
                "hooks": [{
                    "command": "~/.claude/hooks/codeisland-hook.sh",
                    "timeout": 5,
                    "type": "command",
                }],
            },
            {
                "matcher": "",
                "hooks": [{
                    "async": true,
                    "command": "~/.claude/hooks/bark-notify.sh",
                    "timeout": 10,
                    "type": "command",
                }],
            },
        ],
    });

    let cleaned = remove_managed_entries(hooks.as_object().unwrap());
    let session_end = cleaned["SessionEnd"].as_array().expect("SessionEnd");
    assert_eq!(session_end.len(), 1);
    let remaining = session_end[0]["hooks"].as_array().expect("hooks");
    assert_eq!(remaining.len(), 1);
    assert_eq!(
        remaining[0]["command"],
        json!("~/.claude/hooks/bark-notify.sh")
    );
}

#[test]
fn an_event_left_with_no_entries_disappears() {
    let hooks = json!({
        "Stop": [{"matcher": "", "hooks": [{"command": HOOK_COMMAND, "type": "command"}]}],
        "SessionEnd": [],
    });
    let cleaned = remove_managed_entries(hooks.as_object().unwrap());
    assert!(cleaned.is_empty(), "{cleaned:?}");
}

// MARK: - Install

#[test]
fn a_fresh_file_gets_every_event_under_its_own_hook() {
    let outcome = installed(Some("2.1.89"));
    assert!(outcome.changed);
    assert_eq!(event_names(&outcome.text).len(), CLAUDE_EVENTS.len());

    let hooks = hooks_of(&outcome.text);
    let pretool = &hooks["PreToolUse"][0];
    assert_eq!(pretool["matcher"], json!(""));
    assert_eq!(pretool["hooks"][0]["type"], json!("command"));
    assert_eq!(pretool["hooks"][0]["command"], json!(HOOK_COMMAND));
    assert_eq!(pretool["hooks"][0]["timeout"], json!(5));
    assert_eq!(
        hooks["PermissionRequest"][0]["hooks"][0]["timeout"],
        json!(86_400)
    );
    // The `async` planning flag is never written.
    assert!(pretool["hooks"][0].get("async").is_none());
}

#[test]
fn installing_twice_changes_nothing_the_second_time() {
    let first = installed(Some("2.1.89"));
    let second = install(Some(&first.text), HOOK_COMMAND, Some("2.1.89")).expect("reinstall");
    assert!(!second.changed);
    assert_eq!(second.text, first.text, "byte for byte");
}

#[test]
fn install_keeps_the_users_own_hooks_and_their_comments() {
    let original = r#"{
  // my settings
  "model": "sonnet",
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "notify-send x"}]}
    ]
  },
  "autoshare": false
}"#;
    let outcome = install(Some(original), HOOK_COMMAND, Some("2.1.89")).expect("install");
    assert!(outcome.changed);
    assert!(outcome.text.contains("// my settings"));
    assert!(outcome.text.contains("\"autoshare\": false"));
    assert!(
        outcome.text.contains("notify-send x"),
        "the user's hook stays"
    );

    // Their entry is still first in PreToolUse; ours was appended.
    let hooks = hooks_of(&outcome.text);
    let pretool = hooks["PreToolUse"].as_array().expect("PreToolUse");
    assert_eq!(pretool.len(), 2);
    assert_eq!(pretool[0]["matcher"], json!("Bash"));
    assert_eq!(pretool[1]["matcher"], json!(""));
}

#[test]
fn a_stale_async_key_is_repaired() {
    let original = format!(
        r#"{{
  "hooks": {{
    "PreToolUse": [
      {{"matcher": "", "hooks": [{{"type": "command", "command": "{HOOK_COMMAND}", "timeout": 5, "async": true}}]}}
    ]
  }}
}}"#
    );
    let hooks = hooks_of(&original);
    assert!(has_stale_async_key(hooks.as_object().unwrap()));

    let outcome = install(Some(&original), HOOK_COMMAND, Some("2.1.89")).expect("repair");
    assert!(outcome.changed);
    assert!(!outcome.text.contains("\"async\""), "{}", outcome.text);
    assert!(!has_stale_async_key(
        hooks_of(&outcome.text).as_object().unwrap()
    ));
    // Repair replaces our entry rather than stacking another one.
    assert_eq!(
        hooks_of(&outcome.text)["PreToolUse"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
}

#[test]
fn a_file_that_does_not_parse_is_never_touched() {
    assert!(install(Some("{ \"hooks\": ["), HOOK_COMMAND, Some("2.1.89")).is_none());
    assert!(install(Some("[1, 2, 3]"), HOOK_COMMAND, Some("2.1.89")).is_none());
    assert!(install(Some("{ \"a\": 1,"), HOOK_COMMAND, Some("2.1.89")).is_none());
}

#[test]
fn an_empty_file_is_treated_as_an_empty_object() {
    let outcome = install(Some(""), HOOK_COMMAND, Some("2.1.89")).expect("install");
    assert!(outcome.changed);
    assert_eq!(event_names(&outcome.text).len(), CLAUDE_EVENTS.len());
}

#[test]
fn an_older_build_only_gets_the_events_it_knows() {
    let outcome = installed(Some("2.1.80"));
    let names = event_names(&outcome.text);
    assert!(names.contains(&"StopFailure".to_owned()));
    assert!(!names.contains(&"PostToolUseFailure".to_owned()));
    assert_eq!(names.len(), CLAUDE_EVENTS.len() - 1);
}

// MARK: - Uninstall

fn uninstalled(text: &str) -> UninstallOutcome {
    uninstall(text).expect("uninstall")
}

#[test]
fn uninstall_gives_back_the_original_bytes() {
    let original = "{\n  \"model\": \"sonnet\"\n}\n";
    let outcome = install(Some(original), HOOK_COMMAND, Some("2.1.89")).expect("install");
    let back = uninstalled(&outcome.text);
    assert!(back.changed);
    assert_eq!(back.text, original, "byte for byte");
}

#[test]
fn uninstall_keeps_a_users_own_hooks() {
    let original = r#"{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "notify-send x"}]}
    ]
  }
}"#;
    let outcome = install(Some(original), HOOK_COMMAND, Some("2.1.89")).expect("install");
    let back = uninstalled(&outcome.text);
    let hooks = hooks_of(&back.text);
    assert_eq!(hooks.as_object().unwrap().len(), 1);
    let pretool = hooks["PreToolUse"].as_array().unwrap();
    assert_eq!(pretool.len(), 1);
    assert_eq!(pretool[0]["matcher"], json!("Bash"));
}

#[test]
fn uninstall_of_a_file_with_nothing_of_ours_changes_nothing() {
    let original = "{\n  \"model\": \"sonnet\"\n}";
    let back = uninstalled(original);
    assert!(!back.changed);
    assert_eq!(back.text, original);
}

#[test]
fn uninstall_of_an_unparseable_file_does_nothing() {
    assert!(uninstall("{ not json").is_none());
    assert!(uninstall("[]").is_none());
}

// MARK: - Back-up

#[test]
fn a_back_up_is_made_once_and_never_again() {
    let path = "/home/u/.claude/settings.json";
    assert_eq!(
        backup_path(path, "2026-11-20T10:00:00Z", &[]),
        Some(format!("{path}.codeisland.bak.2026-11-20T10:00:00Z"))
    );
    let existing = vec![
        "settings.json".to_owned(),
        "settings.json.codeisland.bak.2026-11-19T08:00:00Z".to_owned(),
    ];
    assert_eq!(backup_path(path, "2026-11-20T10:00:00Z", &existing), None);
    // Someone else's back-up is not ours to count.
    let foreign = vec!["settings.json.bak".to_owned()];
    assert!(
        backup_path(path, "2026-11-20T10:00:00Z", &foreign).is_some(),
        "only our own back-ups stop a new one"
    );
}
