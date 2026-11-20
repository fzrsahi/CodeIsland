//! The installer over a real (temporary) home: what #98 asks for — install,
//! repair and uninstall are idempotent byte for byte, a back-up is made, and a
//! file we cannot parse is never touched.

use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use morrow_platform::hooks::{self, Error, Paths};

/// A throwaway home. Removed on drop.
struct Home {
    root: PathBuf,
}

impl Home {
    fn new(tag: &str) -> Self {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("a clock")
            .as_nanos();
        let root =
            std::env::temp_dir().join(format!("morrow-hooks-{tag}-{}-{nanos}", std::process::id()));
        fs::create_dir_all(root.join(".claude")).expect("home");
        Self { root }
    }

    fn paths(&self) -> Paths {
        Paths::new(&self.root, None)
    }

    fn read(&self, path: &Path) -> String {
        fs::read_to_string(path).unwrap_or_else(|e| panic!("{}: {e}", path.display()))
    }

    fn write(&self, path: &Path, text: &str) {
        fs::create_dir_all(path.parent().expect("a parent")).expect("parent");
        fs::write(path, text).expect("write");
    }

    fn mode(&self, path: &Path) -> u32 {
        use std::os::unix::fs::PermissionsExt;
        fs::metadata(path).expect("metadata").permissions().mode() & 0o777
    }

    /// A stand-in for the bridge binary shipped beside the app.
    fn bridge_source(&self) -> PathBuf {
        let path = self.root.join("dist/morrow-bridge");
        self.write(&path, "#!/bin/sh\nexit 0\n");
        path
    }

    fn back_ups(&self) -> Vec<String> {
        fs::read_dir(self.root.join(".claude"))
            .expect("dir")
            .filter_map(Result::ok)
            .filter_map(|entry| entry.file_name().into_string().ok())
            .filter(|name| name.contains(".codeisland.bak."))
            .collect()
    }
}

