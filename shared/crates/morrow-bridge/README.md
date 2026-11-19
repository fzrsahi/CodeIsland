# morrow-bridge

The hook command agents run on Linux (`docs/hook-edge-protocol.md`).
Claude Code's hook is installed without `--source`, as on macOS (PR #51);
every other agent's with `--source <agent>` (and `--event` where its stdin
names no event). What a hook means is HookIntake's call
(`morrow_core::intake`, the port of `Sources/MorrowCore/HookIntake.swift`);
the bridge gathers the facts and does the I/O. Per invocation it:

1. prints the answer that cannot wait (Google Antigravity's PreToolUse,
   `{"decision":"ask"}`) before anything else can end it;
2. exits 0 at once when `MORROW_SKIP` / `CODEISLAND_SKIP` is set, or inside
   Grok for any hook but Grok's own;
3. resolves the endpoint (`morrow-ipc`), and exits 0 before reading stdin
   unless `lstat` finds a socket this user owns there;
4. reads stdin (deadline 5 s), has HookIntake interpret it, records the
   terminal context, waits the delivery delay (Gemini's permission
   request, 250 ms), and sends the payload (`morrow-protocol`'s encoding);
5. for a hook that waits (a permission request, a question) prints the
   island's answer in the form the agent reads (verbatim, or Gemini's
   `{"decision":…}`).

Every way out is exit 0, a panic too (the panic hook exits 0 before
`panic = "abort"` would). Debug lines go to stderr only with
`MORROW_DEBUG` or `CODEISLAND_DEBUG` set.

| Deadline | Swift bridge | Here |
|---|---|---|
| reading stdin | `alarm(5)` | 5 s |
| a hook nobody waits on: interpret, connect (1000 ms), send, read the reply (1 s per read) | `alarm(4)` | 4 s |
| a hook that waits: interpret, connect (3000 ms), send | `alarm(8)`, then none | 8 s, then none (`Client::send`, then `PendingReply::wait`) |

| Module | |
|---|---|
| `facts` | `Args` (`--source`, `--event`), the `ProcessFacts` trait (what the OS says, so tests hand in a fixture's process tree), and `interpret`: HookIntake's `Facts` built from them, as the Swift bridge's `main.swift` builds them. |
| `process::OsProcess` | Linux: `/proc/<pid>/stat`, `/exe` and `/cmdline`, six processes up; the controlling `/dev/pts/<n>` from `tty_nr`; `$HOME`; `tmux display-message` for the client tty. No `.app` bundle ids. Elsewhere only the parent pid. |
| `run` | The invocation end to end: immediate stdout, deadlines, endpoint I/O, the answer. |

## On Linux

The facts a Linux process has: no `.app` bundle id (so no Codex Desktop
`_term_bundle`), argv from `/proc`, a tty only for a pseudo-terminal.
The custom agent commands are Swift's seeded ones (`~/.claude-govtech`, …,
when the directory exists); custom CLI sources come with the app's settings
(not yet). HookIntake records whatever the environment says, as in Swift:
the linux golden bundle leaves out `_tty`, `_term_bundle`, `_iterm_session`
and a macOS `_term_app`, which a macOS recording cannot vouch for here.

## Tests

- `tests/conformance.rs`: every fixture of `fixtures/linux/bridge-golden.json`
  (84, every source), in process with the fixture's process tree behind
  `ProcessFacts`: forwarded payload as it goes on the wire, stdout, status.
  It shares the golden harness of morrow-core (`#[path]`).
- `tests/bridge_process.rs`: the binary against a `morrow_ipc::unix::Server`
  stand-in: golden fixtures end to end (Claude, Cursor, Codex, Gemini,
  Antigravity with and without an island), a blocking answer after 9 s, an
  island that never answers, stdin invalid / empty / closed / never closed,
  a regular file at the socket path, no island; on Linux, the real `/proc`
  ancestry.
- `tests/fast_exit.rs`: 25 runs with no listener, median under 10 ms;
  `cargo test --release` or `MORROW_BRIDGE_UNDER_TEST` measures a release
  build.
