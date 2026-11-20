//! `morrow-platform`: the OS-facing half of the port (plan §5.2).
//!
//! Crates here touch the file system and the environment; the policy stays in
//! `morrow-core`. One rule holds throughout: the user's own files are theirs,
//! so a write happens only after a back-up and only of the bytes we came for.
//!
//! `capability` answers what each adapter can do on this machine — every
//! feature reports `Supported`, `Degraded(reason)` or `Unsupported(reason)`, so
//! Settings can say "no tray icon: no AppIndicator library" instead of the
//! feature silently not working.

pub mod autostart;
pub mod capability;
pub mod hooks;
pub mod kimi;
pub mod opencode;
pub mod settings;
pub mod yaml_hooks;
