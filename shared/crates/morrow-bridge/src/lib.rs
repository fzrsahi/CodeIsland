//! `morrow-bridge`: the hook command agents run on Linux
//! (`docs/hook-edge-protocol.md`). It gathers the facts of one invocation
//! ([`facts`]: argv, environment, stdin, what the OS says about its
//! process), has HookIntake (`morrow_core::intake`) interpret them, sends
//! the payload to the island at the endpoint (`morrow-ipc`), and prints
//! what HookIntake says to print. It never makes the agent fail: every way
//! out is exit 0.
//!
//! A library as well as a binary, so tests run the interpretation on a
//! fixture's process tree ([`facts::ProcessFacts`]) without spawning it.

pub mod facts;

#[cfg(unix)]
mod deadline;
#[cfg(unix)]
pub mod process;
#[cfg(unix)]
pub mod run;
#[cfg(unix)]
mod sys;
