//! A hook Cursor ran, whichever config it came from
//! (`Sources/MorrowCore/CursorHookPayload.swift`). Cursor also runs the
//! Claude Code hooks it imports, with its own payload; `cursor_version` is
//! the only sign that Cursor, not Claude Code, fired it (#377).

use serde_json::Value;

use crate::JsonObject;
use crate::digest::sha256_hex;

/// The source a Cursor payload declares when no `--source` came with it.
pub const SOURCE: &str = "cursor";

/// Bridge field carrying [`delivery_digest`].
pub const DIGEST_KEY: &str = "_cursor_payload_digest";

/// `isCursorHook`: Cursor sets a non-blank `cursor_version` on every hook
/// input it builds; Claude Code and the other agents never send it.
pub fn is_cursor_hook(payload: &JsonObject) -> bool {
    payload
        .get("cursor_version")
        .and_then(Value::as_str)
        .is_some_and(|version| !version.trim().is_empty())
}

/// `deliveryDigest(of:)`: SHA-256 of the stdin exactly as Cursor wrote it.
/// The hooks of one step read the same bytes, so a step that reaches both
/// of Morrow's hooks yields one digest.
pub fn delivery_digest(stdin: &[u8]) -> String {
    sha256_hex(stdin)
}
