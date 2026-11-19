//! The Unix socket transport against real sockets, in a fresh folder under
//! `/tmp` per test (short enough for `sun_path`; never the real
//! `/tmp/morrow-<uid>.sock`). Runs on macOS and Linux.
#![cfg(unix)]

use std::fs::{self, DirBuilder, Permissions};
use std::os::unix::fs::{DirBuilderExt, MetadataExt, PermissionsExt};
use std::os::unix::net::UnixListener;
use std::path::Path;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::{Duration, Instant};

use morrow_ipc::unix::{Client, Error, Server};
use morrow_ipc::{Endpoint, EndpointKind, Platform, resolve};

const CONNECT_TIMEOUT: Duration = Duration::from_secs(2);
const IO_TIMEOUT: Option<Duration> = Some(Duration::from_secs(5));

/// A folder of this test's own, removed with everything in it on drop.
struct TestDir {
    path: String,
}

impl TestDir {
    fn new() -> Self {
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        let n = NEXT.fetch_add(1, Ordering::Relaxed);
        let path = format!("/tmp/mipc-{}-{n}", std::process::id());
        DirBuilder::new()
            .mode(0o700)
            .create(&path)
            .expect("create test folder");
        Self { path }
    }

    fn join(&self, name: &str) -> String {
        format!("{}/{name}", self.path)
    }

    /// The uid that owns the folder: this process's.
    fn uid(&self) -> u32 {
        fs::metadata(&self.path).unwrap().uid()
    }

    /// The Linux rule with `XDG_RUNTIME_DIR` set to this folder:
    /// `<dir>/morrow/island.sock`, whose `morrow` folder must be private.
    fn runtime_endpoint(&self) -> Endpoint {
        let xdg = self.path.clone();
        let endpoint = resolve(
            Platform::Linux { uid: self.uid() },
            |key| (key == "XDG_RUNTIME_DIR").then(|| xdg.clone()),
            |_| false,
        );
        assert_eq!(endpoint.kind(), EndpointKind::RuntimeDir);
        endpoint
    }

    /// An override endpoint at `<dir>/<name>`.
    fn override_endpoint(&self, name: &str) -> Endpoint {
        let path = self.join(name);
        let endpoint = resolve(
            Platform::Linux { uid: self.uid() },
            |key| (key == "MORROW_SOCKET_PATH").then(|| path.clone()),
            |_| false,
        );
        assert_eq!(endpoint.kind(), EndpointKind::Override);
        endpoint
    }
}

impl Drop for TestDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

/// Accepts `count` connections and answers each with `echo:` and the
/// request. A connection that fails (the probe of a second `bind` sends
/// nothing and closes) is skipped.
fn serve_echo(server: &Server, count: usize) {
    for _ in 0..count {
        let Ok(mut connection) = server.accept() else {
            continue;
        };
        let Ok(request) = connection.read_request() else {
            continue;
        };
        let _ = connection.reply(&[b"echo:".as_slice(), &request].concat());
    }
}

fn round_trip(server: &Server, endpoint: &Endpoint, request: &[u8]) -> Vec<u8> {
    std::thread::scope(|scope| {
        scope.spawn(|| serve_echo(server, 1));
        Client::connect(endpoint, CONNECT_TIMEOUT)
            .expect("connect")
            .send_and_wait(request, IO_TIMEOUT)
            .expect("send and wait")
    })
}

fn mode(path: &str) -> u32 {
    fs::symlink_metadata(path).unwrap().mode() & 0o777
}

#[test]
fn round_trip_sends_half_closes_and_reads_the_reply() {
    let dir = TestDir::new();
    let endpoint = dir.runtime_endpoint();
    let server = Server::bind(&endpoint).expect("bind");

    assert_eq!(round_trip(&server, &endpoint, b"hello"), b"echo:hello");
    assert_eq!(mode(endpoint.as_str()), 0o600, "socket file mode");
    assert_eq!(
        mode(endpoint.private_dir().unwrap()),
        0o700,
        "morrow folder mode"
    );
}

