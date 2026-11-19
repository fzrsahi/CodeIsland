//! The real [`ProcessFacts`]: `/proc` on Linux. Elsewhere only the parent
//! pid, enough to build and run (the macOS bridge is the Swift one; nothing
//! asserts this one's macOS output).

use std::path::Path;
use std::process::{Command, Stdio};

use crate::intake::{Ancestor, ProcessFacts};

/// This process's facts, read from the OS when asked.
#[derive(Debug, Default)]
pub struct OsProcess;

impl ProcessFacts for OsProcess {
    fn parent_pid(&self) -> Option<i32> {
        i32::try_from(std::os::unix::process::parent_id()).ok()
    }

    fn ancestry(&self) -> Vec<Ancestor> {
        let Some(parent) = self.parent_pid() else {
            return Vec::new();
        };
        ancestry_from(parent)
    }

    fn working_directory(&self) -> Option<String> {
        std::env::current_dir().ok()?.to_str().map(str::to_owned)
    }

    /// `tmux display-message -p -t <pane> -F '#{client_tty}'`, by an
    /// explicit path: a hook's PATH may lack the tmux directory.
    fn tmux_client_tty(&self, pane: &str) -> Option<String> {
        let tmux = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
        ]
        .into_iter()
        .find(|path| is_executable(Path::new(path)))?;
        let output = Command::new(tmux)
            .args(["display-message", "-p", "-t", pane, "-F", "#{client_tty}"])
            .stdin(Stdio::null())
            .stderr(Stdio::null())
            .output()
            .ok()?;
        if !output.status.success() {
            return None;
        }
        let text = String::from_utf8(output.stdout).ok()?;
        let text = text.trim();
        (!text.is_empty()).then(|| text.to_owned())
    }
}

fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    path.metadata()
        .is_ok_and(|meta| meta.is_file() && meta.permissions().mode() & 0o111 != 0)
}

/// Up to [`crate::intake::MAX_ANCESTRY`] processes from `pid` up, each once.
#[cfg(target_os = "linux")]
fn ancestry_from(pid: i32) -> Vec<Ancestor> {
    let mut chain = Vec::new();
    let mut current = Some(pid);
    while let Some(pid) = current {
        if pid <= 0
            || chain.len() >= crate::intake::MAX_ANCESTRY
            || chain.iter().any(|a: &Ancestor| a.pid == pid)
        {
            break;
        }
        let executable_path = std::fs::read_link(format!("/proc/{pid}/exe"))
            .ok()
            .and_then(|path| path.to_str().map(str::to_owned));
        chain.push(Ancestor {
            pid,
            executable_path,
        });
        current = std::fs::read_to_string(format!("/proc/{pid}/stat"))
            .ok()
            .and_then(|stat| parent_in_stat(&stat));
    }
    chain
}

/// The parent only: no `/proc` to walk (macOS needs `proc_pidpath`, which
/// the Swift bridge uses and this one does not).
#[cfg(not(target_os = "linux"))]
fn ancestry_from(pid: i32) -> Vec<Ancestor> {
    vec![Ancestor {
        pid,
        executable_path: None,
    }]
}

/// The ppid in `/proc/<pid>/stat`: the 2nd field after the command name,
/// which is in parentheses and may itself hold spaces and `)`.
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
fn parent_in_stat(stat: &str) -> Option<i32> {
    let rest = &stat[stat.rfind(')')? + 1..];
    rest.split_whitespace().nth(1)?.parse().ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stat_parent_survives_odd_command_names() {
        assert_eq!(parent_in_stat("42 (claude) S 41 42 42 0"), Some(41));
        assert_eq!(parent_in_stat("42 (a) b) (c) R 7 1"), Some(7));
        assert_eq!(parent_in_stat("garbage"), None);
    }

    #[test]
    fn own_ancestry_starts_at_the_parent() {
        let process = OsProcess;
        let chain = process.ancestry();
        assert_eq!(chain.first().map(|a| a.pid), process.parent_pid());
        assert!(chain.len() <= crate::intake::MAX_ANCESTRY);
    }
}
