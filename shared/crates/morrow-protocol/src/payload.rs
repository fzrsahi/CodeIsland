//! The forwarded hook payload (`schemas/hook-payload.schema.json`).

use serde_json::Value;

use crate::edge::{self, EdgeFacts};
use crate::shape::{self, Kind};
use crate::{JsonObject, ProtocolError};

/// The keys HookIntake's terminal context writes
/// (`HookIntake.addTerminalContext`, `macos/Sources/MorrowCore/HookIntake.swift`):
/// terminal app, multiplexer panes and tty.
pub const TERMINAL_KEYS: &[&str] = &[
    "_term_app",
    "_term_bundle",
    "_iterm_session",
    "_kitty_window",
    "_tmux",
    "_tmux_pane",
    "_tmux_client_tty",
    "_tty",
    "_cmux_surface_id",
    "_cmux_workspace_id",
    "_zellij",
    "_zellij_pane_id",
    "_zellij_session_name",
    "_wezterm_pane",
    "_herdr_pane_id",
    "_herdr_socket_path",
    "_herdr_bin_path",
    "_superset_workspace_id",
    "_superset_pane_id",
    "_orca_terminal_handle",
    "_orca_worktree_id",
    "_claude_desktop_session",
];

/// `required` of hook-payload.schema.json.
const REQUIRED: &[(&str, Kind)] = &[
    ("hook_event_name", Kind::Str),
    ("session_id", Kind::NonEmptyStr),
];

/// `properties` of hook-payload.schema.json, less the required ones.
const PROPERTIES: &[(&str, Kind)] = &[
    ("_source", Kind::NonEmptyStr),
    ("_ppid", Kind::PidOrToken),
    ("_hook_ppid", Kind::PidOrToken),
    ("_via_plugin", Kind::Bool),
    ("_cursor_payload_digest", Kind::Hex64),
    ("_term_app", Kind::Str),
    ("_term_bundle", Kind::Str),
    ("_iterm_session", Kind::Str),
    ("_kitty_window", Kind::Str),
    ("_tmux", Kind::Str),
    ("_tmux_pane", Kind::Str),
    ("_tmux_client_tty", Kind::Str),
    ("_tty", Kind::StrOrNull),
    ("_cmux_surface_id", Kind::Str),
    ("_cmux_workspace_id", Kind::Str),
    ("_zellij", Kind::Str),
    ("_zellij_pane_id", Kind::Str),
    ("_zellij_session_name", Kind::Str),
    ("_wezterm_pane", Kind::Str),
    ("_herdr_pane_id", Kind::Str),
    ("_herdr_socket_path", Kind::Str),
    ("_herdr_bin_path", Kind::Str),
    ("_superset_workspace_id", Kind::Str),
    ("_superset_pane_id", Kind::Str),
    ("_orca_terminal_handle", Kind::Str),
    ("_orca_worktree_id", Kind::Str),
    ("_claude_desktop_session", Kind::Str),
    ("_hermes_home", Kind::Str),
    ("_hermes_store", Kind::Object),
    ("_remote_host_id", Kind::Str),
    ("_remote_host_name", Kind::Str),
    ("_untracked_process", Kind::Bool),
    ("_pi_tool_call_id", Kind::Str),
    ("_env", Kind::StrMap),
    ("_server_port", Kind::UInt),
    ("cwd", Kind::Str),
    ("transcript_path", Kind::Str),
    ("tool_name", Kind::StrOrNull),
    ("tool_input", Kind::ObjectOrNull),
    ("tool_use_id", Kind::Str),
    ("cursor_version", Kind::Str),
    ("conversation_id", Kind::Str),
    ("question", Kind::StrOrObject),
    ("options", Kind::Array),
    ("prompt", Kind::StrOrArray),
];

/// `patternProperties` of hook-payload.schema.json: every key with one of
/// these prefixes holds a string.
const STRING_PREFIXES: &[&str] = &["_cmux_", "_zellij", "_herdr_", "_superset_", "_orca_"];

