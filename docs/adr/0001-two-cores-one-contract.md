# Two cores, one contract

Status: accepted (2026-11-16)

macOS keeps its Swift core (`Sources/CodeIslandCore`, 21.278 LOC) and SwiftUI shell. Windows and Linux share a second core and a second shell. The two cores never share code — they share a frozen contract: the hook-event schema, the envelope schema, and golden fixtures exported to JSON.

Issue #33 aimed for one core across three operating systems while also keeping macOS on Swift. Those two goals contradict each other; the achievable target is two cores, and pretending otherwise would have produced three (Swift, C#, Rust).

## Considered Options

- **One Rust core with FFI into macOS.** Rejected: the macOS core is 21.278 LOC with 64.728 LOC of tests, and the IPC seam between bridge and app already exists and works. FFI would add permanent risk to the platform that produces all current revenue, in exchange for nothing the socket does not already give.
- **Keep the C# core and add a third.** Rejected: `windows/CodeIsland.*` is 4.561 LOC with its own normalizer and state machine, and it already diverges from the normative protocol — `cursor_version` is specified in `docs/hook-edge-protocol.md:210`, implemented in Swift, and absent from `windows/` entirely.
- **One core, macOS rewritten to match.** Rejected: 79.044 LOC of SwiftUI shell is not the part that needs porting.

## Consequences

- Two implementations of the reducer and attention policy must be kept in step by fixtures, not by review. Every provider fix updates the fixture first.
- The contract becomes the highest-value artifact in the repo, and freezing it precedes any port work.
- A third core is now the failure mode to watch for, not the starting point.
