//! The bridge ends up outside the package (#104): whatever the format, the path
//! a CLI config records is `~/.local/bin/morrow-bridge` and the copy is atomic.

// Unix-only: the assertions are file modes and an executable bit, which Windows
// expresses as ACLs instead. The Windows half arrives with #107.
#![cfg(unix)]

use std::fs;
use std::path::{Path, PathBuf};

use morrow_platform::bridge;

struct Temp(PathBuf);

impl Temp {
    fn new(name: &str) -> Self {
        let path =
            std::env::temp_dir().join(format!("morrow-bridge-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&path);
        fs::create_dir_all(&path).expect("dir");
        Self(path)
    }

    fn home(&self) -> PathBuf {
        self.0.join("home")
    }

    fn shipped(&self, bytes: &str) -> PathBuf {
        let path = self.0.join("app/morrow-bridge");
        fs::create_dir_all(path.parent().expect("parent")).expect("dir");
        fs::write(&path, bytes).expect("write");
        path
    }
}

impl Drop for Temp {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn mode(path: &Path) -> u32 {
    use std::os::unix::fs::PermissionsExt;
    fs::metadata(path).expect("metadata").permissions().mode() & 0o777
}

#[test]
fn the_stable_path_is_the_same_for_every_format() {
    let home = Path::new("/home/u");
    assert_eq!(
        bridge::stable_path(home),
        PathBuf::from("/home/u/.local/bin/morrow-bridge")
    );
    assert_eq!(
        bridge::legacy_path(home),
        PathBuf::from("/home/u/.codeisland/morrow-bridge")
    );
}

#[test]
fn the_bridge_is_copied_out_and_made_executable() {
    let temp = Temp::new("copy");
    let source = temp.shipped("#!/bin/sh\nexit 0\n");
    let placed = bridge::ensure(&source, &temp.home()).expect("placed");

    assert!(placed.copied);
    assert_eq!(placed.path, bridge::stable_path(&temp.home()));
    assert_eq!(
        fs::read(&placed.path).expect("read"),
        b"#!/bin/sh\nexit 0\n"
    );
    assert_eq!(mode(&placed.path), 0o755, "it is run as a program");
}

#[test]
fn an_update_replaces_the_binary_and_a_second_run_does_not() {
    let temp = Temp::new("update");
    let first = temp.shipped("v1");
    bridge::ensure(&first, &temp.home()).expect("first");

    assert!(!bridge::ensure(&first, &temp.home()).expect("again").copied);

    let newer = temp.0.join("app2/morrow-bridge");
    fs::create_dir_all(newer.parent().expect("parent")).expect("dir");
    fs::write(&newer, "v2").expect("write");
    let replaced = bridge::ensure(&newer, &temp.home()).expect("replaced");
    assert!(replaced.copied);
    assert_eq!(fs::read(&replaced.path).expect("read"), b"v2");
}

#[test]
fn no_half_written_binary_is_left_behind() {
    let temp = Temp::new("atomic");
    let placed = bridge::ensure(&temp.shipped("bytes"), &temp.home()).expect("placed");
    let directory = placed.path.parent().expect("parent").to_owned();
    let leftovers: Vec<String> = fs::read_dir(directory)
        .expect("dir")
        .filter_map(Result::ok)
        .filter_map(|entry| entry.file_name().into_string().ok())
        .filter(|name| name.contains("tmp"))
        .collect();
    assert!(leftovers.is_empty(), "{leftovers:?}");
}

#[test]
fn a_missing_source_is_an_error_not_a_missing_bridge() {
    let temp = Temp::new("missing");
    assert!(bridge::ensure(&temp.0.join("nope"), &temp.home()).is_err());
    assert!(!bridge::stable_path(&temp.home()).exists());
}
