//! The bridge binary, spawned as a hook would be, against a stand-in island
//! (`morrow_ipc::unix::Server`) at `MORROW_SOCKET_PATH` in a fresh folder:
//! golden fixtures end to end, the deadlines, and every way stdin or the
//! socket can be broken. Every run must exit 0.
#![cfg(unix)]

mod common;

use std::fs;
use std::io::Write;
use std::process::{Child, Command, Output, Stdio};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

use common::{TestDir, bridge_binary, fixture, project_linux};
use morrow_ipc::unix::{Client, Server};
use morrow_ipc::{Endpoint, EndpointKind, Platform, resolve};
use serde_json::Value;

/// What a [`Server`] stand-in sends to say "the bridge never connected".
const SENTINEL: &[u8] = b"__no_bridge__";

fn override_endpoint(path: &str) -> Endpoint {
    let path = path.to_owned();
    let endpoint = resolve(
        Platform::Linux { uid: 0 },
        |key| (key == "MORROW_SOCKET_PATH").then(|| path.clone()),
        |_| false,
    );
    assert_eq!(endpoint.kind(), EndpointKind::Override);
    endpoint
}

/// A stand-in island: accepts one connection, reads the request, waits
/// `delay`, answers `reply`. The request comes back on the channel.
struct Island {
    endpoint: Endpoint,
    requests: mpsc::Receiver<Vec<u8>>,
}

impl Island {
    fn start(dir: &TestDir, reply: &[u8], delay: Duration) -> Self {
        let endpoint = override_endpoint(&dir.join("island.sock"));
        let server = Server::bind(&endpoint).expect("bind the stand-in island");
        let (tx, requests) = mpsc::channel();
        let reply = reply.to_vec();
        thread::spawn(move || {
            let Ok(mut connection) = server.accept() else {
                return;
            };
            let request = connection.read_request().unwrap_or_default();
            let _ = tx.send(request);
            thread::sleep(delay);
            let _ = connection.reply(&reply);
            // `server` drops here: the socket file goes with it.
        });
        Self { endpoint, requests }
    }

    /// The request the bridge sent, or `None` if it never connected (the
    /// test connects itself to find out).
    fn request(self) -> Option<Vec<u8>> {
        if let Ok(request) = self.requests.recv_timeout(Duration::from_millis(200)) {
            return Some(request);
        }
        if let Ok(client) = Client::connect(&self.endpoint, Duration::from_secs(1)) {
            let _ = client.send(SENTINEL, Some(Duration::from_secs(1)));
        }
        let request = self
            .requests
            .recv_timeout(Duration::from_secs(5))
            .expect("stand-in island answered");
        (request != SENTINEL).then_some(request)
    }
}

/// The bridge with only `env` (and a plain PATH), in `dir/work`.
fn bridge(dir: &TestDir, socket: &str, env: &[(String, String)]) -> Command {
    let work = dir.join("work");
    fs::create_dir_all(&work).unwrap();
    let mut command = Command::new(bridge_binary());
    command
        .env_clear()
        .env("PATH", "/usr/bin:/bin")
        .env("MORROW_SOCKET_PATH", socket)
        .envs(env.iter().cloned())
        .current_dir(&work)
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    command
}

fn feed(mut child: Child, stdin: &[u8]) -> Output {
    let mut pipe = child.stdin.take().expect("stdin piped");
    let _ = pipe.write_all(stdin);
    drop(pipe);
    child.wait_with_output().expect("bridge ran")
}

/// The fixture's payload and the bridge's, with what a live run cannot
/// reproduce made equal: `_ppid` is this test process (the bridge's
/// parent, `$PID0`), the work folder is `$ROOT/work`, and `_source`, which
/// the fixture's process tree decides (the in-process conformance test
/// covers it), is left out of both, as is what the linux bundle does not
/// assert.
fn comparable(mut payload: Value, dir: &TestDir) -> Value {
    project_linux(&mut payload);
    let object = payload.as_object_mut().unwrap();
    object.remove("_source");
    if object.get("_ppid").and_then(Value::as_u64) == Some(u64::from(std::process::id())) {
        object.insert("_ppid".into(), "$PID0".into());
    }
    if let Some(cwd) = object.get("cwd").and_then(Value::as_str) {
        let work = dir.join("work");
        let real_work = fs::canonicalize(&work)
            .unwrap()
            .to_string_lossy()
            .into_owned();
        if cwd == work || cwd == real_work {
            object.insert("cwd".into(), "$ROOT/work".into());
        }
    }
    payload
}

