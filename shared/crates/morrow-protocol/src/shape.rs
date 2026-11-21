//! JSON Schema checks shared by the shapes: just the keywords the contract's
//! schemas use.

use serde_json::Value;

use crate::{JsonObject, ProtocolError};

/// A JSON type or constraint a schema property names.
#[derive(Clone, Copy, Debug)]
pub(crate) enum Kind {
    Str,
    NonEmptyStr,
    Hex,
    Hex64,
    StrOrNull,
    Bool,
    Object,
    ObjectOrNull,
    StrOrObject,
    Array,
    StrOrArray,
    UInt,
    PositiveInt,
    PidOrToken,
    StrMap,
}

impl Kind {
    fn expected(self) -> &'static str {
        match self {
            Kind::Str => "a string",
            Kind::NonEmptyStr => "a non-empty string",
            Kind::Hex => "a hexadecimal string",
            Kind::Hex64 => "a 64-digit hexadecimal string",
            Kind::StrOrNull => "a string or null",
            Kind::Bool => "a boolean",
            Kind::Object => "an object",
            Kind::ObjectOrNull => "an object or null",
            Kind::StrOrObject => "a string or an object",
            Kind::Array => "an array",
            Kind::StrOrArray => "a string or an array",
            Kind::UInt => "a non-negative integer",
            Kind::PositiveInt => "a positive integer",
            Kind::PidOrToken => "a non-negative integer or a `$PID<n>` token",
            Kind::StrMap => "an object of strings",
        }
    }

    fn admits(self, value: &Value) -> bool {
        match self {
            Kind::Str => value.is_string(),
            Kind::NonEmptyStr => value.as_str().is_some_and(|s| !s.is_empty()),
            Kind::Hex => value.as_str().is_some_and(is_hex),
            Kind::Hex64 => value.as_str().is_some_and(|s| s.len() == 64 && is_hex(s)),
            Kind::StrOrNull => value.is_string() || value.is_null(),
            Kind::Bool => value.is_boolean(),
            Kind::Object => value.is_object(),
            Kind::ObjectOrNull => value.is_object() || value.is_null(),
            Kind::StrOrObject => value.is_string() || value.is_object(),
            Kind::Array => value.is_array(),
            Kind::StrOrArray => value.is_string() || value.is_array(),
            Kind::UInt => value.is_u64(),
            Kind::PositiveInt => value.as_u64().is_some_and(|n| n >= 1),
            Kind::PidOrToken => value.is_u64() || value.as_str().is_some_and(is_pid_token),
            Kind::StrMap => value
                .as_object()
                .is_some_and(|map| map.values().all(Value::is_string)),
        }
    }
}

fn is_hex(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|b| b.is_ascii_hexdigit())
}

/// `^\$PID[0-9]+$`: how golden fixtures tokenise a pid.
pub(crate) fn is_pid_token(s: &str) -> bool {
    s.strip_prefix("$PID")
        .is_some_and(|digits| !digits.is_empty() && digits.bytes().all(|b| b.is_ascii_digit()))
}

pub(crate) fn path(prefix: &str, key: &str) -> String {
    if prefix.is_empty() {
        key.to_owned()
    } else {
        format!("{prefix}.{key}")
    }
}

pub(crate) fn type_name(value: &Value) -> &'static str {
    match value {
        Value::Null => "null",
        Value::Bool(_) => "a boolean",
        Value::Number(_) => "a number",
        Value::String(_) => "a string",
        Value::Array(_) => "an array",
        Value::Object(_) => "an object",
    }
}

/// Checks `object[key]` against `kind`, if present.
pub(crate) fn check(
    object: &JsonObject,
    prefix: &str,
    key: &str,
    kind: Kind,
) -> Result<(), ProtocolError> {
    match object.get(key) {
        Some(value) if !kind.admits(value) => Err(ProtocolError::InvalidField {
            field: path(prefix, key),
            expected: kind.expected(),
        }),
        _ => Ok(()),
    }
}

/// Like [`check`], but the key must be present.
pub(crate) fn require(
    object: &JsonObject,
    prefix: &str,
    key: &str,
    kind: Kind,
) -> Result<(), ProtocolError> {
    if object.contains_key(key) {
        check(object, prefix, key, kind)
    } else {
        Err(ProtocolError::MissingField {
            field: path(prefix, key),
        })
    }
}

/// The object `value` holds, or why it is none.
pub(crate) fn into_object(value: Value, field: &str) -> Result<JsonObject, ProtocolError> {
    match value {
        Value::Object(map) => Ok(map),
        other => Err(ProtocolError::NotAnObject {
            field: field.to_owned(),
            found: type_name(&other),
        }),
    }
}

pub(crate) fn decode_object(bytes: &[u8], field: &str) -> Result<JsonObject, ProtocolError> {
    into_object(serde_json::from_slice(bytes)?, field)
}

pub(crate) fn encode_object(object: &JsonObject) -> Vec<u8> {
    serde_json::to_vec(object).expect("a JSON object with string keys always serialises")
}