#[test]
fn a_second_bind_while_the_first_listens_is_already_running() {
    let dir = TestDir::new();
    let endpoint = dir.runtime_endpoint();
    let first = Server::bind(&endpoint).expect("first bind");
    let inode = fs::symlink_metadata(endpoint.as_str()).unwrap().ino();

    match Server::bind(&endpoint) {
        Err(Error::AlreadyRunning { path }) => assert_eq!(path, endpoint.as_str()),
        other => panic!("expected AlreadyRunning, got {other:?}"),
    }

    assert_eq!(
        fs::symlink_metadata(endpoint.as_str()).unwrap().ino(),
        inode,
        "the first island's socket file is untouched"
    );
    // The first island still answers, after reading the probe's empty request.
    let reply = std::thread::scope(|scope| {
        scope.spawn(|| serve_echo(&first, 2));
        Client::connect(&endpoint, CONNECT_TIMEOUT)
            .expect("connect")
            .send_and_wait(b"still here", IO_TIMEOUT)
            .expect("send and wait")
    });
    assert_eq!(reply, b"echo:still here");
}

#[test]
fn a_stale_socket_left_by_a_crashed_island_is_replaced() {
    let dir = TestDir::new();
    let endpoint = dir.runtime_endpoint();
    fs::create_dir(endpoint.private_dir().unwrap()).unwrap();
    fs::set_permissions(
        endpoint.private_dir().unwrap(),
        Permissions::from_mode(0o700),
    )
    .unwrap();
    // A crash: the listener closes, its socket file stays (std never unlinks).
    drop(UnixListener::bind(endpoint.as_str()).expect("bind the crashed island"));
    assert!(
        Path::new(endpoint.as_str()).exists(),
        "stale socket file is there"
    );

    let server = Server::bind(&endpoint).expect("bind over the stale socket");
    assert_eq!(
        round_trip(&server, &endpoint, b"after crash"),
        b"echo:after crash"
    );
}

#[test]
fn a_regular_file_at_the_endpoint_is_refused_and_left_alone() {
    let dir = TestDir::new();
    let endpoint = dir.override_endpoint("island.sock");
    fs::write(endpoint.as_str(), b"not a socket").unwrap();

    assert!(matches!(
        Client::connect(&endpoint, CONNECT_TIMEOUT),
        Err(Error::NotASocket { .. })
    ));
    assert!(matches!(
        Server::bind(&endpoint),
        Err(Error::NotASocket { .. })
    ));
    assert_eq!(fs::read(endpoint.as_str()).unwrap(), b"not a socket");
}

#[test]
fn a_symlink_to_this_users_live_socket_is_refused_and_left_alone() {
    let dir = TestDir::new();
    let real = dir.override_endpoint("real.sock");
    let server = Server::bind(&real).expect("bind the real socket");
    let link = dir.override_endpoint("link.sock");
    std::os::unix::fs::symlink(real.as_str(), link.as_str()).unwrap();

    assert!(matches!(
        Client::connect(&link, CONNECT_TIMEOUT),
        Err(Error::NotASocket { .. })
    ));
    assert!(matches!(Server::bind(&link), Err(Error::NotASocket { .. })));
    assert!(
        fs::symlink_metadata(link.as_str())
            .unwrap()
            .file_type()
            .is_symlink()
    );
    assert_eq!(round_trip(&server, &real, b"real"), b"echo:real");
}

#[test]
fn a_morrow_folder_others_can_write_is_refused_and_not_chmoded() {
    let dir = TestDir::new();
    let endpoint = dir.runtime_endpoint();
    let folder = endpoint.private_dir().unwrap().to_owned();
    fs::create_dir(&folder).unwrap();
    fs::set_permissions(&folder, Permissions::from_mode(0o777)).unwrap();

    match Server::bind(&endpoint) {
        Err(Error::UnsafeDir { path, reason }) => {
            assert_eq!(path, folder);
            assert!(reason.contains("0777"), "reason names the mode: {reason}");
        }
        other => panic!("expected UnsafeDir, got {other:?}"),
    }
    assert!(matches!(
        Client::connect(&endpoint, CONNECT_TIMEOUT),
        Err(Error::UnsafeDir { .. })
    ));
    assert_eq!(
        mode(&folder),
        0o777,
        "someone else's folder is never chmoded"
    );
    assert!(!Path::new(endpoint.as_str()).exists(), "nothing was bound");
}

