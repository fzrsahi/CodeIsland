//! The Settings card's side of the hook installer (`morrow-platform::hooks`):
//! report state, install or repair, remove. The panel never needs this; the
//! user opens Settings and asks for it.

use std::path::PathBuf;

use morrow_platform::hooks::{self, Paths, Report, Status};
use tauri::State;

use crate::HooksSite;

/// What the card shows.
#[derive(serde::Serialize)]
pub struct HooksSnapshot {
    status: Status,
    /// The Claude Code version the plan was made for, from `claude --version`.
    version: Option<String>,
}

/// Read the state of the install.
#[tauri::command]
pub fn hooks_status(site: State<'_, HooksSite>) -> HooksSnapshot {
    let version = claude_version();
    HooksSnapshot {
        status: hooks::status(&site.paths, version.as_deref()),
        version,
    }
}

/// Install or repair.
#[tauri::command]
pub fn hooks_install(site: State<'_, HooksSite>) -> Result<Report, String> {
    let version = claude_version();
    let stamp = stamp();
    hooks::install(
        &site.paths,
        site.bridge_source.as_deref(),
        version.as_deref(),
        &stamp,
    )
    .map_err(|error| error.to_string())
}

/// Remove: the script, the bridge, and our entries in `settings.json`.
#[tauri::command]
pub fn hooks_uninstall(site: State<'_, HooksSite>) -> Result<Report, String> {
    hooks::uninstall(&site.paths).map_err(|error| error.to_string())
}

/// `$CLAUDE_CONFIG_DIR` when set, `~/.claude` otherwise; the bridge beside the
/// app binary unless `$MORROW_BRIDGE_PATH` names another.
pub fn site() -> HooksSite {
    let home = std::env::var_os("HOME").map_or_else(|| PathBuf::from("/"), PathBuf::from);
    let config_dir = std::env::var_os("CLAUDE_CONFIG_DIR")
        .map(PathBuf::from)
        .filter(|path| !path.as_os_str().is_empty());
    HooksSite {
        paths: Paths::new(&home, config_dir.as_deref()),
        bridge_source: bridge_source(),
    }
}

fn bridge_source() -> Option<PathBuf> {
    if let Some(explicit) = std::env::var_os("MORROW_BRIDGE_PATH").map(PathBuf::from) {
        return explicit.is_file().then_some(explicit);
    }
    // Beside the app binary, which is where a deb, an AppImage and a `cargo
    // run` all put the two together.
    let exe = std::env::current_exe().ok()?;
    let sibling = exe.parent()?.join("morrow-bridge");
    sibling.is_file().then_some(sibling)
}

/// `claude --version` → `"2.1.89"`. Unknown when it is not installed, when it
/// answers something else, or when it hangs: the gated events then stay out.
fn claude_version() -> Option<String> {
    let output = std::process::Command::new("claude")
        .arg("--version")
        .output()
        .ok()?;
    let text = String::from_utf8_lossy(&output.stdout);
    let first = text.split_whitespace().next()?;
    let numeric = first
        .trim_start_matches('v')
        .split('-')
        .next()
        .unwrap_or(first);
    numeric
        .split('.')
        .all(|part| part.parse::<u32>().is_ok())
        .then(|| numeric.to_owned())
}

/// Seconds since the epoch, for the back-up name: unique enough for one
/// machine's first write, and not worth a date library.
fn stamp() -> String {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_secs().to_string())
        .unwrap_or_else(|_| "0".to_owned())
}
