//! Reading a config file's top level, comments and all (`parseJSONFile`,
//! `parseJSONString`, `isSameJSONDocument`).

use serde_json::{Map, Value};

use super::json_editor::strip_json_comments;

/// The document's top level, or `None` when it does not parse or is not an
/// object. Callers treat `None` as "never write this file".
pub fn object(source: &str) -> Option<Map<String, Value>> {
    let value: Value = serde_json::from_str(&strip_json_comments(source)).ok()?;
    value.as_object().cloned()
}

/// Same document, whatever the key order, spacing or comments: a file that
/// already says this is left alone rather than rewritten on every launch.
pub fn same_document(left: &str, right: &str) -> bool {
    let parse = |text: &str| serde_json::from_str::<Value>(&strip_json_comments(text));
    match (parse(left), parse(right)) {
        (Ok(left), Ok(right)) => left == right,
        _ => false,
    }
}
