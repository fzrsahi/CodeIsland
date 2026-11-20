//! The Windows hook installer over a real (temporary) profile (#108): the same
//! promises as the Unix one — install, repair and uninstall are idempotent, a
//! back-up is made once, and a file we cannot parse is never touched — plus the
//! two things Windows adds: a `.cmd` the shell can run, and an `.exe` bridge.

use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use morrow_platform::hooks::{Error, Status};
use morrow_platform::hooks_windows::{self as hooks, Paths};

/// A profile folder, removed on drop.
struct Profile(PathBuf);

impl Profile {
    fn new(name: &str) -> Self {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!("morrow-win-hooks-{name}-{nanos}"));
        fs::create_dir_all(&path).expect("profile");
        Self(path)
    }

    fn paths(&self) -> Paths {
        Paths::new(&self.0, None)
    }

    fn write(&self, path: &Path, text: &str) {
        fs::create_dir_all(path.parent().expect("parent")).expect("dir");
        fs::write(path, text).expect("write");
    }

    fn read(&self, path: &Path) -> String {
        fs::read_to_string(path).expect("read")
    }

    /// `Morrow.exe`, as the package ships it.
    fn bridge_source(&self) -> PathBuf {
        let path = self.0.join("dist/morrow-bridge.exe");
        self.write(&path, "MZ fake");
        path
    }

    fn backups(&self) -> Vec<String> {
        fs::read_dir(self.0.join(".claude"))
            .expect("dir")
            .filter_map(Result::ok)
            .filter_map(|entry| entry.file_name().into_string().ok())
            .filter(|name| name.contains(".codeisland.bak."))
            .collect()
    }
}

