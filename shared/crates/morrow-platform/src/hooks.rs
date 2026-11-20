//! Installing, repairing and removing the Claude Code hook on this machine
//! (`ConfigInstaller.install()` / `uninstall()` / `isInstalled()`, Claude
//! slice).
//!
//! The policy is `morrow_core::installer::claude_hooks`; this is the part that
//! needs a file system: `~/.codeisland` (ours, 0700), the hook script, the
//! bridge binary beside it, and the user's `settings.json` (theirs — backed up
//! once, and never rewritten when it does not parse).

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use morrow_core::installer::claude_hooks;
use morrow_core::installer::codex_config;
use morrow_core::installer::targets::{self, Target};

/// Bumped when the script below changes, so an install from an older build is
/// rewritten instead of left in place (`hookScriptVersion`).
pub const HOOK_SCRIPT_VERSION: u32 = 2;

/// What the hook command runs. The stable path first, the older in-app one
/// second, so a machine installed before #104 keeps working; a missing binary is
/// a clean no-op instead of an error on every tool call.
pub fn hook_script() -> String {
    format!(
        "#!/bin/sh\n\
         {marker} — the bridge binary, copied out of the package to a stable path\n\
         BRIDGE=\"$HOME/.local/bin/morrow-bridge\"\n\
         [ -x \"$BRIDGE\" ] || BRIDGE=\"$HOME/.codeisland/morrow-bridge\"\n\
         [ -x \"$BRIDGE\" ] || exit 0\n\
         exec \"$BRIDGE\" \"$@\"\n",
        marker = version_marker(),
    )
}

/// Where everything lives. `config_dir` is Claude Code's, i.e.
/// `$CLAUDE_CONFIG_DIR` when set, `~/.claude` otherwise.
pub struct Paths {
    /// The user's home: every other CLI's file hangs off it.
    pub home: PathBuf,
    /// `~/.codeisland` — this user's alone; holds sessions and the hook.
    pub codeisland_dir: PathBuf,
    /// The script every hook command names.
    pub script: PathBuf,
    /// The bridge binary the script runs.
    pub bridge: PathBuf,
    /// The user's own file.
    pub settings: PathBuf,
}

impl Paths {
    pub fn new(home: &Path, config_dir: Option<&Path>) -> Self {
        let codeisland_dir = home.join(".codeisland");
        let config_dir = config_dir.map_or_else(|| home.join(".claude"), Path::to_path_buf);
        Self {
            home: home.to_path_buf(),
            script: codeisland_dir.join("codeisland-hook.sh"),
            bridge: crate::bridge::stable_path(home),
            settings: config_dir.join("settings.json"),
            codeisland_dir,
        }
    }
}

/// What is on disk right now.
#[derive(Debug, PartialEq, Eq, serde::Serialize)]
pub struct Status {
    pub codeisland_dir: PathBuf,
    pub script_installed: bool,
    pub bridge_installed: bool,
    /// Every event of this build carries our hook, with no stale `async` key.
    pub hooks_installed: bool,
    pub settings: PathBuf,
    pub settings_exists: bool,
}

/// One of the other hook targets, and where its file stands.
#[derive(Debug, PartialEq, Eq, serde::Serialize)]
pub struct TargetStatus {
    pub source: &'static str,
    pub name: &'static str,
    /// The CLI's own directory is there: without it there is nothing to hook
    /// (`installExternalHooks` skips rather than creating one).
    pub detected: bool,
    pub installed: bool,
    pub path: PathBuf,
}

/// Every target the core knows, in table order.
pub fn targets_status(paths: &Paths) -> Vec<TargetStatus> {
    targets::TARGETS
        .iter()
        .map(|target| {
            let path = paths.home.join(target.path);
            let text = read_text(&path).ok().flatten();
            TargetStatus {
                source: target.source,
                name: target.name,
                detected: cli_dir_exists(paths, target),
                installed: text
                    .as_deref()
                    .is_some_and(|text| targets::is_installed(target, text)),
                path,
            }
        })
        .collect()
}

