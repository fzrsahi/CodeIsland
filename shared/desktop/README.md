# shared/desktop

Morrow's Tauri v2 **shell** for Linux (ADR-0002), X11 first: crate
`morrow-app` in `src-tauri/` (a member of the root workspace) and a Svelte 5
**frontend** in `src/`. Windows uses the same shell later (#47).

```
morrow-bridge ──UDS──▶ listener (std thread) ──▶ Feed: Sessions::apply
      ▲                   │ waits? (PermissionRequest)
      │                   ▼
      │            held thread ◀── decision ── Feed: Permissions (cards)
      └─ reply, close                            │ ≤60 Hz        ▲
frontend ◀── Channel<Snapshot> ── pusher thread ◀┘               │
frontend ── answer_permission(id, allow|deny) ───────────────────┘
frontend ── set_island_size(w, h) ──▶ island::fit: pin size, top centre
```

| Module | |
|---|---|
| `main.rs` | Binds the endpoint (`morrow_ipc::unix::Server::bind(current_endpoint())`); a second island exits 0. Commands `subscribe`, `answer_permission`, `set_island_size`, `smoke_card`. |
| `listener.rs` | Accepts on a std thread, decodes with `morrow_protocol::decode_payload`. A hook nobody waits on gets the empty reply at once. A permission request is held on a thread of its own: it replies with the decision and closes, or, when `Connection::peer_gone` says the bridge left (checked every 100 ms), drops the card. |
| `permissions.rs` | Which hook waits (`PermissionRequest`, not one Cursor ran; `TODO(#93)`: HookIntake), the held cards (id, session, source, tool, one-line summary), and the replies, byte for byte the macOS island's `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"\|"deny"}}}`, which the bridge prints verbatim. |
| `sessions.rs` | The trivial reduction: session id → source, last event, cwd basename, updated at. `TODO(#93)`: morrow-core's `reduce`. |
| `feed.rs` | Sessions + held permission requests + the frontend's channel; pushes the snapshot (`sessions`, `permissions`) at most once a frame. |
| `island.rs` → `anchoring` | #109: says whether the panel is a layer surface or an always-on-top window, and why |
| `windows_panel.rs` (`cfg(windows)`)| #106: `WM_NCHITTEST` → `HTTRANSPARENT` outside the rounded island, `MA_NOACTIVATE` on clicks, `WS_EX_NOACTIVATE` lifted while a Question card is open |
| `island.rs` | The **panel** window and the **tight-fit** rule. |

## The panel window

Frameless, transparent, always on top (`_NET_WM_STATE_ABOVE`), out of the
taskbar (`_NET_WM_STATE_SKIP_TASKBAR`), `focusable(false)` (tao: GTK
accept-focus off, so `WM_HINTS` input is false and the window manager never
focuses it, on map or on click), at the top centre of the primary monitor.

**Tight-fit** (plan §6.1, strategy 1): the frontend measures the island
(`offsetWidth`/`offsetHeight`, fixed CSS widths so the measure never depends
on the window) on every layout change and calls `set_island_size`; the shell
resizes the window to exactly that and centres it again. No click-through API
is used: outside the island there is no window. Collapsed ≈ 240×34 (the macOS
collapsed island without a notch is 34 pt high); expanded 360 wide, one row
per session. A permission card widens the island to 360 and adds its height,
expanded or not; collapsing the list leaves the cards. Approve and Deny are
clicks on the nonactivating window, so the focused window keeps focus.

GTK ignores resizes of a window built non-resizable (it keeps the natural
size, 200 px high here), so the window is built resizable and `fit` pins it:
minimum = maximum = the island. The window manager then offers no resize
(`_NET_WM_ALLOWED_ACTIONS` has no `_NET_WM_ACTION_RESIZE`).

## Build

```sh
(cd shared/desktop && bun install && bun run build)   # dist/, embedded by Tauri
cargo build -p morrow-app                             # needs GTK3 + WebKitGTK 4.1 dev libs
```

The default feature `custom-protocol` serves the embedded `dist/`; there is
no dev server. On a host without the GTK libraries, build in the image of
`linux/ci/Dockerfile`.

`MORROW_SMOKE=1` prints `morrow-smoke: …` lines on stdout (the endpoint, each
push with its session and card counts, each fit, and after each fit every
card's Approve and Deny rectangles with the time) for `linux/ci/smoke-x11.sh`
and `linux/ci/e2e1.sh`, and changes nothing else.

## Tests

- `cargo test -p morrow-app`: the reduction (`sessions.rs`), the held
  requests: approve, deny, a gone hook, the replies against
  `Sources/Morrow/AppState.swift` (`permissions.rs`).
- `linux/ci/test-desktop.sh`: fmt, clippy `-D warnings`, test, in the image.
- `linux/ci/smoke-x11.sh`: Xvfb + Openbox, the release bridge, `xdotool`,
  `xprop`; prints an Evidence block.
- `linux/ci/e2e1.sh`: gate E2E-1, Approve and Deny end to end under 300 ms,
  in Xvfb or on a real X11 desktop (`DISPLAY` set); prints an Evidence block.
  Both source `linux/ci/x11-lib.sh`.

## Limits

- Only checked under Xvfb + Openbox. A real X11 desktop (a compositor,
  panels, HiDPI) and Wayland are not.
- Without a compositor, transparent pixels render black; with tight-fit there
  are almost none.
- The socket file is not removed when the app is killed; the next start
  recovers it as stale (`morrow-ipc`).
- Collapse resizes at once: there is no animation yet to shrink after.
- Only Claude Code's `PermissionRequest` is held, answered allow or deny.
  No "always allow", no question card, no Gemini `{"decision":…}` form
  (#93). A request the island drops while its hook is there (the app quits)
  closes the connection with no answer, not `{}`.

## Wayland anchoring (#109)

`morrow_platform::compositor` answers which desktop this is and whether the panel
can be a layer surface — Sway, Hyprland, KDE Plasma, COSMIC, niri, labwc, Wayfire
and river have `wlr-layer-shell`; GNOME does not, and the plan (§6.4) asks for that
to be **stated, not simulated**.

- The answer is environment variables, so it is tested on any machine
  (`tests/compositor_anchoring.rs`, 8 cases).
- `island::anchoring` is the only place a layer surface would be created. tao
  upstream closed both PRs (`tauri#15913`, `tauri#15914`, `tao#1316`), so a build
  that anchors needs the pinned patch: until that fork decision is made, this
  build keeps the window path and reports the reason, in the log and in Settings.
- An AppImage on Wayland says something different, because `tauri#15781` forces
  `GDK_BACKEND=x11`: the layer-shell code would never run, so claiming `Available`
  would be a lie the user finds by looking at their screen. `.deb`/`.rpm` are the
  Wayland path, as the plan says.
