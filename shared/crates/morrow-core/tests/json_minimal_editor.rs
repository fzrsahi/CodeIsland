//! `JSONMinimalEditorTests` (`macos/Tests/MorrowTests/JSONMinimalEditorTests.swift`)
//! ported test for test: 15 of 15.

use serde_json::{Value, json};

use morrow_core::installer::json_editor::{
    delete_top_level_key, set_top_level_value, strip_json_comments,
};

fn value(text: &str) -> Value {
    serde_json::from_str(text).expect("valid JSON")
}

fn parsed(text: &str) -> Value {
    serde_json::from_str(text).expect("valid JSON")
}

// MARK: - set_top_level_value: an existing key keeps unrelated bytes

#[test]
fn replace_preserves_unrelated_keys_order_and_slashes_and_comments() {
    let original = r#"{
  "env": {
    "ANTHROPIC_API_KEY": "sk-xxx",
    "MAX_MCP_OUTPUT_TOKENS": "200000"
  },
  "hooks": {
    "PreToolUse": []
  },
  "autoMemoryEnabled": false
}"#;
    let new_hooks = json!({
        "PreToolUse": [{
            "matcher": "",
            "hooks": [{
                "type": "command",
                "command": "~/.codeisland/codeisland-hook.sh",
                "timeout": 5,
            }],
        }],
    });
    let result = set_top_level_value(original, "hooks", &new_hooks).expect("edited");

    // The user's keys survive verbatim (API key intact, slashes un-escaped,
    // order unchanged).
    assert!(
        result.contains("\"ANTHROPIC_API_KEY\": \"sk-xxx\""),
        "ANTHROPIC_API_KEY must survive untouched"
    );
    assert!(result.contains("\"MAX_MCP_OUTPUT_TOKENS\": \"200000\""));
    assert!(result.contains("\"autoMemoryEnabled\": false"));
    assert!(
        !result.contains("\\/"),
        "paths must not be escaped with \\/"
    );

    // "env" stays before "hooks", "hooks" before "autoMemoryEnabled".
    let env = result.find("\"env\"").expect("env");
    let hooks = result.find("\"hooks\"").expect("hooks");
    let auto = result.find("\"autoMemoryEnabled\"").expect("auto");
    assert!(env < hooks);
    assert!(hooks < auto);

    // The new payload is there.
    assert!(result.contains("~/.codeisland/codeisland-hook.sh"));

    // And the result still parses.
    assert!(parsed(&result).is_object());
}

#[test]
fn replace_preserves_jsonc_comments_outside_the_target_key() {
    let original = r#"{
  // User-authored settings below
  "model": "sonnet",
  "hooks": {},
  /* auto-generated */
  "autoshare": false
}"#;
    let result = set_top_level_value(original, "hooks", &json!({"X": "Y"})).expect("edited");
    assert!(result.contains("// User-authored settings below"));
    assert!(result.contains("/* auto-generated */"));
    assert!(result.contains("\"model\": \"sonnet\""));
}

#[test]
fn replace_preserves_trailing_newline() {
    let with_newline = "{\n  \"hooks\": {}\n}\n";
    let result = set_top_level_value(with_newline, "hooks", &json!({"A": 1})).expect("edited");
    assert!(result.ends_with('\n'), "trailing newline must be preserved");

    let without = "{\n  \"hooks\": {}\n}";
    let result = set_top_level_value(without, "hooks", &json!({"A": 1})).expect("edited");
    assert!(
        !result.ends_with('\n'),
        "the no-trailing-newline style must be preserved too"
    );
}

// MARK: - set_top_level_value: a new key

#[test]
fn insert_appends_the_new_key_at_the_end_with_matching_indent() {
    let original = r#"{
  "model": "sonnet"
}"#;
    let result = set_top_level_value(original, "hooks", &json!({"A": 1})).expect("edited");
    assert!(result.contains("\"model\": \"sonnet\""));
    assert!(result.contains("\"hooks\""));
    let parsed = parsed(&result);
    assert_eq!(parsed["hooks"]["A"], json!(1));
    assert_eq!(parsed["model"], json!("sonnet"));
}

