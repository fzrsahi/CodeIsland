//! The linux golden bundle (`fixtures/linux/bridge-golden.json`, inputs in
//! `fixtures/neutral/`) against the bridge's interpretation, in process: each
//! fixture's argv, environment, stdin and process tree go in; the forwarded
//! payload, stdout and exit status must be the bundle's.
//!
//! Only Claude Code's hook is claimed (#89): fixtures with a `--source` or
//! that resolve to another agent are listed as skipped. TODO(#93): every
//! fixture, once HookIntake is morrow-core's.
#![cfg(unix)]

mod common;

use std::collections::HashMap;

use common::{Fixture, linux_fixtures, out_of_scope};
use morrow_bridge::intake::{Ancestor, Args, MAX_ANCESTRY, ProcessFacts};
use morrow_bridge::run::{Log, encode, interpret};
use serde_json::Value;

/// The fixtures this ticket claims; a change in the filter or the bundle
/// shows here instead of silently testing fewer.
const CLAIMED: usize = 23;

/// A fixture's process tree, as Swift's golden runner builds it: the
/// ancestors under a root, padded with neutral processes to six, each with
/// a pid of its own. The hook runs in `$ROOT/work`, as there.
struct FixtureProcess {
    ancestry: Vec<Ancestor>,
}

const FIRST_PID: i32 = 4100;

impl FixtureProcess {
    fn new(fixture: &Fixture) -> Self {
        let mut paths = fixture.ancestor_paths();
        let mut index = 1;
        while paths.len() < MAX_ANCESTRY {
            paths.push(format!("neutral/proc{index}"));
            index += 1;
        }
        let ancestry = paths
            .into_iter()
            .enumerate()
            .map(|(i, path)| Ancestor {
                pid: FIRST_PID + i as i32,
                executable_path: Some(format!("/tmp/ci-golden-root/tree/{path}")),
            })
            .collect();
        Self { ancestry }
    }

    fn token(&self, pid: i64) -> Option<String> {
        self.ancestry
            .iter()
            .position(|a| i64::from(a.pid) == pid)
            .map(|i| format!("$PID{i}"))
    }
}

impl ProcessFacts for FixtureProcess {
    fn parent_pid(&self) -> Option<i32> {
        self.ancestry.first().map(|a| a.pid)
    }
    fn ancestry(&self) -> Vec<Ancestor> {
        self.ancestry.clone()
    }
    fn working_directory(&self) -> Option<String> {
        Some("$ROOT/work".into())
    }
    // The golden runner's PATH has no tmux.
    fn tmux_client_tty(&self, _pane: &str) -> Option<String> {
        None
    }
}

/// What the bridge does with a fixture: the forwarded payload with pids
/// replaced by their `$PID<n>` tokens, and its stdout. Its status is 0 on
/// every path (`run` returns, `main` exits 0).
fn run_fixture(fixture: &Fixture) -> (Option<Value>, String) {
    let process = FixtureProcess::new(fixture);
    let args = Args::parse(fixture.arguments());
    let environment: HashMap<String, String> = fixture.environment().into_iter().collect();
    if !fixture.has_socket() {
        return (None, String::new());
    }
    let Some((mut intake, facts)) =
        interpret(&args, &environment, fixture.stdin().as_bytes(), &process)
    else {
        return (None, String::new());
    };
    intake.add_terminal_context(&facts);

    // What goes on the wire decodes as a hook payload.
    let wire = encode(&intake, &Log::from_environment(&HashMap::new()));
    let decoded = morrow_protocol::decode_payload(&wire)
        .unwrap_or_else(|e| panic!("{}: forwarded bytes are no hook payload: {e}", fixture.name));
    let mut forwarded = Value::Object(decoded.into_object());
    tokenize_pids(&mut forwarded, &process);

    let stdout = intake
        .stdout_for_answer(fixture.reply().as_bytes())
        .map(|bytes| String::from_utf8_lossy(bytes).into_owned())
        .unwrap_or_default();
    (Some(forwarded), stdout)
}

/// `_ppid`, `_hook_ppid` and a `-ppid-<pid>` session id, as the golden
/// normalizer writes them.
fn tokenize_pids(payload: &mut Value, process: &FixtureProcess) {
    let Some(object) = payload.as_object_mut() else {
        return;
    };
    for key in ["_ppid", "_hook_ppid"] {
        if let Some(token) = object
            .get(key)
            .and_then(Value::as_i64)
            .and_then(|p| process.token(p))
        {
            object.insert(key.into(), token.into());
        }
    }
    if let Some(session) = object.get("session_id").and_then(Value::as_str) {
        if let Some((head, pid)) = session.rsplit_once("-ppid-") {
            if let Some(token) = pid.parse().ok().and_then(|p| process.token(p)) {
                let session = format!("{head}-ppid-{token}");
                object.insert("session_id".into(), session.into());
            }
        }
    }
}

#[test]
fn claude_hook_fixtures_match_the_linux_bundle() {
    let mut passed = Vec::new();
    let mut skipped = Vec::new();
    let mut failures = Vec::new();

    for fixture in linux_fixtures() {
        if let Some(reason) = out_of_scope(&fixture) {
            skipped.push(format!("{} ({reason})", fixture.name));
            continue;
        }
        let (forwarded, stdout) = run_fixture(&fixture);
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
        if stdout != fixture.expected_stdout() {
            wrong.push(format!(
                "stdout: expected {:?}, got {stdout:?}",
                fixture.expected_stdout()
            ));
        }
        if fixture.expected_status() != 0 {
            wrong.push(format!(
                "status: expected {}, the bridge always exits 0",
                fixture.expected_status()
            ));
        }
        if wrong.is_empty() {
            passed.push(fixture.name);
        } else {
            failures.push(format!("{}:\n  {}", fixture.name, wrong.join("\n  ")));
        }
    }

    println!(
        "conformance (linux, claude hook): {} passed, {} failed, {} skipped",
        passed.len(),
        failures.len(),
        skipped.len()
    );
    println!("passed: {}", passed.join(", "));
    println!("skipped:\n  {}", skipped.join("\n  "));
    assert!(
        failures.is_empty(),
        "{} fixture(s) differ:\n{}",
        failures.len(),
        failures.join("\n")
    );
    assert_eq!(passed.len(), CLAIMED, "claimed fixture count changed");
}
