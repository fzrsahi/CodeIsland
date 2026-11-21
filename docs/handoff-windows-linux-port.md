# Handoff — Windows & Linux port

Start here if you are picking up the port. This document is an index, a list of traps, and who does what. The plan lives elsewhere; do not re-derive it.

Last updated: 2026-11-19, on branch `docs/#33-windows-linux-architecture` (PR #49).

## Read these, in this order

| Artifact | What it answers |
|---|---|
| [`GLOSSARY.md`](../GLOSSARY.md) | Source, Agent, Hook target, Core, Shell, Endpoint, Capability, Tight-fit window. Read before writing any code or issue. |
| [`docs/adr/0001-two-cores-one-contract.md`](adr/0001-two-cores-one-contract.md) | Why two cores, one contract. Core language: **Rust** (decided in #117; Option E ran and was rejected). |
| [`docs/adr/0002-tauri-v2-shell.md`](adr/0002-tauri-v2-shell.md) | Why Tauri and not WPF/Avalonia/mygo, and the window plumbing it costs. |
| [`docs/plan-windows-linux.md`](plan-windows-linux.md) | Module map, endpoint contract (§3.1), monorepo layout (§4), adapters (§5.2), window plumbing (§6), **§7 = canonical phases**, §8 PR slicing, §9 packaging. If any other doc disagrees with §7, §7 wins. |
| [`docs/progress-windows-linux-port.md`](progress-windows-linux-port.md) | **Live status board and checkpoint log.** Update it before you stop. |
| [Issue #33](https://github.com/fzrsahi/Morrow/issues/33) | Epic. Phase table mirrors plan §7; **Stack PR** section holds the current PR stack and merge order. |
| [Issue #47](https://github.com/fzrsahi/Morrow/issues/47) / [#48](https://github.com/fzrsahi/Morrow/issues/48) | Windows (W0–W7, W-001…W-009) / Linux (L0–L7, L-001…L-012). |
| [Spec #82](https://github.com/fzrsahi/Morrow/issues/82) | User stories, implementation decisions, test seams. Tickets #83–#110 hang off #47/#48/#70 with native *blocked by* links: work a ticket only when all its blockers are closed. |
| [Issue #70](https://github.com/fzrsahi/Morrow/issues/70) | CI runners (Debian host, macOS KVM, Windows QEMU), path routing, EC2 mirror. |
| [`docs/research-mygo-vs-tauri.md`](research-mygo-vs-tauri.md) | Primary sources and measurements. **§9 (Go core + mygo) is superseded.** |

Superseded, still useful for Wayland risks and acceptance criteria: [`docs/archive/linux-avalonia-plan.md`](archive/linux-avalonia-plan.md) and [`windows/Morrow-Windows-Complete-Development-Plan.md`](../windows/Morrow-Windows-Complete-Development-Plan.md). Do not follow their phases or technology.

## State

Live state is in [`progress-windows-linux-port.md`](progress-windows-linux-port.md). Summary at this writing (2026-11-20): core language decided **Rust** (#117); phase 1 complete as a PR stack (#120 → #121 → #122 → #123 → #125), with the E2E-1 gate green in Xvfb and waiting for a real X11 run; phase 2 in progress as one stack: #127 fixtures, #128 `HookIntake`, #130 `reduceHookEvent` + desktop wired, #131 `AttentionPolicy.intents` + `reduce_event`, #132 `MarkdownBlockParser` + `GitBranchReader`, #133 transcript tail (`scan_lines` + `TailState`).

`main` now carries repo-wide agent rules (`AGENTS.md`, from #119): issue-first, 1 issue = 1 PR, stacked PRs, `.woodpecker.yaml` owned by @aazhrt, and a pre-commit `scripts/ci/verify-local.sh`. Until #126 merges, that guard blocks merging `main` into feature branches (#124).

## Who does what

The dev machine is macOS arm64 only. Work is split by what can be proven where.

| Work | Where it can be proven | Owner |
|---|---|---|
| Docs, ADRs, contract, fixtures, schemas | anywhere | dev machine |
| Rust crates without UI (`protocol`, `ipc` UDS, `core`, `bridge`, `hooks`) | macOS + Linux container (`cargo test`) | dev machine |
| Tauri shell build + X11 smoke (Xvfb + `xdotool`) | Linux container | dev machine |
| **`E2E-1` / `E2E-2` final gate on X11 and Wayland** | real Linux desktop | collaborator with the Debian host (#70) |
| Windows plumbing, WebView2 focus, SMTC, NSIS, signing | Windows 10/11 (QEMU on the Debian host, or hardware) | collaborator |
| Pipeline, runner, deploy, `.woodpecker.yaml` | server CI | @aazhrt only (AGENTS.md §2); the repo ships `scripts/ci/*` per plan §8.1 |
| Removing the C# core (Phase 6) | — | needs sign-off from the `windows/` maintainer |

Every PR that needs another machine ships a script that runs its gate and prints the evidence block for the PR, so the collaborator runs one command and pastes the output.

## Checkpoint discipline

- **Update `progress-windows-linux-port.md` before you stop**, even mid-task.
- Log entry is three lines: *done*, *next*, *blocking*. The third is the one that matters when resuming.
- Commit the progress update on the branch you are working on.
- Never delete a status row; change its status or add a row.

## Traps

- **`HookIntake` is pure, with injected facts.** It imports only Foundation, and every process lookup arrives as a closure in `Facts` (`macos/Sources/MorrowCore/HookIntake.swift:13-15`; line 551 calls `facts.tmuxClientTTY`). It belongs in `core`. The real Darwin calls (`proc_pidpath`, `proc_pidinfo`, `sysctl(KERN_PROCARGS2)`, `/dev/tty`) are in `macos/Sources/MorrowBridge/main.swift:41-114`. An earlier version of this handoff had this backwards.
- **`reduceHookEvent` is not fully pure.** It calls `Date()` throughout and reads `UserDefaults.standard` for custom sources (`SessionSnapshot.swift:451,463`). Inject a clock and the custom-source list, or conformance runs are flaky.
- **Two fixture sets, two seams.** #50 covers the bridge (stdin → forwarded payload/stdout); #127 covers the reducer and `AttentionPolicy`, with clock tokens `$Tk` and per-case `custom_sources`. A core port is done only when its fixture set passes 100%.
- **The "neutral" fixtures are a macOS projection.** Inputs carry iTerm env and `/Users/...` paths; `_tty` in the Linux bundle is `/dev/ttys009`. Do not treat the per-OS bundles as real Linux/Windows behaviour.
- **Click-through does not come for free.** The macOS panel is a large transparent rectangle that relies on WindowServer pass-through (`PanelWindowController.swift:191-206`); no `ignoresMouseEvents` anywhere. `HTTRANSPARENT` is same-thread only. Use a tight-fit window (plan §6.1).
- **There is no global pointer on Wayland.** Outside-click collapse (`PanelWindowController.swift:374`) and lyrics hover-hide (`CyberMusicView.swift:2280-2350`) only see events on our own surface there.
- **tauri#15913 closed without merging.** Layer-shell is a patch we maintain. AppImage forces X11 (tauri#15781).
- **Endpoints are already divergent.** Plugins default to `/tmp/codeisland-<uid>.sock`, the app listens on `/tmp/morrow-<uid>.sock` (bug #78). Every edge follows the endpoint contract (PR #115, `shared/contract/fixtures/endpoint/cases.json`); resolve the path at send time.
- **The Windows pipe can be squatted.** `windows/Morrow.Ipc/PipeEndpoint.cs` sets no `PipeSecurity`/`CurrentUserOnly` and the client never verifies the server. The Rust implementation must.
- **Core scope is about twice what it looks like.** ~15–18K LOC of domain logic lives in the app target (`ConfigInstaller`, `Discovery/`, `RemoteInstaller`, `HookServer`, …), not in `MorrowCore`.
- **`morrow-core` stays pure.** OS-specific code lives in `morrow-platform`/`morrow-bridge`; `shared/ci/rust-purity.sh` checks the dependency tree (it cannot see direct `std::process` use — review for it).
- **The pre-commit guard blocks merging `main`** into feature branches while `main` brings `.woodpecker.yaml` changes (#124, fix in PR #126). Use merges, never `--no-verify`.
- **SwiftPM cache breaks in fresh worktrees** ("unable to read tree"), which also fails the pre-push hook. Run `swift package resolve --disable-dependency-cache` once per new worktree.
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

- Dev machine: macOS arm64, **8 GB RAM / 6 cores**, Swift 6.4.2, `rustc` 1.98.0, Docker CLI with Colima. It crashed once when three heavy jobs ran together; follow the resource budget in `AGENTS.md` §4.
- Colima: `colima start --cpu 2 --memory 2`; containers `--cpus 2 --memory 1800m --memory-swap 3g`, `CARGO_BUILD_JOBS=1`. The Tauri/WebKitGTK build peaked at 1.72 GB, close to the cap.
- Linux image for the shell and gates: built from `linux/ci/Dockerfile` (PR #123); about 90 s to build, 3.85 GB.
- No Windows or Linux desktop on the dev machine. Behavioural claims for those OSes are documentation-derived unless a PR's Evidence says otherwise.
- CI: Woodpecker on a self-hosted macOS runner (`local` backend); no Linux lane yet (#70). GitHub Actions is unavailable.

## Next actions

Lanes run side by side; inside a lane, work is sequential. On the dev machine at most one **heavy** lane runs at a time (AGENTS.md §4). **Light** lanes (no build) can run beside it.

| Lane | Kind | Work, in order | Waits on |
|---|---|---|---|
| **A. Rust core** | heavy (Docker) | phase 2 core is ported (#131–#133 in PRs); next either the platform transcript watcher or the deferred app-side payloads (checklist, recap, model label) as new tickets | — |
| **B. Swift fixes** | heavy (host Swift) | #78 plugin endpoint fix → #86 replay of #118 on fresh `main` (split its `.woodpecker.yaml` edits into a PR for @aazhrt) | #115 answers; stack merged |
| **C. Stack upkeep** | light, but each `git push` is heavy (pre-push `swift build`) | after #126 merges: merge `main` into #49, then each stack PR's base into it, bottom-up; retarget children to `main` as bases merge | PR #126; reviews |
| **D. Collaborator gates** | other machines | run `linux/ci/e2e1.sh` on real X11 (PR #125); later E2E-2 Linux (#98), Windows VM gates (#105–#108) | — |
| **E. Next frontier** | heavy (Docker) | after lane A: #98 installer + E2E-2, #101 adapter batch 1, #104 Linux packaging, #105 Windows pipe | #91, #93, #83 merged or stacked |

Safe pairings on the dev machine: A + C(without push), B + C(without push), A + B only with both caps in place (Docker 1.8 GB, Swift `-j 2`) and no push until one finishes. Queue pushes; run them one at a time.

Open decisions blocking work: the three endpoint-contract questions on PR #115 (blocks #78), and the real-X11 E2E-1 run (closes phase 1).