/// A process id as a payload records it: a number, or the `$PID<n>` token
/// golden fixtures put in its place.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PidOrToken<'a> {
    Pid(u64),
    Token(&'a str),
}

/// The JSON object a bridge forwards to the island: the agent's stdin object
/// with HookIntake's `_` fields. Every key is kept, in the order it arrived,
/// whether this crate knows it or not.
#[derive(Clone, Debug, PartialEq)]
pub struct HookPayload {
    object: JsonObject,
    edge: Option<EdgeFacts>,
}

impl HookPayload {
    /// Checks `object` against hook-payload.schema.json.
    ///
    /// # Errors
    /// The first field that breaks the schema, or an `_edge` that breaks
    /// the edge facts' schema.
    pub fn from_object(object: JsonObject) -> Result<Self, ProtocolError> {
        Self::checked(object, "")
    }

    pub(crate) fn checked(object: JsonObject, prefix: &str) -> Result<Self, ProtocolError> {
        for &(key, kind) in REQUIRED {
            shape::require(&object, prefix, key, kind)?;
        }
        for &(key, kind) in PROPERTIES {
            shape::check(&object, prefix, key, kind)?;
        }
        for key in object.keys() {
            if STRING_PREFIXES.iter().any(|p| key.starts_with(p)) {
                shape::check(&object, prefix, key, Kind::Str)?;
            }
        }
        let edge = object
            .get(edge::KEY)
            .map(|value| EdgeFacts::from_value(value, &shape::path(prefix, edge::KEY)))
            .transpose()?;
        Ok(Self { object, edge })
    }

    /// The whole object, in arrival order.
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

    /// `hook_event_name`: present, as the schema requires; may be empty.
    #[must_use]
    pub fn hook_event_name(&self) -> &str {
        self.str("hook_event_name").unwrap_or_default()
    }

    /// `session_id`: present and non-empty, as the schema requires.
    #[must_use]
    pub fn session_id(&self) -> &str {
        self.str("session_id").unwrap_or_default()
    }

    /// `_source`: the source HookIntake attributed the hook to.
    #[must_use]
    pub fn source(&self) -> Option<&str> {
        self.str("_source")
    }

    /// `_ppid`: the long-lived agent process the island tracks.
    #[must_use]
    pub fn ppid(&self) -> Option<PidOrToken<'_>> {
        self.pid("_ppid")
    }

    /// `_hook_ppid`: the hook's immediate parent.
    #[must_use]
    pub fn hook_ppid(&self) -> Option<PidOrToken<'_>> {
        self.pid("_hook_ppid")
    }

    /// `_edge`, if the payload carries one.
    #[must_use]
    pub fn edge(&self) -> Option<&EdgeFacts> {
        self.edge.as_ref()
    }

    /// The [`TERMINAL_KEYS`] the payload holds a string for, in arrival order.
    /// A `_tty` of `null` is no terminal and is left out.
    pub fn terminal(&self) -> impl Iterator<Item = (&str, &str)> {
        self.object.iter().filter_map(|(key, value)| {
            let text = value.as_str()?;
            TERMINAL_KEYS
                .contains(&key.as_str())
                .then_some((key.as_str(), text))
        })
    }

    fn str(&self, key: &str) -> Option<&str> {
        self.object.get(key).and_then(Value::as_str)
    }

    fn pid(&self, key: &str) -> Option<PidOrToken<'_>> {
        match self.object.get(key)? {
            Value::String(token) => Some(PidOrToken::Token(token)),
            number => number.as_u64().map(PidOrToken::Pid),
        }
    }
}

/// Decodes a forwarded payload.
///
/// # Errors
/// Invalid JSON, anything but an object, or a field that breaks
/// hook-payload.schema.json.
pub fn decode_payload(bytes: &[u8]) -> Result<HookPayload, ProtocolError> {
    HookPayload::from_object(shape::decode_object(bytes, "payload")?)
}

/// Encodes a payload as compact JSON, every key in arrival order.
#[must_use]
pub fn encode_payload(payload: &HookPayload) -> Vec<u8> {
    shape::encode_object(&payload.object)
}
