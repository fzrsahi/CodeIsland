# Tauri v2 for the Windows and Linux shell

Status: accepted (2026-11-16), consequences corrected 2026-11-18.

Windows and Linux get one Tauri v2 shell with a Svelte 5 frontend, replacing the WPF app in `windows/Morrow.Windows`. The shell decision holds whichever core language ADR-0001's experiment selects.

The deciding factors are one shell for two operating systems and asymmetry of risk, not performance. Tauri is **not** assumed to be lighter than .NET: WebView2 runs a browser process group, and no credible WPF-vs-Tauri idle measurement was found. Memory is measured at W4/L4 against the RSS <150 MB gate.

mygo native UI measured 34.1 MB at rest against a webview's ~125–185 MB, and ships per-region click-through and `gtk-layer-shell` as first-class APIs. But mygo is weeks old at `v0.9.1` with most commits from one person, while the surface to reproduce is 46 SwiftUI views and 23 mascots — months in a native toolkit, weeks in CSS. Losing 120 MB costs a marketing line; losing the framework costs the port.

## Considered Options

- **WPF (existing `windows/`) + Avalonia for Linux.** Rejected: two UI stacks, keeps the divergent C# core alive, and every Cyber/Pixel/lyrics view is new native work in each.
- **Avalonia for both, over the C# core.** Rejected: one UI stack, but keeps the divergent C# core and still rewrites every view.
- **mygo native UI (Go).** Rejected on maturity, not on merit.
- **`iced` / `gpui` / `slint`.** Rejected: `gpui` has no Windows backend, `iced` transparency is broken on Windows 11, and none has `wlr-layer-shell`.

## Consequences

Window plumbing is our work, roughly two weeks that ship no features, and each piece needs a fallback rather than a silent failure:

- **Click-through.** The macOS panel is a large transparent rectangle and relies on WindowServer passing clicks through transparent pixels; webviews do not. `WM_NCHITTEST` → `HTTRANSPARENT` only reaches windows in the same thread, so it does not work. Tauri has whole-window `set_ignore_cursor_events` only. Primary strategy: a tight-fit window sized to the island; input regions (`SetWindowRgn`, GTK input shape) as a spike; whole-window toggling from our own cursor polling as a fallback (impossible on Wayland).
- **Nonactivating.** tao's `focusable(false)` already sets `WS_EX_NOACTIVATE`; WebView2 focus behaviour is verified in Phase 4 (`WM_MOUSEACTIVATE` → `MA_NOACTIVATE` if needed).
- **Wayland layer-shell.** tauri#15913 closed without merging its PRs, so the workaround is a patch we maintain; GNOME has no layer-shell and gets an explicit "anchoring unavailable". AppImage forces `GDK_BACKEND=x11` (tauri#15781), so Wayland users are served by `.deb`/`.rpm`.
- Tauri's GTK4 migration has no date, and the open tao GTK4 port drops X11 always-on-top and skip-taskbar. Pin GTK3-era versions.

The shell decision does not lock the core: the bridge-to-app seam is a socket, and a Swift sidecar core (ADR-0001, Option E) fits behind the same shell.
