//! The Claude Code hook installer on Windows (#108).
//!
//! Same policy as [`crate::hooks`] — plan the settings change first, refuse an
//! unparseable file, back up once, write only when the text changes — with the
//! three things Windows spells differently:
//!
//! | | Unix | Windows |
//! |---|---|---|
//! | home | `$HOME` | `%USERPROFILE%` |
//! | our folder | `~/.codeisland`, mode `0700` | `%USERPROFILE%\.codeisland`, ACLs inherited |
//! | the hook command runs | `/bin/sh` script | `morrow-hook.cmd`, so `cmd.exe` can run it |
//! | the bridge | `~/.local/bin/morrow-bridge` | `%USERPROFILE%\.local\bin\morrow-bridge.exe` |
//!
//! Compiled on every platform, like `windows_rules`: none of it needs Win32, and
//! a hook installer that can only be tested on Windows is a hook installer that
//! is not tested. The default paths come from `USERPROFILE`, which a test never
//! relies on.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use morrow_core::installer::claude_hooks;

pub use crate::hooks::{Error, Report, Status};

/// Bumped when the script below changes, so an install from an older build is
/// rewritten instead of left in place.
pub const HOOK_SCRIPT_VERSION: u32 = 1;

/// Where everything lives on Windows.
pub struct Paths {
    pub home: PathBuf,
    /// `%USERPROFILE%\.codeisland` — ours.
    pub codeisland_dir: PathBuf,
    /// The `.cmd` every hook command names.
    pub script: PathBuf,
    /// The bridge the script runs.
    pub bridge: PathBuf,
    /// The user's own file: `%CLAUDE_CONFIG_DIR%\settings.json` or
    /// `%USERPROFILE%\.claude\settings.json`.
    pub settings: PathBuf,
}

impl Paths {
    pub fn new(home: &Path, config_dir: Option<&Path>) -> Self {
        let codeisland_dir = home.join(".codeisland");
        let config_dir = config_dir.map_or_else(|| home.join(".claude"), Path::to_path_buf);
        Self {
            script: codeisland_dir.join("morrow-hook.cmd"),
            bridge: home.join(".local").join("bin").join("morrow-bridge.exe"),
            settings: config_dir.join("settings.json"),
            codeisland_dir,
            home: home.to_path_buf(),
        }
    }

