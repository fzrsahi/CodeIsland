//! Morrow's **core** (`GLOSSARY.md`): the pure domain library both shells
//! share. It runs no process, opens no file or socket and reads no
//! environment; whatever the OS knows comes in as values and closures.
//!
//! - [`intake`]: what one hook invocation means (`HookIntake` in
//!   `Sources/MorrowCore`), from the facts an edge observed.
//! - [`digest`]: SHA-256, for the delivery digest of a hook Cursor ran.
#![forbid(unsafe_code)]

pub mod digest;
pub mod intake;

/// A JSON object, keys in arrival order.
pub type JsonObject = serde_json::Map<String, serde_json::Value>;
