//! The YAML sources as a managed block (#151, option B): our region in, our
//! region out, and not one other byte of the user's file changed.

use morrow_core::installer::yaml_hooks::{
    FENCE_CLOSE, FENCE_OPEN, Refusal, SOURCES, install, is_installed, remove, source_for,
};

const BRIDGE: &str = "~/.codeisland/codeisland-hook.sh";

fn hermes() -> &'static morrow_core::installer::yaml_hooks::Source {
    source_for("hermes").expect("hermes")
}

fn traecli() -> &'static morrow_core::installer::yaml_hooks::Source {
    source_for("traecli").expect("traecli")
}

// MARK: - The table

#[test]
fn both_yaml_sources_are_here_and_keep_their_own_event_names() {
    let sources: Vec<&str> = SOURCES.iter().map(|source| source.source).collect();
    assert_eq!(sources, ["hermes", "traecli"]);
    assert_eq!(hermes().path, ".hermes/config.yaml");
    assert_eq!(traecli().path, ".trae/traecli.yaml");
    assert_eq!(hermes().events[0].0, "pre_tool_call");
    assert_eq!(traecli().events[0].0, "session_start");
    // The longest timeout is the permission request's day.
    let traecli_max = traecli()
        .events
        .iter()
        .map(|(_, timeout)| *timeout)
        .max()
        .unwrap();
    assert_eq!(traecli_max, 86_400);
}

// MARK: - Install

#[test]
fn a_file_without_hooks_gets_one_and_our_block() {
    let original = "model: hermes-4\n# my comment\n";
    let text = install(hermes(), original, BRIDGE).expect("install");

    assert!(
        text.starts_with(original.trim_end()),
        "the user's lines are first: {text}"
    );
    assert!(text.contains("\nhooks:\n"), "a top-level key: {text}");
    assert!(text.contains(FENCE_OPEN));
    assert!(text.contains(FENCE_CLOSE));
    assert!(text.contains("pre_tool_call:"));
    assert!(text.contains("--source hermes"));
    assert!(is_installed(hermes(), &text));
}

#[test]
fn the_users_comments_inside_the_file_are_untouched() {
    let original = "# top of file\nmodel: x\n\n# a section\nhooks:\n# trailing note\nother: 1\n";
    let text = install(hermes(), original, BRIDGE).expect("install");
    assert!(text.contains("# top of file"));
    assert!(text.contains("# a section"));
    assert!(text.contains("# trailing note"));
    assert!(text.contains("other: 1"));
    assert!(text.contains("pre_tool_call:"));
}

#[test]
fn an_empty_inline_hooks_value_becomes_a_key() {
    let text = install(hermes(), "hooks: {}\nmodel: x\n", BRIDGE).expect("install");
    assert!(text.contains("hooks:\n"), "{text}");
    assert!(!text.contains("hooks: {}"));
    assert!(text.contains("pre_tool_call:"));
}

#[test]
fn traecli_gets_one_item_with_every_event_as_a_matcher() {
    let text = install(traecli(), "", BRIDGE).expect("install");
    assert_eq!(text.matches("- type: command").count(), 1);
    assert!(text.contains("command: '~/.codeisland/codeisland-hook.sh --source traecli'"));
    assert!(text.contains("timeout: '86400s'"));
    assert!(text.contains("- event: permission_request"));
    assert!(text.contains("matchers:"));
}

#[test]
fn installing_twice_is_stable() {
    for source in SOURCES {
        let first = install(source, "model: x\n", BRIDGE).expect("install");
        let second = install(source, &first, BRIDGE).expect("reinstall");
        assert_eq!(first, second, "{} is stable", source.source);
        assert_eq!(
            second.matches(FENCE_OPEN).count(),
            1,
            "{}: one region",
            source.source
        );
    }
}

#[test]
fn a_command_with_a_space_is_quoted() {
    let text = install(hermes(), "", "/home/a b/.codeisland/codeisland-hook.sh").expect("install");
    assert!(
        text.contains("'\"/home/a b/.codeisland/codeisland-hook.sh\" --source hermes'"),
        "{text}"
    );
}

// MARK: - Refusals

#[test]
fn an_inline_layout_we_cannot_merge_is_refused() {
    let error = install(hermes(), "hooks: [one]\n", BRIDGE).expect_err("refuses");
    assert!(matches!(error, Refusal::InlineHooks(_)), "{error:?}");
    let error = install(traecli(), "hooks: {pre_tool_call: []}\n", BRIDGE).expect_err("refuses");
    assert!(matches!(error, Refusal::InlineHooks(_)), "{error:?}");
}

#[test]
fn a_tab_indented_file_is_refused() {
    let error = install(hermes(), "model: x\n\thooks:\n", BRIDGE).expect_err("refuses");
    assert!(
        matches!(error, Refusal::TabIndentation | Refusal::NestedHooks),
        "{error:?}"
    );
}

#[test]
fn a_nested_hooks_key_is_refused() {
    let error = install(hermes(), "agent:\n  hooks:\n", BRIDGE).expect_err("refuses");
    assert_eq!(error, Refusal::NestedHooks);
}

// MARK: - Removal

#[test]
fn uninstall_gives_the_file_back() {
    for source in SOURCES {
        for original in [
            "model: x\n",
            "# only a comment\n",
            "model: x\nhooks:\nother: 1\n",
        ] {
            let installed = install(source, original, BRIDGE).expect("install");
            let back = remove(&installed);
            assert_eq!(back, original, "{} from {original:?}", source.source);
            assert!(!is_installed(source, &back), "{}", source.source);
        }
    }
}

#[test]
fn uninstall_keeps_a_hooks_key_the_user_wrote() {
    let original = "hooks:\n  pre_tool_call:\n    - command: 'echo mine'\n";
    let installed = install(hermes(), original, BRIDGE).expect("install");
    let back = remove(&installed);
    assert_eq!(back, original, "their block and key stay");
    assert!(back.contains("echo mine"));
}

#[test]
fn uninstall_of_a_file_without_our_block_changes_nothing() {
    for source in SOURCES {
        let original = "model: x\n";
        assert_eq!(remove(original), original);
        assert!(!is_installed(source, original));
    }
}

#[test]
fn a_dangling_hooks_key_we_made_is_dropped() {
    // We added `hooks:` on a file that had none; uninstall leaves no empty key.
    let installed = install(hermes(), "model: x\n", BRIDGE).expect("install");
    let back = remove(&installed);
    assert!(!back.contains("hooks:"), "{back}");
}
