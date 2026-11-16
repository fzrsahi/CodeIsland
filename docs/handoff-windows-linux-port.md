# Handoff — Windows & Linux port

Start here if you are picking up the port. This document is an index and a list of traps, not a plan. The plan lives elsewhere; do not re-derive it.

Last updated: 2026-11-16, on branch `docs/#33-windows-linux-architecture`.

## Read these, in this order

| Artifact | What it answers |
|---|---|
| [`GLOSSARY.md`](../GLOSSARY.md) | What Source, Agent, Hook target, Core, Shell, Panel, Island mean here. Read before writing any code or issue. |
| [`docs/adr/0001-two-cores-one-contract.md`](adr/0001-two-cores-one-contract.md) | Why there are two cores and not one. |
| [`docs/adr/0002-tauri-v2-shell.md`](adr/0002-tauri-v2-shell.md) | Why Tauri and not mygo, and what that costs. |
| [`docs/plan-windows-linux.md`](plan-windows-linux.md) | Module map, seams, adapters, **§7 = the canonical phase list**, **§8 = PR slicing rules**. §0 is a document map. If any other doc disagrees with §7, §7 wins. |
| [`docs/progress-windows-linux-port.md`](progress-windows-linux-port.md) | **Live status board and checkpoint log.** Read this second, after the handoff. Update it before you stop. |
| [Issue #33](https://github.com/fzrsahi/CodeIsland/issues/33) | Parent. **The implementation order lives in its body**, under "Urutan Implementasi", and mirrors §7. |
| [Issue #47](https://github.com/fzrsahi/CodeIsland/issues/47) | Windows scope, work items W0–W6, acceptance W-001…W-008. |
| [Issue #48](https://github.com/fzrsahi/CodeIsland/issues/48) | Linux scope, work items L0–L7, acceptance L-001…L-011. |
| [`docs/research-mygo-vs-tauri.md`](research-mygo-vs-tauri.md) | Primary sources and measurements. Force-added past `.gitignore:83`; the ADRs stand without it. |

`W#` and `L#` are **local work items, not a sequence**. The sequence is phases 0–6 in §7, and each phase says which local items it contains.

Superseded, but still useful for Wayland risk analysis and acceptance criteria: [`linux/CodeIsland-Linux-Development-Plan.md`](../linux/CodeIsland-Linux-Development-Plan.md) and [`windows/CodeIsland-Windows-Complete-Development-Plan.md`](../windows/CodeIsland-Windows-Complete-Development-Plan.md). Both now carry a SUPERSEDED banner. Do not follow their phases or their technology choices.

## State

The live state is in [`docs/progress-windows-linux-port.md`](progress-windows-linux-port.md) — status board and checkpoint log. Do not duplicate it here; it will go stale within a day.

As of this writing: branch `docs/#33-windows-linux-architecture`, not pushed, no PR, no application code, `rust/` does not exist, phase 0 not started.

Untracked and **not** part of this work: `PRODUCT.md`, `linux/CodeIsland-Linux-Development-Plan.md`.

## Checkpoint discipline

This is the part that gets skipped and then costs a whole session.

- **Update `docs/progress-windows-linux-port.md` before you stop**, even mid-task. Half-finished work with a written checkpoint is resumable; finished-looking work with none is not.
- The log entry is three lines: *what is done*, *what is next*, *what is blocking*. The third line is the one people omit and the only one that matters when resuming.
- Commit the progress update on the branch you are working on, not a separate one. Conflicts here are trivial.
- Never delete a status row. Change its status, or add a row if a PR was split.
- If you cannot answer "which phase is running, what is its gate, what blocks it" from the progress doc alone, the last checkpoint was incomplete — fix it before starting work.

## Traps

Each of these cost time to find. They are not in the ADRs.

- **`HookIntake` is not pure.** It calls `proc_pidpath`, opens `/dev/tty`, and parses `_iterm_session` (`Sources/CodeIslandCore/HookIntake.swift:551`). It belongs in `platform`, not `core`. The pure seam is `reduceHookEvent` (`Sources/CodeIslandCore/SessionSnapshot.swift:1143`) and `AttentionPolicy`.
- **The golden fixtures are a macOS suite.** They contain `_ppid` 78×, `_term_bundle` 8×, `_term_app` 5×, `_tty` 3×, `_iterm_session` 2×. A byte-identical stdout gate is unachievable off macOS until they are split neutral vs per-OS.
- **The fixtures are Swift literals**, not JSON — `enum` with raw string literals. Nothing outside Swift can read them today. Exporting them is Phase 0's first task, and it blocks every other language.
- **Do not add `#[cfg(target_os)]` to `codeisland-core`.** If it appears, it is a bug; move it to `codeisland-platform`. Enforce with `cargo tree -p codeisland-core` in CI, or the purity rule will erode within two weeks.
- **Bridge language is not a performance question.** Measured here: Go 5.31 ms vs Rust 4.49 ms median cold start; both sit at the OS `fork/exec` floor. Rust is chosen for toolchain unity.
- **The audio visualizer needs no audio capture.** `CAMusicVisuals.swift` / `CAMusicCurves` generate sine curves. There is no `AVAudioEngine` tap to port, and no loopback capture needed on Windows or Linux.
- **`KnownTools.All` stores paths as backslash strings** (`@".claude\settings.json"`). On Linux this silently yields a filename containing a literal backslash — detection fails with no error. Store paths as segment arrays.
- **The C# side is not verified.** Per codegraph, `SessionSnapshot` (C#) and `KnownTools` have no covering tests. Do not treat `windows/CodeIsland.Core` as a reference implementation; it is the divergent one (`cursor_version` has 0 matches there).
- **`windows/` is not ours.** It arrived as one squashed commit `31116ab` by an outside contributor whose README calls it "not an official Windows release". Deleting `RawAgentEventNormalizer.cs` + `SessionStateMachine.cs` (phase 6) needs their sign-off first.
- **Three plan docs exist; only one is canonical.** `docs/plan-windows-linux.md` §7 and #33's "Urutan Implementasi" are the same list. `linux/…Development-Plan.md` (Avalonia) and `windows/…Development-Plan.md` (WPF) are superseded — useful for acceptance criteria and Wayland risks, wrong on phases and technology.
- **There are two end-to-end gates, not one.** `E2E-1` (phase 1) is synthetic: hook JSON piped into the bridge, panel shows it, Approve travels back to stdout. `E2E-2` (phases 3 and 4) uses a real `claude` with an installed hook. `E2E-1` proves the wiring; `E2E-2` proves the product. Do not let `E2E-2` be the first time the round-trip is tested.

## Suggested skills

| Skill | When |
|---|---|
| `codebase-design` | Designing the Rust module interfaces — deep modules, where the seams go, what belongs in `core` vs `platform` |
| `domain-modeling` | `GLOSSARY.md` exists; challenge terms as they drift, especially Source / Agent / Hook target |
| `tdd` | Phase 2 — the exported fixtures *are* the tests; port reducer-first, red-green |
| `diagnosing-bugs` | When click-through, layer-shell, or focus-stealing misbehaves on a real machine |
| `wizard` | Steps only a human can do: Windows code-signing certificate, Windows VM or hardware, GNOME AppIndicator install |
| `pr` | Opening the PR for phases 0–1 |
| `code-review` | Reviewing the port against the contract |

## Environment facts

- Dev machine is macOS arm64; `go` 1.27.0 and `rustc` 1.98.0 are installed.
- **No Windows or Linux machine is available.** Every Windows/Linux behavioural claim in these artifacts is documentation-derived, not measured. Only the bridge cold-start numbers were measured on this machine. Treat the rest as hypotheses to verify in phase 1.
- `gh` is authenticated as a repo collaborator. Do not print or copy the token.

## Next actions

The ordering comments on #47 and #48 are written. Both point at #48 for the work that starts now.

1. **Phase 0** — export `BridgeGoldenFixtures`/`Expectations` to `fixtures/*.json`, split neutral vs per-OS, and fix `cursor_version` in `RawAgentEventNormalizer.cs`. Definition of done is in the #48 comment.
2. **Phase 1** — the Linux X11 vertical slice. Do not start it until Phase 0's fixtures are readable outside Swift.
3. **Do not start Windows** (#47). It is phase 4 and inherits a proven shell and a conformant core.

If Phase 1's gate fails — no click-through, or focus is stolen — stop and report rather than starting Phase 2.
