# Two cores, one contract

Status: accepted (2026-11-16), amended 2026-11-18, **core language decided 2026-11-19: Rust** (see the last section).

macOS keeps its Swift core (`Sources/MorrowCore`, 21.699 LOC in 73 files) and SwiftUI shell. Windows and Linux share a second shell. The cores never share code — they share a frozen contract: the hook-event schema, the envelope schema, the golden fixtures exported to JSON, and the IPC endpoint rules (`docs/plan-windows-linux.md` §3.1).

Issue #33 aimed for one core across three operating systems. The first version of this ADR said that goal contradicts keeping macOS on Swift. That is only true if the shared core must be something other than Swift. The defensible statement is: running the original plan as written (Rust core while the C# core lives on) would have produced **three** cores, and the realistic choices are a Rust core for Windows/Linux or the Swift core compiled for them.

## Considered Options

- **One Rust core with FFI into macOS.** Rejected: the IPC seam between bridge and app already exists on macOS, and FFI adds permanent risk to the platform that ships today in exchange for nothing the socket does not already give.
- **Keep the C# core and add a third.** Rejected: `windows/Morrow.*` portable C# is ~1.5K LOC with its own normalizer and state machine, and it diverged from the normative protocol — `cursor_version` (`docs/hook-edge-protocol.md:210`) was absent from `windows/` until PR #51.
- **One core, macOS rewritten to match.** Rejected: the 80.544 LOC SwiftUI shell is not the part that needs porting.
- **Rust core for Windows/Linux** (default). One toolchain with the Tauri shell, in-process, mature crates for the hard parts (`notify`, `rusqlite`, named pipes, WinRT). Cost: re-implementing ~37–40K LOC of Swift-equivalent behaviour — `MorrowCore` 21.7K plus ~15–18K of domain logic that lives in the app target today (`ConfigInstaller`, `Discovery/`, `RemoteInstaller`, `HookServer`/`HookSocket`, …) — and keeping it in step forever.
- **Option E — the Swift `MorrowCore` compiled for Windows/Linux, run as a sidecar behind the Tauri shell** (precedent: DigUp). One core and one test suite; ~13 of 73 files need shims, the hardest being `JSONLTailer`'s vnode `DispatchSource`. Cost: shipping the Swift runtime on Windows, Foundation-on-Windows maturity, a JSON-lines process boundary between core and shell, and a Swift CI lane on two more OSes. **Not rejected: decided by the Phase 0.5 experiment.**

## Decision rule

Phase 0.5 runs a 1–2 day experiment: Darwin→Glibc guards in the 6 files that import Darwin, a vendored `CSQLite` target, `swift-crypto` for CryptoKit, then `swift build` and the pure core suites in a Linux container.

- Green within 2 days and ≥80% of the pure-logic core tests pass → write ADR-0003 choosing Option E; the Tauri shell (ADR-0002) is unchanged.
- Blocked by Foundation or Glibc gaps → Rust is confirmed; record the evidence here.

Until the experiment runs, Rust is the default and no Rust code beyond Phase 1's vertical slice is written.

## Consequences

- Two implementations of the reducer and attention policy (if Rust) must be kept in step by fixtures, not by review. Every provider fix updates the fixture first.
- The contract, including endpoint rules, becomes the highest-value artifact in the repo. The plugin socket regression after the rebrand (plan §12) shows what happens when an edge is outside the contract.
- A third core is the failure mode to watch for, not the starting point.

## Decision after the experiment (2026-11-19)

The #85 experiment met the decision rule: `MorrowCore` built on Linux and 96.8% of pure-logic tests passed ([`docs/experiments/option-e-linux.md`](../experiments/option-e-linux.md), ADR-0003). The maintainers nevertheless chose **option B, a Rust core**, in PR #117. The rule was written as a trigger for reconsidering, and it was reconsidered; it does not bind the outcome.

The trade-offs weighed (PR #117):

- **For Rust:** one language and one process with the Tauri shell, a small binary without a Swift/ICU runtime, mature Windows crates, and no dependency on Foundation-on-Windows, which the experiment did not measure.
- **Accepted costs:** two cores kept in step by fixtures forever, and re-implementing ~37–40K LOC of behaviour, which adds an estimated 4–6 weeks to Phases 2–3.

Consequences:

- Tickets #93–#97 (core port) stay as written. The reducer/attention fixture export (#92) is mandatory before #94; a port without it is guesswork.
- Every provider fix lands in Swift and Rust, fixture first. A PR that changes reducer or attention behaviour in Swift without re-exporting fixtures fails CI.
- The experiment's shims (`docs/experiments/option-e/`) are not maintained.

