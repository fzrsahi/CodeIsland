//! Swift's casts on a `JSONSerialization` value (`value as? String`,
//! `as? Int`, `as? [String]`, …), which the reducer reads its payloads with.

use serde_json::Value;

use crate::JsonObject;

/// `value as? String`.
pub fn string(value: Option<&Value>) -> Option<&str> {
    value?.as_str()
}

/// `value as? String`, kept only when not empty (`let s, !s.isEmpty`).
pub fn non_empty(value: Option<&Value>) -> Option<&str> {
    string(value).filter(|s| !s.is_empty())
}

/// `SubsessionRouter.nonEmptyString` / `HookEvent.firstString`: a string with
/// something besides whitespace, trimmed.
pub fn trimmed(value: Option<&Value>) -> Option<&str> {
    string(value).map(str::trim).filter(|s| !s.is_empty())
}

/// `value as? Bool`: a JSON boolean, or a number that is exactly 0 or 1.
pub fn bool(value: Option<&Value>) -> Option<bool> {
    match value? {
        Value::Bool(b) => Some(*b),
        Value::Number(n) => match n.as_f64() {
            Some(0.0) => Some(false),
            Some(1.0) => Some(true),
            _ => None,
        },
        _ => None,
    }
}

/// `value as? Bool == true`.
pub fn is_true(value: Option<&Value>) -> bool {
    bool(value) == Some(true)
}

/// `value as? Int`: a number with an exact `Int` value.
pub fn int(value: Option<&Value>) -> Option<i64> {
    let Value::Number(n) = value? else {
        return None;
    };
    if let Some(i) = n.as_i64() {
        return Some(i);
    }
    let f = n.as_f64()?;
    // i64::MAX as f64 rounds up to 2^63, which is out of range.
    (f.fract() == 0.0 && f >= i64::MIN as f64 && f < i64::MAX as f64).then_some(f as i64)
}

/// `(value as? NSNumber)?.int64Value`: any number (a boolean is 0 or 1),
/// truncated.
pub fn int64_value(value: Option<&Value>) -> Option<i64> {
    match value? {
        Value::Bool(b) => Some(i64::from(*b)),
        Value::Number(n) => n.as_i64().or_else(|| n.as_f64().map(|f| f as i64)),
        _ => None,
    }
}

/// `value as? [String: Any]`.
pub fn object(value: Option<&Value>) -> Option<&JsonObject> {
    value?.as_object()
}

/// `value as? [String]`: an array of strings only.
pub fn strings(value: Option<&Value>) -> Option<Vec<&str>> {
    value?.as_array()?.iter().map(Value::as_str).collect()
}

/// `value as? [String: String]`: an object of strings only.
pub fn string_map(value: Option<&Value>) -> Option<Vec<(&str, &str)>> {
    object(value)?
        .iter()
        .map(|(k, v)| v.as_str().map(|v| (k.as_str(), v)))
        .collect()
}

/// `(path as NSString).lastPathComponent`.
pub fn last_path_component(path: &str) -> &str {
    let trimmed = path.trim_end_matches('/');
    if trimmed.is_empty() {
        return if path.is_empty() { "" } else { "/" };
    }
    trimmed.rsplit('/').next().unwrap_or(trimmed)
}

/// The first `n` characters of `s` (`String(s.prefix(n))`, counted in
/// chars where Swift counts grapheme clusters).
pub fn prefix(s: &str, n: usize) -> String {
    s.chars().take(n).collect()
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn casts_follow_nsnumber_bridging() {
        assert_eq!(bool(Some(&json!(1))), Some(true));
        assert_eq!(bool(Some(&json!(2))), None);
        assert_eq!(int(Some(&json!(4242.0))), Some(4242));
        assert_eq!(int(Some(&json!(1.5))), None);
        assert_eq!(int(Some(&json!(true))), None);
        assert_eq!(strings(Some(&json!(["a", 1]))), None);
        assert_eq!(string_map(Some(&json!({"A": "1", "B": 2}))), None);
        assert_eq!(last_path_component("/a/b.txt"), "b.txt");
        assert_eq!(last_path_component("/a/b/"), "b");
        assert_eq!(last_path_component("/"), "/");
    }
}
