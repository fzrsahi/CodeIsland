//! The other hook targets (`ConfigInstallerTests`' external-CLI cases, and the
//! install/repair/uninstall shape #99 asks for), over text instead of a file
//! system.

use serde_json::Value;

use morrow_core::installer::json_editor::strip_json_comments;
use morrow_core::installer::targets::{
    Format, TARGETS, command_for, install, is_installed, target_for, uninstall,
};

const BRIDGE: &str = "~/.codeisland/codeisland-hook.sh";

fn parsed(text: &str) -> Value {
    serde_json::from_str(&strip_json_comments(text)).expect("valid JSON")
}

fn target(source: &str) -> &'static morrow_core::installer::targets::Target {
    target_for(source).unwrap_or_else(|| panic!("no target {source}"))
}

fn event_names(text: &str, key: &str) -> Vec<String> {
    parsed(text)[key]
        .as_object()
        .map(|hooks| hooks.keys().cloned().collect())
        .unwrap_or_default()
}

// MARK: - The table

#[test]
fn every_target_of_the_ticket_is_here() {
    let sources: Vec<&str> = TARGETS.iter().map(|target| target.source).collect();
    assert_eq!(
        sources,
        [
            "codex",
            "gemini",
            "cursor",
            "qoder",
            "droid",
            "codebuddy",
            "copilot"
        ]
    );
    // OpenCode is a plugin file, not a hooks key: its own slice.
    assert!(target_for("opencode").is_none());
}

#[test]
fn the_paths_and_keys_are_the_ones_macos_writes() {
    assert_eq!(target("codex").path, ".codex/hooks.json");
    assert_eq!(target("gemini").path, ".gemini/settings.json");
    assert_eq!(target("cursor").path, ".cursor/hooks.json");
    assert_eq!(target("qoder").path, ".qoder/settings.json");
    assert_eq!(target("droid").path, ".factory/settings.json");
    assert_eq!(target("codebuddy").path, ".codebuddy/settings.json");
    assert_eq!(target("copilot").path, ".copilot/hooks/codeisland.json");
    for target in TARGETS {
        assert_eq!(target.key, "hooks");
    }
}

#[test]
fn each_target_keeps_its_own_format_and_event_names() {
    assert_eq!(target("codex").format, Format::Nested);
    assert_eq!(target("gemini").format, Format::Nested);
    assert_eq!(target("cursor").format, Format::Flat);
    assert_eq!(target("qoder").format, Format::Claude);
    assert_eq!(target("droid").format, Format::Claude);
    assert_eq!(target("codebuddy").format, Format::Claude);
    assert_eq!(target("copilot").format, Format::Copilot);

    let gemini: Vec<&str> = target("gemini")
        .events
        .iter()
        .map(|event| event.name)
        .collect();
    assert_eq!(
        gemini,
        [
            "SessionStart",
            "SessionEnd",
            "BeforeTool",
            "AfterTool",
            "BeforeAgent",
            "AfterAgent"
        ]
    );
    // Gemini counts milliseconds: a day is 86_400_000, not 86_400.
    let before_tool = target("gemini")
        .events
        .iter()
        .find(|event| event.name == "BeforeTool")
        .expect("BeforeTool");
    assert_eq!(before_tool.timeout, 86_400_000);

    let copilot: Vec<&str> = target("copilot")
        .events
        .iter()
        .map(|event| event.name)
        .collect();
    assert_eq!(
        copilot,
        [
            "sessionStart",
            "sessionEnd",
            "userPromptSubmitted",
            "preToolUse",
            "postToolUse",
            "errorOccurred"
        ]
    );
}

// MARK: - Commands

#[test]
fn the_event_rides_on_the_command_only_where_stdin_lacks_it() {
    let cursor = target("cursor");
    assert_eq!(
        command_for(cursor, BRIDGE, "beforeSubmitPrompt"),
        "~/.codeisland/codeisland-hook.sh --source cursor --event beforeSubmitPrompt"
    );
    // Codex reports the event itself.
    assert_eq!(
        command_for(target("codex"), BRIDGE, "PreToolUse"),
        "~/.codeisland/codeisland-hook.sh --source codex"
    );
    // Gemini does not, so it gets the flag too.
    assert_eq!(
        command_for(target("gemini"), BRIDGE, "BeforeTool"),
        "~/.codeisland/codeisland-hook.sh --source gemini --event BeforeTool"
    );
    // Copilot neither.
    assert_eq!(
        command_for(target("copilot"), BRIDGE, "preToolUse"),
        "~/.codeisland/codeisland-hook.sh --source copilot --event preToolUse"
    );
    // A home with a space quotes the script, not the flags.
    assert_eq!(
        command_for(
            target("codex"),
            "/home/a b/.codeisland/codeisland-hook.sh",
            "Stop"
        ),
        "\"/home/a b/.codeisland/codeisland-hook.sh\" --source codex"
    );
}

