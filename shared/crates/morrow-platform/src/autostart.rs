//! Start at login, the FreeDesktop way: an entry in
//! `$XDG_CONFIG_HOME/autostart` (`Settings.swift:800`'s `SMAppService`
//! counterpart).
//!
//! The file is ours — nothing else writes it — so it is written whole and
//! removed whole; there is no user data to preserve. `Hidden=true` rather than
//! deleting, when the desktop expects the entry to stay, would only confuse
//! `status`, so this installs and removes.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

/// The entry's file name. `morrow.desktop`, like the app.
pub const ENTRY: &str = "morrow.desktop";

/// Where the entry goes.
pub fn path(config_home: &Path) -> PathBuf {
    config_home.join("autostart").join(ENTRY)
}

/// The entry for a binary at `executable`.
///
/// `X-GNOME-Autostart-enabled` and `OnlyShowIn` are left out on purpose: the
/// entry is one line of intent, and every desktop that reads `autostart`
/// understands it.
pub fn entry(executable: &Path) -> String {
    let exec = executable.display().to_string();
    // Desktop Entry quoting: an argument with spaces or reserved characters is
    // wrapped in double quotes, with `"` and `\` escaped.
    let exec = if exec.contains(' ') || exec.contains('"') || exec.contains('\\') {
        format!("\"{}\"", exec.replace('\\', "\\\\").replace('"', "\\\""))
    } else {
        exec
    };
    format!(
        "[Desktop Entry]\n\
         Type=Application\n\
         Name=Morrow\n\
         Comment=The island that tells you what your agents are doing\n\
         Exec={exec}\n\
         Terminal=false\n\
         X-GNOME-Autostart-enabled=true\n"
    )
}

/// What the card shows.
#[derive(Debug, PartialEq, Eq, serde::Serialize)]
pub struct Status {
    pub installed: bool,
    pub path: PathBuf,
}

pub fn status(config_home: &Path) -> Status {
    let path = path(config_home);
    Status {
        installed: path.is_file(),
        path,
    }
}

/// Write the entry. Returns whether anything changed.
pub fn install(config_home: &Path, executable: &Path) -> io::Result<bool> {
    let path = path(config_home);
    let wanted = entry(executable);
    if fs::read_to_string(&path).is_ok_and(|existing| existing == wanted) {
        return Ok(false);
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(&path, wanted)?;
    Ok(true)
}

/// Remove the entry. Returns whether anything was removed.
pub fn uninstall(config_home: &Path) -> io::Result<bool> {
    match fs::remove_file(path(config_home)) {
        Ok(()) => Ok(true),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(error),
    }
}
