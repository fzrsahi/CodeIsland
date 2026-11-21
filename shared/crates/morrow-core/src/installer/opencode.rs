//! Registering Morrow's plugin in an `opencode.json` / `opencode.jsonc`
//! (`mergeOpencodePluginRef` / `removeOpencodePluginRef`).
//!
//! OpenCode has no hooks key: it loads every plugin an array names. So the
//! install writes our reference into `plugin`, keeping the user's own entries
//! and every byte around them, and uninstall takes it back out.

use serde_json::{Value, json};

use super::json_editor::{delete_top_level_key, set_top_level_value};
use super::settings::object;

/// The schema a fresh file points at, as OpenCode's own docs do.
pub const SCHEMA: &str = "https://opencode.ai/config.json";

/// What marks a plugin entry as ours — this app's name, which the plugin file
/// and its path both carry (`HookId.current`).
pub const IDENTIFIER: &str = "codeisland";

/// The names an older build registered under.
const LEGACY: &[&str] = &["vibe-island"];

fn is_ours(entry: &str) -> bool {
    entry.contains(IDENTIFIER) || LEGACY.iter().any(|legacy| entry.contains(legacy))
}

/// Whether `plugin` already names us (`isOpencodePluginInstalled`'s check).
pub fn is_registered(existing: &str) -> bool {
    object(existing)
        .and_then(|root| root.get("plugin").cloned())
        .and_then(|plugin| plugin.as_array().cloned())
        .is_some_and(|entries| entries.iter().filter_map(Value::as_str).any(is_ours))
}

/// The file with our reference in `plugin`, or `None` when it does not parse as
/// a JSON object — the caller keeps the file and stages nothing over it (#89).
///
/// A brand-new file gets a minimal canonical document instead.
pub fn merge_plugin_ref(existing: Option<&str>, plugin_ref: &str) -> Option<String> {
    let Some(contents) = existing.filter(|text| !text.is_empty()) else {
        let mut document = serde_json::to_string_pretty(&json!({
            "$schema": SCHEMA,
            "plugin": [plugin_ref],
        }))
        .ok()?;
        document.push('\n');
        return Some(document);
    };

    let parsed = object(contents)?;
    let mut plugins: Vec<String> = parsed
        .get("plugin")
        .and_then(Value::as_array)
        .map(|entries| {
            entries
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_owned)
                .collect()
        })
        .unwrap_or_default();
    plugins.retain(|entry| !is_ours(entry));
    plugins.push(plugin_ref.to_owned());

    let mut merged = set_top_level_value(contents, "plugin", &json!(plugins))?;
    // A document without a schema hint gets one, at the end, without touching
    // the rest.
    if parsed.get("$schema").is_none() {
        if let Some(with_schema) = set_top_level_value(&merged, "$schema", &json!(SCHEMA)) {
            merged = with_schema;
        }
    }
    Some(merged)
}

/// The file without our reference: whole key deleted when it held only ours,
/// `None` when the file is absent, unparseable, or never named us.
pub fn remove_plugin_ref(existing: &str) -> Option<String> {
    let parsed = object(existing)?;
    let plugins = parsed.get("plugin")?.as_array()?;
    if !plugins.iter().filter_map(Value::as_str).any(is_ours) {
        return None;
    }
    let kept: Vec<&str> = plugins
        .iter()
        .filter_map(Value::as_str)
        .filter(|entry| !is_ours(entry))
        .collect();
    if kept.is_empty() {
        return delete_top_level_key(existing, "plugin");
    }
    set_top_level_value(existing, "plugin", &json!(kept))
}
