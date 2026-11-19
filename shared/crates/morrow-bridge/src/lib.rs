//! `morrow-bridge`: the hook command Claude Code runs on Linux
//! (`docs/hook-edge-protocol.md`). It reads the hook's stdin, interprets it
//! ([`intake`], the bridge's part of HookIntake until #93), sends the payload
//! to the island at the endpoint (`morrow-ipc`), and prints the island's
//! answer for a hook that waits for one. It never makes the agent fail:
//! every way out is exit 0.
//!
//! A library as well as a binary, so tests run the interpretation on a
//! fixture's process tree ([`intake::ProcessFacts`]) without spawning it.

pub mod digest;
pub mod intake;

#[cfg(unix)]
mod deadline;
#[cfg(unix)]
pub mod process;
#[cfg(unix)]
pub mod run;
#[cfg(unix)]
mod sys;
