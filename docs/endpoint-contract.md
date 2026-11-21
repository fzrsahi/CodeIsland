# Endpoint contract

> Interim location. This document moves to `shared/contract/` with the
> monorepo layout PR (#86). Issue #84; spec #82; plan
> `docs/plan-windows-linux.md` §3.1.

The **endpoint** is the address a bridge or plugin sends envelopes to: a Unix
socket path on macOS and Linux, a named pipe on Windows. It is part of the
**contract**: every edge (the bridge, every plugin, the app's listener) on an
OS resolves it with the rule below, and trusts it only after the peer checks
below pass.

The rule is tested by a case table, `fixtures/endpoint/cases.json` (schema:
`schemas/endpoint-cases.schema.json`, validator:
`scripts/validate-endpoint-cases.py`). Each case gives an OS, an environment,
a uid or SID, and the files that exist, and names the endpoint string an
implementation must return. Swift runs every `macos` case
(`Tests/MorrowCoreTests/EndpointContractTests.swift`). The Rust port (#88,
#105) and the plugin tests (#78) must run the cases for their OS.

The key words MUST, MUST NOT, SHOULD and MAY are used as in RFC 2119.

## 1. Common rules

1. **Resolve at send time.** An edge MUST resolve the endpoint each time it
   is about to connect (once per hook invocation for the bridge, once per
   event or request for a long-lived plugin), never once at module load. An
   agent can start before the island, and the macOS rule depends on which
   files exist at that moment.
2. **Inputs.** The rule reads only the process environment, the current
   user's id (uid on macOS/Linux, SID string on Windows) and, on macOS, whether
   two fixed paths exist. Nothing else.
3. **Output.** An exact string. Implementations MUST NOT normalize an
   override (no tilde expansion, no `realpath`, no making relative paths
   absolute). The cases compare strings byte for byte.
4. **Environment overrides.** On every OS the overrides are, in order,
   `MORROW_SOCKET_PATH`, then `CODEISLAND_SOCKET_PATH`. The first one that
   applies is returned as is, and no file check is made. When an override
   *applies* differs per OS today (an empty value), see §2.1 and OQ-1.
5. **One endpoint.** The resolved string is the only endpoint an edge tries
   for the local island. No edge may try a second candidate when the first
   fails its peer check; it sends nothing instead (exit 0, silently, for a
   hook).
6. **The listener resolves the same way.** The app binds the endpoint the
   same rule gives in its own environment. An override set only in the
   agent's environment points that agent somewhere the island may not be;
   that is the user's choice.

## 2. macOS (implemented: `Sources/MorrowCore/SocketPath.swift`)

`SocketPath.resolve(environment:uid:fileExists:)` is the reference
implementation; `SocketPath.path` calls it with the process environment,
`getuid()` and `FileManager.default.fileExists(atPath:)`.

### 2.1 Resolution, as the code behaves today

```
if env has key MORROW_SOCKET_PATH:      return env[MORROW_SOCKET_PATH]
if env has key CODEISLAND_SOCKET_PATH:  return env[CODEISLAND_SOCKET_PATH]
morrow = "/tmp/morrow-"     + decimal(uid) + ".sock"
legacy = "/tmp/codeisland-" + decimal(uid) + ".sock"
if not exists(morrow) and exists(legacy): return legacy
return morrow
```

- **"Has key" means set, even to the empty string.** Swift's
  `environment["MORROW_SOCKET_PATH"] ?? environment["CODEISLAND_SOCKET_PATH"]`
  returns a non-nil `""` when the variable is set but empty. So
  `MORROW_SOCKET_PATH=` resolves to `""`, and also hides a
  `CODEISLAND_SOCKET_PATH` that is set. `lstat("")` fails, so the bridge
  sees `Holder.nobody` and exits 0, and the app cannot bind: an empty
  override disables delivery. This is probably a bug; see OQ-1. The cases
  `macos-empty-*` pin today's behaviour in `expected` and the proposed one
  in `proposed`.
- **"Exists" follows symlinks** (`stat(2)` semantics, what `FileManager`
  does). A path of any kind counts: socket, regular file, directory. A
  symlink counts only when its target exists. So a stray regular file or a
  symlink at the legacy path is *selected* while the morrow path is absent;
  the peer check (§2.2) then refuses it and the edge sends nothing. See OQ-2.
- `uid` is printed in decimal, no padding.
- `XDG_RUNTIME_DIR` is ignored on macOS.

Edges that do not run Swift (the TypeScript and JavaScript plugins, #78)
MUST return the same `expected` string for every `macos` case. While OQ-1 is
open, that means an empty override is used as is (and fails the peer check),
which differs from the `||` idiom in JavaScript.

### 2.2 Peer verification (client side)

Before connecting, an edge MUST `lstat(2)` the endpoint (never `stat`) and
continue only when it is a socket (`S_IFSOCK`) owned by the edge's uid
(`SocketPath.holder(of:)` returns `.thisUser`). A symlink is refused even
when it points to this user's socket: whoever owns the symlink can repoint
it. Anything else (`.nobody`, `.notASocket`, `.otherUser`) means: send
nothing, exit 0.

After `connect(2)`, the edge MUST check the listener's credentials with
`getpeereid(2)` (`SocketPath.peerIsUser(_:uid:)`) and send nothing unless
the peer uid is the edge's uid. This covers an override outside a sticky
directory, where the file could be swapped between `lstat` and `connect`.
Where the language has no peer-credential API (Node), the `lstat` check
stands alone, and a plugin that must be sure SHOULD hand the request to the
bridge, which does both.

### 2.3 Listener, stale sockets, single instance

`HookSocketListener.start()` (`Sources/Morrow/HookSocket.swift`):

1. Refuse a path that does not fit `sun_path`, before touching anything.
2. **Probe before unlink.** If a socket this user owns is at the path, and
   it accepts a connection, and `getpeereid` says the listener is this user
   (`islandListening(at:)`), another island is running: leave its socket
   alone and do not start. At launch, `AppDelegate` quits in that case
   (single instance per user per endpoint).
3. Otherwise the file is stale (or absent): `unlink` it, then `bind` with
   `umask(077)` so the socket file is never reachable by anyone else, then
   `chmod 0700`.
4. On stop, remove only the socket file this listener made (same device and
   inode, still a socket), never a file that has replaced it.

## 3. Linux (target for the Rust port, #88)

### 3.1 Resolution

```
for name in [MORROW_SOCKET_PATH, CODEISLAND_SOCKET_PATH]:
    if env[name] is set and non-empty: return env[name]
xdg = env[XDG_RUNTIME_DIR]
if xdg is set and xdg starts with "/":
    return rstrip(xdg, "/") + "/morrow/island.sock"
return "/tmp/morrow-" + decimal(uid) + ".sock"
```

- An empty value counts as unset, for both overrides and for
  `XDG_RUNTIME_DIR` (OQ-1).
- `XDG_RUNTIME_DIR` is used only when absolute. A relative or empty value
  falls through to `/tmp`.
- Trailing slashes are removed before joining, so `/run/user/1000/` and
  `/run/user/1000` give the same string, and `/` gives
  `/morrow/island.sock`. This is what `Path::join`, `os.path.join` and
  Node's `path.join` produce.
- No file is checked, and there is no legacy path: no Linux island ever
  listened at `/tmp/codeisland-<uid>.sock`.
- Linux accepts `CODEISLAND_SOCKET_PATH` too (plan §3.1 listed only
  `MORROW_SOCKET_PATH`) so the shared plugin code has one override rule for
  every OS.

### 3.2 Peer verification

Client, before connect: `lstat` the endpoint; it MUST be a socket owned by
the edge's uid, not a symlink (as §2.2). For the `XDG_RUNTIME_DIR` path, the
parent directory `$XDG_RUNTIME_DIR/morrow` MUST also pass `lstat`: a
directory (not a symlink) owned by the edge's uid with mode `0700` (no group
or other bits).

Client, after connect: `getsockopt(SO_PEERCRED)`; send nothing unless the
peer uid is the edge's uid.

Listener: create `$XDG_RUNTIME_DIR/morrow` with mode `0700` if absent; if it
exists, verify it as above and refuse to start (with a reason the user can
see) if it fails, never `chmod` someone else's directory. Then the same
probe-before-unlink, `umask(077)` bind and remove-only-what-I-made steps as
§2.3, with `SO_PEERCRED` in place of `getpeereid`.

## 4. Windows (target for the Rust port, #105)

### 4.1 Resolution

```
for name in [MORROW_SOCKET_PATH, CODEISLAND_SOCKET_PATH]:
    if env[name] is set and non-empty: return env[name]
return "\\.\pipe\morrow-" + normalize(sid)
normalize(sid) = sid with every character outside [A-Za-z0-9] replaced by "-"
```

- `sid` is the string form of the current user's SID (`S-1-5-21-…`). Real
  SIDs are ASCII letters, digits and `-`, so for them `normalize` is the
  identity. Case is preserved.
- The rule is ASCII-only. `windows/Morrow.Ipc/PipeEndpoint.cs` uses
  `char.IsLetterOrDigit`, which also keeps non-ASCII letters; for real SIDs
  both give the same name. The case `windows-sid-non-ascii-letter-becomes-dash`
  fixes the ASCII rule.
- An override is the full pipe path (`\\.\pipe\name`), used as is.
- If the SID cannot be read, there is no endpoint: the edge sends nothing.
  The C# fallback to `"unknown"` (a name every user shares) is not
  conformant.

### 4.2 Peer verification

Server: create the first instance with `FILE_FLAG_FIRST_PIPE_INSTANCE`
(`first_pipe_instance(true)`) so creation fails if anyone already owns the
name; `PIPE_REJECT_REMOTE_CLIENTS`; and a DACL that grants access to the
current user only (no `Everyone`, no `Authenticated Users`). If the first
instance cannot be created because the name exists, probe it as a client
(§4.2 client check); if it is this user's island, do not start (single
instance); otherwise refuse to start and say the name is taken.

Client: after `CreateFile`, call `GetNamedPipeServerProcessId`, open that
process's token, and send nothing unless its user SID equals the client's.

The current C# `PipeEndpoint.CreateServer` sets no `PipeSecurity` and the
client checks nothing, so the pipe can be squatted. The Rust implementation
MUST close this.

## 5. Remote-host endpoint (separate kind, not in the case table)

On an SSH host the island is reached through an sshd forward, not a local
listener. This is a different endpoint kind with its own rule, implemented
in `Sources/Morrow/Resources/morrow-remote-hook.py` and
`Sources/Morrow/RemoteInstaller.swift`:

- Path: `CODEISLAND_SOCKET_PATH` (the installer writes it into every hook
  command), else `/tmp/codeisland-<uid>/island.sock`
  (`RemoteInstaller.remoteSocketPath(forUID:)`), where `<uid>` is the SSH
  user's. The remote hook reads only `CODEISLAND_SOCKET_PATH`, with Python
  `or` semantics (empty counts as unset).
- The folder `/tmp/codeisland-<uid>` is made by the island on the host as
  the SSH user, mode `0700` (`0711` where agents run as other users),
  verified not a symlink and owned by that user.
- Owner: the socket must be owned by `CODEISLAND_SOCKET_OWNER_UID` when the
  installer set it (agents running as other users), else by the hook's own
  uid. After connect, `SO_PEERCRED` / `LOCAL_PEERCRED` where available.
- Legacy command path: when `CODEISLAND_SOCKET_PATH` is
  `/tmp/codeisland-<uid>.sock` (written by older installs), the hook tries
  `/tmp/codeisland-<uid>/island.sock` first, then that path
  (`_island_sockets()`). This is the one place an edge tries two candidates.
- On the Mac, each host's forward ends at a per-host socket in the user's
  temporary folder (`RemoteHookSockets`); those are island-internal and no
  edge resolves them.

`docs/hook-edge-protocol.md` §Transport describes this path as
`/tmp/morrow-<uid>/island.sock`; the code uses `/tmp/codeisland-<uid>/…`.
See OQ-3.

## 6. Open questions

- **OQ-1: empty override values.** On macOS, Swift treats a set-but-empty
  `MORROW_SOCKET_PATH` or `CODEISLAND_SOCKET_PATH` as an override, returning
  `""` (delivery silently disabled, and a non-empty `CODEISLAND_SOCKET_PATH`
  is hidden). The Python remote hook and every JS/TS plugin treat empty as
  unset. **Proposed:** empty counts as unset on every OS (the `proposed`
  values in the `macos-empty-*` cases). Linux and Windows already follow the
  proposed rule. Changing macOS is a runtime change, out of scope for #84;
  when it lands, move each `proposed` into `expected` and delete the
  `proposed` fields.
- **OQ-2: legacy selection does not check the file kind.** A regular file or
  a symlink at `/tmp/codeisland-<uid>.sock` (with no morrow socket) is
  selected, then refused by the peer check, so nothing is delivered even if
  the island is listening at the morrow path. Selecting the legacy path only
  when `lstat` says it is a socket this user owns would avoid that. Today's
  behaviour is pinned (`macos-legacy-regular-file-still-selected`,
  `macos-legacy-symlink-to-existing-target-counts-as-present`).
- **OQ-3: remote socket path in the protocol doc.** `hook-edge-protocol.md`
  says `/tmp/morrow-<uid>/island.sock`; the shipped code says
  `/tmp/codeisland-<uid>/island.sock`. The doc should follow the code unless
  the remote path is meant to be renamed (which needs a migration for hosts
  already set up).