#[test]
fn insert_into_an_empty_object() {
    let result = set_top_level_value("{}", "hooks", &json!({"A": 1})).expect("edited");
    let parsed = parsed(&result);
    assert!(parsed.get("hooks").is_some(), "{result}");
}

// MARK: - set_top_level_value: refusal on invalid input

#[test]
fn returns_none_when_the_top_level_is_an_array() {
    assert!(set_top_level_value("[1, 2, 3]", "hooks", &json!({})).is_none());
}

#[test]
fn returns_none_on_malformed_json() {
    assert!(set_top_level_value("{ \"hooks\": [", "hooks", &json!({})).is_none());
}

#[test]
fn returns_none_on_a_truncated_object() {
    assert!(set_top_level_value("{ \"a\": 1,", "hooks", &json!({})).is_none());
}

// MARK: - delete_top_level_key

#[test]
fn delete_removes_the_key_and_its_trailing_comma() {
    let original = r#"{
  "a": 1,
  "hooks": {},
  "b": 2
}"#;
    let result = delete_top_level_key(original, "hooks").expect("edited");
    assert!(!result.contains("hooks"));
    let parsed = parsed(&result);
    assert_eq!(parsed["a"], json!(1));
    assert_eq!(parsed["b"], json!(2));
}

#[test]
fn delete_removes_the_preceding_comma_for_the_last_key() {
    let original = r#"{
  "a": 1,
  "hooks": {}
}"#;
    let result = delete_top_level_key(original, "hooks").expect("edited");
    let parsed = parsed(&result);
    assert_eq!(parsed["a"], json!(1));
    assert!(parsed.get("hooks").is_none(), "{result}");
}

#[test]
fn delete_of_the_only_key_yields_an_empty_object() {
    let original = "{\n  \"hooks\": {}\n}";
    let result = delete_top_level_key(original, "hooks").expect("edited");
    let parsed = parsed(&result);
    assert_eq!(parsed.as_object().map(|map| map.len()), Some(0), "{result}");
}

#[test]
fn delete_of_a_missing_key_returns_the_source_unchanged() {
    let original = "{\n  \"a\": 1\n}";
    let result = delete_top_level_key(original, "hooks").expect("edited");
    assert_eq!(result, original);
}

// MARK: - Idempotency

#[test]
fn setting_the_same_value_twice_is_stable() {
    let original = r#"{
  "model": "sonnet",
  "hooks": { "A": 1 }
}"#;
    let first = set_top_level_value(original, "hooks", &json!({"A": 1})).expect("edited");
    let second = set_top_level_value(&first, "hooks", &json!({"A": 1})).expect("edited");
    assert_eq!(first, second, "writing the same value twice must converge");
}

// MARK: - Array values (plugin: [...])

#[test]
fn replace_a_string_array_and_preserve_the_surrounding_keys() {
    let original = r#"{
  "model": "sonnet",
  "plugin": ["file:///old/codeisland.js"],
  "autoshare": false
}"#;
    let result = set_top_level_value(original, "plugin", &json!(["file:///new/codeisland.js"]))
        .expect("edited");
    assert!(result.contains("\"model\": \"sonnet\""));
    assert!(result.contains("\"autoshare\": false"));
    assert!(result.contains("file:///new/codeisland.js"));
    assert!(!result.contains("file:///old/codeisland.js"));
    assert!(!result.contains("\\/"));
    let _ = value(&result);
}

// MARK: - JSONC

#[test]
fn comments_are_stripped_and_slashes_inside_strings_are_kept() {
    let source = r#"{
  // a line comment
  "url": "https://example.com/x", /* and a block one */
  "path": "~/.codeisland/codeisland-hook.sh"
}"#;
    let stripped = strip_json_comments(source);
    assert!(!stripped.contains("a line comment"));
    assert!(!stripped.contains("and a block one"));
    assert!(stripped.contains("https://example.com/x"), "{stripped}");
    assert!(stripped.contains("~/.codeisland/codeisland-hook.sh"));
    // What is left is plain JSON.
    assert!(serde_json::from_str::<Value>(&stripped).is_ok());
}
