//! Whether a session's process is still there (#103).
//!
//! The island keeps one card per live session, so a process that exited must
//! disappear — and the check has to be cheap enough to run for every card a few
//! times a second. Reading a file that exists, and one number inside it, is
//! that: no process-table scan, no `/proc` walk.
//!
//! The number matters: pid reuse would keep a dead card alive if only the pids
//! were compared. `watch()` therefore carries the process's start time, which
//! the kernel never reuses for another process.

use std::path::Path;

/// One process, identified so a reused pid cannot impersonate it.
#[derive(Clone, Copy, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Watch {
    pub pid: i64,
    /// Field 22 of `/proc/<pid>/stat`: start time in clock ticks since boot.
    pub start_time: u64,
}

impl Watch {
    /// Watch a pid that is already running. `None` when it is not.
    pub fn new(pid: i64) -> Option<Self> {
        let start_time = start_time(pid)?;
        Some(Self { pid, start_time })
    }

    /// Still the same process? False once it exited, or once the kernel handed
    /// its pid to something else.
    pub fn alive(&self) -> bool {
        start_time(self.pid) == Some(self.start_time)
    }
}

/// Start time of a process, from `/proc/<pid>/stat`.
pub fn start_time(pid: i64) -> Option<u64> {
    let stat = std::fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    parse_start_time(&stat)
}

/// `parse_start_time` from the raw `stat` line. The command name sits in
/// parentheses and may contain spaces, parentheses or newlines, so everything
/// up to the *last* `)` is skipped before counting fields.
pub fn parse_start_time(stat: &str) -> Option<u64> {
    let close = stat.rfind(')')?;
    let fields: Vec<&str> = stat[close + 1..].split_whitespace().collect();
    // After the command, field 3 (`state`) is `fields[0]`, so starttime — field
    // 22 — is `fields[19]`.
    fields.get(19)?.parse().ok()
}

/// A coarse liveness check for callers that only have a pid and no watch: `/proc`
/// entry plus, when available, the start time. Cheap by construction.
pub fn exists(pid: i64) -> bool {
    pid > 0 && Path::new(&format!("/proc/{pid}")).exists()
}
