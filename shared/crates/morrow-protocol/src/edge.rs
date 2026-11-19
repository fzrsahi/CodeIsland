//! Edge facts (`$defs/edgeFacts` and `$defs/edgePayload` of
//! hook-envelope.schema.json; `_edge` fields in docs/hook-edge-protocol.md).

use std::collections::BTreeMap;

use serde_json::Value;

use crate::shape::{self, Kind};
use crate::{JsonObject, ProtocolError};

/// The payload key the facts travel under.
pub(crate) const KEY: &str = "_edge";

/// The facts version this build reads (`HookEdgeFacts.version`). Fields are
/// added without changing it; facts naming another version are read for the
/// fields this one knows, so no `v` is refused for being newer.
pub const EDGE_FACTS_VERSION: u64 = 1;

const PROPERTIES: &[(&str, Kind)] = &[
    ("source", Kind::Str),
    ("event", Kind::Str),
    ("cwd", Kind::Str),
    ("tty", Kind::Str),
    ("stdin_sha256", Kind::Hex),
    ("waits", Kind::Bool),
    ("host", Kind::Object),
    ("env", Kind::StrMap),
    ("tmux_client_tty", Kind::Str),
];

/// What an edge observed, typed. Keys this build does not know stay in
/// `other`, in arrival order; the payload that carried the facts keeps them
/// all on the wire.
#[derive(Clone, Debug, PartialEq)]
#[non_exhaustive]
pub struct EdgeFacts {
    /// Facts version, `>= 1`.
    pub v: u64,
    /// The agent the hook was installed for (the bridge's `--source`).
    pub source: Option<String>,
    /// The bridge's `--event`, for agents whose stdin names no event.
    pub event: Option<String>,
    pub cwd: Option<String>,
    pub tty: Option<String>,
    /// SHA-256 of the stdin bytes, hex.
    pub stdin_sha256: Option<String>,
    /// Whether the edge waits for the answer.
    pub waits: Option<bool>,
    pub host: Option<EdgeHost>,
    pub env: Option<BTreeMap<String, String>>,
    pub tmux_client_tty: Option<String>,
    pub other: JsonObject,
}

/// `_edge.host`: the machine the edge runs on.
#[derive(Clone, Debug, PartialEq)]
#[non_exhaustive]
pub struct EdgeHost {
    pub id: String,
    pub name: Option<String>,
    pub other: JsonObject,
}

impl EdgeFacts {
    /// Reads facts from the `_edge` value found at `field`.
    pub(crate) fn from_value(value: &Value, field: &str) -> Result<Self, ProtocolError> {
        let Value::Object(object) = value else {
            return Err(ProtocolError::NotAnObject {
                field: field.to_owned(),
                found: shape::type_name(value),
            });
        };
        shape::require(object, field, "v", Kind::PositiveInt)?;
        for &(key, kind) in PROPERTIES {
            shape::check(object, field, key, kind)?;
        }
        // `"ppid": false` in the schema: no pid of another machine is one the
        // island can track.
        if object.contains_key("ppid") {
            return Err(ProtocolError::ForbiddenField {
                field: shape::path(field, "ppid"),
            });
        }
        let host = object
            .get("host")
            .and_then(Value::as_object)
            .map(|host| EdgeHost::from_object(host, &shape::path(field, "host")))
            .transpose()?;
        let string = |key: &str| object.get(key).and_then(Value::as_str).map(str::to_owned);
        Ok(Self {
            v: object.get("v").and_then(Value::as_u64).unwrap_or_default(),
            source: string("source"),
            event: string("event"),
            cwd: string("cwd"),
            tty: string("tty"),
            stdin_sha256: string("stdin_sha256"),
            waits: object.get("waits").and_then(Value::as_bool),
            host,
            env: object.get("env").and_then(Value::as_object).map(|env| {
                env.iter()
                    .filter_map(|(k, v)| Some((k.clone(), v.as_str()?.to_owned())))
                    .collect()
            }),
            tmux_client_tty: string("tmux_client_tty"),
            other: others(object, &["v"], PROPERTIES),
        })
    }
}

impl EdgeHost {
    fn from_object(object: &JsonObject, field: &str) -> Result<Self, ProtocolError> {
        shape::require(object, field, "id", Kind::Str)?;
        shape::check(object, field, "name", Kind::Str)?;
        Ok(Self {
            id: object
                .get("id")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_owned(),
            name: object
                .get("name")
                .and_then(Value::as_str)
                .map(str::to_owned),
            other: others(object, &["id", "name"], &[]),
        })
    }
}

fn others(object: &JsonObject, known: &[&str], properties: &[(&str, Kind)]) -> JsonObject {
    object
        .iter()
        .filter(|(key, _)| {
            !known.contains(&key.as_str()) && !properties.iter().any(|(k, _)| k == key)
        })
        .map(|(key, value)| (key.clone(), value.clone()))
        .collect()
}

/// An edge's payload (`$defs/edgePayload`): the agent's stdin object as it
/// was, plus the `_edge` facts. HookIntake, not this crate, interprets it.
#[derive(Clone, Debug, PartialEq)]
pub struct EdgePayload {
    object: JsonObject,
    facts: EdgeFacts,
}

impl EdgePayload {
    /// Checks `object` against `$defs/edgePayload`.
    ///
    /// # Errors
    /// No `_edge`, or one that breaks the edge facts' schema.
    pub fn from_object(object: JsonObject) -> Result<Self, ProtocolError> {
        let facts = match object.get(KEY) {
            Some(value) => EdgeFacts::from_value(value, KEY)?,
            None => {
                return Err(ProtocolError::MissingField {
                    field: KEY.to_owned(),
                });
            }
        };
        Ok(Self { object, facts })
    }

    #[must_use]
    pub fn facts(&self) -> &EdgeFacts {
        &self.facts
    }

    /// The whole object, `_edge` included, in arrival order.
    #[must_use]
    pub fn as_object(&self) -> &JsonObject {
        &self.object
    }

    #[must_use]
    pub fn into_object(self) -> JsonObject {
        self.object
    }

    #[must_use]
    pub fn get(&self, key: &str) -> Option<&Value> {
        self.object.get(key)
    }
}
