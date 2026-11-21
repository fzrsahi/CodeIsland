//! The golden bundles (`fixtures/*/bridge-golden.json`, exported from the
//! Swift suite) as HookIntake's conformance test reads them, after
//! `macos/Tests/MorrowCoreTests/HookIntakeGoldenTests.swift`: each fixture's
//! process tree under a fixed root, the payload normalized as the Swift
//! golden normalizer writes it (`$PID<n>`, `$ROOT`, `$HOME`), and projected
//! through the bundle's `omitted_keys` / `omitted_values`.
//!
//! Shared with morrow-bridge's conformance test (`#[path]`), which runs the
//! same fixtures through the bridge's own fact gathering.
#![allow(dead_code)]

use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

use morrow_core::JsonObject;
use morrow_core::intake::MAX_ANCESTRY;
use morrow_core::intake::host_harness::outermost_app_bundle_path;
use serde_json::Value;

/// Where the hook runs: `$ROOT`, and `$ROOT/work` its working directory.
pub const ROOT: &str = "/golden-root/case";
/// Where the fixtures' ancestor executables are.
pub const TREE: &str = "/golden-root/tree";
/// `$HOME`.
pub const HOME: &str = "/golden-home";
/// The parent's pid; each ancestor above it one more.
pub const FIRST_PID: i32 = 1001;

/// `fixtures/` at the repository root. #86 moves it to `shared/contract/`.
pub fn fixtures_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../shared/contract/fixtures")
}

fn read_bundle(scope: &str) -> Value {
    let path = fixtures_dir().join(scope).join("bridge-golden.json");
    let text = fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    serde_json::from_str(&text).expect("bundle is JSON")
}

/// One scope's bundle, each fixture with its neutral input.
pub struct Bundle {
    pub scope: String,
    pub fixtures: Vec<Fixture>,
    omitted_keys: Vec<String>,
    omitted_values: HashMap<String, Vec<String>>,
}

impl Bundle {
    pub fn load(scope: &str) -> Self {
        let neutral = read_bundle("neutral");
        let bundle = if scope == "neutral" {
            neutral.clone()
        } else {
            read_bundle(scope)
        };
        let inputs = neutral["fixtures"].as_array().expect("neutral fixtures");
        let fixtures = bundle["fixtures"]
            .as_array()
            .expect("fixtures")
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
            .collect();
        let strings = |v: &Value| -> Vec<String> {
            v.as_array()
                .map(|a| {
                    a.iter()
                        .filter_map(|s| s.as_str().map(str::to_owned))
                        .collect()
                })
                .unwrap_or_default()
        };
        Self {
            scope: scope.to_owned(),
            fixtures,
            omitted_keys: strings(&bundle["omitted_keys"]),
            omitted_values: bundle["omitted_values"]
                .as_object()
                .map(|o| o.iter().map(|(k, v)| (k.clone(), strings(v))).collect())
                .unwrap_or_default(),
        }
    }

    /// `BridgeGoldenJSONExporter.projectedForwarded`: the payload without
    /// the keys this scope does not assert.
    pub fn project(&self, mut forwarded: Value) -> Value {
        if let Some(object) = forwarded.as_object_mut() {
            object.retain(|key, value| {
                if self.omitted_keys.contains(key) {
                    return false;
                }
                let dropped = self.omitted_values.get(key);
                !matches!((dropped, value.as_str()), (Some(d), Some(s)) if d.iter().any(|x| x == s))
            });
        }
        forwarded
    }
}

/// One fixture: the neutral input with the scope's expectation.
#[derive(Clone, Debug)]
pub struct Fixture {
    pub name: String,
    pub input: Value,
    pub expectation: Value,
}

/// One process of a fixture's tree, nearest first.
#[derive(Clone, Debug)]
pub struct ChainProcess {
    pub pid: i32,
    pub executable_path: String,
    /// The argv the Swift golden runner's stub ran with: its own arguments,
    /// then the rest of the chain.
    pub arguments: Vec<String>,
    pub bundle_identifier: Option<String>,
}

impl Fixture {
    /// argv after argv\[0\].
    pub fn arguments(&self) -> Vec<String> {
        strings(&self.input["arguments"])
    }

    fn flag(&self, flag: &str) -> Option<String> {
        let args = self.arguments();
        let index = args.iter().position(|a| a == flag)?;
        args.get(index + 1).cloned()
    }

    pub fn source_tag(&self) -> Option<String> {
        self.flag("--source")
    }

    pub fn event_tag(&self) -> Option<String> {
        self.flag("--event")
    }

    /// The environment, `$ROOT` replaced, unfiltered.
    pub fn environment(&self) -> HashMap<String, String> {
        self.input["environment"]
            .as_object()
            .map(|env| {
                env.iter()
                    .map(|(k, v)| {
                        let value = v.as_str().unwrap_or_default().replace("$ROOT", ROOT);
                        (k.clone(), value)
                    })
                    .collect()
            })
            .unwrap_or_default()
    }

    pub fn stdin(&self) -> &str {
        self.input["stdin"].as_str().unwrap_or_default()
    }

    pub fn reply(&self) -> &str {
        self.input["reply"].as_str().unwrap_or_default()
    }

    pub fn has_socket(&self) -> bool {
        self.input["has_socket"].as_bool().unwrap_or(true)
    }

    /// The files that exist, as absolute paths.
    pub fn files(&self) -> Vec<String> {
        self.input["files"]
            .as_object()
            .map(|f| f.keys().map(|k| format!("{ROOT}/{k}")).collect())
            .unwrap_or_default()
    }

