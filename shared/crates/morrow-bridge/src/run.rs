//! One hook invocation, end to end (the Swift bridge's `main.swift`): every
//! way out is exit 0, and nothing is printed but what HookIntake says to
//! print: an immediate answer (Google Antigravity's PreToolUse), or the
//! island's answer to a hook that waits for one.

use std::collections::HashMap;
use std::fs;
use std::io::{self, Read, Write};
use std::os::unix::fs::{FileTypeExt, MetadataExt};
use std::time::Duration;

use morrow_core::intake::{HookIntake, SourceCatalog, admits};
use morrow_ipc::Endpoint;
use morrow_ipc::unix::{Client, current_endpoint};
use morrow_protocol::{HookPayload, encode_payload};

use crate::deadline::Deadline;
use crate::facts::{Args, interpret};
use crate::process::OsProcess;

/// Reading stdin: an agent that never closes its pipe cannot hold the hook.
const STDIN_DEADLINE: Duration = Duration::from_secs(5);
/// Interpreting, connecting and the whole exchange of a hook nobody waits on.
const NON_BLOCKING_DEADLINE: Duration = Duration::from_secs(4);
/// Interpreting, connecting and sending a hook that waits; the reply then
/// takes as long as the user does.
const BLOCKING_DEADLINE: Duration = Duration::from_secs(8);
const NON_BLOCKING_CONNECT: Duration = Duration::from_millis(1000);
const BLOCKING_CONNECT: Duration = Duration::from_millis(3000);
/// Each read and write of a hook nobody waits on: the island answers a
/// lifecycle event at once (protocol, *Transport*).
const NON_BLOCKING_IO: Duration = Duration::from_secs(1);

/// What the hook prints before anything else can end it, from argv alone
/// (`HookIntake.immediateStdout(sourceTag:eventName:)`). The catalog is
/// empty: the seeded custom commands are Claude's, which cannot make a hook
/// Antigravity's.
pub fn immediate_stdout(args: &Args) -> Option<&'static str> {
    morrow_core::intake::immediate_stdout(
        args.source.as_deref(),
        args.event.as_deref(),
        &SourceCatalog::default(),
    )
}

/// The bytes to forward: the payload as morrow-protocol encodes it. One
/// the schema refuses (an agent's odd field) still goes out as JSON, as the
/// Swift bridge sends it; the island decides.
pub fn encode(intake: &HookIntake<'_>, log: &Log) -> Vec<u8> {
    match HookPayload::from_object(intake.payload().clone()) {
        Ok(payload) => encode_payload(&payload),
        Err(error) => {
            log.note(&format!(
                "payload breaks hook-payload.schema.json ({error}), sending it anyway"
            ));
            serde_json::to_vec(intake.payload()).unwrap_or_default()
        }
    }
}

/// Lines on stderr, only with `MORROW_DEBUG` or `CODEISLAND_DEBUG` set.
#[derive(Clone, Copy, Debug)]
pub struct Log {
    enabled: bool,
}

impl Log {
    pub fn from_environment(environment: &HashMap<String, String>) -> Self {
        let set = |key: &str| environment.get(key).is_some_and(|v| !v.is_empty());
        Self {
            enabled: set("MORROW_DEBUG") || set("CODEISLAND_DEBUG"),
        }
    }

    pub fn note(&self, message: &str) {
        if self.enabled {
            let _ = writeln!(io::stderr(), "morrow-bridge: {message}");
        }
    }
}

/// Whether `lstat` finds a socket this user owns at the endpoint: the
/// check made before stdin is read, so that a hook with no island to talk
/// to costs nothing. [`Client::connect`] checks again, and the peer.
fn own_socket_at(endpoint: &Endpoint) -> bool {
    fs::symlink_metadata(endpoint.as_str())
        .is_ok_and(|meta| meta.file_type().is_socket() && meta.uid() == crate::sys::current_uid())
}

