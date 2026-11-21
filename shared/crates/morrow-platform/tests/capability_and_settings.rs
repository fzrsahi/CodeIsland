//! The Capability table, autostart and settings storage (#101): what Settings
//! promises to say out loud, and the two files it owns.

use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use morrow_platform::autostart;
use morrow_platform::capability::{Capability, Environment, Feature, table};
use serde_json::json;

fn temp(tag: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("a clock")
        .as_nanos();
    let root =
        std::env::temp_dir().join(format!("morrow-cap-{tag}-{}-{nanos}", std::process::id()));
    fs::create_dir_all(&root).expect("root");
    root
}

fn x11(config_home: PathBuf) -> Environment {
    Environment {
        os: morrow_platform::capability::Os::Linux,
        session_type: Some("x11".into()),
        has_session_bus: true,
        path_tools: vec!["/usr/bin".into()],
        config_home,
        claude_credentials: PathBuf::from("/nonexistent/.credentials.json"),
        has_portal_shortcuts: false,
        appimage: false,
    }
}

fn wayland(config_home: PathBuf) -> Environment {
    Environment {
        os: morrow_platform::capability::Os::Linux,
        session_type: Some("wayland".into()),
        ..x11(config_home)
    }
}

// MARK: - The table

#[test]
fn every_feature_gets_a_row_and_a_label() {
    let env = x11(temp("table"));
    let rows = table(&env);
    assert_eq!(rows.len(), Feature::ALL.len());
    assert!(rows.len() >= 21, "the plan's whole table is covered");
    for row in &rows {
        assert!(!row.feature.is_empty());
        assert!(!row.capability.label().is_empty());
        // Anything short of Supported has to explain itself.
        if !row.capability.is_supported() {
            assert!(
                row.capability
                    .reason()
                    .is_some_and(|reason| !reason.is_empty()),
                "{} says {} with no reason",
                row.feature,
                row.capability.label()
            );
        }
    }
}

#[test]
fn a_wayland_session_loses_the_x11_only_adapters_and_says_why() {
    let env = wayland(temp("wayland"));
    for feature in [
        Feature::PointerMonitor,
        Feature::TerminalVisibility,
        Feature::Fullscreen,
        Feature::SyntheticInput,
    ] {
        let capability = feature.probe(&env);
        assert!(
            matches!(capability, Capability::Unsupported(_)),
            "{} should be unsupported on Wayland",
            feature.name()
        );
    }
    // The hotkey is not simply gone: it needs a portal, or a desktop binding.
    let hotkey = Feature::GlobalHotkey.probe(&env);
    assert!(matches!(hotkey, Capability::Unsupported(_)));
    assert!(hotkey.reason().unwrap().contains("morrow toggle"));
}

#[test]
fn x11_supports_what_wayland_cannot() {
    let env = x11(temp("x11-features"));
    for feature in [
        Feature::PointerMonitor,
        Feature::TerminalVisibility,
        Feature::Fullscreen,
        Feature::SyntheticInput,
        Feature::GlobalHotkey,
    ] {
        assert_eq!(
            feature.probe(&env),
            Capability::Supported,
            "{} on X11",
            feature.name()
        );
    }
}

#[test]
fn a_missing_appindicator_is_reported_not_fatal() {
    // No library on PATH: the tray is unsupported, and everything else still
    // answers — the panel keeps working without a tray icon.
    let env = x11(temp("tray"));
    let tray = Feature::Tray.probe(&env);
    assert!(matches!(tray, Capability::Unsupported(_)), "{tray:?}");
    assert!(
        Feature::PointerMonitor.probe(&env).is_supported(),
        "one missing adapter does not take the others down"
    );
}

#[test]
fn no_session_bus_marks_the_bus_bound_features() {
    let mut env = x11(temp("no-bus"));
    env.has_session_bus = false;
    for feature in [
        Feature::NowPlaying,
        Feature::SessionLock,
        Feature::Secrets,
        Feature::Ble,
    ] {
        assert!(
            matches!(feature.probe(&env), Capability::Unsupported(_)),
            "{} without a bus",
            feature.name()
        );
    }
    // Volume does not need the bus: it shells out.
    assert!(matches!(
        Feature::SystemVolume.probe(&env),
        Capability::Unsupported(_) | Capability::Supported
    ));
}

