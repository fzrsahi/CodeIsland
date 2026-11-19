//! What the bridge's tests share: the golden bundles, a fresh folder under
//! `/tmp` per test, and the bridge binary.
#![allow(dead_code)]

use std::fs::{self, DirBuilder};
use std::os::unix::fs::DirBuilderExt;
use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};

use serde_json::Value;

/// `fixtures/` at the repository root. #86 moves it to `shared/contract/`.
pub fn fixtures_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../fixtures")
}

pub fn bundle(scope: &str) -> Value {
    let path = fixtures_dir().join(scope).join("bridge-golden.json");
    let text = fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    serde_json::from_str(&text).expect("bundle is JSON")
}

/// One fixture: the neutral input with the linux expectation.
#[derive(Clone, Debug)]
pub struct Fixture {
    pub name: String,
    pub input: Value,
    pub expectation: Value,
}

impl Fixture {
    pub fn arguments(&self) -> Vec<String> {
        strings(&self.input["arguments"])
    }

    pub fn stdin(&self) -> &str {
        self.input["stdin"].as_str().unwrap_or_default()
    }

    pub fn reply(&self) -> &str {
        self.input["reply"].as_str().unwrap_or_default()
    }

    pub fn environment(&self) -> Vec<(String, String)> {
        self.input["environment"]
            .as_object()
            .map(|env| {
                env.iter()
                    .map(|(k, v)| (k.clone(), v.as_str().unwrap_or_default().to_owned()))
                    .collect()
            })
            .unwrap_or_default()
    }

    /// Paths of the ancestors, nearest first, as the fixture names them.
    pub fn ancestor_paths(&self) -> Vec<String> {
        self.input["ancestors"]
            .as_array()
            .map(|a| {
                a.iter()
                    .map(|x| x["path"].as_str().unwrap_or_default().to_owned())
                    .collect()
            })
            .unwrap_or_default()
    }

    pub fn has_socket(&self) -> bool {
        self.input["has_socket"].as_bool().unwrap_or(true)
    }

    /// The forwarded payload, `None` when nothing is sent.
    pub fn forwarded(&self) -> Option<&Value> {
        Some(&self.expectation["forwarded"]).filter(|v| !v.is_null())
    }

    pub fn expected_stdout(&self) -> &str {
        self.expectation["stdout"].as_str().unwrap_or_default()
    }

    pub fn expected_status(&self) -> i64 {
        self.expectation["status"].as_i64().unwrap_or(-1)
    }
}

fn strings(value: &Value) -> Vec<String> {
    value
        .as_array()
        .map(|a| {
            a.iter()
                .filter_map(|s| s.as_str().map(str::to_owned))
                .collect()
        })
        .unwrap_or_default()
}

/// Every fixture of the linux bundle, with its neutral input.
pub fn linux_fixtures() -> Vec<Fixture> {
    let neutral = bundle("neutral");
    let linux = bundle("linux");
    let inputs = neutral["fixtures"].as_array().expect("neutral fixtures");
    linux["fixtures"]
        .as_array()
        .expect("linux fixtures")
        .iter()
        .map(|f| {
            let name = f["name"].as_str().expect("name").to_owned();
            let input = inputs
                .iter()
                .find(|n| n["name"] == f["name"])
                .unwrap_or_else(|| panic!("{name}: no neutral input"))["input"]
                .clone();
            Fixture {
                name,
                input,
                expectation: f["expectation"].clone(),
            }
        })
        .collect()
}

pub fn fixture(name: &str) -> Fixture {
    linux_fixtures()
        .into_iter()
        .find(|f| f.name == name)
        .unwrap_or_else(|| panic!("no fixture {name}"))
}

/// Why a fixture is outside this ticket's claim, `None` when it is in:
/// Claude Code's hook (no `--source`), attributed to Claude, to no source
/// (the island's default, Claude), or to Cursor by its payload (rule 2,
/// Cursor running Claude Code's hook). Dropped events count as in.
pub fn out_of_scope(fixture: &Fixture) -> Option<String> {
    let args = fixture.arguments();
    if let Some(i) = args.iter().position(|a| a == "--source") {
        let source = args.get(i + 1).map_or("", String::as_str);
        return Some(format!("--source {source}"));
    }
    let source = fixture.forwarded().and_then(|f| f["_source"].as_str());
    match source {
        None | Some("claude" | "cursor" | "cursor-cli") => None,
        Some(other) => Some(format!("resolves to {other}")),
    }
}

/// A folder of this test's own under `/tmp` (short enough for `sun_path`),
/// removed on drop.
pub struct TestDir {
    pub path: String,
}

impl TestDir {
    pub fn new() -> Self {
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        let n = NEXT.fetch_add(1, Ordering::Relaxed);
        let path = format!("/tmp/mbr-{}-{n}", std::process::id());
        let _ = fs::remove_dir_all(&path);
        DirBuilder::new()
            .mode(0o700)
            .create(&path)
            .expect("create test folder");
        Self { path }
    }

    pub fn join(&self, name: &str) -> String {
        format!("{}/{name}", self.path)
    }
}

impl Drop for TestDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

/// The bridge under test: `MORROW_BRIDGE_UNDER_TEST` (a release build,
/// say), else the one cargo built for this test.
pub fn bridge_binary() -> String {
    std::env::var("MORROW_BRIDGE_UNDER_TEST")
        .unwrap_or_else(|_| env!("CARGO_BIN_EXE_morrow-bridge").to_owned())
}
