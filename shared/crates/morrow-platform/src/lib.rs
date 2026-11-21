//! `morrow-platform`: the OS-facing half of the port (plan §5.2).
//!
//! Crates here touch the file system and the environment; the policy stays in
//! `morrow-core`. One rule holds throughout: the user's own files are theirs,
//! so a write happens only after a back-up and only of the bytes we came for.

pub mod hooks;
pub mod opencode;
