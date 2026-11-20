//! Morrow's **core** (`GLOSSARY.md`): the pure domain library both shells
//! share. It runs no process, opens no file or socket and reads no
//! environment; whatever the OS knows comes in as values and closures.
//!
//! - [`intake`]: what one hook invocation means (`HookIntake` in
//!   `Sources/MorrowCore`), from the facts an edge observed.
//! - [`reduce`]: what a hook event does to the sessions (`reduceHookEvent`),
//!   with the clock and the custom sources handed in.
//! - [`attention`]: what a moment calls for (`AttentionPolicy.intents`) — a
//!   sound, a completion card, a push, a follow-up reminder.
//! - [`markdown`]: the block structure of an assistant reply, for the
//!   frontend to draw.
//! - [`git`]: the checked-out branch of a session's `cwd`, from `.git` read
//!   through a [`git::Disk`] the shell hands in.
//! - [`transcript`]: the live transcript's newest prompt, reply, turn status,
//!   Cursor question, idle recap and model tag, from the JSONL lines the
//!   platform watcher reads.
//! - [`session_recap`], [`model_label`], [`time`]: the pieces those readings
//!   are made of.
//! - [`agent_tasks`]: the agent's own checklist — the vocabulary and the
//!   events a hook or transcript row carries (the list that applies them is
//!   #138).
//! - [`digest`]: SHA-256, for the delivery digest of a hook Cursor ran.
#![forbid(unsafe_code)]

pub mod agent_tasks;
pub mod attention;
pub mod digest;
pub mod git;
pub mod intake;
pub mod markdown;
pub mod model_label;
pub mod reduce;
pub mod session_recap;
pub mod time;
pub mod transcript;

/// A JSON object, keys in arrival order.
pub type JsonObject = serde_json::Map<String, serde_json::Value>;