    /// The process tree as the Swift golden runner builds it: the
    /// fixture's ancestors, padded with neutral processes to six.
    pub fn chain(&self) -> Vec<ChainProcess> {
        let mut ancestors: Vec<(String, Vec<String>)> = self.input["ancestors"]
            .as_array()
            .map(|a| {
                a.iter()
                    .map(|x| {
                        let path = x["path"].as_str().unwrap_or_default().to_owned();
                        (path, strings(&x["arguments"]))
                    })
                    .collect()
            })
            .unwrap_or_default();
        let mut index = 1;
        while ancestors.len() < MAX_ANCESTRY {
            ancestors.push((format!("neutral/proc{index}"), Vec::new()));
            index += 1;
        }
        // Farthest ancestor first; each one runs what follows its `--`.
        let mut command: Vec<String> = Vec::new();
        for (path, arguments) in ancestors.iter().rev() {
            command.push(format!("{TREE}/{path}"));
            command.extend(arguments.iter().cloned());
            command.push("--".into());
        }
        command.push("morrow-bridge".into());
        command.extend(self.arguments());
        let bundles = self.input["bundle_identifiers"]
            .as_object()
            .cloned()
            .unwrap_or_default();

        ancestors
            .iter()
            .enumerate()
            .map(|(i, (path, _))| {
                let full = format!("{TREE}/{path}");
                let argv_start = command.iter().position(|c| *c == full).unwrap_or(0);
                let bundle_identifier = outermost_app_bundle_path(&full).and_then(|app| {
                    bundles
                        .get(&app[TREE.len() + 1..])
                        .and_then(Value::as_str)
                        .map(str::to_owned)
                });
                ChainProcess {
                    pid: FIRST_PID + i as i32,
                    executable_path: full,
                    arguments: command[argv_start..].to_vec(),
                    bundle_identifier,
                }
            })
            .collect()
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

/// `BridgeGoldenNormalizer.canonicalString`, as a value: `_ppid` /
/// `_hook_ppid` numbers and a `-ppid-<pid>` session id as `$PID<n>`, and
/// `$ROOT` / `$HOME` for those paths in every string.
pub fn normalize(payload: &JsonObject, pids: &[i32]) -> Value {
    normalize_value(&Value::Object(payload.clone()), None, pids)
}

fn normalize_value(value: &Value, key: Option<&str>, pids: &[i32]) -> Value {
    let token = |pid: i64| {
        pids.iter()
            .position(|p| i64::from(*p) == pid)
            .map(|i| format!("$PID{i}"))
    };
    match value {
        Value::Object(object) => Value::Object(
            object
                .iter()
                .map(|(k, v)| (k.clone(), normalize_value(v, Some(k), pids)))
                .collect(),
        ),
        Value::Array(array) => Value::Array(
            array
                .iter()
                .map(|v| normalize_value(v, None, pids))
                .collect(),
        ),
        Value::Number(n) if matches!(key, Some("_ppid" | "_hook_ppid")) => n
            .as_i64()
            .and_then(token)
            .map_or_else(|| value.clone(), Value::from),
        Value::String(text) => {
            let mut text = text.clone();
            if key == Some("session_id") {
                if let Some(at) = text.find("-ppid-") {
                    let head = &text[..at + "-ppid-".len()];
                    if let Some(t) = text[head.len()..].parse().ok().and_then(token) {
                        text = format!("{head}{t}");
                    }
                }
            }
            Value::String(text.replace(ROOT, "$ROOT").replace(HOME, "$HOME"))
        }
        other => other.clone(),
    }
}

/// What a run of one fixture produced.
pub struct Outcome {
    /// The forwarded payload, normalized; `None` when nothing was sent.
    pub forwarded: Option<Value>,
    pub stdout: String,
}

/// Runs every fixture of `bundle` and compares; panics listing every
/// difference. Returns how many passed.
pub fn assert_bundle(bundle: &Bundle, label: &str, run: impl Fn(&Fixture) -> Outcome) -> usize {
    let mut passed = 0;
    let mut failures = Vec::new();
    for fixture in &bundle.fixtures {
        let outcome = run(fixture);
        let forwarded = outcome.forwarded.map(|f| bundle.project(f));
        let mut wrong = Vec::new();
        if forwarded.as_ref() != fixture.forwarded() {
            wrong.push(format!(
                "forwarded\n    expected: {}\n    actual:   {}",
                fixture
                    .forwarded()
                    .map_or("<nothing>".into(), Value::to_string),
                forwarded.map_or("<nothing>".into(), |v| v.to_string()),
            ));
        }
        if outcome.stdout != fixture.expected_stdout() {
            wrong.push(format!(
                "stdout: expected {:?}, got {:?}",
                fixture.expected_stdout(),
                outcome.stdout
            ));
        }
        if fixture.expected_status() != 0 {
            wrong.push(format!(
                "status: expected {}, a hook always exits 0",
                fixture.expected_status()
            ));
        }
        if wrong.is_empty() {
            passed += 1;
        } else {
            failures.push(format!("{}:\n  {}", fixture.name, wrong.join("\n  ")));
        }
    }
    println!(
        "conformance ({label}, {}): {passed} passed, {} failed, 0 skipped, of {}",
        bundle.scope,
        failures.len(),
        bundle.fixtures.len()
    );
    assert!(
        failures.is_empty(),
        "{} fixture(s) differ:\n{}",
        failures.len(),
        failures.join("\n")
    );
    passed
}