impl Drop for Home {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

const STAMP: &str = "2026-11-20T12:00:00Z";

#[test]
fn a_fresh_home_gets_the_script_the_bridge_and_every_event() {
    let home = Home::new("fresh");
    let paths = home.paths();
    let source = home.bridge_source();

    let report = hooks::install(&paths, Some(&source), Some("2.1.89"), STAMP).expect("install");
    assert!(report.script_written);
    assert!(report.bridge_copied);
    assert!(report.settings_changed);
    assert_eq!(report.backup, None, "a new file has nothing to back up");

    assert_eq!(home.mode(&paths.codeisland_dir), 0o700);
    assert_eq!(home.mode(&paths.script), 0o700);
    assert_eq!(
        paths.bridge,
        home.root.join(".local/bin/morrow-bridge"),
        "the hook config records this path, so it lives outside any package"
    );
    assert_eq!(home.mode(&paths.bridge), 0o755);
    let script = home.read(&paths.script);
    assert!(script.contains("# Morrow hook v2"), "{script}");
    assert!(
        script.contains("$HOME/.local/bin/morrow-bridge")
            && script.contains("$HOME/.codeisland/morrow-bridge"),
        "the stable path first, the older one as a fallback: {script}"
    );
    assert!(script.contains("exec \"$BRIDGE\" \"$@\""));

    let settings = home.read(&paths.settings);
    assert!(settings.contains("\"UserPromptSubmit\""));
    assert!(settings.contains("\"PreCompact\""));
    assert!(settings.contains("codeisland-hook.sh"));

    let status = hooks::status(&paths, Some("2.1.89"));
    assert!(status.script_installed);
    assert!(status.bridge_installed);
    assert!(status.hooks_installed);
    assert!(status.settings_exists);
}

#[test]
fn installing_twice_changes_nothing_the_second_time() {
    let home = Home::new("twice");
    let paths = home.paths();
    let source = home.bridge_source();

    hooks::install(&paths, Some(&source), Some("2.1.89"), STAMP).expect("install");
    let settings = home.read(&paths.settings);
    let script = home.read(&paths.script);

    let again = hooks::install(
        &paths,
        Some(&source),
        Some("2.1.89"),
        "2026-11-21T09:00:00Z",
    )
    .expect("reinstall");
    assert!(!again.script_written, "the script is current");
    assert!(!again.bridge_copied, "the binary is the same bytes");
    assert!(!again.settings_changed, "the hooks are already there");
    assert_eq!(home.read(&paths.settings), settings, "byte for byte");
    assert_eq!(home.read(&paths.script), script);
}

#[test]
fn a_file_that_does_not_parse_is_left_alone() {
    let home = Home::new("refuse");
    let paths = home.paths();
    let source = home.bridge_source();
    let broken = "{ \"hooks\": [";
    home.write(&paths.settings, broken);

    let error = hooks::install(&paths, Some(&source), Some("2.1.89"), STAMP).expect_err("refuses");
    assert!(matches!(error, Error::UnparseableSettings(_)), "{error}");
    assert_eq!(home.read(&paths.settings), broken);
    assert!(!paths.script.exists(), "a refusal touches nothing at all");
    assert!(!paths.bridge.exists());
}

#[test]
fn uninstall_gives_the_settings_back_and_removes_ours() {
    let home = Home::new("uninstall");
    let paths = home.paths();
    let source = home.bridge_source();
    let original = "{\n  \"model\": \"sonnet\"\n}\n";
    home.write(&paths.settings, original);

    hooks::install(&paths, Some(&source), Some("2.1.89"), STAMP).expect("install");
    assert_ne!(home.read(&paths.settings), original);

    let report = hooks::uninstall(&paths).expect("uninstall");
    assert!(report.settings_changed);
    assert!(report.script_written);
    assert!(report.bridge_copied);
    assert_eq!(home.read(&paths.settings), original, "byte for byte");
    assert!(!paths.script.exists());
    assert!(!paths.bridge.exists());
    assert!(!hooks::status(&paths, Some("2.1.89")).hooks_installed);
}

#[test]
fn one_back_up_per_file_ever() {
    let home = Home::new("backup");
    let paths = home.paths();
    let source = home.bridge_source();
    let original = "{\n  \"model\": \"sonnet\"\n}\n";
    home.write(&paths.settings, original);

    let first = hooks::install(&paths, Some(&source), Some("2.1.89"), STAMP).expect("install");
    let backup = first.backup.expect("a back-up before the first write");
    assert_eq!(home.read(&backup), original, "the back-up is the original");

    // Something goes stale, so the second run really does write: an `async`
    // key from an older install is the one marker that forces a repair.
    let stale = home.read(&paths.settings).replacen(
        "\"command\": \"~/.codeisland/codeisland-hook.sh\",",
        "\"command\": \"~/.codeisland/codeisland-hook.sh\", \"async\": true,",
        1,
    );
    assert_ne!(stale, home.read(&paths.settings), "the edit applied");
    home.write(&paths.settings, &stale);
    let second = hooks::install(
        &paths,
        Some(&source),
        Some("2.1.89"),
        "2026-11-22T00:00:00Z",
    )
    .expect("repair");
    assert!(second.settings_changed);
    assert_eq!(second.backup, None, "a back-up already exists");
    assert_eq!(home.back_ups().len(), 1, "{:?}", home.back_ups());
}

#[test]
fn status_says_what_is_missing() {
    let home = Home::new("status");
    let paths = home.paths();

    let empty = hooks::status(&paths, Some("2.1.89"));
    assert!(!empty.script_installed);
    assert!(!empty.bridge_installed);
    assert!(!empty.hooks_installed);
    assert!(!empty.settings_exists);

    // A settings file with only one event is not an install.
    home.write(
        &paths.settings,
        r#"{"hooks":{"PreToolUse":[{"matcher":"","hooks":[{"type":"command","command":"~/.codeisland/codeisland-hook.sh","timeout":5}]}]}}"#,
    );
    assert!(!hooks::status(&paths, Some("2.1.89")).hooks_installed);
}

#[test]
fn a_symlinked_settings_file_is_written_at_its_target() {
    let home = Home::new("symlink");
    let paths = home.paths();
    let source = home.bridge_source();

    // A dotfiles setup: the link is the user's, the file lives elsewhere.
    let target = home.root.join("dotfiles/settings.json");
    home.write(&target, "{\n  \"model\": \"sonnet\"\n}\n");
    std::os::unix::fs::symlink(&target, &paths.settings).expect("symlink");

    hooks::install(&paths, Some(&source), Some("2.1.89"), STAMP).expect("install");
    let metadata = fs::symlink_metadata(&paths.settings).expect("metadata");
    assert!(metadata.file_type().is_symlink(), "the link survives");
    assert!(
        home.read(&target).contains("codeisland-hook.sh"),
        "written through"
    );
}

#[test]
fn claude_config_dir_is_honoured() {
    let home = Home::new("config-dir");
    let config_dir = home.root.join("custom-claude");
    let paths = Paths::new(&home.root, Some(&config_dir));
    assert_eq!(paths.settings, config_dir.join("settings.json"));
    assert_eq!(paths.codeisland_dir, home.root.join(".codeisland"));
}

#[test]
fn a_missing_bridge_source_still_installs_the_script() {
    let home = Home::new("no-bridge");
    let paths = home.paths();
    let report = hooks::install(&paths, None, Some("2.1.89"), STAMP).expect("install");
    assert!(report.script_written);
    assert!(!report.bridge_copied);
    assert!(!hooks::status(&paths, Some("2.1.89")).bridge_installed);
    // The script is a clean no-op without it.
    assert!(
        home.read(&paths.script)
            .contains("[ -x \"$BRIDGE\" ] || exit 0")
    );
}

// MARK: - The other hook targets (#99)

fn cli_dir(home: &Home, name: &str) {
    fs::create_dir_all(home.root.join(name)).expect("cli dir");
}

#[test]
fn a_target_without_its_cli_is_left_alone() {
    let home = Home::new("target-absent");
    let paths = home.paths();

    // `~/.cursor` does not exist: nothing to hook, nothing written.
    assert_eq!(
        hooks::install_target(&paths, "cursor", STAMP).expect("no-op"),
        None
    );
    assert!(!home.root.join(".cursor").exists());

    let status = hooks::targets_status(&paths);
    let cursor = status
        .iter()
        .find(|row| row.source == "cursor")
        .expect("cursor");
    assert!(!cursor.detected);
    assert!(!cursor.installed);
}

#[test]
fn a_detected_target_gets_its_file_and_its_back_up() {
    let home = Home::new("target-install");
    let paths = home.paths();
    cli_dir(&home, ".cursor");
    let settings = home.root.join(".cursor/hooks.json");
    home.write(&settings, "{\n  \"telemetry\": false\n}\n");

    let report = hooks::install_target(&paths, "cursor", STAMP)
        .expect("install")
        .expect("a report");
    assert!(report.settings_changed);
    let backup = report.backup.expect("a back-up");
    assert_eq!(home.read(&backup), "{\n  \"telemetry\": false\n}\n");

    let text = home.read(&settings);
    assert!(text.contains("\"beforeSubmitPrompt\""));
    assert!(
        text.contains("--source cursor --event beforeSubmitPrompt"),
        "{text}"
    );
    assert!(text.contains("\"telemetry\": false"));

    // Installed, and a second run changes nothing.
    let status = hooks::targets_status(&paths);
    assert!(
        status
            .iter()
            .find(|row| row.source == "cursor")
            .expect("cursor")
            .installed
    );
    let again = hooks::install_target(&paths, "cursor", "2026-11-21T00:00:00Z")
        .expect("reinstall")
        .expect("a report");
    assert!(!again.settings_changed);
    assert_eq!(home.read(&settings), text);
}

#[test]
fn a_target_install_creates_the_hooks_directory_copilot_needs() {
    let home = Home::new("target-copilot");
    let paths = home.paths();
    cli_dir(&home, ".copilot");

    hooks::install_target(&paths, "copilot", STAMP)
        .expect("install")
        .expect("a report");
    let text = home.read(&home.root.join(".copilot/hooks/codeisland.json"));
    assert!(text.contains("\"version\""));
    assert!(text.contains("--event preToolUse"));
}

#[test]
fn a_target_uninstall_gives_the_file_back() {
    let home = Home::new("target-uninstall");
    let paths = home.paths();
    cli_dir(&home, ".gemini");
    let settings = home.root.join(".gemini/settings.json");
    let original = "{\n  \"theme\": \"dark\"\n}\n";
    home.write(&settings, original);

    hooks::install_target(&paths, "gemini", STAMP).expect("install");
    assert_ne!(home.read(&settings), original);
    hooks::uninstall_target(&paths, "gemini").expect("uninstall");
    assert_eq!(home.read(&settings), original);
}

#[test]
fn an_unparseable_target_file_refuses_and_writes_nothing() {
    let home = Home::new("target-refuse");
    let paths = home.paths();
    cli_dir(&home, ".codex");
    let settings = home.root.join(".codex/hooks.json");
    home.write(&settings, "{ \"hooks\": [");

    let error = hooks::install_target(&paths, "codex", STAMP).expect_err("refuses");
    assert!(matches!(error, Error::UnparseableSettings(_)), "{error}");
    assert_eq!(home.read(&settings), "{ \"hooks\": [");
}

#[test]
fn an_unknown_target_is_an_error_not_a_silent_no_op() {
    let home = Home::new("target-unknown");
    let paths = home.paths();
    assert!(hooks::install_target(&paths, "nope", STAMP).is_err());
    assert!(hooks::uninstall_target(&paths, "nope").is_err());
}

#[test]
fn codex_also_gets_the_feature_flag_in_config_toml() {
    let home = Home::new("codex-flag");
    let paths = home.paths();
    cli_dir(&home, ".codex");
    let config = home.root.join(".codex/config.toml");
    home.write(&config, "model = \"gpt-6-sol\"\n");

    let report = hooks::install_target(&paths, "codex", STAMP)
        .expect("install")
        .expect("a report");
    assert!(report.flag_enabled);
    assert_eq!(
        home.read(&config),
        "model = \"gpt-6-sol\"\nfeatures.hooks = true\n"
    );

    // Second run: the flag is already on, nothing to do.
    let again = hooks::install_target(&paths, "codex", STAMP)
        .expect("reinstall")
        .expect("a report");
    assert!(!again.flag_enabled);
    assert_eq!(
        home.read(&config),
        "model = \"gpt-6-sol\"\nfeatures.hooks = true\n"
    );
}

#[test]
fn a_codex_config_the_editor_will_not_touch_is_an_error() {
    let home = Home::new("codex-unsafe");
    let paths = home.paths();
    cli_dir(&home, ".codex");
    let config = home.root.join(".codex/config.toml");
    let unsafe_layout = "features = { hooks = false }\n";
    home.write(&config, unsafe_layout);

    let error = hooks::install_target(&paths, "codex", STAMP).expect_err("refuses");
    assert!(matches!(error, Error::UnparseableSettings(_)), "{error}");
    assert_eq!(home.read(&config), unsafe_layout, "left as it was");
}
