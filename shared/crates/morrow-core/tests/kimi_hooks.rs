//! `ConfigInstallerTests`' Kimi cases (`removeKimiHooks`,
//! `contentsContainsKimiHook`) plus the install/restore properties #100 asks for.

use morrow_core::installer::kimi::{EVENTS, install, is_installed, remove};

const COMMAND: &str = "~/.codeisland/codeisland-hook.sh";

#[test]
fn removal_preserves_every_other_block() {
    let toml = r#"default_model = "kimi-k2-5"

[[hooks]]
event = "Stop"
command = "/Users/test/.codeisland/codeisland-bridge --source kimi"
timeout = 5

[[mcpServers]]
name = "test"
command = "npx"

[[hooks]]
event = "UserPromptSubmit"
command = "echo hello"
timeout = 1"#;

    let cleaned = remove(toml);
    assert!(!cleaned.contains("codeisland-bridge"), "{cleaned}");
    assert!(cleaned.contains("[[mcpServers]]"));
    assert!(cleaned.contains("echo hello"));
    assert!(cleaned.contains("default_model"));
}

#[test]
fn install_appends_a_block_per_event_and_keeps_the_users_file() {
    let original = "default_model = \"kimi-k2-5\"\n# my comment\n";
    let text = install(original, COMMAND);
    assert!(
        text.starts_with(original),
        "nothing above is touched: {text}"
    );
    assert!(text.contains("# my comment"));
    for (event, _) in EVENTS {
        assert!(
            text.contains(&format!("event = \"{event}\"")),
            "missing {event}"
        );
    }
    // The tool events carry a matcher; nothing else does.
    let pretool = text
        .split("[[hooks]]")
        .find(|block| block.contains("\"PreToolUse\""))
        .expect("PreToolUse");
    assert!(pretool.contains("matcher = \".*\""));
    let stop = text
        .split("[[hooks]]")
        .find(|block| block.contains("\"Stop\""))
        .expect("Stop");
    assert!(!stop.contains("matcher"));
    assert!(is_installed(&text));
}

#[test]
fn installing_twice_is_stable() {
    let first = install("default_model = \"kimi\"\n", COMMAND);
    let second = install(&first, COMMAND);
    assert_eq!(first, second, "no block is doubled");
    assert_eq!(second.matches("[[hooks]]").count(), EVENTS.len());
}

#[test]
fn install_from_nothing_is_a_clean_file() {
    let text = install("", COMMAND);
    assert!(!text.starts_with('\n'), "{text}");
    assert_eq!(text.matches("[[hooks]]").count(), EVENTS.len());
    assert!(text.ends_with('\n'));
}

#[test]
fn uninstall_gives_the_file_back() {
    let original = "default_model = \"kimi-k2-5\"\n\n# keep me\n";
    let installed = install(original, COMMAND);
    let back = remove(&installed);
    assert_eq!(back, original.trim_end(), "nothing of ours is left");
    assert!(!back.contains("codeisland"));
}

#[test]
fn a_legacy_scalar_is_commented_out_and_restored() {
    let original =
        "default_model = \"kimi\"\nhooks = [{ event = \"Stop\", command = \"old.sh\" }]\n";
    let installed = install(original, COMMAND);
    assert!(
        installed.contains("# [CodeIsland] commented out legacy scalar hooks"),
        "{installed}"
    );
    assert!(installed.contains("# hooks = [{ event = \"Stop\""));

    let back = remove(&installed);
    assert!(
        back.contains("hooks = [{ event = \"Stop\", command = \"old.sh\" }]"),
        "{back}"
    );
    assert!(!back.contains("commented out legacy scalar hooks"));
}

#[test]
fn a_command_with_a_space_is_quoted() {
    let text = install("", "/home/a b/.codeisland/codeisland-hook.sh");
    assert!(
        text.contains("command = \"\"/home/a b/.codeisland/codeisland-hook.sh\" --source kimi\""),
        "{text}"
    );
}

#[test]
fn a_file_without_our_blocks_is_not_installed() {
    assert!(!is_installed("default_model = \"kimi\"\n"));
    assert!(!is_installed(
        "[[hooks]]\nevent = \"Stop\"\ncommand = \"echo hi\"\n"
    ));
    assert!(is_installed(&install("", COMMAND)));
}