    /// The paths of the machine this runs on: `%USERPROFILE%`, and
    /// `%CLAUDE_CONFIG_DIR%` when Claude Code was pointed elsewhere.
    pub fn probe() -> Self {
        let home = std::env::var_os("USERPROFILE")
            .or_else(|| std::env::var_os("HOME"))
            .map_or_else(|| PathBuf::from(r"C:\"), PathBuf::from);
        let config = std::env::var_os("CLAUDE_CONFIG_DIR").map(PathBuf::from);
        Self::new(&home, config.as_deref())
    }
}

/// What the settings file names as the command: the script's absolute path, in
/// quotes, because `cmd.exe` splits on spaces and a profile can contain one.
///
/// Absolute rather than `%USERPROFILE%`-relative on purpose: Claude Code passes
/// the string to `cmd.exe`, which expands `%NAME%` — but a hook command that
/// only works when the variable happens to exist is a hook command that stops
/// working in the one context nobody tested.
pub fn command(paths: &Paths) -> String {
    format!("\"{}\"", paths.script.display())
}

/// The script the hook command runs.
///
/// `%*` forwards whatever arguments the CLI passes, and a missing bridge is a
/// clean `exit /b 0`: a hook that fails on every tool call would be worse than
/// no hook at all.
pub fn hook_script() -> String {
    [
        "@echo off".to_owned(),
        format!(
            "rem {} - the bridge copied out of the package",
            version_marker()
        ),
        r#"set "BRIDGE=%USERPROFILE%\.local\bin\morrow-bridge.exe""#.to_owned(),
        r#"if not exist "%BRIDGE%" exit /b 0"#.to_owned(),
        r#""%BRIDGE%" %*"#.to_owned(),
    ]
    // CRLF: `cmd.exe` reads both, but a `.cmd` with bare LF confuses the
    // `if`/`exit` parsing in older builds, and the file costs nothing.
    .join("\r\n")
        + "\r\n"
}

/// Install or repair everything. `bridge_source` is the `.exe` shipped beside
/// the app; when it is missing the script still lands, and reports it.
pub fn install(
    paths: &Paths,
    bridge_source: Option<&Path>,
    version: Option<&str>,
    stamp: &str,
) -> Result<Report, Error> {
    // Plan first: a refusal leaves the machine as it was, script and exe too.
    let command = command(paths);
    let existing = read_text(&paths.settings)?;
    let plan = claude_hooks::install(existing.as_deref(), &command, version)
        .ok_or_else(|| Error::UnparseableSettings(paths.settings.clone()))?;

    let mut report = Report::default();

    fs::create_dir_all(&paths.codeisland_dir)?;
    match read_text(&paths.script)? {
        Some(text) if text.contains(&version_marker()) => {}
        _ => {
            fs::write(&paths.script, hook_script())?;
            report.script_written = true;
        }
    }

    if let Some(source) = bridge_source {
        report.bridge_copied = crate::bridge::ensure_at(source, &paths.bridge)?.copied;
    }

    if plan.changed {
        if existing.is_some() {
            report.backup = back_up(&paths.settings, stamp)?;
        }
        // A profile where Claude Code has never run has no `.claude` folder yet;
        // the settings file we are about to write is the reason to make it.
        if let Some(parent) = paths.settings.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(&paths.settings, &plan.text)?;
        report.settings_changed = true;
    }

    Ok(report)
}

/// Take the hook back out: our entries in `settings.json`, the script and the
/// exe. The user's own hooks stay, and a file that held only ours comes back
/// byte for byte.
pub fn uninstall(paths: &Paths) -> Result<Report, Error> {
    let existing = read_text(&paths.settings)?;
    let plan = match existing.as_deref() {
        Some(text) => claude_hooks::uninstall(text)
            .ok_or_else(|| Error::UnparseableSettings(paths.settings.clone()))?,
        None => return Ok(Report::default()),
    };

    let mut report = Report::default();
    if plan.changed {
        fs::write(&paths.settings, &plan.text)?;
        report.settings_changed = true;
    }
    report.script_written = remove_file(&paths.script)?;
    report.bridge_copied = remove_file(&paths.bridge)?;
    Ok(report)
}

/// What a Settings page shows.
pub fn status(paths: &Paths, version: Option<&str>) -> Status {
    let settings = read_text(&paths.settings).ok().flatten();
    let command = command(paths);
    Status {
        codeisland_dir: paths.codeisland_dir.clone(),
        script_installed: paths.script.is_file(),
        bridge_installed: paths.bridge.is_file(),
        hooks_installed: settings
            .as_deref()
            .is_some_and(|text| claude_hooks::is_installed(text, &command, version)),
        settings: paths.settings.clone(),
        settings_exists: paths.settings.is_file(),
    }
}

/// One back-up per file, ever, as on Unix: a second install does not pile them
/// up.
fn back_up(settings: &Path, stamp: &str) -> io::Result<Option<PathBuf>> {
    let directory = settings.parent().unwrap_or(Path::new("."));
    let names: Vec<String> = fs::read_dir(directory)?
        .filter_map(Result::ok)
        .filter_map(|entry| entry.file_name().into_string().ok())
        .collect();
    let Some(path) = claude_hooks::backup_path(&settings.to_string_lossy(), stamp, &names) else {
        return Ok(None);
    };
    fs::copy(settings, &path)?;
    Ok(Some(PathBuf::from(path)))
}

fn read_text(path: &Path) -> io::Result<Option<String>> {
    match fs::read_to_string(path) {
        Ok(text) => Ok(Some(text)),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error),
    }
}

fn remove_file(path: &Path) -> io::Result<bool> {
    match fs::remove_file(path) {
        Ok(()) => Ok(true),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(error),
    }
}

fn version_marker() -> String {
    format!("# Morrow hook v{HOOK_SCRIPT_VERSION}")
}
