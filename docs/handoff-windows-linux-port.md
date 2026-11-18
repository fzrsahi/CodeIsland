# Handoff — Windows & Linux port

Start here if you are picking up the port. This document is an index, a list of traps, and who does what. The plan lives elsewhere; do not re-derive it.

Last updated: 2026-11-18, on branch `docs/#33-windows-linux-architecture` (PR #49), after merging `origin/main` (Morrow rebrand).

## Read these, in this order

| Artifact | What it answers |
|---|---|
| [`GLOSSARY.md`](../GLOSSARY.md) | Source, Agent, Hook target, Core, Shell, Endpoint, Capability, Tight-fit window. Read before writing any code or issue. |
| [`docs/adr/0001-two-cores-one-contract.md`](adr/0001-two-cores-one-contract.md) | Why two cores, and the experiment that may make it one (Option E). |
| [`docs/adr/0002-tauri-v2-shell.md`](adr/0002-tauri-v2-shell.md) | Why Tauri and not WPF/Avalonia/mygo, and the window plumbing it costs. |
| [`docs/plan-windows-linux.md`](plan-windows-linux.md) | Module map, endpoint contract (§3.1), monorepo layout (§4), adapters (§5.2), window plumbing (§6), **§7 = canonical phases**, §8 PR slicing, §9 packaging. If any other doc disagrees with §7, §7 wins. |
| [`docs/progress-windows-linux-port.md`](progress-windows-linux-port.md) | **Live status board and checkpoint log.** Update it before you stop. |
| [Issue #33](https://github.com/fzrsahi/Morrow/issues/33) | Parent. Implementation order in its body ("Urutan Implementasi") mirrors §7. |
| [Issue #47](https://github.com/fzrsahi/Morrow/issues/47) / [#48](https://github.com/fzrsahi/Morrow/issues/48) | Windows (W0–W7, W-001…W-009) / Linux (L0–L7, L-001…L-012). |
| [Issue #70](https://github.com/fzrsahi/Morrow/issues/70) | CI runners (Debian host, macOS KVM, Windows QEMU), path routing, EC2 mirror. |
| [`docs/research-mygo-vs-tauri.md`](research-mygo-vs-tauri.md) | Primary sources and measurements. **§9 (Go core + mygo) is superseded.** |

Superseded, still useful for Wayland risks and acceptance criteria: [`docs/archive/linux-avalonia-plan.md`](archive/linux-avalonia-plan.md) and [`windows/Morrow-Windows-Complete-Development-Plan.md`](../windows/Morrow-Windows-Complete-Development-Plan.md). Do not follow their phases or technology.

## State

Live state is in [`progress-windows-linux-port.md`](progress-windows-linux-port.md). Summary at this writing: Phase 0 PRs #49–#52 open; #50 and #52 need revisions; no Rust code; Phase 0.5 (monorepo move, endpoint contract, Option E experiment) not started.

## Who does what

The dev machine is macOS arm64 only. Work is split by what can be proven where.

| Work | Where it can be proven | Owner |
|---|---|---|
| Docs, ADRs, contract, fixtures, schemas | anywhere | dev machine |
| Rust crates without UI (`protocol`, `ipc` UDS, `core`, `bridge`, `hooks`) | macOS + Linux container (`cargo test`) | dev machine |
| Option E experiment (Swift core on Linux) | Linux container | dev machine |
| Tauri shell build + X11 smoke (Xvfb + `xdotool`) | Linux container | dev machine |
| **`E2E-1` / `E2E-2` final gate on X11 and Wayland** | real Linux desktop | collaborator with the Debian host (#70) |
| Windows plumbing, WebView2 focus, SMTC, NSIS, signing | Windows 10/11 (QEMU on the Debian host, or hardware) | collaborator |
| Pipeline, runner, deploy (upload EC2 / GitHub Releases) | server CI | pemilik #70 — repo menyediakan skrip `test`/`package`/`manifest` (plan §8.1) |
| Removing the C# core (Phase 6) | — | needs sign-off from the `windows/` maintainer |

Every PR that needs another machine ships a script that runs its gate and prints the evidence block for the PR, so the collaborator runs one command and pastes the output.

## Checkpoint discipline

- **Update `progress-windows-linux-port.md` before you stop**, even mid-task.
- Log entry is three lines: *done*, *next*, *blocking*. The third is the one that matters when resuming.
- Commit the progress update on the branch you are working on.
- Never delete a status row; change its status or add a row.

## Traps

- **`HookIntake` is pure, with injected facts.** It imports only Foundation, and every process lookup arrives as a closure in `Facts` (`Sources/MorrowCore/HookIntake.swift:13-15`; line 551 calls `facts.tmuxClientTTY`). It belongs in `core`. The real Darwin calls (`proc_pidpath`, `proc_pidinfo`, `sysctl(KERN_PROCARGS2)`, `/dev/tty`) are in `Sources/MorrowBridge/main.swift:41-114`. An earlier version of this handoff had this backwards.
- **`reduceHookEvent` is not fully pure.** It calls `Date()` throughout and reads `UserDefaults.standard` for custom sources (`SessionSnapshot.swift:451,463`). Inject a clock and the custom-source list, or conformance runs are flaky.
- **The fixtures in #50 cover the bridge only.** No reducer or `AttentionPolicy` fixture exists. Exporting them is the first PR of Phase 2.
- **The "neutral" fixtures are a macOS projection.** Inputs carry iTerm env and `/Users/...` paths; `_tty` in the Linux bundle is `/dev/ttys009`. Do not treat the per-OS bundles as real Linux/Windows behaviour.
- **Click-through does not come for free.** The macOS panel is a large transparent rectangle that relies on WindowServer pass-through (`PanelWindowController.swift:191-206`); no `ignoresMouseEvents` anywhere. `HTTRANSPARENT` is same-thread only. Use a tight-fit window (plan §6.1).
- **There is no global pointer on Wayland.** Outside-click collapse (`PanelWindowController.swift:374`) and lyrics hover-hide (`CyberMusicView.swift:2280-2350`) only see events on our own surface there.
- **tauri#15913 closed without merging.** Layer-shell is a patch we maintain. AppImage forces X11 (tauri#15781).
- **Endpoints are already divergent.** Plugins default to `/tmp/codeisland-<uid>.sock`, the app listens on `/tmp/morrow-<uid>.sock` (plan §12). Every edge must follow plan §3.1; resolve the path at send time.
- **The Windows pipe can be squatted.** `windows/Morrow.Ipc/PipeEndpoint.cs` sets no `PipeSecurity`/`CurrentUserOnly` and the client never verifies the server. The Rust implementation must.
- **Core scope is about twice what it looks like.** ~15–18K LOC of domain logic lives in the app target (`ConfigInstaller`, `Discovery/`, `RemoteInstaller`, `HookServer`, …), not in `MorrowCore`.
- **Do not add `#[cfg(target_os)]` to `morrow-core`.** Move it to `morrow-platform`; enforce with `cargo tree -p morrow-core` in CI.
- **Bridge language is not a performance question.** Go 5.31 ms vs Rust 4.49 ms vs Swift 5.3 ms median cold start; all at the `fork/exec` floor.
- **The audio visualizer needs no audio capture** (`CAMusicVisuals.swift:22-31`).
- **`KnownTools.All` stores paths as backslash strings.** On Linux this silently yields a filename with a literal backslash. Store paths as segments.
- **`windows/` is not ours.** One squashed commit `31116ab` by an outside contributor. Phase 6 needs their sign-off.
- **Windows Authenticode signing is skipped for the beta** (#70). The Tauri updater's Ed25519 signature is still mandatory and unrelated. Free GA paths: Microsoft Store MSIX or SignPath Foundation (plan §9).
- **The Windows VM is not a per-PR runner.** Linux compiles `#[cfg(windows)]` code with `cargo xwin check` and runs portable tests; the VM builds releases and judges the Phase 4 gates (plan §9).
- **Two end-to-end gates, not one.** `E2E-1` (synthetic, Phase 1) proves the wiring; `E2E-2` (real `claude`, Phases 3–4) proves the product.

## Suggested skills

| Skill | When |
|---|---|
| `codebase-design` | Rust module interfaces, `core` vs `platform` seams |
| `domain-modeling` | Keep `GLOSSARY.md` honest |
| `tdd` | Phase 2 — the exported fixtures are the tests |
| `diagnosing-bugs` | Click-through, layer-shell, focus stealing on real machines |
| `wizard` | Steps only a human can do: Windows signing, VM setup, GNOME AppIndicator |
| `pr` | Every PR body |

## Environment facts

- Dev machine: macOS arm64, Swift 6.4.2, `rustc` 1.98.0, `go` 1.27.0, Docker CLI with Colima.
- No Windows or Linux desktop on the dev machine. Behavioural claims for those OSes are documentation-derived unless a PR's Evidence says otherwise.
- CI: Woodpecker on a self-hosted macOS runner (`local` backend); GitHub Actions is unavailable (billing lock). A Linux lane needs a second agent with the docker backend (#70).

## Next actions

1. Revise and merge Phase 0: #49 (this), #50 (exporter path, neutral rules, validator), #51 (reworked: Claude hook without `--source`, Swift precedence), #52 (drop `windows.yml`, `pipefail`, Morrow names).
2. Fix the plugin endpoint regression in its own PR ([#78](https://github.com/fzrsahi/Morrow/issues/78)) — it is a live macOS bug.
3. Phase 0.5: monorepo move PR, endpoint contract, Option E experiment → ADR-0003 or ADR-0001 evidence.
4. Phase 1 vertical slice, with the gate script handed to the collaborator for the real X11 run.