/// Writes `text` to stdout at once.
fn print(text: &[u8]) {
    let mut stdout = io::stdout().lock();
    let _ = stdout.write_all(text).and_then(|()| stdout.flush());
}

/// The process environment, UTF-8 variables only.
fn environment() -> HashMap<String, String> {
    std::env::vars_os()
        .filter_map(|(key, value)| Some((key.into_string().ok()?, value.into_string().ok()?)))
        .collect()
}

/// The bridge. Returns when the hook is done; the caller exits 0.
pub fn run() {
    let environment = environment();
    let log = Log::from_environment(&environment);
    // With `panic = "abort"` the hook still runs: a bug exits 0 too.
    std::panic::set_hook(Box::new(move |info| {
        log.note(&format!("panic: {info}"));
        std::process::exit(0);
    }));

    let args = Args::parse(
        std::env::args_os()
            .skip(1)
            .filter_map(|a| a.into_string().ok()),
    );
    // Google Antigravity refuses the tool call when its PreToolUse hook
    // prints no decision: answer before any way out below (#339).
    let mut wrote_immediate = false;
    let mut write_immediate = |text: Option<&str>| {
        if let (false, Some(text)) = (wrote_immediate, text) {
            wrote_immediate = true;
            print(text.as_bytes());
        }
    };
    write_immediate(immediate_stdout(&args));
    if !admits(args.source.as_deref(), &environment) {
        return;
    }
    let endpoint = current_endpoint();
    if !own_socket_at(&endpoint) {
        log.note(&format!(
            "no socket of this user at {endpoint}, not sending"
        ));
        return;
    }

    let deadline = Deadline::start();
    let arm = |after| deadline.as_ref().inspect(|d| d.arm(after));
    let disarm = || deadline.as_ref().inspect(|d| d.disarm());

    arm(STDIN_DEADLINE);
    let mut stdin = Vec::new();
    if io::stdin().lock().read_to_end(&mut stdin).is_err() {
        stdin.clear();
    }
    disarm();

    let process = OsProcess;
    let Some(mut intake) = interpret(&args, &environment, &stdin, &process) else {
        log.note(&format!(
            "dropped: stdin is not a JSON object or names no session ({} bytes)",
            stdin.len()
        ));
        return;
    };
    // Antigravity wired through Gemini-style hooks names the event on stdin.
    write_immediate(intake.immediate_stdout());
    let waits = intake.waits_for_answer;
    log.note(&format!(
        "event={} normalized={} source={} session={} waits={waits}",
        intake.event_name,
        intake.normalized_event_name,
        intake.source.as_deref().unwrap_or("-"),
        intake.session_id,
    ));

    arm(if waits {
        BLOCKING_DEADLINE
    } else {
        NON_BLOCKING_DEADLINE
    });
    intake.add_terminal_context();
    let request = encode(&intake, &log);
    // Gemini prints its own approval prompt first; the card follows.
    if !intake.delivery_delay.is_zero() {
        std::thread::sleep(intake.delivery_delay);
    }

    let connect_timeout = if waits {
        BLOCKING_CONNECT
    } else {
        NON_BLOCKING_CONNECT
    };
    let client = match Client::connect(&endpoint, connect_timeout) {
        Ok(client) => client,
        Err(error) => {
            log.note(&format!("not sending: {error}"));
            return;
        }
    };
    let reply = if waits {
        let pending = match client.send(&request, None) {
            Ok(pending) => pending,
            Err(error) => {
                log.note(&format!("send failed: {error}"));
                return;
            }
        };
        // Sent: the user answers in their own time.
        disarm();
        pending.wait(None)
    } else {
        client.send_and_wait(&request, Some(NON_BLOCKING_IO))
    };
    let reply = match reply {
        Ok(reply) => reply,
        Err(error) => {
            log.note(&format!("no reply: {error}"));
            return;
        }
    };
    if let Some(answer) = intake.stdout_for_answer(&reply) {
        print(&answer);
    }
}