// MARK: - Install, per format

#[test]
fn a_claude_format_fork_gets_the_matcher_wrapper_and_a_timeout() {
    let qoder = target("qoder");
    let outcome = install(qoder, None, BRIDGE).expect("install");
    assert!(outcome.changed);
    let entry = &parsed(&outcome.text)["hooks"]["PermissionRequest"][0];
    assert_eq!(entry["matcher"], Value::from("*"));
    assert_eq!(entry["hooks"][0]["type"], Value::from("command"));
    assert_eq!(entry["hooks"][0]["timeout"], Value::from(86_400));
    assert_eq!(
        entry["hooks"][0]["command"],
        Value::from("~/.codeisland/codeisland-hook.sh --source qoder")
    );
}

#[test]
fn a_nested_target_gets_no_matcher() {
    let codex = target("codex");
    let outcome = install(codex, None, BRIDGE).expect("install");
    let entry = &parsed(&outcome.text)["hooks"]["PreToolUse"][0];
    assert!(entry.get("matcher").is_none(), "{entry}");
    assert_eq!(entry["hooks"][0]["timeout"], Value::from(5));
    // SessionEnd is the 3-second one.
    let session_end = &parsed(&outcome.text)["hooks"]["SessionEnd"][0];
    assert_eq!(session_end["hooks"][0]["timeout"], Value::from(3));
}

#[test]
fn a_flat_target_gets_a_bare_command() {
    let cursor = target("cursor");
    let outcome = install(cursor, None, BRIDGE).expect("install");
    let hooks = &parsed(&outcome.text)["hooks"];
    let entry = &hooks["beforeShellExecution"][0];
    assert_eq!(
        entry,
        &parsed(
            r#"{"command":"~/.codeisland/codeisland-hook.sh --source cursor --event beforeShellExecution"}"#
        )
    );
}

#[test]
fn copilot_gets_bash_and_a_seeded_version() {
    let copilot = target("copilot");
    let outcome = install(copilot, None, BRIDGE).expect("install");
    let document = parsed(&outcome.text);
    assert_eq!(document["version"], Value::from(1));
    let entry = &document["hooks"]["preToolUse"][0];
    assert_eq!(entry["type"], Value::from("command"));
    assert_eq!(entry["timeoutSec"], Value::from(5));
    assert_eq!(
        entry["bash"],
        Value::from("~/.codeisland/codeisland-hook.sh --source copilot --event preToolUse")
    );
}

#[test]
fn a_version_the_user_set_is_left_alone() {
    let copilot = target("copilot");
    let original = "{\n  \"version\": 2\n}\n";
    let outcome = install(copilot, Some(original), BRIDGE).expect("install");
    assert_eq!(
        parsed(&outcome.text)["version"],
        Value::from(2),
        "no downgrade"
    );
}

#[test]
fn installing_twice_changes_nothing_the_second_time() {
    for target in TARGETS {
        let first = install(target, None, BRIDGE).expect("install");
        let second = install(target, Some(&first.text), BRIDGE).expect("reinstall");
        assert!(!second.changed, "{} reinstalled", target.source);
        assert_eq!(second.text, first.text, "{} byte for byte", target.source);
        assert!(is_installed(target, &first.text), "{}", target.source);
    }
}

#[test]
fn json5_comments_and_the_users_own_entries_survive() {
    let cursor = target("cursor");
    let original = r#"{
  // my own hook
  "hooks": {
    "beforeSubmitPrompt": [
      {"command": "notify-send worked"}
    ]
  },
  "telemetry": false
}"#;
    let outcome = install(cursor, Some(original), BRIDGE).expect("install");
    assert!(outcome.text.contains("// my own hook"));
    assert!(outcome.text.contains("\"telemetry\": false"));
    assert!(outcome.text.contains("notify-send worked"));
    let entries = parsed(&outcome.text)["hooks"]["beforeSubmitPrompt"]
        .as_array()
        .cloned()
        .unwrap();
    assert_eq!(entries.len(), 2, "the user's entry stays, ours is appended");
    assert_eq!(entries[0]["command"], Value::from("notify-send worked"));
}