#[test]
fn a_symlinked_morrow_folder_is_refused() {
    let dir = TestDir::new();
    let endpoint = dir.runtime_endpoint();
    let elsewhere = dir.join("elsewhere");
    DirBuilder::new().mode(0o700).create(&elsewhere).unwrap();
    std::os::unix::fs::symlink(&elsewhere, endpoint.private_dir().unwrap()).unwrap();

    assert!(matches!(
        Server::bind(&endpoint),
        Err(Error::UnsafeDir { .. })
    ));
}

#[test]
fn connecting_to_nothing_fails_fast_within_the_timeout() {
    let dir = TestDir::new();

    let absent = dir.override_endpoint("absent.sock");
    let start = Instant::now();
    let result = Client::connect(&absent, CONNECT_TIMEOUT);
    let absent_elapsed = start.elapsed();
    assert!(matches!(result, Err(Error::NotFound { .. })), "{result:?}");

    let stale = dir.override_endpoint("stale.sock");
    drop(UnixListener::bind(stale.as_str()).unwrap());
    let start = Instant::now();
    let result = Client::connect(&stale, CONNECT_TIMEOUT);
    let stale_elapsed = start.elapsed();
    match &result {
        Err(Error::Io {
            op: "connect",
            source,
            ..
        }) => {
            assert_eq!(source.kind(), std::io::ErrorKind::ConnectionRefused);
        }
        other => panic!("expected a refused connect, got {other:?}"),
    }

    println!("connect to nothing: absent {absent_elapsed:?}, stale {stale_elapsed:?}");
    for elapsed in [absent_elapsed, stale_elapsed] {
        assert!(elapsed < CONNECT_TIMEOUT / 4, "took {elapsed:?}");
    }
}

#[test]
fn a_peer_of_another_uid_is_refused_on_both_sides() {
    let dir = TestDir::new();
    let me = dir.uid();
    let other = me.wrapping_add(1);

    // Server side: a listener for `other` gets a connection from `me`.
    let endpoint = dir.override_endpoint("other.sock");
    let server = Server::bind_as(&endpoint, other).expect("bind as another uid");
    let (accepted, reply) = std::thread::scope(|scope| {
        let accepted = scope.spawn(|| server.accept().map(|_| ()));
        let reply = Client::connect(&endpoint, CONNECT_TIMEOUT)
            .expect("the file and the listener are this user's")
            .send_and_wait(b"secret", IO_TIMEOUT);
        (accepted.join().unwrap(), reply)
    });
    match accepted {
        Err(Error::PeerNotUser { peer, expected }) => assert_eq!((peer, expected), (me, other)),
        other => panic!("expected PeerNotUser, got {other:?}"),
    }
    assert!(
        reply.as_deref().map_or(true, <[u8]>::is_empty),
        "the refused client gets no answer: {reply:?}"
    );

    // Client side: `other` refuses `me`'s socket before connecting.
    let mine = dir.override_endpoint("mine.sock");
    let _server = Server::bind(&mine).expect("bind");
    match Client::connect_as(&mine, CONNECT_TIMEOUT, other) {
        Err(Error::OtherUser {
            owner, expected, ..
        }) => assert_eq!((owner, expected), (me, other)),
        other => panic!("expected OtherUser, got {other:?}"),
    }
}

#[test]
fn dropping_the_server_removes_its_socket_file_and_nothing_else() {
    let dir = TestDir::new();
    let endpoint = dir.override_endpoint("island.sock");

    drop(Server::bind(&endpoint).expect("bind"));
    assert!(
        !Path::new(endpoint.as_str()).exists(),
        "own socket file removed"
    );

    let server = Server::bind(&endpoint).expect("bind again");
    fs::remove_file(endpoint.as_str()).unwrap();
    fs::write(endpoint.as_str(), b"replacement").unwrap();
    drop(server);
    assert_eq!(fs::read(endpoint.as_str()).unwrap(), b"replacement");
}

#[test]
fn a_named_pipe_endpoint_is_not_a_unix_socket() {
    let pipe = resolve(Platform::Windows { sid: "S-1-5-18" }, |_| None, |_| false);
    assert!(matches!(
        Client::connect(&pipe, CONNECT_TIMEOUT),
        Err(Error::NotAUnixEndpoint { .. })
    ));
    assert!(matches!(
        Server::bind(&pipe),
        Err(Error::NotAUnixEndpoint { .. })
    ));
}
