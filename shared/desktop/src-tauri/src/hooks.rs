//! The Settings card's side of the hook installer (`morrow-platform::hooks`):
//! report state, install or repair, remove. The panel never needs this; the
//! user opens Settings and asks for it.

use std::path::PathBuf;

use morrow_platform::hooks::{self, Paths, Report, Status, TargetStatus};
use morrow_platform::kimi;
use morrow_platform::opencode;
use tauri::State;

use crate::HooksSite;

/// What the card shows.
#[derive(serde::Serialize)]
pub struct HooksSnapshot {
    status: Status,
    /// The other hook targets and where each one's file stands.
    targets: Vec<TargetStatus>,
    /// OpenCode: a plugin file rather than a hooks key.
    opencode: opencode::Status,
    /// Kimi: hooks in a TOML file, appended rather than re-serialised.
    kimi: kimi::Status,
    /// The Claude Code version the plan was made for, from `claude --version`.
    version: Option<String>,
}

/// Read the state of the install.
#[tauri::command]
pub fn hooks_status(site: State<'_, HooksSite>) -> HooksSnapshot {
    let version = claude_version();
    HooksSnapshot {
        status: hooks::status(&site.paths, version.as_deref()),
        targets: hooks::targets_status(&site.paths),
        opencode: opencode::status(&site.opencode),
        kimi: kimi::status(&site.kimi),
        version,
    }
}

/// Install or repair OpenCode's plugin. `false` when OpenCode is not on this
/// machine or its config does not parse.
#[tauri::command]
pub fn opencode_install(site: State<'_, HooksSite>) -> Result<bool, String> {
    opencode::install(&site.opencode, &stamp())
        .map(|done| done.is_some())
        .map_err(|error| error.to_string())
}

/// Install or repair Kimi's `[[hooks]]` blocks. `false` when Kimi is not on
/// this machine.
#[tauri::command]
pub fn kimi_install(site: State<'_, HooksSite>) -> Result<bool, String> {
    kimi::install(&site.kimi, &stamp())
        .map(|done| done.is_some())
        .map_err(|error| error.to_string())
}

/// Take Kimi's blocks back out, restoring a legacy scalar if there was one.
#[tauri::command]
pub fn kimi_uninstall(site: State<'_, HooksSite>) -> Result<bool, String> {
    kimi::uninstall(&site.kimi, &stamp())
        .map(|done| done.is_some())
        .map_err(|error| error.to_string())
}

/// Take OpenCode's plugin and its registration back out.
#[tauri::command]
pub fn opencode_uninstall(site: State<'_, HooksSite>) -> Result<bool, String> {
    opencode::uninstall(&site.opencode, &stamp())
        .map(|done| done.is_some())
        .map_err(|error| error.to_string())
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

/// Install or repair one of the other CLIs (`None` when that CLI is not on
/// this machine, so there is nothing to hook).
#[tauri::command]
pub fn target_install(
    site: State<'_, HooksSite>,
    source: String,
) -> Result<Option<Report>, String> {
    hooks::install_target(&site.paths, &source, &stamp()).map_err(|error| error.to_string())
}

/// Take one CLI's hook back out.
#[tauri::command]
pub fn target_uninstall(
    site: State<'_, HooksSite>,
    source: String,
) -> Result<Option<Report>, String> {
    hooks::uninstall_target(&site.paths, &source).map_err(|error| error.to_string())
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
        kimi: kimi::Site::new(&home),
        opencode: opencode::Site::new(&home),
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
