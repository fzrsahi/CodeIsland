//! The linux golden bundle (`fixtures/linux/bridge-golden.json`, inputs in
//! `fixtures/neutral/`) against the bridge, in process: each fixture's argv,
//! environment and stdin, and its process tree behind the bridge's
//! [`ProcessFacts`], go through the bridge's fact gathering and HookIntake
//! (`morrow_core::intake`); the forwarded payload (as it goes on the wire),
//! stdout and exit status must be the bundle's. Every fixture, every source.
//! morrow-core's own conformance test runs the same fixtures on facts
//! handed to HookIntake directly.
#![cfg(unix)]

#[path = "../../morrow-core/tests/golden/mod.rs"]
mod golden;

use std::collections::HashMap;

use golden::{Bundle, ChainProcess, Fixture, HOME, Outcome, ROOT, assert_bundle, normalize};
use morrow_bridge::facts::{Args, ProcessFacts, interpret};
use morrow_bridge::run::{Log, encode, immediate_stdout};

/// Every fixture of the bundle; a change in it shows here.
const FIXTURES: usize = 84;

/// A fixture's process tree and files, as the OS would report them.
struct FixtureProcess {
    chain: Vec<ChainProcess>,
    files: Vec<String>,
}

impl ProcessFacts for FixtureProcess {
    fn parent_pid(&self) -> Option<i32> {
        self.chain.first().map(|p| p.pid)
    }
    fn ancestry(&self) -> Vec<(i32, Option<String>)> {
        self.chain
            .iter()
            .map(|p| (p.pid, Some(p.executable_path.clone())))
            .collect()
    }
    fn arguments(&self, pid: i32) -> Vec<String> {
        self.chain
            .iter()
            .find(|p| p.pid == pid)
            .map(|p| p.arguments.clone())
            .unwrap_or_default()
    }
    fn bundle_identifier(&self, executable_path: &str) -> Option<String> {
        self.chain
            .iter()
            .find(|p| p.executable_path == executable_path)
            .and_then(|p| p.bundle_identifier.clone())
    }
    fn working_directory(&self) -> Option<String> {
        Some(format!("{ROOT}/work"))
    }
    // The golden runner has no controlling terminal and no tmux.
    fn tty(&self) -> Option<String> {
        None
    }
    fn home_directory(&self) -> Option<String> {
        Some(HOME.to_owned())
    }
    fn tmux_client_tty(&self, _pane: &str) -> Option<String> {
        None
    }
    fn file_exists(&self, path: &str) -> bool {
        self.files.iter().any(|f| f == path)
    }
}

/// `run::run` without the transport: the immediate answer, admission, the
/// socket check, interpretation, terminal context, the encoded payload and
/// the answer's stdout.
fn run_fixture(fixture: &Fixture) -> Outcome {
    let args = Args::parse(fixture.arguments());
    let environment: HashMap<String, String> = fixture.environment();
    let mut stdout = String::new();
    let immediate = immediate_stdout(&args);
    stdout.push_str(immediate.unwrap_or_default());
    if !morrow_core::intake::admits(args.source.as_deref(), &environment) || !fixture.has_socket() {
        return Outcome {
            forwarded: None,
            stdout,
        };
    }
    let process = FixtureProcess {
        chain: fixture.chain(),
        files: fixture.files(),
    };
    let Some(mut intake) = interpret(&args, &environment, fixture.stdin().as_bytes(), &process)
    else {
        return Outcome {
            forwarded: None,
            stdout,
        };
    };
    if immediate.is_none() {
        stdout.push_str(intake.immediate_stdout().unwrap_or_default());
    }
    intake.add_terminal_context();

    // What goes on the wire decodes as a hook payload.
    let wire = encode(&intake, &Log::from_environment(&HashMap::new()));
    let decoded = morrow_protocol::decode_payload(&wire)
        .unwrap_or_else(|e| panic!("{}: forwarded bytes are no hook payload: {e}", fixture.name));
    let pids: Vec<i32> = process.chain.iter().map(|p| p.pid).collect();
    let forwarded = normalize(&decoded.into_object(), &pids);

    if let Some(answer) = intake.stdout_for_answer(fixture.reply().as_bytes()) {
        stdout.push_str(&String::from_utf8_lossy(&answer));
    }
    Outcome {
        forwarded: Some(forwarded),
        stdout,
    }
}

#[test]
fn every_fixture_matches_the_linux_bundle() {
    let bundle = Bundle::load("linux");
    assert_eq!(bundle.fixtures.len(), FIXTURES, "linux fixture count");
    let passed = assert_bundle(&bundle, "morrow-bridge", run_fixture);
    assert_eq!(passed, FIXTURES);
}
