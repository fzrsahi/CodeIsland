//! What arrives on the endpoint (hook-envelope.schema.json): one of
//! `$defs/ipcEnvelopeV1` or `$defs/edgePayload`.

use serde_json::Value;

use crate::edge::{self, EdgePayload};
use crate::payload::HookPayload;
use crate::shape;
use crate::{JsonObject, ProtocolError};

/// The IPC envelope version this build reads and writes.
pub const IPC_ENVELOPE_VERSION: u64 = 1;

/// One request on the endpoint.
#[derive(Clone, Debug, PartialEq)]
pub enum Envelope {
    /// `{"v": 1, "payload": {…}}`: a payload a bridge already interpreted.
    Ipc(HookPayload),
    /// The agent's stdin object plus `_edge`: facts for HookIntake.
    Edge(EdgePayload),
}

/// Decodes a request. An object with `_edge` is an edge payload (the IPC
/// envelope allows no key but `v` and `payload`); otherwise it must be an IPC
/// envelope, and a `v` other than [`IPC_ENVELOPE_VERSION`] is refused before
/// anything else is read.
///
/// # Errors
/// Invalid JSON, anything but an object, an unsupported `v`, a key the
/// envelope does not allow, or a payload or facts that break their schema.
pub fn decode_envelope(bytes: &[u8]) -> Result<Envelope, ProtocolError> {
    let object = shape::decode_object(bytes, "envelope")?;
    if object.contains_key(edge::KEY) {
        return EdgePayload::from_object(object).map(Envelope::Edge);
    }
    decode_ipc(object).map(Envelope::Ipc)
}

fn decode_ipc(mut object: JsonObject) -> Result<HookPayload, ProtocolError> {
    match object.get("v") {
        None if object.contains_key("payload") => {
            return Err(ProtocolError::MissingField {
                field: "v".to_owned(),
            });
        }
        None => return Err(ProtocolError::NotAnEnvelope),
        Some(Value::Number(v)) if v.as_u64() == Some(IPC_ENVELOPE_VERSION) => {}
        Some(Value::Number(v)) if v.is_i64() || v.is_u64() => {
            return Err(ProtocolError::UnsupportedVersion {
                found: v.clone(),
                supported: IPC_ENVELOPE_VERSION,
            });
        }
        Some(_) => {
            return Err(ProtocolError::InvalidField {
                field: "v".to_owned(),
                expected: "an integer",
            });
        }
    }
    if let Some(key) = object.keys().find(|key| *key != "v" && *key != "payload") {
        return Err(ProtocolError::ForbiddenField { field: key.clone() });
    }
    let payload = object
        .remove("payload")
        .ok_or_else(|| ProtocolError::MissingField {
            field: "payload".to_owned(),
        })?;
    HookPayload::checked(shape::into_object(payload, "payload")?, "payload")
}

/// Encodes a request as compact JSON. An IPC envelope is written
/// `{"v":1,"payload":…}`; an edge payload as it arrived.
#[must_use]
pub fn encode_envelope(envelope: &Envelope) -> Vec<u8> {
    match envelope {
        Envelope::Ipc(payload) => {
            let mut bytes = format!(r#"{{"v":{IPC_ENVELOPE_VERSION},"payload":"#).into_bytes();
            bytes.extend(crate::encode_payload(payload));
            bytes.push(b'}');
            bytes
        }
        Envelope::Edge(edge) => shape::encode_object(edge.as_object()),
    }
}
