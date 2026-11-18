# CodeIsland Linux Port — Development Plan

Status: **SUPERSEDED (2026-11-16), diarsipkan 2026-11-18** dari `linux/CodeIsland-Linux-Development-Plan.md` (folder `linux/` dihapus dari `main` saat rebrand Morrow). Jangan ikuti fase dan pilihan teknologinya. Rencana yang berlaku ada di [`docs/plan-windows-linux.md`](../plan-windows-linux.md) §7 dan [issue #48](https://github.com/fzrsahi/Morrow/issues/48). Path `Sources/CodeIsland*` dan `windows/CodeIsland.*` di bawah sekarang `Sources/Morrow*` dan `windows/Morrow.*`.

Pilihan Avalonia di §2.3 sudah mati — digantikan [ADR-0002](../adr/0002-tauri-v2-shell.md).

Yang **masih berlaku** dari dokumen ini: §3 analisis per-file platform abstraction, §5 tabel padanan file Windows→Linux, dan §6 tabel risiko (terutama Wayland). Acceptance criteria L-001…L-012 di §5 juga masih dipakai — #48 memakai nomor yang sama.

---

## 1. Starting point (measured, not assumed)

| Layer | Location | TFM | Portable today? |
|---|---|---|---|
| macOS app | `Sources/CodeIsland` (203 Swift files, 79 import AppKit) | macOS 14 | No — AppKit/SwiftUI |
| macOS bridge | `Sources/CodeIslandBridge` | macOS 14 | No — POSIX sockets, but logic is reusable as reference |
| Headless core | `windows/CodeIsland.Core` | `net8.0` | **Yes** |
| Protocol | `windows/CodeIsland.Protocol` | `net8.0` | **Yes** |
| IPC | `windows/CodeIsland.Ipc` | `net8.0` | Partly — named pipes + Windows SID |
| Bridge | `windows/CodeIsland.Bridge` | `net8.0` | Partly — see above |
| Hooks | `windows/CodeIsland.Hooks`, `.Hooks.Cli` | `net8.0` | Partly — Windows paths and `cmd.exe` |
| Bluetooth | `windows/CodeIsland.Bluetooth` | `net8.0` | Protocol only; no BLE transport implemented yet |
| Desktop UI | `windows/CodeIsland.Windows` | `net8.0-windows` + WPF | No |

Conclusion: **the Windows port already did most of the cross-platform work.** A Linux port is not a rewrite; it is (a) a small platform-abstraction refactor of the headless layer, and (b) a second UI front-end.

## 2. Strategy

### 2.1 Do not port Swift

`Sources/CodeIsland` is 79 files deep in AppKit. Swift on Linux ships Foundation + swift-corelibs only; there is no AppKit, no SwiftUI, no `NSStatusItem`, no `NSWindow`. Porting would mean rewriting the entire UI in GTK anyway, while losing the already-working C# headless layer. Rejected.

### 2.2 Do not rewrite the UI in a web stack

Tauri/Electron would give one UI for three OSes, but it discards the WPF work in `windows/CodeIsland.Windows` and adds a JS toolchain to a repo that currently has none. Only worth it if Windows UI parity is also being abandoned. Rejected for v1.

### 2.3 Chosen: Avalonia front-end over the shared C# core

```
                 ┌──────────────────────┐
                 │  CodeIsland.Core     │  (unchanged, net8.0)
                 │  CodeIsland.Protocol │  (unchanged, net8.0)
                 └──────────┬───────────┘
                            │
                 ┌──────────▼───────────┐
                 │  CodeIsland.Ipc      │  ← needs IEndpoint abstraction
                 │  CodeIsland.Hooks    │  ← needs POSIX path + shell handling
                 │  CodeIsland.Bridge   │  ← consumes both
                 └──────────┬───────────┘
                            │
        ┌───────────────────┴───────────────────┐
        │                                       │
┌───────▼────────────┐              ┌───────────▼────────────┐
│ CodeIsland.Windows │  WPF         │ CodeIsland.Linux       │  Avalonia
│ (existing)         │  net8.0-w   │ (new)                  │  net8.0
└────────────────────┘              └────────────────────────┘
```

Avalonia is chosen because its XAML dialect is close enough to WPF that views port by edit rather than by rewrite, and it has no Windows dependency.

## 3. Platform abstraction work (file-level)

### 3.1 IPC endpoint — `windows/CodeIsland.Ipc/`

Current state:

- `PipeEndpoint.cs` is `[SupportedOSPlatform("windows")]`, builds the pipe name from `WindowsIdentity.GetCurrent().User` (SID), and returns `NamedPipeServerStream` / `NamedPipeClientStream`.
- `PipeServer.cs` and `PipeClient.cs` are typed directly against `NamedPipeServerStream` / `NamedPipeClientStream`.
- macOS reference: `Sources/CodeIslandCore/SocketPath.swift` → `/tmp/codeisland-<uid>.sock`, overridable via `CODEISLAND_SOCKET_PATH`.

Required change: introduce an endpoint abstraction.

| Platform | Transport | Address |
|---|---|---|
| Windows | Named pipe | `codeisland-<userSid>` (unchanged) |
| Linux | Unix domain socket | `${XDG_RUNTIME_DIR:-/tmp}/codeisland-<uid>.sock` |
| (macOS, future) | Unix domain socket | `/tmp/codeisland-<uid>.sock` |

- Keep `CODEISLAND_SOCKET_PATH` honoured so the existing macOS debugging habits and the remote-hook script keep working.
- `$XDG_RUNTIME_DIR` is already `0700` and tmpfs-backed — it gives the same "only this user" property that the SID-derived pipe name gives on Windows. Fall back to `/tmp` with a `0700` parent check, mirroring the ownership check the macOS bridge does.
- Server must still be single-instance: on Linux, bind failure on an existing socket file must be distinguished from a stale socket left by a crash (unlink after a failed connect probe).

### 3.2 Hook tool definitions — `windows/CodeIsland.Hooks/HookTool.cs`

`KnownTools.All` currently hardcodes Windows separators:

```csharp
[".claude\\settings.json", ".claude.json"]
[".codex\\hooks.json", ".codex\\config.json"]
[".config\\opencode\\opencode.json"]
```

On Linux `Path.Combine(home, ".claude\\settings.json")` yields a filename containing a literal backslash — detection silently fails. Fix: store config paths as segment arrays (`[".claude", "settings.json"]`) and let `Path.Combine` join them, or use `/` and normalise. The macOS original is the source of truth for the real per-tool paths and should be cross-checked (`Sources/CodeIslandCore/ConfigRootDiscovery.swift`, `ClaudeConfigPaths.swift`, `CodexHooksConfig.swift`, `ExtraConfigDirs.swift`).

`ExecutableNames` already includes extension-less names (`claude`, `codex`, …), so the list itself is fine.

### 3.3 Executable detection — `windows/CodeIsland.Hooks/ToolDetector.cs`

`FindExecutable` only calls `File.Exists`. On Linux a non-executable file with the right name would be accepted. Add an executable-bit check on Unix (`File.GetUnixFileMode`), and skip the `.exe`/`.cmd` candidates on non-Windows. Also consult `~/.local/bin` and `/usr/local/bin` explicitly when the GUI process was started from a desktop launcher with a truncated `PATH`.

### 3.4 Hook command construction — `windows/CodeIsland.Hooks/HookRegistration.cs`

`Create` builds `"<abs path>" send --stdin --registration <marker>`. Double quotes are valid POSIX shell, so the format survives — but:

- The bridge path resolves to `CodeIsland.Bridge.exe`; on Linux the published binary is `CodeIsland.Bridge` (or `codeisland-bridge`). Path resolution must be platform-aware.
- `NativeHookInstaller.cs` embeds a `Bun.spawn(["cmd.exe", "/d", "/s", "/c", command], …)` in the generated OpenCode plugin. On Linux that must become `Bun.spawn(["/bin/sh", "-c", command])`.
- Hook config files are JSON with the same schema on both platforms, so `HookFileStore` (backup, idempotent install, removal) needs no change beyond the path issue above.

### 3.5 Windows-only desktop files that need a Linux counterpart

| Windows file | Purpose | Linux approach |
|---|---|---|
| `TerminalActivator.cs` | Win32 `EnumWindows` + `SetForegroundWindow` | `/proc/<pid>/cwd` to match sessions; `wmctrl -a` / `xdotool` / per-terminal IPC. X11 only. |
| `GlobalHotKeyManager.cs` | `RegisterHotKey` | X11 `XGrabKey` via `X11`/`SharpHook`. **Not possible on Wayland.** |
| `DisplayPositioner.cs` | `SetWindowPos`, monitor enumeration | `_NET_WM_STATE_ABOVE` + `_NET_WM_STRUT_PARTIAL`. **Not possible on Wayland.** |
| `FullscreenDetector.cs` | hide over exclusive fullscreen | `_NET_WM_STATE_FULLSCREEN` on the active window. Partial on Wayland. |
| `TrayMenuRenderer.cs` | `Shell_NotifyIcon` | StatusNotifierItem / `libayatana-appindicator`. GNOME needs the AppIndicator extension installed. |
| `StartupRegistration.cs` | `HKCU\…\Run` | `~/.config/autostart/codeisland.desktop` |

`CodeIsland.Windows.Smoke/Program.cs` is also Windows-bound (it fakes `cursor.cmd`, `wt.exe`); a Linux smoke project should assert the POSIX equivalents instead of being conditionally compiled.

### 3.6 Paths and settings

.NET on Unix already maps `Environment.SpecialFolder` sensibly, so most call sites are fine:

| API | Unix mapping |
|---|---|
| `ApplicationData` | `$XDG_CONFIG_HOME` (`~/.config`) |
| `LocalApplicationData` | `$XDG_DATA_HOME` (`~/.local/share`) |
| `UserProfile` | `$HOME` |

Rule to enforce: **config in `~/.config/codeisland`, logs/cache/backups in `~/.local/share/codeisland`.** Any hardcoded `%AppData%` string or backslash literal is a bug.

## 4. Phases

Each phase has a verification gate; do not start the next phase before it passes.

### Phase 1 — Endpoint abstraction

- Introduce the endpoint abstraction in `CodeIsland.Ipc`; keep the Windows named-pipe path byte-identical so the existing Windows build and hooks are unaffected.
- Add Unix domain socket implementation.
- Verification: `dotnet run --project CodeIsland.Bridge -- self-test` passes on Ubuntu **and** the existing Windows CI job stays green.

### Phase 2 — Hook install on Linux

- Fix `KnownTools` paths, `ToolDetector` executable bit, `HookRegistration` bridge path, OpenCode plugin shell.
- Verification: install hooks for Claude Code and Codex on a clean Ubuntu container; a real `claude` run produces events in the bridge log; `uninstall` restores the backup byte-for-byte.

### Phase 3 — Avalonia shell (read-only)

- New project `CodeIsland.Linux` (`net8.0`, Avalonia) referencing `Core` + `Ipc` + `Hooks`.
- Frameless always-on-top pill, session list, collapsed/expanded states. No actions yet.
- Verification: simulated event replay drives the panel; idle CPU < 1%, RSS < 150 MB.

### Phase 4 — Interaction

- Approve / deny / always-allow / answer question, routed back through IPC.
- Tray menu, autostart `.desktop`, settings persistence.
- Verification: end-to-end approve from panel returns the correct hook response to a simulated CLI; response timeout path covered by a test.

### Phase 5 — Desktop integration (X11 first)

- Terminal activation, global hotkeys, multi-monitor placement, fullscreen suppression.
- Capability detection with an explicit settings toggle per feature; Wayland degrades to "panel only, no hotkeys, no anchoring".
- Verification: on X11, window-level terminal activation succeeds for kitty, wezterm, alacritty, gnome-terminal; on Wayland the app starts, shows the panel, and clearly reports which features are unavailable.

### Phase 6 — Packaging and CI

- `dotnet publish -r linux-x64 --self-contained` → `.tar.gz` + `.deb` + AppImage.
- New `.github/workflows/linux.yml` mirroring `windows.yml` (restore, test, build, smoke, package, upload artifact).
- Verification: artifact runs on a clean Ubuntu 24.04 VM with no .NET installed; uninstall leaves no files behind.

### Phase 7 — Optional: BLE / ESP32

`CodeIsland.Bluetooth` currently contains only `BuddyProtocol.cs` — no transport. Linux transport would be BlueZ over D-Bus (`Tmds.DBus` or `Linux.Bluetooth`). Out of scope until the Windows BLE transport exists, so the protocol stays single-sourced.

## 5. Acceptance checklist

| ID | Feature | Linux acceptance |
|---|---|---|
| L-001 | Bridge + IPC | Unix socket, single instance, stale-socket recovery |
| L-002 | Hook install | Detect, install, repair, uninstall idempotent for every supported tool |
| L-003 | Live events | Same latency budget as Windows (< 300 ms P95 hook → panel) |
| L-004 | Permission approval | Action returns to the originating hook |
| L-005 | Question answering | Text response routed correctly |
| L-006 | Panel | Frameless, always-on-top (X11), drag, collapse |
| L-007 | Tray | StatusNotifierItem; documented GNOME extension requirement |
| L-008 | Autostart | XDG `.desktop` entry, removable from settings |
| L-009 | Hotkeys | X11 registered; Wayland reported as unsupported, not silently broken |
| L-010 | Terminal jump | Window-level on X11; copy-path fallback everywhere |
| L-011 | Settings | Persisted under `~/.config`, no data loss on upgrade |
| L-012 | Packaging | tar.gz / .deb / AppImage, self-contained, verified checksum |

## 6. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| **Wayland forbids always-on-top, absolute positioning, and global hotkeys** | High — three core interactions are impossible | Ship X11 as the supported path; on Wayland run panel-only and say so in the UI. Do not fake it. |
| GNOME hides tray icons by default | Medium | Detect AppIndicator availability; fall back to a hotkey + panel affordance. |
| Terminal activation has no portable API | Medium-High | Window-level only; per-terminal adapters behind a capability probe; copy-path fallback always present. |
| `KnownTools` config paths drift from the real CLIs | High | Port the macOS adapters as golden fixtures; add a health check that reports "config not found" instead of failing silently. |
| Two UIs diverge (WPF vs Avalonia) | Medium | Keep all behaviour in `Core`/`Hooks`; views hold no logic. Treat the Windows UI as the reference for interaction spec only. |
| Hook runs in a GUI-less environment | Medium | Bridge must exit 0 fast when no listener exists (already the Windows contract) — never block the AI CLI. |
| Distro packaging fragmentation | Medium | Ship self-contained; do not depend on a distro .NET package. |

## 7. Explicit non-goals for v1

- Notch geometry (does not exist on Linux; the panel is a floating pill).
- Apple Watch / Live Activities parity.
- Tab-level terminal targeting.
- BLE/ESP32 transport.
- Wayland-native overlay protocols (`wlr-layer-shell` is compositor-specific; revisit only if demand exists).

## 8. Execution order

1. Freeze the endpoint contract and its tests before touching any UI.
2. Get `Bridge -- self-test` green on Linux first — it proves Core, Protocol and IPC in one command.
3. Hook install for two tools (Claude, Codex) before adding the other seven.
4. Read-only panel before any interaction.
5. X11 desktop integration before Wayland investigation.
6. Packaging and CI before feature breadth — a broken release pipeline hides regressions.
7. Every phase ends with a runnable artifact and a written capability report.

## 9. Open questions to settle before coding

1. Does the Windows named-pipe name need to stay SID-derived, or can Linux use uid and Windows keep SID? (Recommendation: yes, keep them independent — the name is never transmitted over the wire.)
2. Should the Linux UI be a separate `CodeIsland.Linux` project, or should `CodeIsland.Windows` be renamed and re-targeted to Avalonia for both OSes? (Recommendation: separate project first; unify only if the WPF views prove portable.)
3. Is macOS eventually expected to move onto the C# core too, or does `Sources/CodeIsland` stay the canonical macOS implementation? This decides whether protocol changes land in Swift or C# first.
