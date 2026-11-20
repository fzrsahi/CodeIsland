//! Kimi's TOML install over a real (temporary) home.

use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use morrow_platform::kimi::{Site, install, status, uninstall};

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
            std::env::temp_dir().join(format!("morrow-kimi-{tag}-{}-{nanos}", std::process::id()));
        fs::create_dir_all(&root).expect("home");
        Self { root }
    }

    fn modern(&self) -> Site {
        Site::new(&self.root)
    }
}

impl Drop for Home {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

const STAMP: &str = "2026-11-20T12:00:00Z";

#[test]
fn without_kimi_nothing_is_written() {
    let home = Home::new("absent");
    let site = home.modern();
    assert!(!site.detected());
    assert_eq!(install(&site, STAMP).expect("no-op"), None);
    assert!(!site.config_dir.exists(), "no directory is created");
}

#[test]
fn install_writes_our_blocks_and_keeps_the_users_file() {
    let home = Home::new("install");
    fs::create_dir_all(home.root.join(".kimi-code")).expect("dir");
    let site = home.modern();
    fs::write(&site.config, "default_model = \"kimi-k2-5\"\n# keep\n").expect("write");

    install(&site, STAMP).expect("install").expect("a result");
    let text = fs::read_to_string(&site.config).expect("read");
    assert!(
        text.starts_with("default_model = \"kimi-k2-5\"\n# keep\n"),
        "{text}"
    );
    assert!(text.contains("[[hooks]]"));
    assert!(text.contains("--source kimi"));
    assert!(status(&site).installed);
    // A back-up of the user's file, before our blocks.
    let names: Vec<String> = fs::read_dir(&site.config_dir)
        .expect("dir")
        .filter_map(Result::ok)
        .filter_map(|entry| entry.file_name().into_string().ok())
        .collect();
    assert!(
        names
            .iter()
            .any(|name| name.starts_with("config.toml.codeisland.bak.")),
        "{names:?}"
    );
}

#[test]
fn installing_twice_changes_nothing() {
    let home = Home::new("twice");
    fs::create_dir_all(home.root.join(".kimi-code")).expect("dir");
    let site = home.modern();
    install(&site, STAMP).expect("install");
    let first = fs::read_to_string(&site.config).expect("read");
    install(&site, "2026-11-21T00:00:00Z").expect("reinstall");
    assert_eq!(fs::read_to_string(&site.config).expect("read"), first);
}

#[test]
fn the_legacy_home_is_used_when_it_is_the_one_present() {
    let home = Home::new("legacy");
    fs::create_dir_all(home.root.join(".kimi")).expect("dir");
    let site = home.modern();
    assert_eq!(site.config, home.root.join(".kimi/config.toml"));
    install(&site, STAMP).expect("install").expect("a result");
    assert!(
        fs::read_to_string(&site.config)
            .expect("read")
            .contains("[[hooks]]")
    );
}

#[test]
fn uninstall_removes_our_blocks_and_the_rest_stays() {
    let home = Home::new("uninstall");
    fs::create_dir_all(home.root.join(".kimi-code")).expect("dir");
    let site = home.modern();
    fs::write(&site.config, "default_model = \"kimi-k2-5\"\n").expect("write");

    install(&site, STAMP).expect("install");
    uninstall(&site, STAMP)
        .expect("uninstall")
        .expect("a result");
    let text = fs::read_to_string(&site.config).expect("read");
    assert!(!text.contains("codeisland"), "{text}");
    assert!(text.contains("default_model"));
    assert!(!status(&site).installed);
}