fn run_fixture_end_to_end(name: &str) {
    let fixture = fixture(name);
    let dir = TestDir::new();
    let island = Island::start(&dir, fixture.reply().as_bytes(), Duration::ZERO);
    let child = bridge(&dir, island.endpoint.as_str(), &fixture.environment())
        .args(fixture.arguments())
        .stdin(Stdio::piped())
        .spawn()
        .expect("spawn bridge");
    let output = feed(child, fixture.stdin().as_bytes());
    let forwarded = island.request().map(|bytes| {
        let payload = morrow_protocol::decode_payload(&bytes).expect("a hook payload");
        comparable(Value::Object(payload.into_object()), &dir)
    });

    assert_eq!(output.status.code(), Some(0), "{name}: exit status");
    assert_eq!(
        String::from_utf8_lossy(&output.stdout),
        fixture.expected_stdout(),
        "{name}: stdout"
    );
    let expected = fixture.forwarded().cloned().map(|v| comparable(v, &dir));
    assert_eq!(forwarded, expected, "{name}: forwarded payload");
}

#[test]
fn permission_allow_prints_the_answer() {
    run_fixture_end_to_end("claude-homebrew-permission-allow");
}

#[test]
fn permission_deny_prints_the_answer() {
    run_fixture_end_to_end("claude-permission-deny");
}

#[test]
fn permission_with_an_empty_answer_prints_nothing() {
    run_fixture_end_to_end("claude-permission-empty-reply");
}

#[test]
fn question_prints_the_answer() {
    run_fixture_end_to_end("claude-notification-question");
}

#[test]
fn plain_notification_ignores_the_reply() {
    run_fixture_end_to_end("claude-notification-plain");
}

#[test]
fn tool_step_in_tmux_is_forwarded_with_its_pane() {
    run_fixture_end_to_end("claude-in-tmux-pretooluse");
}

#[test]
fn aliases_and_the_working_directory_come_from_the_bridge() {
    run_fixture_end_to_end("camelcase-fork");
}

#[test]
fn cursor_running_claudes_hook_is_never_held() {
    run_fixture_end_to_end("cursor-imported-claude-permission-never-held");
}

#[test]
fn an_event_without_a_session_is_not_sent() {
    run_fixture_end_to_end("no-session-no-source");
}

#[test]
fn codex_permission_with_its_source_prints_the_answer() {
    run_fixture_end_to_end("codex-permission-request-deny");
}

#[test]
fn gemini_permission_answer_is_put_as_gemini_reads_it() {
    run_fixture_end_to_end("gemini-beforetool-allow");
}

#[test]
fn antigravity_pre_tool_use_is_answered_at_once() {
    run_fixture_end_to_end("agy-pretooluse");
}

/// Antigravity refuses the tool call when its hook prints nothing: the
/// answer comes before the bridge finds no island and exits.
#[test]
fn antigravity_is_answered_with_no_island_running() {
    let fixture = fixture("agy-pretooluse-island-not-running");
    let dir = TestDir::new();
    let child = bridge(&dir, &dir.join("absent.sock"), &fixture.environment())
        .args(fixture.arguments())
        .stdin(Stdio::piped())
        .spawn()
        .unwrap();
    let output = feed(child, fixture.stdin().as_bytes());
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(
        String::from_utf8_lossy(&output.stdout),
        fixture.expected_stdout()
    );
    assert_eq!(fixture.expected_stdout(), r#"{"decision":"ask"}"#);
}

/// A Stop event: valid, non-blocking.
const STOP: &[u8] = br#"{"session_id":"s-1","hook_event_name":"Stop","cwd":"/x"}"#;
const PERMISSION: &[u8] =
    br#"{"session_id":"s-2","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"ls"}}"#;

fn assert_nothing_sent_for_stdin(stdin: &[u8]) {
    let dir = TestDir::new();
    let island = Island::start(&dir, b"{}", Duration::ZERO);
    let child = bridge(&dir, island.endpoint.as_str(), &[])
        .stdin(Stdio::piped())
        .spawn()
        .unwrap();
    let output = feed(child, stdin);
    assert_eq!(output.status.code(), Some(0));
    assert!(output.stdout.is_empty());
    assert_eq!(island.request(), None, "nothing sent for stdin {stdin:?}");
}

#[test]
fn invalid_json_exits_0_and_sends_nothing() {
    assert_nothing_sent_for_stdin(b"{not json");
    assert_nothing_sent_for_stdin(b"[1,2]");
}

#[test]
fn empty_stdin_exits_0_and_sends_nothing() {
    assert_nothing_sent_for_stdin(b"");
}

#[test]
fn closed_stdin_exits_0_and_sends_nothing() {
    let dir = TestDir::new();
    let island = Island::start(&dir, b"{}", Duration::ZERO);
    // fd 0 closed altogether, not an empty pipe.
    let output = Command::new("/bin/sh")
        .args(["-c", "exec \"$0\" <&-", &bridge_binary()])
        .env_clear()
        .env("MORROW_SOCKET_PATH", island.endpoint.as_str())
        .stdout(Stdio::piped())
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(0));
    assert!(output.stdout.is_empty());
    assert_eq!(island.request(), None);
}

