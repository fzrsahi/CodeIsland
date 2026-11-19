# morrow-ipc

The **endpoint** (`GLOSSARY.md`) and the local transport to it: where a
bridge or plugin sends an envelope, and a Unix socket that only talks to a
peer of the same user. The rule and the checks are
`docs/endpoint-contract.md`. Not part of the core: this crate reaches the OS
(`libc`, `socket2`), so it is not in `scripts/ci/rust-pure-crates.txt`.

| Item | Contract |
|---|---|
| `resolve`, `Platform`, `Endpoint`, `EndpointKind` | §2.1 (macOS), §3.1 (Linux), §4.1 (Windows): pure, no I/O |
| `unix::current_endpoint` | the rule with this process's environment, uid and files |
| `unix::Client`, `unix::PendingReply` | §2.2 / §3.2 client side: `lstat`, private folder, connect timeout, peer uid, one request and its reply (`send_and_wait`, or `send` then `wait` for a caller whose deadline covers only the send) |
| `unix::Server`, `unix::Connection` | §2.3 / §3.2 listener: private folder, probe before unlink, single instance, umask `077` + `0600`, peer uid on accept, removes only its own file |
| `unix::Error` | why an endpoint, a peer or a file was refused |

## Owns

- The endpoint rule for every OS, as a function of what it reads (environment,
  uid or SID, whether a path exists). The case table
  `fixtures/endpoint/cases.json` is the test.
- Trusting a Unix socket endpoint: the path is a socket this user owns (never a
  symlink), `$XDG_RUNTIME_DIR/morrow` is a real `0700` folder of this user's,
  and the kernel says the process at the other end is this user
  (`SO_PEERCRED` on Linux, `getpeereid` on macOS).
- Listening: one island per endpoint (`Error::AlreadyRunning`), recovery from
  the socket file a crashed island left (it refuses a connection, so it is
  removed and rebound), and never removing anything that is not this user's
  socket.
- Byte transport: the client writes the request, half-closes, reads until
  the island closes; the server reads to EOF and writes one reply.

## Does not own

- What the bytes are (`morrow-protocol`) or mean (HookIntake, `morrow-core`).
- Named pipes. Windows resolution is here because it is pure; the pipe
  server and client, with first-instance, reject-remote, DACL and server-SID
  checks (§4.2), are #105.
- An async runtime. Calls block; the app runs `Server::accept` on a thread
  of its own until a tokio transport is needed.
- Logging. `Server::accept` returns `Error::PeerNotUser` for a refused peer,
  already closed, and the caller logs it and keeps accepting.
- Reading stdin, the hook's exit code, process ancestry: `morrow-bridge` (#89).

## Limits

- `Server::bind` sets the process umask around `bind(2)`. The umask is
  process-wide: a file another thread creates in that moment is private too.
- `unix::current_endpoint` treats a variable that is not UTF-8 as unset, so a
  non-UTF-8 override path is ignored.
- `Client::send_and_wait`'s timeout bounds each read and write, not the whole
  exchange.

## Tests

- `tests/endpoint_cases.rs` runs every case of the table, all three OSes. The
  table's path is the `CASES_PATH` constant there, the one place to change when
  #86 moves it to `shared/contract/fixtures`.
- `tests/unix_socket.rs` (Unix) runs real sockets in a fresh folder under
  `/tmp`: round trip, single instance, stale recovery, a file or symlink at the
  path, an unsafe or symlinked `morrow` folder, connect to nothing, a peer of
  another uid, and drop removing only its own file. A test cannot create
  another user, so the uid is passed in (`Client::connect_as`,
  `Server::bind_as`).
