use serde_json::Number;

/// Why bytes are not a shape of the contract. `field` is a dotted path from
/// the decoded object, e.g. `payload.session_id` or `_edge.host.id`.
#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum ProtocolError {
    #[error("invalid JSON: {0}")]
    Json(#[from] serde_json::Error),

    #[error("{field} must be a JSON object, found {found}")]
    NotAnObject { field: String, found: &'static str },

    #[error("missing required field `{field}`")]
    MissingField { field: String },

    #[error("field `{field}` must be {expected}")]
    InvalidField {
        field: String,
        expected: &'static str,
    },

    #[error("field `{field}` is not allowed")]
    ForbiddenField { field: String },

    #[error("unsupported envelope version {found} (this build reads {supported})")]
    UnsupportedVersion { found: Number, supported: u64 },

    #[error("neither an IPC envelope (`v` and `payload`) nor an edge payload (`_edge`)")]
    NotAnEnvelope,
}
