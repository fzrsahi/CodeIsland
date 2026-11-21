//! OpenCode's plugin install over a real (temporary) home.

use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use morrow_platform::opencode::{self, Site, Status, install, status, uninstall};

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
            std::env::temp_dir().join(format!("morrow-oc-{tag}-{}-{nanos}", std::process::id()));
        fs::create_dir_all(root.join(".config/opencode")).expect("home");
        Self { root }
    }

    fn site(&self) -> Site {
        Site::new(&self.root)
    }

    fn read(&self, path: &PathBuf) -> String {
        fs::read_to_string(path).unwrap_or_else(|e| panic!("{}: {e}", path.display()))
    }

    fn write(&self, path: &PathBuf, text: &str) {
        fs::create_dir_all(path.parent().expect("parent")).expect("parent");
        fs::write(path, text).expect("write");
    }
}

impl Drop for Home {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

const STAMP: &str = "2026-11-20T12:00:00Z";

#[test]
fn without_opencode_nothing_is_written() {
    let home = Home::new("absent");
    let root = std::env::temp_dir().join(format!(
        "morrow-oc-absent-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let site = Site::new(&root);
    assert!(!site.detected());
    assert_eq!(install(&site, STAMP).expect("no-op"), None);
    assert!(!root.exists(), "no directory is created");
    let _ = home;
}

#[test]
fn install_writes_the_plugin_and_registers_it() {
    let home = Home::new("install");
    let site = home.site();
    install(&site, STAMP).expect("install").expect("a result");

    let plugin = home.read(&site.plugin);
    assert!(
        plugin.contains(&format!("// version: {}", opencode::PLUGIN_VERSION)),
        "the version marker"
    );
    assert!(plugin.contains("codeisland"), "the plugin's own name");

    let config = home.read(&site.config);
    assert_eq!(site.config.file_name().unwrap(), "opencode.json");
    assert!(config.contains("$schema"), "{config}");
    assert!(
        config.contains(&format!("file://{}", site.plugin.display())),
        "{config}"
    );

    let status = status(&site);
    assert!(status.detected);
    assert!(status.plugin_installed);
    assert!(status.registered);
}

#[test]
fn an_existing_jsonc_is_the_target_not_a_new_json() {
    let home = Home::new("jsonc");
    let site = home.site();
    let jsonc = site.config_dir.join("opencode.jsonc");
    home.write(&jsonc, "{\n  // mine\n  \"theme\": \"dark\"\n}\n");
    let site = Site::new(&home.root);
    assert_eq!(site.config, jsonc);

    install(&site, STAMP).expect("install");
    let text = home.read(&jsonc);
    assert!(text.contains("// mine"), "the comment survives");
    assert!(text.contains("file://"));
    assert!(
        !site.config_dir.join("opencode.json").exists(),
        "no stray .json"
    );
}

#[test]
fn installing_twice_changes_nothing() {
    let home = Home::new("twice");
    let site = home.site();
    install(&site, STAMP).expect("install");
    let config = home.read(&site.config);
    let plugin = home.read(&site.plugin);

    install(&site, "2026-11-21T00:00:00Z").expect("reinstall");
    assert_eq!(home.read(&site.config), config);
    assert_eq!(home.read(&site.plugin), plugin);
    assert_eq!(home.read(&site.config).matches("codeisland").count(), 1);
}

#[test]
fn an_unparseable_config_refuses_and_stages_nothing() {
    let home = Home::new("refuse");
    let site = home.site();
    let broken = "{ \"plugin\": [";
    home.write(&site.config, broken);

    assert!(install(&site, STAMP).is_err());
    assert_eq!(home.read(&site.config), broken);
    assert!(!site.plugin.exists(), "the plugin is not staged");
}

#[test]
fn uninstall_removes_the_plugin_and_its_registration() {
    let home = Home::new("uninstall");
    let site = home.site();
    let original = "{\n  \"theme\": \"dark\"\n}\n";
    home.write(&site.config, original);

    install(&site, STAMP).expect("install");
    uninstall(&site, STAMP).expect("uninstall");

    assert!(!site.plugin.exists());
    let config = home.read(&site.config);
    assert!(!config.contains("file://"), "{config}");
    assert!(config.contains("\"theme\": \"dark\""));
}

#[test]
fn a_legacy_config_json_registration_is_cleaned_up() {
    let home = Home::new("legacy");
    let site = home.site();
    let legacy_ref = "file:///old/.config/opencode/plugins/codeisland.js";
    home.write(
        &site.legacy_config,
        &format!("{{\n  \"plugin\": [\"{legacy_ref}\"]\n}}\n"),
    );

    install(&site, STAMP).expect("install");
    let legacy = home.read(&site.legacy_config);
    assert!(!legacy.contains("codeisland"), "{legacy}");
}

#[test]
fn status_reports_a_stale_plugin_file() {
    let home = Home::new("stale");
    let site = home.site();
    install(&site, STAMP).expect("install");
    // An older build's copy: right place, old version marker.
    home.write(&site.plugin, "// version: v1\nexport {};\n");
    let status: Status = status(&site);
    assert!(!status.plugin_installed);
    // And installing again rewrites it.
    install(&site, STAMP).expect("repair");
    assert!(
        home.read(&site.plugin)
            .contains(&format!("// version: {}", opencode::PLUGIN_VERSION))
    );
}

/// The marker in the shipped plugin and the constant the installer compares
/// against must be the same string: when they drifted (#161 bumped the resource
/// and not the constant) every install read as stale for ever, and two tests
/// failed on `main`.
#[test]
fn the_shipped_plugin_carries_the_versions_the_installer_expects() {
    let resource = include_str!("../../../../Sources/Morrow/Resources/morrow-opencode.js");
    assert!(
        resource.contains(&format!("// version: {}", opencode::PLUGIN_VERSION)),
        "the resource says something else than PLUGIN_VERSION ({})",
        opencode::PLUGIN_VERSION
    );
}