#[test]
fn a_missing_credentials_file_is_degraded_rather_than_broken() {
    let env = x11(temp("creds"));
    let capability = Feature::ClaudeCredentials.probe(&env);
    assert!(
        matches!(capability, Capability::Degraded(_)),
        "{capability:?}"
    );
}

// MARK: - Autostart

#[test]
fn autostart_writes_one_desktop_entry_and_takes_it_back() {
    let root = temp("autostart");
    let config = root.join(".config");
    fs::create_dir_all(&config).expect("config");

    assert!(!autostart::status(&config).installed);
    assert!(autostart::install(&config, PathBuf::from("/usr/bin/morrow-app").as_path()).unwrap());
    let text = fs::read_to_string(autostart::path(&config)).expect("read");
    assert!(text.starts_with("[Desktop Entry]"));
    assert!(text.contains("Exec=/usr/bin/morrow-app"));
    assert!(text.contains("Type=Application"));
    assert!(autostart::status(&config).installed);

    // Second install: the same bytes, nothing written.
    assert!(!autostart::install(&config, PathBuf::from("/usr/bin/morrow-app").as_path()).unwrap());
    assert!(autostart::uninstall(&config).unwrap());
    assert!(!autostart::status(&config).installed);
    assert!(!autostart::uninstall(&config).unwrap(), "already gone");
}

#[test]
fn a_path_with_spaces_is_quoted_in_the_entry() {
    let root = temp("autostart-space");
    let config = root.join(".config");
    autostart::install(&config, PathBuf::from("/home/a b/morrow-app").as_path()).unwrap();
    let text = fs::read_to_string(autostart::path(&config)).expect("read");
    assert!(text.contains("Exec=\"/home/a b/morrow-app\""), "{text}");
}

// MARK: - Settings

#[test]
fn settings_round_trip_and_keep_every_other_key() {
    let root = temp("settings");
    let dir = root.join(".codeisland");
    fs::create_dir_all(&dir).expect("dir");
    fs::write(
        morrow_platform::settings::path(&dir),
        "{\n  \"theme\": \"dark\",\n  \"sound\": \"8bit\"\n}\n",
    )
    .expect("write");

    assert!(morrow_platform::settings::set(&dir, "sound", &json!("modern")).unwrap());
    let loaded = morrow_platform::settings::load(&dir).unwrap();
    assert_eq!(loaded["sound"], json!("modern"));
    assert_eq!(loaded["theme"], json!("dark"), "an unrelated key is kept");
    let text = fs::read_to_string(morrow_platform::settings::path(&dir)).expect("read");
    assert!(text.ends_with('\n'), "the file's own newline stays");

    // The same value again changes nothing.
    assert!(!morrow_platform::settings::set(&dir, "sound", &json!("modern")).unwrap());
}

#[test]
fn settings_of_a_missing_file_are_an_empty_object() {
    let root = temp("settings-empty");
    let dir = root.join(".codeisland");
    let loaded = morrow_platform::settings::load(&dir).unwrap();
    assert_eq!(loaded, json!({}));

    assert!(morrow_platform::settings::set(&dir, "sound", &json!("8bit")).unwrap());
    let text = fs::read_to_string(morrow_platform::settings::path(&dir)).expect("read");
    assert!(text.starts_with('{'), "{text}");
}

#[test]
fn settings_that_do_not_parse_are_never_rewritten() {
    let root = temp("settings-broken");
    let dir = root.join(".codeisland");
    fs::create_dir_all(&dir).expect("dir");
    let broken = "{ \"theme\": ";
    fs::write(morrow_platform::settings::path(&dir), broken).expect("write");

    let error = morrow_platform::settings::set(&dir, "sound", &json!("8bit")).expect_err("refuses");
    assert_eq!(error.kind(), std::io::ErrorKind::InvalidData);
    assert_eq!(
        fs::read_to_string(morrow_platform::settings::path(&dir)).expect("read"),
        broken
    );
}
