//! `mergeOpencodePluginRef` / `removeOpencodePluginRef`, from
//! `ConfigInstallerTests`' OpenCode cases (#132's jsonc preference included).

use serde_json::Value;

use morrow_core::installer::json_editor::strip_json_comments;
use morrow_core::installer::opencode::{
    IDENTIFIER, SCHEMA, is_registered, merge_plugin_ref, remove_plugin_ref,
};

const REF: &str = "file:///home/u/.config/opencode/plugins/codeisland.js";

fn parsed(text: &str) -> Value {
    serde_json::from_str(&strip_json_comments(text)).expect("valid JSON")
}

#[test]
fn a_fresh_file_gets_the_schema_and_our_reference() {
    let merged = merge_plugin_ref(None, REF).expect("a new file");
    let document = parsed(&merged);
    assert_eq!(document["$schema"], Value::from(SCHEMA));
    assert_eq!(document["plugin"], serde_json::json!([REF]));
    assert!(merged.ends_with('\n'));
}

#[test]
fn the_users_own_plugins_and_comments_survive() {
    let original = r#"{
  // mine
  "plugin": ["file:///home/u/plugins/mine.js"],
  "theme": "dark"
}"#;
    let merged = merge_plugin_ref(Some(original), REF).expect("merged");
    assert!(merged.contains("// mine"));
    assert!(merged.contains("\"theme\": \"dark\""));
    let plugins = parsed(&merged)["plugin"].as_array().cloned().unwrap();
    assert_eq!(plugins.len(), 2);
    assert_eq!(plugins[0], Value::from("file:///home/u/plugins/mine.js"));
    assert_eq!(plugins[1], Value::from(REF));
}

#[test]
fn a_schema_hint_is_added_when_missing_and_kept_when_present() {
    let merged = merge_plugin_ref(Some("{\n  \"theme\": \"dark\"\n}"), REF).expect("merged");
    assert_eq!(parsed(&merged)["$schema"], Value::from(SCHEMA));

    let already = format!("{{\n  \"$schema\": \"{SCHEMA}\",\n  \"theme\": \"dark\"\n}}");
    let merged = merge_plugin_ref(Some(&already), REF).expect("merged");
    assert_eq!(
        merged.matches(SCHEMA).count(),
        1,
        "the hint is not duplicated: {merged}"
    );
}

#[test]
fn a_legacy_reference_is_replaced_rather_than_stacked() {
    let original = r#"{"plugin": ["/Users/x/.vibe-island/plugin.js"]}"#;
    let merged = merge_plugin_ref(Some(original), REF).expect("merged");
    let plugins = parsed(&merged)["plugin"].as_array().cloned().unwrap();
    assert_eq!(plugins, vec![Value::from(REF)]);
    assert!(!merged.contains("vibe-island"));
}

#[test]
fn merging_twice_is_stable() {
    let first = merge_plugin_ref(Some("{\n  \"theme\": \"dark\"\n}"), REF).expect("merged");
    let second = merge_plugin_ref(Some(&first), REF).expect("merged");
    assert_eq!(first, second);
    let plugins = parsed(&second)["plugin"].as_array().cloned().unwrap();
    assert_eq!(plugins.len(), 1, "our entry is not duplicated");
}

#[test]
fn an_unparseable_file_is_refused() {
    assert!(merge_plugin_ref(Some("{ \"plugin\": ["), REF).is_none());
    assert!(merge_plugin_ref(Some("[1, 2]"), REF).is_none());
    assert!(remove_plugin_ref("{ nope").is_none());
}

#[test]
fn removal_deletes_the_key_when_it_held_only_ours() {
    let original = "{\n  \"theme\": \"dark\"\n}\n";
    let merged = merge_plugin_ref(Some(original), REF).expect("merged");
    let back = remove_plugin_ref(&merged).expect("removed");
    let document = parsed(&back);
    assert!(document.get("plugin").is_none(), "{back}");
    assert_eq!(document["theme"], Value::from("dark"));
    // The `$schema` we added stays: `removeOpencodePluginRef` takes the plugin
    // back out, nothing else.
    assert_eq!(document["$schema"], Value::from(SCHEMA));
}

#[test]
fn removal_keeps_the_users_plugins() {
    let original = r#"{"plugin": ["file:///home/u/plugins/mine.js", "file:///x/codeisland.js"]}"#;
    let back = remove_plugin_ref(original).expect("removed");
    let plugins = parsed(&back)["plugin"].as_array().cloned().unwrap();
    assert_eq!(plugins, vec![Value::from("file:///home/u/plugins/mine.js")]);
}

#[test]
fn removal_of_a_file_without_us_does_nothing() {
    assert!(remove_plugin_ref("{\"plugin\": [\"file:///mine.js\"]}").is_none());
    assert!(remove_plugin_ref("{\"theme\": \"dark\"}").is_none());
}

#[test]
fn registration_is_recognised_however_the_path_reads() {
    assert!(is_registered(&format!("{{\"plugin\": [\"{REF}\"]}}")));
    assert!(is_registered(
        "{\"plugin\": [\"/old/.vibe-island/plugin.js\"]}"
    ));
    assert!(!is_registered("{\"plugin\": [\"file:///mine.js\"]}"));
    assert!(!is_registered("{}"));
    assert!(REF.contains(IDENTIFIER));
}
