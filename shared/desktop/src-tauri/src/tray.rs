//! The tray icon (#101, L-006): a menu that reaches the island when the island
//! itself is out of the way.
//!
//! On Linux this is a StatusNotifierItem through AppIndicator, which the desktop
//! has to provide. When it is not there the tray is simply absent — the panel
//! keeps working, and Settings says why (`capability::Feature::Tray`).

use std::sync::OnceLock;

use morrow_platform::capability::Capability;
use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{App, Manager};

use crate::island;

/// What actually happened, for the Capability table: the probe cannot know
/// whether the status notifier registered, only whether the library is there.
static OUTCOME: OnceLock<Capability> = OnceLock::new();

pub fn outcome() -> Option<Capability> {
    OUTCOME.get().cloned()
}

/// Build the tray. A failure is recorded, not fatal: the island is the app.
pub fn create(app: &App) {
    let result = build(app);
    let _ = OUTCOME.set(match &result {
        Ok(()) => Capability::Supported,
        Err(error) => Capability::Degraded(format!("no tray icon: {error}")),
    });
    if let Err(error) = result {
        eprintln!("morrow-app: tray unavailable ({error}); the island still works");
    }
}

fn build(app: &App) -> tauri::Result<()> {
    let toggle = MenuItem::with_id(app, "toggle", "Show or hide the island", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit Morrow", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&toggle, &quit])?;

    TrayIconBuilder::with_id("morrow")
        .tooltip("Morrow")
        .menu(&menu)
        .show_menu_on_left_click(true)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "toggle" => toggle_island(app),
            "quit" => app.exit(0),
            _ => {}
        })
        .build(app)?;
    Ok(())
}

/// Show the island if it is hidden, hide it if it is showing.
pub fn toggle_island(app: &tauri::AppHandle) {
    let Some(window) = app.get_webview_window(island::LABEL) else {
        return;
    };
    let visible = window.is_visible().unwrap_or(false);
    if visible {
        let _ = window.hide();
    } else {
        let _ = window.show();
    }
}
