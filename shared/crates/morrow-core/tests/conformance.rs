//! HookIntake on the facts of every golden fixture, handed over directly
//! (no process, no socket), must produce what the Swift bridge recorded:
//! the forwarded payload, stdout and exit status of the neutral bundle
//! (every input, every source) and of the linux bundle. The port of
//! `macos/Tests/MorrowCoreTests/HookIntakeGoldenTests.swift`.

mod golden;

use std::collections::HashMap;

use golden::{Bundle, Fixture, HOME, Outcome, ROOT, assert_bundle, normalize};
use morrow_core::intake::cursor_hook_payload::delivery_digest;
use morrow_core::intake::{
    Ancestor, ENVIRONMENT_KEYS, Facts, HookIntake, SourceCatalog, admits, immediate_stdout,
    stdin_object,
};

/// Every fixture of the neutral bundle; a change in the bundle shows here.
const FIXTURES: usize = 84;

/// The bridge's flow on injected facts, as the Swift test runs it.
fn deliver(fixture: &Fixture, filter_environment: bool) -> Outcome {
    let source_tag = fixture.source_tag();
    let event_tag = fixture.event_tag();
    let mut environment = fixture.environment();
    if filter_environment {
        environment.retain(|key, _| ENVIRONMENT_KEYS.contains(&key.as_str()));
    }
    let catalog = SourceCatalog::default();

    let mut stdout = String::new();
    let mut wrote_immediate = false;
    let mut write_immediate = |text: Option<&str>, stdout: &mut String| {
        if let (false, Some(text)) = (wrote_immediate, text) {
            wrote_immediate = true;
            stdout.push_str(text);
        }
    };
    write_immediate(
        immediate_stdout(source_tag.as_deref(), event_tag.as_deref(), &catalog),
        &mut stdout,
    );
    let nothing = |stdout| Outcome {
        forwarded: None,
        stdout,
    };
    if !admits(source_tag.as_deref(), &environment) || !fixture.has_socket() {
        return nothing(stdout);
    }
    let input = fixture.stdin().as_bytes();
    let Some(object) = (!input.is_empty())
        .then(|| stdin_object(input, source_tag.as_deref()))
        .flatten()
    else {
        return nothing(stdout);
    };

    let chain = fixture.chain();
    let pids: Vec<i32> = chain.iter().map(|p| p.pid).collect();
    let files = fixture.files();
    let facts = Facts {
        source_tag: source_tag.clone(),
        event_tag,
        environment,
        parent_pid: Some(pids[0]),
        ancestry: chain
            .into_iter()
            .map(|p| {
                let (arguments, bundle) = (p.arguments, p.bundle_identifier);
                Ancestor::new(p.pid, Some(p.executable_path))
                    .with_arguments(move || arguments.clone())
                    .with_bundle_identifier(move || bundle.clone())
            })
            .collect(),
        working_directory: Box::new(|| Some(format!("{ROOT}/work"))),
        home_directory: Box::new(|| Some(HOME.to_owned())),
        expanding_tilde_in_path: Box::new(|path| {
            if path == "~" {
                HOME.to_owned()
            } else if let Some(rest) = path.strip_prefix('~').filter(|r| r.starts_with('/')) {
                format!("{HOME}{rest}")
            } else {
                path.to_owned()
            }
        }),
        stdin_digest: Box::new(move || Some(delivery_digest(input))),
        file_exists: Box::new(move |path| files.iter().any(|f| f == path)),
        catalog,
        ..Facts::default()
    };
    let Some(mut intake) = HookIntake::new(object, facts) else {
        return nothing(stdout);
    };
    write_immediate(intake.immediate_stdout(), &mut stdout);
    intake.add_terminal_context();
    if let Some(answer) = intake.stdout_for_answer(fixture.reply().as_bytes()) {
        stdout.push_str(&String::from_utf8_lossy(&answer));
    }
    Outcome {
        forwarded: Some(normalize(intake.payload(), &pids)),
        stdout,
    }
}

#[test]
fn intake_reproduces_the_neutral_bundle() {
    let bundle = Bundle::load("neutral");
    assert_eq!(bundle.fixtures.len(), FIXTURES, "neutral fixture count");
    let passed = assert_bundle(&bundle, "morrow-core intake", |f| deliver(f, true));
    assert_eq!(passed, FIXTURES);
}

#[test]
fn intake_reproduces_the_linux_bundle() {
    let bundle = Bundle::load("linux");
    assert_eq!(bundle.fixtures.len(), FIXTURES, "linux fixture count");
    let passed = assert_bundle(&bundle, "morrow-core intake", |f| deliver(f, true));
    assert_eq!(passed, FIXTURES);
}

/// HookIntake reads only `ENVIRONMENT_KEYS`: the rest of an environment
/// changes nothing (Swift's `testIntakeReadsNoOtherEnvironment`).
#[test]
fn intake_reads_no_other_environment() {
    for mut fixture in Bundle::load("neutral").fixtures {
        let clean = deliver(&fixture, true).forwarded;
        let noise: HashMap<&str, &str> = HashMap::from([
            ("UNRELATED_SECRET", "x"),
            ("PATH", "/usr/bin"),
            ("HOME", "/elsewhere"),
        ]);
        let environment = fixture.input["environment"].as_object_mut();
        if let Some(environment) = environment {
            for (key, value) in noise {
                environment.entry(key).or_insert(value.into());
            }
        } else {
            fixture.input["environment"] = serde_json::json!(noise);
        }
        assert_eq!(
            deliver(&fixture, false).forwarded,
            clean,
            "{}",
            fixture.name
        );
    }
}
