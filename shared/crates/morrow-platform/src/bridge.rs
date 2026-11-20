//! Where the bridge binary lives after the app is installed (#104).
//!
//! The hook config a CLI keeps records an *absolute* path, so the bridge cannot
//! live inside an AppImage: the mount point changes on every launch and the
//! configured path dies with it. It is copied out once to `~/.local/bin`, which
//! is stable across formats (deb, rpm, AppImage) and across updates.
//!
//! The copy is atomic (temp + rename) because the bridge may be executing while
//! an update replaces it: a half-written file would fail a hook call rather than
//! delay it.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

/// The binary's file name, as every hook command spells it.
pub const NAME: &str = "morrow-bridge";

/// `~/.local/bin/morrow-bridge` — the path hook configs record.
pub fn stable_path(home: &Path) -> PathBuf {
    home.join(".local").join("bin").join(NAME)
}

/// `~/.codeisland/morrow-bridge` — where the first installer put it. Still
/// found by the hook script, so an install from before this change keeps
/// working rather than silently going quiet.
pub fn legacy_path(home: &Path) -> PathBuf {
    home.join(".codeisland").join(NAME)
}

/// What `ensure` did.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Placed {
    pub path: PathBuf,
    /// False when the destination already held the same bytes.
    pub copied: bool,
}

/// Put `source` at the stable path, unless it is already there with the same
/// content. An error is the sentence the installer reports.
pub fn ensure(source: &Path, home: &Path) -> io::Result<Placed> {
    let path = stable_path(home);
    let wanted = fs::read(source)?;
    if fs::read(&path).is_ok_and(|current| current == wanted) {
        return Ok(Placed {
            path,
            copied: false,
        });
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let temp = path.with_extension(format!("tmp{}", std::process::id()));
    fs::write(&temp, &wanted)?;
    // A Unix binary needs the executable bit; on Windows an .exe inherits the
    // folder's ACLs, which is the same rule (this user, `~/.local/bin`).
    #[cfg(unix)]
    fs::set_permissions(&temp, std::os::unix::fs::PermissionsExt::from_mode(0o755))?;
    fs::rename(&temp, &path)?;
    Ok(Placed { path, copied: true })
}
