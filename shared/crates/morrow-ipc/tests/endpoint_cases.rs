//! Every case of the endpoint case table (`fixtures/endpoint/cases.json`,
//! contract §1) through [`morrow_ipc::resolve`]: macOS, Linux and Windows.

use std::collections::BTreeMap;
use std::path::PathBuf;

use morrow_ipc::{Platform, resolve};
use serde_json::Value;

/// The case table, from the repository root. The monorepo move (#86)
/// changes this to `shared/contract/fixtures/endpoint/cases.json`; nothing
/// else names the path.
const CASES_PATH: &str = "fixtures/endpoint/cases.json";

/// How many symlinks `exists` follows before it gives up (a loop).
const MAX_SYMLINKS: usize = 8;

fn cases() -> Vec<Value> {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .join(CASES_PATH);
    let text = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("cannot read {}: {e}", path.display()));
    let table: Value = serde_json::from_str(&text).expect("case table is JSON");
    assert_eq!(table["version"], 1, "case table version");
    table["cases"]
        .as_array()
        .expect("`cases` is an array")
        .clone()
}

/// `exists` as `stat(2)` sees the case's files: a symlink exists when its
/// target does.
fn exists_in(existing: &[Value], path: &str) -> bool {
    let mut path = path.to_owned();
    for _ in 0..MAX_SYMLINKS {
        let Some(entry) = existing.iter().find(|e| e["path"] == path.as_str()) else {
            return false;
        };
        if entry["kind"] != "symlink" {
            return true;
        }
        path = entry["target"].as_str().expect("symlink target").to_owned();
    }
    false
}

#[test]
fn every_endpoint_case_resolves_to_its_expected_string() {
    let cases = cases();
    let mut counts: BTreeMap<String, usize> = BTreeMap::new();
    let mut failures = Vec::new();

    for case in &cases {
        let name = case["name"].as_str().expect("name");
        let os = case["os"].as_str().expect("os");
        let env: BTreeMap<String, String> =
            serde_json::from_value(case["env"].clone()).expect("env is string to string");
        let existing = case["existing"].as_array().expect("existing").clone();
        let uid = || u32::try_from(case["uid"].as_u64().expect("uid")).expect("uid fits u32");
        let platform = match os {
            "macos" => Platform::Macos { uid: uid() },
            "linux" => Platform::Linux { uid: uid() },
            "windows" => Platform::Windows {
                sid: case["sid"].as_str().expect("sid"),
            },
            other => panic!("{name}: unknown os {other}"),
        };

        let got = resolve(
            platform,
            |key| env.get(key).cloned(),
            |path| exists_in(&existing, path),
        );
        let expected = case["expected"].as_str().expect("expected");
        if got.as_str() != expected {
            failures.push(format!(
                "{name}: got {:?}, expected {expected:?}",
                got.as_str()
            ));
        }
        *counts.entry(os.to_owned()).or_default() += 1;
    }

    let summary: Vec<String> = counts.iter().map(|(os, n)| format!("{os} {n}")).collect();
    println!(
        "endpoint cases: {} total ({}), {} failed",
        cases.len(),
        summary.join(", "),
        failures.len()
    );
    for os in ["macos", "linux", "windows"] {
        assert!(counts.get(os).copied().unwrap_or(0) > 0, "no {os} case ran");
    }
    assert!(
        failures.is_empty(),
        "failing cases:\n{}",
        failures.join("\n")
    );
}

#[test]
fn private_dir_is_the_morrow_folder_of_the_runtime_dir_only() {
    let env = |vars: &'static [(&'static str, &'static str)]| {
        move |key: &str| {
            vars.iter()
                .find(|(k, _)| *k == key)
                .map(|(_, v)| (*v).to_owned())
        }
    };
    let linux = Platform::Linux { uid: 1000 };
    let runtime = resolve(
        linux,
        env(&[("XDG_RUNTIME_DIR", "/run/user/1000/")]),
        |_| false,
    );
    assert_eq!(runtime.private_dir(), Some("/run/user/1000/morrow"));
    let root = resolve(linux, env(&[("XDG_RUNTIME_DIR", "/")]), |_| false);
    assert_eq!(root.private_dir(), Some("/morrow"));
    let tmp = resolve(linux, env(&[]), |_| false);
    assert_eq!(tmp.private_dir(), None);
    let custom = resolve(
        linux,
        env(&[("MORROW_SOCKET_PATH", "/run/user/1000/morrow/island.sock")]),
        |_| false,
    );
    assert_eq!(
        custom.private_dir(),
        None,
        "an override's folder is not checked"
    );
}
