//! Editing a CLI's config file without disturbing the user's own bytes
//! (`Sources/Morrow/JSONMinimalEditor.swift`, `ConfigInstaller.swift`).
//!
//! The config *files* belong to the user: comments, key order and the trailing
//! newline matter. [`json_editor`] replaces the text range of one top-level
//! key and leaves everything else alone; [`claude_hooks`] is the Claude Code
//! slice of the installer, ported as a plan over text — the platform reads the
//! file, writes the result and keeps the back-up.

pub mod claude_hooks;
pub mod codex_config;
pub mod json_editor;
pub mod kimi;
pub mod opencode;
pub mod settings;
pub mod targets;
pub mod yaml_hooks;