/// The directory each CLI proves itself by. Codex keeps `~/.codex`, Gemini
/// `~/.gemini`; a file the user has never run their CLI for is ours to leave
/// alone.
const CLI_DIRS: &[(&str, &str)] = &[
    ("codex", ".codex"),
    ("gemini", ".gemini"),
    ("cursor", ".cursor"),
    ("qoder", ".qoder"),
    ("droid", ".factory"),
    ("codebuddy", ".codebuddy"),
    ("copilot", ".copilot"),
];

/// Install or repair one target. `None` when the CLI is not on this machine, or
/// when its file does not parse as a JSON object (nothing is written then).
pub fn install_target(paths: &Paths, source: &str, stamp: &str) -> Result<Option<Report>, Error> {
    let Some(target) = targets::target_for(source) else {
        return Err(Error::Io(io::Error::new(
            io::ErrorKind::NotFound,
            format!("no hook target named {source}"),
        )));
    };
    if !cli_dir_exists(paths, target) {
        return Ok(None);
    }
    let path = paths.home.join(target.path);
    let existing = read_text(&path)?;
    let outcome = targets::install(target, existing.as_deref(), claude_hooks::HOOK_COMMAND)
        .ok_or_else(|| Error::UnparseableSettings(path.clone()))?;

    let mut report = Report::default();
    if outcome.changed {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        if existing.is_some() {
            report.backup = back_up(&path, stamp)?;
        }
        fs::write(&path, &outcome.text)?;
        report.settings_changed = true;
    }

    // Codex only reads `hooks.json` when `config.toml` turns the feature on
    // (`enableCodexFeatureFlag`).
    if target.source == "codex" {
        report.flag_enabled = enable_codex_hooks(paths)?;
    }
    Ok(Some(report))
}

/// `features.hooks = true` in `~/.codex/config.toml`, or an error when that
/// file's layout is one the editor will not touch.
fn enable_codex_hooks(paths: &Paths) -> Result<bool, Error> {
    let config_path = paths.home.join(".codex/config.toml");
    let existing = read_text(&config_path)?.unwrap_or_default();
    let Some(updated) = codex_config::enabling_hooks(&existing) else {
        return Err(Error::UnparseableSettings(config_path));
    };
    if updated == existing {
        return Ok(false);
    }
    if let Some(parent) = config_path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(&config_path, updated)?;
    Ok(true)
}

/// Take one target's hook back out.
pub fn uninstall_target(paths: &Paths, source: &str) -> Result<Option<Report>, Error> {
    let Some(target) = targets::target_for(source) else {
        return Err(Error::Io(io::Error::new(
            io::ErrorKind::NotFound,
            format!("no hook target named {source}"),
        )));
    };
    let path = paths.home.join(target.path);
    let Some(existing) = read_text(&path)? else {
        return Ok(None);
    };
    let outcome = targets::uninstall(target, &existing)
        .ok_or_else(|| Error::UnparseableSettings(path.clone()))?;
    let mut report = Report::default();
    if outcome.changed {
        fs::write(&path, &outcome.text)?;
        report.settings_changed = true;
    }
    Ok(Some(report))
}

fn cli_dir_exists(paths: &Paths, target: &Target) -> bool {
    CLI_DIRS
        .iter()
        .find(|(source, _)| *source == target.source)
        .is_none_or(|(_, directory)| paths.home.join(directory).is_dir())
}

/// What an install or uninstall did.
#[derive(Debug, Default, PartialEq, Eq, serde::Serialize)]
pub struct Report {
    pub script_written: bool,
    pub bridge_copied: bool,
    pub settings_changed: bool,
    /// Codex's `features.hooks = true` was added (or flipped) in `config.toml`.
    pub flag_enabled: bool,
    /// The back-up this run made, if it made one.
    pub backup: Option<PathBuf>,
}

