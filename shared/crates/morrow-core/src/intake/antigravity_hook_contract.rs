//! How Morrow answers Google Antigravity's (`agy`) `PreToolUse` hook
//! (`Sources/MorrowCore/AntigravityHookContract.swift`, #339): Antigravity
//! refuses the tool call when the hook prints no decision, so the bridge
//! prints `ask` at once, which hands the call back to Antigravity's own
//! permission engine.

use super::event_normalizer;
use super::session_snapshot::{SourceCatalog, normalized_supported_source};

/// `PreToolUse` stdout that leaves the decision to Antigravity itself.
pub const DEFER_TO_NATIVE_PERMISSION: &str = r#"{"decision":"ask"}"#;

/// `isAntigravityPreToolUse`: Gemini CLI never emits `PreToolUse`, so a
/// Gemini-tagged `PreToolUse` is `agy` reading hooks wired with
/// `--source gemini` (#233).
pub fn is_antigravity_pre_tool_use(
    source: Option<&str>,
    event_name: Option<&str>,
    catalog: &SourceCatalog,
) -> bool {
    let Some(event_name) = event_name else {
        return false;
    };
    if event_normalizer::normalize(event_name) != "PreToolUse" {
        return false;
    }
    matches!(
        normalized_supported_source(source, catalog).as_deref(),
        Some("google-antigravity" | "gemini")
    )
}

/// `hookStdout`: what the bridge must print for this invocation before
/// anything else can end it, or `None` when it owes Antigravity nothing.
pub fn hook_stdout(
    source: Option<&str>,
    event_name: Option<&str>,
    catalog: &SourceCatalog,
) -> Option<&'static str> {
    is_antigravity_pre_tool_use(source, event_name, catalog).then_some(DEFER_TO_NATIVE_PERMISSION)
}
