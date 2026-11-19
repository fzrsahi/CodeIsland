# shared/desktop

Morrow's Tauri v2 **shell** for Linux (ADR-0002), X11 first: crate
`morrow-app` in `src-tauri/` (a member of the root workspace) and a Svelte 5
**frontend** in `src/`. Windows uses the same shell later (#47).

```
morrow-bridge ──UDS──▶ listener (std thread) ──▶ Feed: Sessions::apply
                                                  │ ≤60 Hz
frontend ◀── Channel<Snapshot> ── pusher thread ◀─┘
frontend ── set_island_size(w, h) ──▶ island::fit: pin size, top centre
```

| Module | |
|---|---|
| `main.rs` | Binds the endpoint (`morrow_ipc::unix::Server::bind(current_endpoint())`); a second island exits 0. Commands `subscribe` and `set_island_size`. |
| `listener.rs` | Accepts on a std thread, decodes with `morrow_protocol::decode_payload`, replies empty at once. `TODO(#91)`: a hook that waits holds its connection until the panel answers. |
| `sessions.rs` | The trivial reduction: session id → source, last event, cwd basename, updated at. `TODO(#93)`: morrow-core's `reduce`. |
| `feed.rs` | Sessions + the frontend's channel; pushes the snapshot at most once a frame. |
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
per session.

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
push, each fit) for `linux/ci/smoke-x11.sh`, and changes nothing else.

## Tests

- `cargo test -p morrow-app`: the reduction (`sessions.rs`).
- `linux/ci/test-desktop.sh`: fmt, clippy `-D warnings`, test, in the image.
- `linux/ci/smoke-x11.sh`: Xvfb + Openbox, the release bridge, `xdotool`,
  `xprop`; prints an Evidence block.

## Limits

- Only checked under Xvfb + Openbox. A real X11 desktop (a compositor,
  panels, HiDPI) and Wayland are not.
- Without a compositor, transparent pixels render black; with tight-fit there
  are almost none.
- The socket file is not removed when the app is killed; the next start
  recovers it as stale (`morrow-ipc`).
- Collapse resizes at once: there is no animation yet to shrink after.
