//! The global hotkey (#101, L-007): one shortcut that brings the island up
//! wherever the user is.
//!
//! X11 grabs it directly. Wayland cannot, which is why the capability table
//! points at the desktop's own binding instead; a failed registration here is
//! reported the same way, never fatal.

use std::sync::OnceLock;

use morrow_platform::capability::Capability;
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};

/// The default binding. `Super+Space` is unclaimed on most desktops; Settings
/// will grow a field for it, which is why it lives in one place.
pub const DEFAULT: &str = "Super+Space";

static OUTCOME: OnceLock<Capability> = OnceLock::new();

pub fn outcome() -> Option<Capability> {
    OUTCOME.get().cloned()
}

/// Register the shortcut, recording what happened for the Capability table.
pub fn install(app: &tauri::AppHandle) {
    let shortcut: Shortcut = match DEFAULT.parse() {
        Ok(shortcut) => shortcut,
        Err(error) => {
            let _ = OUTCOME.set(Capability::Unsupported(format!(
                "{DEFAULT} is not a shortcut: {error}"
            )));
            return;
        }
    };
    let result = app
        .global_shortcut()
        .on_shortcut(shortcut, |app, _shortcut, event| {
            if event.state() == ShortcutState::Pressed {
                crate::tray::toggle_island(app);
            }
        });
    let _ = OUTCOME.set(match &result {
        Ok(()) => Capability::Supported,
        Err(error) => Capability::Degraded(format!(
            "could not grab {DEFAULT}: {error}; bind `morrow toggle` in the desktop instead"
        )),
    });
    if let Err(error) = result {
        eprintln!("morrow-app: global hotkey unavailable ({error})");
    }
}