#[derive(Debug)]
pub enum Error {
    /// The user's `settings.json` is not a JSON object. It stays untouched
    /// (#89): a settings file that half-parses is worth more than ours.
    UnparseableSettings(PathBuf),
    /// The core refused a layout rather than guess at it — an inline `hooks:`
    /// value, tab indentation. The file is untouched.
    Refused(String),
    Io(io::Error),
}

impl From<io::Error> for Error {
    fn from(error: io::Error) -> Self {
        Self::Io(error)
    }
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::UnparseableSettings(path) => write!(
                f,
                "{} is not a JSON object; leaving it alone",
                path.display()
            ),
            Self::Refused(reason) => write!(f, "not written: {reason}"),
            Self::Io(error) => write!(f, "{error}"),
        }
    }
}

impl std::error::Error for Error {}

/// Install or repair everything. `bridge_source` is the binary shipped beside
/// the app; when it is missing the script still lands, and reports it.
pub fn install(
    paths: &Paths,
    bridge_source: Option<&Path>,
    version: Option<&str>,
    stamp: &str,
) -> Result<Report, Error> {
    // Plan the settings change first: a refusal must leave the machine as it
    // was, script and binary included.
    let existing = read_text(&paths.settings)?;
    let plan = existing
        .as_deref()
        .map_or_else(
            || claude_hooks::install(None, claude_hooks::HOOK_COMMAND, version),
            |text| claude_hooks::install(Some(text), claude_hooks::HOOK_COMMAND, version),
        )
        .ok_or_else(|| Error::UnparseableSettings(paths.settings.clone()))?;

    let mut report = Report::default();

    fs::create_dir_all(&paths.codeisland_dir)?;
    private(&paths.codeisland_dir, 0o700)?;

    match read_text(&paths.script)? {
        Some(text) if text.contains(&version_marker()) => private(&paths.script, 0o700)?,
        _ => {
            write_script(&paths.script)?;
            report.script_written = true;
        }
    }

    if let Some(source) = bridge_source {
        report.bridge_copied = crate::bridge::ensure(source, &paths.home)?.copied;
    }

    if plan.changed {
        if existing.is_some() {
            report.backup = back_up(&paths.settings, stamp)?;
        }
        fs::write(&paths.settings, &plan.text)?;
        report.settings_changed = true;
    }

    Ok(report)
}

/// Take the hook back out: the script, the bridge, and our entries in
/// `settings.json` — which comes back byte for byte when it held only ours.
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
    Status {
        codeisland_dir: paths.codeisland_dir.clone(),
        script_installed: paths.script.is_file(),
        bridge_installed: paths.bridge.is_file(),
        hooks_installed: settings.as_deref().is_some_and(|text| {
            claude_hooks::is_installed(text, claude_hooks::HOOK_COMMAND, version)
        }),
        settings: paths.settings.clone(),
        settings_exists: paths.settings.is_file(),
    }
}

fn version_marker() -> String {
    format!("# Morrow hook v{HOOK_SCRIPT_VERSION}")
}

pub(crate) fn read_text(path: &Path) -> io::Result<Option<String>> {
    match fs::read(path) {
        Ok(bytes) => Ok(String::from_utf8(bytes).ok()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error),
    }
}

/// 0700: `~/.codeisland` holds this user's prompts and replies.
fn private(path: &Path, mode: u32) -> io::Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(path, fs::Permissions::from_mode(mode))?;
    }
    #[cfg(not(unix))]
    let _ = (path, mode);
    Ok(())
}

fn write_script(path: &Path) -> io::Result<()> {
    fs::write(path, hook_script())?;
    private(path, 0o700)
}

/// One back-up per file, ever: a second install does not pile them up
/// (`backupOpencodeConfig`).
pub(crate) fn back_up(settings: &Path, stamp: &str) -> io::Result<Option<PathBuf>> {
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

fn remove_file(path: &Path) -> io::Result<bool> {
    match fs::remove_file(path) {
        Ok(()) => Ok(true),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(error),
    }
}
