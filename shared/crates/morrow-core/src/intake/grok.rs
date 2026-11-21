//! Grok Build (`Sources/MorrowCore/GrokHookForwardingPolicy.swift`,
//! `GrokSessionPaths.swift`).

use std::collections::HashMap;

/// `GrokHookForwardingPolicy.isGrokRuntime`: Grok sets at least one of
/// these for its hook subprocesses; whitespace-only values are absent.
pub fn is_grok_runtime(environment: &HashMap<String, String>) -> bool {
    let set = |key: &str| environment.get(key).is_some_and(|v| !v.trim().is_empty());
    set("GROK_SESSION_ID") || set("GROK_HOOK_EVENT")
}

/// `GrokHookForwardingPolicy.shouldForward`: inside Grok only Morrow's own
/// `--source grok` hook; the Claude Code and Cursor hooks Grok imports are
/// duplicate deliveries.
pub fn should_forward(source: Option<&str>, environment: &HashMap<String, String>) -> bool {
    !is_grok_runtime(environment) || source == Some("grok")
}

/// `GrokSessionPaths.encodedCwd`: the whole cwd percent-encoded into one
/// path component, `/` included. Kept as they are: alphanumerics and
/// `-._~`, as Swift's `CharacterSet.alphanumerics` (Rust's
/// `char::is_alphanumeric`; the two differ on some combining marks).
pub fn encoded_cwd(cwd: &str) -> String {
    let mut encoded = String::with_capacity(cwd.len());
    for c in cwd.chars() {
        if c.is_alphanumeric() || "-._~".contains(c) {
            encoded.push(c);
        } else {
            let mut buffer = [0; 4];
            for byte in c.encode_utf8(&mut buffer).bytes() {
                encoded.push_str(&format!("%{byte:02X}"));
            }
        }
    }
    encoded
}

/// `GrokSessionPaths.chatHistoryPath`.
pub fn chat_history_path(grok_home: &str, cwd: &str, session_id: &str) -> Option<String> {
    if session_id.is_empty() || session_id.contains('/') {
        return None;
    }
    Some(format!(
        "{grok_home}/sessions/{}/{session_id}/chat_history.jsonl",
        encoded_cwd(cwd)
    ))
}

/// `GrokSessionPaths.existingChatHistoryPath`: the path only once the file
/// exists, so the tailer is never pinned to a file Grok has not written.
pub fn existing_chat_history_path(
    grok_home: &str,
    cwd: &str,
    session_id: &str,
    file_exists: &dyn Fn(&str) -> bool,
) -> Option<String> {
    chat_history_path(grok_home, cwd, session_id).filter(|path| file_exists(path))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cwd_is_one_component() {
        assert_eq!(encoded_cwd("/Users/me"), "%2FUsers%2Fme");
        assert_eq!(encoded_cwd("/a b/é~"), "%2Fa%20b%2Fé~");
        assert_eq!(chat_history_path("/g", "/x", "a/b"), None);
        assert_eq!(chat_history_path("/g", "/x", ""), None);
    }
}
