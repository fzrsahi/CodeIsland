# Swift core as a sidecar for Windows and Linux (Option E)

Status: proposed (2026-11-19), pending maintainer acceptance. Until it is accepted, ADR-0001's default (Rust) stands and no Rust code beyond Phase 1's vertical slice is written.

ADR-0001's decision rule picks Option E when `MorrowCore` builds in a Linux container within 2 days and at least 80% of the pure-logic core tests pass. The #85 experiment ([`docs/experiments/option-e-linux.md`](../experiments/option-e-linux.md)) met both conditions:

- **Green.** `MorrowCore` builds with Swift 6.2.4 on Ubuntu 22.04 (aarch64) after shims in 16 of 73 files (+146/−7 LOC), a 2-file `CSQLite` system-library target, and `swift-crypto` in place of CryptoKit. It took about 30 minutes of the 2-day timebox.
- **96.8% pass.** 973 of 1,005 pure-logic tests pass. None fail at runtime. The 30 that don't pass are three markdown-rendering suites that can't compile on Linux, and 2 are skipped by the container environment. The contract suites spec #82 names (`AttentionPolicyTests`, `SubsessionReducerTests`, `CursorSessionFoldingTests`, `HookIntakeGoldenTests`) all pass.

So the Windows and Linux core is the existing Swift `MorrowCore`, compiled for those platforms and run as a sidecar process behind the Tauri v2 shell (ADR-0002, unchanged). The shell and core talk JSON-lines over the process boundary. There is one core, one test suite, and the frozen contract from ADR-0001 still governs the bridge and the endpoints.

## What the experiment did not settle

Accepting this ADR means accepting these as open risks, each with its own gate:

- **Windows is unmeasured.** Foundation on Windows, the Swift runtime installer, AF_UNIX vs named pipes and SID-based peer checks were not built or tested. This is the risk ADR-0001 named first. Gate: `MorrowCore` + pure suites on a Windows VM before Phase 4 starts. If that fails, Windows falls back to the Rust core and this ADR is narrowed to Linux.
- **Three stubs are blockers.** `JSONLTailer` needs an inotify watcher; the Linux stand-in polls and misses file replacement (2 of 46 tailer tests fail). `ChatMessageTextFormatter` and `MarkdownPreviewText` use `AttributedString` markdown APIs that swift-foundation on Linux lacks. On the Tauri shell, markdown is rendered from `MarkdownBlockParser` blocks, so these two files are likely not needed in the sidecar.
- **The scope measured is `MorrowCore` only (21.7K LOC).** The ~15–18K LOC of domain logic held in the app target (plan §5.1) was not built. `ConfigInstaller.swift` imports AppKit and Yams. Moving it into a portable target is work Option E still has to do, though it is less work than rewriting it in Rust.
- **Binary size and dependencies.** A static-stdlib release executable linking all of `MorrowCore` is 58 MB stripped (aarch64) and still links `libsqlite3` and `libcurl` dynamically. No Rust build was measured for comparison. ADR-0002 already does not treat memory or size as deciding.
- **Sidecar latency.** The JSON-lines boundary is unmeasured against the `E2E-1` <300 ms gate.
- **Toolchain cost.** CI needs a Swift lane on Linux (and Windows): about 85 s for a cold debug build with tests at `-j 1`, most of it swift-crypto.

## Consequences

- Phase 1's `morrow-core` crate is replaced by a Swift sidecar target built from `Sources/MorrowCore`. `morrow-protocol`, `morrow-ipc`, `morrow-platform` and the shell stay Rust/Tauri. The bridge for Windows/Linux is a separate decision; this ADR doesn't make it.
- Linux/Windows shims live in `MorrowCore` behind `#if canImport(...)` / `#if os(...)` guards. That changes the macOS product sources, so it needs its own PR, with `swift test` green on macOS and no behaviour change there.
- Phase 2's conformance tickets (#93–#97) become "the same Swift tests pass on Linux/Windows" instead of "the Rust port matches the Swift fixtures". Exporting the reducer and attention fixtures (#92) is still useful for the bridge and the C# migration.
- If the Windows gate fails, there are two core languages again (Swift on macOS and Linux, Rust on Windows), split by OS instead of by macOS vs the rest. Run the Windows gate before any shell code depends on the sidecar protocol, so that outcome costs as little as possible.