#[test]
fn a_file_that_does_not_parse_is_never_touched() {
    for target in TARGETS {
        assert!(install(target, Some("{ \"hooks\": ["), BRIDGE).is_none());
        assert!(install(target, Some("[1, 2, 3]"), BRIDGE).is_none());
        assert!(uninstall(target, "{ nope").is_none());
    }
}

#[test]
fn a_stale_entry_is_repaired_rather_than_stacked() {
    let codex = target("codex");
    // An entry from an older build: right command, missing timeout.
    let original = r#"{
  "hooks": {
    "PreToolUse": [
      {"hooks": [{"type": "command", "command": "~/.codeisland/codeisland-hook.sh --source codex"}]}
    ]
  }
}"#;
    assert!(
        !is_installed(codex, original),
        "the other events are missing"
    );
    let outcome = install(codex, Some(original), BRIDGE).expect("repair");
    let entries = parsed(&outcome.text)["hooks"]["PreToolUse"]
        .as_array()
        .cloned()
        .unwrap();
    assert_eq!(entries.len(), 1, "the stale one is replaced, not kept");
    assert_eq!(entries[0]["hooks"][0]["timeout"], Value::from(5));
}

// MARK: - Uninstall

#[test]
fn uninstall_gives_the_original_bytes_back() {
    for target in TARGETS {
        // Copilot keeps the `version` we seeded: `uninstallHooks` removes hook
        // entries, not the schema key.
        if target.seeds_version {
            continue;
        }
        for original in ["{\n  \"model\": \"x\"\n}\n", "{}\n"] {
            let outcome = install(target, Some(original), BRIDGE).expect("install");
            let back = uninstall(target, &outcome.text).expect("uninstall");
            assert_eq!(back.text, original, "{} from {original}", target.source);
            assert!(back.changed, "{}", target.source);
        }
    }
}

#[test]
fn copilot_keeps_its_seeded_version_after_uninstall() {
    let copilot = target("copilot");
    let original = "{\n  \"model\": \"x\"\n}\n";
    let outcome = install(copilot, Some(original), BRIDGE).expect("install");
    let back = uninstall(copilot, &outcome.text).expect("uninstall");
    let document = parsed(&back.text);
    assert_eq!(document["version"], Value::from(1));
    assert!(
        document.get("hooks").is_none(),
        "{back_text}",
        back_text = back.text
    );
}

#[test]
fn an_empty_hooks_key_is_deleted_rather_than_left_behind() {
    // Swift's `uninstallHooks` deletes an emptied key, so a file whose `hooks`
    // was an empty object comes back as `{}` — not as it was. Nothing of the
    // user's is lost: an empty object held nothing.
    let codex = target("codex");
    let original = "{\n  \"hooks\": {}\n}\n";
    let outcome = install(codex, Some(original), BRIDGE).expect("install");
    let back = uninstall(codex, &outcome.text).expect("uninstall");
    assert_eq!(back.text, "{}\n");
}

#[test]
fn uninstall_keeps_a_users_own_hooks() {
    let gemini = target("gemini");
    let original = r#"{
  "hooks": {
    "BeforeTool": [
      {"hooks": [{"type": "command", "command": "echo mine", "timeout": 1}]}
    ]
  }
}"#;
    let outcome = install(gemini, Some(original), BRIDGE).expect("install");
    let back = uninstall(gemini, &outcome.text).expect("uninstall");
    let entries = parsed(&back.text)["hooks"]["BeforeTool"]
        .as_array()
        .cloned()
        .unwrap();
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0]["hooks"][0]["command"], Value::from("echo mine"));
}

#[test]
fn uninstall_of_a_file_with_nothing_of_ours_changes_nothing() {
    for target in TARGETS {
        let original = "{\n  \"model\": \"x\"\n}";
        let outcome = uninstall(target, original).expect("uninstall");
        assert!(!outcome.changed, "{}", target.source);
        assert_eq!(outcome.text, original);
    }
}

#[test]
fn every_event_of_a_target_lands() {
    for target in TARGETS {
        let outcome = install(target, None, BRIDGE).expect("install");
        let names = event_names(&outcome.text, target.key);
        assert_eq!(names.len(), target.events.len(), "{}", target.source);
        assert!(is_installed(target, &outcome.text), "{}", target.source);
    }
}
