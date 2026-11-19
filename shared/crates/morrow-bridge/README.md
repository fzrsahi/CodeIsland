# morrow-bridge

The hook command Claude Code runs on Linux (`docs/hook-edge-protocol.md`).
Claude Code's hook is installed without `--source`, as on macOS (PR #51). Per
invocation it:

1. exits 0 at once when `MORROW_SKIP` / `CODEISLAND_SKIP` is set, or inside
   Grok for any hook but Grok's own;
2. resolves the endpoint (`morrow-ipc`), and exits 0 before reading stdin
   unless `lstat` finds a socket this user owns there;
3. reads stdin (deadline 5 s), interprets it (`intake`), records the
   terminal context, and sends the payload (`morrow-protocol`'s encoding);
4. for a hook that waits (a permission request, a question) prints the
   island's answer verbatim, as Claude Code reads it.

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
| `intake` | The bridge's part of HookIntake: source (declared `--source`, a supported `_source`, a non-blank `cursor_version`, Claude in the ancestry), aliases, `_ppid` / `_hook_ppid`, the `<source>-ppid-<pid>` fallback session id, waiting, terminal context, stdout. `TODO(#93)`: moves to morrow-core. |
| `intake::ProcessFacts` | What the OS says (parent, ancestry, cwd, tmux client tty), so tests hand in a fixture's process tree. |
| `process::OsProcess` | Linux: `/proc/<pid>/stat` and `/proc/<pid>/exe`, six processes up. Elsewhere only the parent pid. |
| `run` | The invocation end to end; `interpret` is the part without transport, which the conformance test runs. |
| `digest` | SHA-256 for `_cursor_payload_digest`, without a crypto crate. |

## Linux terminal context

The keys of the linux golden bundle: no `_tty`, `_term_bundle` or
`_iterm_session`, and no `_term_app` naming a macOS terminal
(`iTerm.app`, `Apple_Terminal`). tmux, kitty, zellij, WezTerm, cmux, Herdr,
Superset, Orca and Claude Desktop keys come from the environment as in Swift;
an `_env` a plugin sends is passed on as it came.

## Not served yet (#93)

Sources other than Claude Code's hook: Hermes, Grok runtime aliases, Copilot
and Cline payload shapes, Google Antigravity's immediate stdout, Gemini's
`{"decision":…}` answer and delivery delay, ancestry inference of agents
other than Claude (so omo under OpenCode goes out with no `_source`), the
per-source path rules other than `claude` and `cursor-cli`, Codex Desktop's
`_term_bundle`. The macOS process tree is not read (the macOS bridge is the
Swift one).

## Tests

- `tests/conformance.rs`: every fixture of `fixtures/linux/bridge-golden.json`
  that Claude Code's hook serves (no `--source`; Claude, no source, or Cursor
  by its payload), in process with the fixture's process tree: forwarded
  payload, stdout, status. The others are printed as skipped.
- `tests/bridge_process.rs`: the binary against a `morrow_ipc::unix::Server`
  stand-in: golden fixtures end to end, a blocking answer after 9 s, an
  island that never answers, stdin invalid / empty / closed / never closed,
  a regular file at the socket path, no island; on Linux, the real `/proc`
  ancestry.
- `tests/fast_exit.rs`: 25 runs with no listener, median under 10 ms;
  `cargo test --release` or `MORROW_BRIDGE_UNDER_TEST` measures a release
  build.