#[test]
fn a_regular_file_at_the_socket_path_exits_before_reading_stdin() {
    let dir = TestDir::new();
    let path = dir.join("island.sock");
    fs::write(&path, b"not a socket").unwrap();
    let started = Instant::now();
    // stdin stays open and empty: a bridge that read it would wait 5 s.
    let mut child = bridge(&dir, &path, &[])
        .stdin(Stdio::piped())
        .spawn()
        .unwrap();
    // `wait` would close stdin first: keep it open until the bridge is gone.
    let open_stdin = child.stdin.take();
    let status = child.wait().unwrap();
    let elapsed = started.elapsed();
    drop(open_stdin);
    assert_eq!(status.code(), Some(0));
    assert!(elapsed < Duration::from_secs(1), "took {elapsed:?}");
}

#[test]
fn stdin_left_open_gives_up_after_5_s() {
    let dir = TestDir::new();
    let island = Island::start(&dir, b"{}", Duration::ZERO);
    let started = Instant::now();
    let mut child = bridge(&dir, island.endpoint.as_str(), &[])
        .stdin(Stdio::piped())
        .spawn()
        .unwrap();
    // `wait` would close stdin first: keep it open until the bridge is gone.
    let open_stdin = child.stdin.take();
    let status = child.wait().unwrap();
    let elapsed = started.elapsed();
    drop(open_stdin);
    assert_eq!(status.code(), Some(0));
    assert!(
        elapsed >= Duration::from_millis(4900) && elapsed < Duration::from_secs(7),
        "took {elapsed:?}"
    );
    assert_eq!(island.request(), None);
}

#[test]
fn an_island_that_never_answers_does_not_hold_a_non_blocking_event() {
    let dir = TestDir::new();
    let island = Island::start(&dir, b"{}", Duration::from_secs(10));
    let started = Instant::now();
    let child = bridge(&dir, island.endpoint.as_str(), &[])
        .stdin(Stdio::piped())
        .spawn()
        .unwrap();
    let output = feed(child, STOP);
    let elapsed = started.elapsed();
    assert_eq!(output.status.code(), Some(0));
    assert!(output.stdout.is_empty());
    assert!(elapsed < Duration::from_millis(4500), "took {elapsed:?}");
    assert!(
        island.requests.recv_timeout(Duration::from_secs(1)).is_ok(),
        "the event was delivered"
    );
}

#[test]
fn a_blocking_event_waits_past_every_deadline_for_the_answer() {
    let dir = TestDir::new();
    let answer = br#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#;
    // Past the 8 s deadline of connect + send.
    let island = Island::start(&dir, answer, Duration::from_secs(9));
    let started = Instant::now();
    let child = bridge(&dir, island.endpoint.as_str(), &[])
        .stdin(Stdio::piped())
        .spawn()
        .unwrap();
    let output = feed(child, PERMISSION);
    assert_eq!(output.status.code(), Some(0));
    assert!(started.elapsed() >= Duration::from_secs(9));
    assert_eq!(output.stdout, answer);
}

/// The real process tree, read from `/proc`: Claude Code's native binary
/// (a copy of `sh` at its install path) runs the hook, so the event is
/// Claude's and `_ppid` is that process.
#[cfg(target_os = "linux")]
#[test]
fn claude_in_the_process_tree_is_the_source_and_the_tracked_process() {
    let dir = TestDir::new();
    let claude = dir.join("home/.local/share/claude/versions/2.1.294");
    fs::create_dir_all(std::path::Path::new(&claude).parent().unwrap()).unwrap();
    fs::copy("/bin/sh", &claude).unwrap();
    let island = Island::start(&dir, b"{}", Duration::ZERO);
    // `; :` keeps the shell from exec-ing the bridge: the shell stays its parent.
    let work = dir.join("work");
    fs::create_dir_all(&work).unwrap();
    let child = Command::new(&claude)
        .args(["-c", "\"$0\"; :", &bridge_binary()])
        .env_clear()
        .env("MORROW_SOCKET_PATH", island.endpoint.as_str())
        .current_dir(&work)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let claude_pid = child.id();
    let output = feed(child, STOP);
    assert_eq!(output.status.code(), Some(0));
    let request = island.request().expect("the event was sent");
    let payload: Value = serde_json::from_slice(&request).unwrap();
    assert_eq!(payload["_source"], "claude");
    assert_eq!(payload["_ppid"], u64::from(claude_pid));
    assert!(payload.get("_hook_ppid").is_none());
}

#[test]
fn a_missing_island_exits_0_silently() {
    let dir = TestDir::new();
    let child = bridge(&dir, &dir.join("absent.sock"), &[])
        .stdin(Stdio::piped())
        .spawn()
        .unwrap();
    let output = feed(child, PERMISSION);
    assert_eq!(output.status.code(), Some(0));
    assert!(output.stdout.is_empty());
}
