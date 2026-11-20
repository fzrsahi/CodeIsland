//! The Settings page's other half (#101): the Capability table, start at login,
//! and the settings file itself. Batch 1 of the adapters — tray, hotkey and the
//! rest of the runtime wiring come with the panel work they depend on.

use std::path::PathBuf;

use morrow_platform::capability::{self, Feature};
use morrow_platform::{autostart, settings};
use serde_json::Value;
use tauri::State;

use crate::HooksSite;

/// Every adapter and what it can do on this machine.
///
/// The probes read the environment; for the two adapters that register at
/// startup, what actually happened wins over what was expected — a tray whose
/// status notifier did not come up says so, rather than repeating the guess.
#[tauri::command]
pub fn capabilities() -> Vec<capability::Row> {
    let mut rows = capability::table(&capability::Environment::probe());
    for (feature, outcome) in [
        (Feature::Tray, crate::tray::outcome()),
        (Feature::GlobalHotkey, crate::hotkey::outcome()),
    ] {
        if let (Some(outcome), Some(row)) = (
            outcome,
            rows.iter_mut().find(|row| row.feature == feature.name()),
        ) {
            row.capability = outcome;
        }
    }
    rows
}

/// Whether the autostart entry is there.
#[tauri::command]
pub fn autostart_status(site: State<'_, HooksSite>) -> autostart::Status {
    autostart::status(&site.paths.home.join(".config"))
}

/// Install or remove the autostart entry. Returns whether anything changed.
#[tauri::command]
pub fn autostart_set(site: State<'_, HooksSite>, enabled: bool) -> Result<bool, String> {
    let config_home = site.paths.home.join(".config");
    if enabled {
        let executable = std::env::current_exe().map_err(|error| error.to_string())?;
        autostart::install(&config_home, &executable).map_err(|error| error.to_string())
    } else {
        autostart::uninstall(&config_home).map_err(|error| error.to_string())
    }
}

/// The user's settings document.
#[tauri::command]
pub fn settings_load(site: State<'_, HooksSite>) -> Result<Value, String> {
    settings::load(&site.paths.codeisland_dir).map_err(|error| error.to_string())
}

/// Set one top-level setting.
#[tauri::command]
pub fn settings_set(site: State<'_, HooksSite>, key: String, value: Value) -> Result<bool, String> {
    settings::set(&site.paths.codeisland_dir, &key, &value).map_err(|error| error.to_string())
}

/// Where the settings file is, for a "reveal" button.
#[tauri::command]
pub fn settings_path(site: State<'_, HooksSite>) -> PathBuf {
    settings::path(&site.paths.codeisland_dir)
}
