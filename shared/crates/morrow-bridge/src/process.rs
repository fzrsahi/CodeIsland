//! The real [`ProcessFacts`]: `/proc` on Linux. Elsewhere only the parent
//! pid, enough to build and run (the macOS bridge is the Swift one; nothing
//! asserts this one's macOS output).

use std::path::Path;
use std::process::{Command, Stdio};

use crate::facts::ProcessFacts;

/// This process's facts, read from the OS when asked.
#[derive(Debug, Default)]
pub struct OsProcess;

impl ProcessFacts for OsProcess {
    fn parent_pid(&self) -> Option<i32> {
        i32::try_from(std::os::unix::process::parent_id()).ok()
    }

    fn ancestry(&self) -> Vec<(i32, Option<String>)> {
        let Some(parent) = self.parent_pid() else {
            return Vec::new();
        };
        ancestry_from(parent)
    }

    /// `/proc/<pid>/cmdline`, empty arguments left out as the Swift
    /// bridge's `ProcArgsParser` leaves them.
    fn arguments(&self, pid: i32) -> Vec<String> {
        arguments_of(pid)
    }

    /// No `.app` bundles here (the Swift bridge reads `Info.plist`).
    fn bundle_identifier(&self, _executable_path: &str) -> Option<String> {
        None
    }

    fn working_directory(&self) -> Option<String> {
        std::env::current_dir().ok()?.to_str().map(str::to_owned)
    }

    fn tty(&self) -> Option<String> {
        controlling_tty()
    }

    fn home_directory(&self) -> Option<String> {
        std::env::var("HOME").ok().filter(|home| !home.is_empty())
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

    fn file_exists(&self, path: &str) -> bool {
        Path::new(path).exists()
    }
}

fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    path.metadata()
        .is_ok_and(|meta| meta.is_file() && meta.permissions().mode() & 0o111 != 0)
}

/// Up to `MAX_ANCESTRY` processes from `pid` up, each once.
#[cfg(target_os = "linux")]
fn ancestry_from(pid: i32) -> Vec<(i32, Option<String>)> {
    use morrow_core::intake::MAX_ANCESTRY;

    let mut chain: Vec<(i32, Option<String>)> = Vec::new();
    let mut current = Some(pid);
    while let Some(pid) = current {
        if pid <= 0 || chain.len() >= MAX_ANCESTRY || chain.iter().any(|(p, _)| *p == pid) {
            break;
        }
        let executable_path = std::fs::read_link(format!("/proc/{pid}/exe"))
            .ok()
            .and_then(|path| path.to_str().map(str::to_owned));
        chain.push((pid, executable_path));
        current = std::fs::read_to_string(format!("/proc/{pid}/stat"))
            .ok()
            .and_then(|stat| stat_field(&stat, 1)?.parse().ok());
    }
    chain
}

/// The parent only: no `/proc` to walk (macOS needs `proc_pidpath`, which
/// the Swift bridge uses and this one does not).
#[cfg(not(target_os = "linux"))]
fn ancestry_from(pid: i32) -> Vec<(i32, Option<String>)> {
    vec![(pid, None)]
}

#[cfg(target_os = "linux")]
fn arguments_of(pid: i32) -> Vec<String> {
    std::fs::read(format!("/proc/{pid}/cmdline"))
        .map(|cmdline| {
            cmdline
                .split(|byte| *byte == 0)
                .filter(|argument| !argument.is_empty())
                .map(|argument| String::from_utf8_lossy(argument).into_owned())
                .collect()
        })
        .unwrap_or_default()
}

#[cfg(not(target_os = "linux"))]
fn arguments_of(_pid: i32) -> Vec<String> {
    Vec::new()
}

/// The controlling terminal, a pseudo-terminal's `/dev/pts/<n>`, from
/// `tty_nr` in `/proc/self/stat` (opening `/dev/tty` only names
/// `/dev/tty`). `None` with no controlling terminal or another kind.
#[cfg(target_os = "linux")]
fn controlling_tty() -> Option<String> {
    let stat = std::fs::read_to_string("/proc/self/stat").ok()?;
    pts_name(stat_field(&stat, 4)?.parse().ok()?)
}

#[cfg(not(target_os = "linux"))]
fn controlling_tty() -> Option<String> {
    None
}

/// `/dev/pts/<n>` for a `tty_nr`: Unix98 pty slaves are majors 136 to 143,
/// 256 minors each (the minor's high bits above bit 8 of `tty_nr`).
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
fn pts_name(tty_nr: u32) -> Option<String> {
    let major = (tty_nr >> 8) & 0xfff;
    let minor = (tty_nr & 0xff) | ((tty_nr >> 12) & 0xfff00);
    (136..=143)
        .contains(&major)
        .then(|| format!("/dev/pts/{}", (major - 136) * 256 + minor))
}

/// Field `n` of `/proc/<pid>/stat` counted from the one after the command
/// name (0: state, 1: ppid, 4: tty_nr). The name is in parentheses and may
/// itself hold spaces and `)`.
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
fn stat_field(stat: &str, n: usize) -> Option<&str> {
    let rest = &stat[stat.rfind(')')? + 1..];
    rest.split_whitespace().nth(n)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stat_fields_survive_odd_command_names() {
        assert_eq!(stat_field("42 (claude) S 41 42 42 34816 0", 1), Some("41"));
        assert_eq!(stat_field("42 (a) b) (c) R 7 1", 1), Some("7"));
        assert_eq!(
            stat_field("42 (claude) S 41 42 42 34816 0", 4),
            Some("34816")
        );
        assert_eq!(stat_field("garbage", 1), None);
    }

    #[test]
    fn pts_names_from_tty_nr() {
        // 34816 = major 136, minor 0.
        assert_eq!(pts_name(34816).as_deref(), Some("/dev/pts/0"));
        assert_eq!(pts_name((136 << 8) | 3).as_deref(), Some("/dev/pts/3"));
        assert_eq!(pts_name((137 << 8) | 1).as_deref(), Some("/dev/pts/257"));
        assert_eq!(pts_name(0), None);
        // /dev/tty1: major 4.
        assert_eq!(pts_name((4 << 8) | 1), None);
    }

    #[test]
    fn own_ancestry_starts_at_the_parent() {
        let process = OsProcess;
        let chain = process.ancestry();
        assert_eq!(chain.first().map(|(pid, _)| *pid), process.parent_pid());
        assert!(chain.len() <= morrow_core::intake::MAX_ANCESTRY);
    }
}
