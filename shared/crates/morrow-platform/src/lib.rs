//! `morrow-platform`: the OS-facing half of the port (plan §5.2).
//!
//! Crates here touch the file system and the environment; the policy stays in
//! `morrow-core`. One rule holds throughout: the user's own files are theirs,
//! so a write happens only after a back-up and only of the bytes we came for.
//!
//! `terminal`, `process`, `lock` and `notify` are #103's adapters: jump to a
//! session's window (or hand over its path — L-009's floor), notice a process
//! that ended without walking the process table, go quiet while the screen is
//! locked, and post a reminder. `runner` is the one seam they all share: the
//! tools a desktop already ships, injected so every adapter is testable without
//! a desktop behind it.
//!
//! `capability` answers what each adapter can do on this machine — every
//! feature reports `Supported`, `Degraded(reason)` or `Unsupported(reason)`, so
//! Settings can say "no tray icon: no AppIndicator library" instead of the
//! feature silently not working.

pub mod autostart;
pub mod capability;
pub mod hooks;
pub mod kimi;
pub mod lock;
pub mod music;
pub mod notify;
pub mod opencode;
pub mod process;
pub mod runner;
pub mod settings;
pub mod terminal;
pub mod yaml_hooks;
