//! Hermes and TraeCli over a real (temporary) home.

use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use morrow_platform::hooks::Error;
use morrow_platform::yaml_hooks::{Site, install, sites, status, uninstall};

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
            std::env::temp_dir().join(format!("morrow-yaml-{tag}-{}-{nanos}", std::process::id()));
        fs::create_dir_all(&root).expect("home");
        Self { root }
    }

    fn site(&self, source: &str) -> Site {
        sites(&self.root)
            .into_iter()
            .find(|site| site.source.source == source)
            .expect("a site")
    }
}

impl Drop for Home {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

const STAMP: &str = "2026-11-20T12:00:00Z";

#[test]
fn without_the_cli_nothing_is_written() {
    let home = Home::new("absent");
    let site = home.site("hermes");
    assert!(!site.detected());
    assert_eq!(install(&site, STAMP).expect("no-op"), None);
    assert!(!home.root.join(".hermes").exists());
}

#[test]
fn install_keeps_the_users_yaml_and_adds_our_block() {
    let home = Home::new("install");
    fs::create_dir_all(home.root.join(".hermes")).expect("dir");
    let site = home.site("hermes");
    let original = "# my hermes config\nmodel: hermes-4\n";
    fs::write(&site.config, original).expect("write");

    install(&site, STAMP).expect("install").expect("a result");
    let text = fs::read_to_string(&site.config).expect("read");
    assert!(text.starts_with(original), "{text}");
    assert!(text.contains("pre_tool_call:"));
    assert!(status(&site).installed);
    assert!(status(&site).refusal.is_none());

    // One back-up of the user's file.
    let names: Vec<String> = fs::read_dir(home.root.join(".hermes"))
        .expect("dir")
        .filter_map(Result::ok)
        .filter_map(|entry| entry.file_name().into_string().ok())
        .collect();
    assert!(
        names
            .iter()
            .any(|name| name.starts_with("config.yaml.codeisland.bak.")),
        "{names:?}"
    );
}

#[test]
fn traecli_is_installed_in_its_own_file() {
    let home = Home::new("traecli");
    fs::create_dir_all(home.root.join(".trae")).expect("dir");
    let site = home.site("traecli");
    install(&site, STAMP).expect("install").expect("a result");
    let text = fs::read_to_string(&site.config).expect("read");
    assert!(text.contains("--source traecli"));
    assert!(text.contains("matchers:"));
}

#[test]
fn installing_twice_changes_nothing() {
    let home = Home::new("twice");
    fs::create_dir_all(home.root.join(".hermes")).expect("dir");
    let site = home.site("hermes");
    install(&site, STAMP).expect("install");
    let first = fs::read_to_string(&site.config).expect("read");
    install(&site, "2026-11-21T00:00:00Z").expect("reinstall");
    assert_eq!(fs::read_to_string(&site.config).expect("read"), first);
}

#[test]
fn a_layout_the_core_refuses_leaves_the_file_alone() {
    let home = Home::new("refuse");
    fs::create_dir_all(home.root.join(".hermes")).expect("dir");
    let site = home.site("hermes");
    let inline = "hooks: [one]\n";
    fs::write(&site.config, inline).expect("write");

    let error = install(&site, STAMP).expect_err("refuses");
    assert!(matches!(error, Error::Refused(_)), "{error}");
    assert_eq!(fs::read_to_string(&site.config).expect("read"), inline);
    // And the card says why.
    assert!(status(&site).refusal.is_some());
}

#[test]
fn uninstall_gives_the_file_back() {
    let home = Home::new("uninstall");
    fs::create_dir_all(home.root.join(".trae")).expect("dir");
    let site = home.site("traecli");
    let original = "model: trae\n# note\n";
    fs::write(&site.config, original).expect("write");

    install(&site, STAMP).expect("install");
    uninstall(&site, STAMP)
        .expect("uninstall")
        .expect("a result");
    assert_eq!(fs::read_to_string(&site.config).expect("read"), original);
    assert!(!status(&site).installed);
}
