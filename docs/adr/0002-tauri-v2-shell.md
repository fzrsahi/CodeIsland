# Tauri v2 for the Windows and Linux shell

Status: accepted (2026-11-16)

Windows and Linux get one Tauri v2 shell over the Rust core, with a Svelte 5 frontend. Not mygo, which was the strongest alternative and wins on memory and window plumbing.

The deciding factor is asymmetry of risk, not performance. mygo native UI measured 34.1 MB at rest against a webview's ~125–185 MB, and mygo ships per-region click-through and `gtk-layer-shell` as first-class APIs where Tauri has neither. But mygo is 7 weeks old at `v0.9.1` with 136 open issues and 920 of its commits from one person, while the surface to reproduce is 43 SwiftUI views and 22 mascots — months in a native toolkit, weeks in CSS. Losing 120 MB costs a marketing line; losing the framework costs the port.

## Considered Options

- **mygo native UI (Go).** Rejected on maturity, not on merit. Would win if the shell were being written anyway and the project could pin to pre-1.0 APIs.
- **Avalonia over the existing C# core.** Rejected: cheapest in the short term and reuses 4.561 LOC, but keeps the divergent C# core alive and does not reach WinRT or `btleplug` as cleanly.
- **`iced` / `gpui` / `slint`.** Rejected: `gpui` has no Windows backend, `iced` transparency is broken on Windows 11, and none of them have `wlr-layer-shell`.

## Consequences

Three Tauri gaps must be closed by us, roughly one to two weeks of work that ships no features: per-region click-through, nonactivating windows, and Wayland layer-shell. Each needs a documented fallback — a tight-fit window, and explicit "anchoring unavailable" on GNOME — rather than a silent failure.

The shell decision does not lock the core: the bridge-to-app seam is a socket, so the core could be replaced without touching the shell.