impl Drop for Profile {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

const STAMP: &str = "2026-11-20T12:00:00Z";

#[test]
fn a_fresh_profile_gets_the_cmd_the_exe_and_every_event() {
    let profile = Profile::new("fresh");
    let paths = profile.paths();
    assert_eq!(
        paths.script,
        profile.0.join(".codeisland").join("morrow-hook.cmd"),
        "cmd.exe needs a .cmd to run"
    );
    assert_eq!(
        paths.bridge,
        profile
            .0
            .join(".local")
            .join("bin")
            .join("morrow-bridge.exe"),
        "outside the package, stable across updates"
    );

    let report = hooks::install(
        &paths,
        Some(&profile.bridge_source()),
        Some("2.1.89"),
        STAMP,
    )
    .expect("install");
    assert!(report.script_written);
    assert!(report.bridge_copied);
    assert!(report.settings_changed);
    assert_eq!(report.backup, None, "a new file has nothing to back up");

    let script = profile.read(&paths.script);
    assert!(script.starts_with("@echo off\r\n"), "{script:?}");
    assert!(script.contains("# Morrow hook v1"), "{script}");
    assert!(
        script.contains(r#"set "BRIDGE=%USERPROFILE%\.local\bin\morrow-bridge.exe""#),
        "{script}"
    );
    assert!(
        script.contains(r#"if not exist "%BRIDGE%" exit /b 0"#),
        "a missing bridge must not fail every tool call: {script}"
    );
    assert!(script.contains(r#""%BRIDGE%" %*"#), "{script}");

    let settings = profile.read(&paths.settings);
    // The command is the quoted absolute path: `cmd.exe` splits on spaces, and a
    // profile folder can contain one.
    let expected = format!("\"{}\"", paths.script.display());
    // As JSON escapes it: backslashes doubled on Windows, untouched elsewhere.
    let encoded = serde_json::to_string(&expected).expect("json");
    assert!(
        settings.contains(&encoded),
        "settings name {expected} (as {encoded}): {settings}"
    );
    assert!(settings.contains("\"UserPromptSubmit\""));
    assert!(settings.contains("\"PreCompact\""));

    let status = hooks::status(&paths, Some("2.1.89"));
    assert!(status.script_installed);
    assert!(status.bridge_installed);
    assert!(hooks_installed(&status), "{status:?}");
}

#[test]
fn a_second_install_changes_nothing() {
    let profile = Profile::new("idempotent");
    let paths = profile.paths();
    let source = profile.bridge_source();
    hooks::install(&paths, Some(&source), Some("2.1.89"), STAMP).expect("first");
    let before = profile.read(&paths.settings);

    let report = hooks::install(&paths, Some(&source), Some("2.1.89"), STAMP).expect("second");
    assert!(!report.script_written);
    assert!(!report.bridge_copied);
    assert!(!report.settings_changed);
    assert_eq!(report.backup, None);
    assert_eq!(profile.read(&paths.settings), before);
    assert!(
        profile.backups().is_empty(),
        "no back-up of an unchanged file"
    );
}

#[test]
fn a_users_own_hooks_and_a_backup_are_respected() {
    let profile = Profile::new("user-hooks");
    let paths = profile.paths();
    let original = r#"{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "echo mine" } ] }
    ]
  }
}"#;
    profile.write(&paths.settings, original);

    let report = hooks::install(
        &paths,
        Some(&profile.bridge_source()),
        Some("2.1.89"),
        STAMP,
    )
    .expect("install");
    assert!(report.settings_changed);
    assert!(report.backup.is_some(), "the user's file was changed");
    let backup = report.backup.expect("path");
    assert_eq!(
        profile.read(&backup),
        original,
        "the back-up is the file as it was"
    );
    assert_eq!(profile.backups().len(), 1, "one back-up, ever");

    let settings = profile.read(&paths.settings);
    assert!(
        settings.contains("echo mine"),
        "their hook survives: {settings}"
    );

    // A second install reuses the back-up instead of making a second one.
    hooks::install(
        &paths,
        Some(&profile.bridge_source()),
        Some("2.1.89"),
        STAMP,
    )
    .expect("again");
    assert_eq!(profile.backups().len(), 1);

    let report = hooks::uninstall(&paths).expect("uninstall");
    assert!(report.settings_changed);
    let settings = profile.read(&paths.settings);
    assert!(
        settings.contains("echo mine"),
        "their hook survives: {settings}"
    );
    assert!(!settings.contains("morrow-hook.cmd"), "{settings}");
    assert!(!paths.script.exists());
    assert!(!paths.bridge.exists());
}

#[test]
fn an_unparseable_settings_file_is_never_touched() {
    let profile = Profile::new("unparseable");
    let paths = profile.paths();
    let broken = "{ this is not json";
    profile.write(&paths.settings, broken);

    match hooks::install(
        &paths,
        Some(&profile.bridge_source()),
        Some("2.1.89"),
        STAMP,
    ) {
        Err(Error::UnparseableSettings(path)) => assert_eq!(path, paths.settings),
        other => panic!("expected a refusal, got {other:?}"),
    }
    assert_eq!(profile.read(&paths.settings), broken, "byte for byte");
    assert!(!paths.script.exists(), "a refusal writes nothing at all");
    assert!(!paths.bridge.exists());
    assert!(profile.backups().is_empty());
}

#[test]
fn an_older_cli_gets_only_the_events_it_knows() {
    let profile = Profile::new("version-gate");
    let paths = profile.paths();
    hooks::install(
        &paths,
        Some(&profile.bridge_source()),
        Some("2.1.80"),
        STAMP,
    )
    .expect("install");
    let settings = profile.read(&paths.settings);
    // `PreCompact` arrived in 2.1.78 and is present; the 2.1.89-only events are
    // not, because a key the CLI does not know is a hook it will not run.
    assert!(settings.contains("\"PreCompact\""));
    assert!(
        !settings.contains("\"PostToolUseFailure\""),
        "2.1.80 does not know this event: {settings}"
    );
}

#[test]
fn uninstalling_with_nothing_installed_is_not_an_error() {
    let profile = Profile::new("empty");
    let paths = profile.paths();
    let report = hooks::uninstall(&paths).expect("nothing to remove");
    assert_eq!(report, morrow_platform::hooks::Report::default());
    assert!(!paths.settings.exists(), "no file invented");
}

fn hooks_installed(status: &Status) -> bool {
    status.hooks_installed
}
