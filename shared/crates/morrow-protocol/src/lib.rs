//! The wire shapes of Morrow's contract (`schemas/hook-payload.schema.json`,
//! `schemas/hook-envelope.schema.json`, `shared/contract/hook-edge-protocol.md`):
//!
//! - [`HookPayload`]: the JSON object a bridge forwards to the island.
//! - [`EdgeFacts`]: the `_edge` object an edge that cannot run HookIntake
//!   sends next to the agent's stdin object, in an [`EdgePayload`].
//! - [`Envelope`]: what arrives on the endpoint, either a versioned IPC
//!   envelope around a [`HookPayload`] or an [`EdgePayload`].
//!
//! Decoding checks the shape the schemas define and nothing more; encoding
//! writes back every key, known or not, in the order it arrived. What a
//! payload *means* is HookIntake's business, not this crate's.
#![forbid(unsafe_code)]

mod edge;
mod envelope;
mod error;
mod payload;
mod shape;

pub use edge::{EDGE_FACTS_VERSION, EdgeFacts, EdgeHost, EdgePayload};
pub use envelope::{Envelope, IPC_ENVELOPE_VERSION, decode_envelope, encode_envelope};
pub use error::ProtocolError;
pub use payload::{HookPayload, PidOrToken, TERMINAL_KEYS, decode_payload, encode_payload};

/// The JSON object every shape is built on. Key order is preserved.
pub type JsonObject = serde_json::Map<String, serde_json::Value>;
