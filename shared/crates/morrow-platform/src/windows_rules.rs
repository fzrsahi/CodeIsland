//! The Windows adapters' decisions, without Windows (#107).
//!
//! Three questions the Windows modules have to answer, kept here because they
//! are pure and a wrong answer is silent: which process's window is a session's
//! terminal, what a notification state means for "may I show a card", and how a
//! path is written into the registry so `reg.exe` reads it back whole.

use std::collections::BTreeMap;

/// A process and its parent, as `/proc`-style introspection or
/// `CreateToolhelp32Snapshot` gives them.
pub type Parents = BTreeMap<u32, u32>;

/// The pid whose window a session should raise: the outermost ancestor that is
/// a terminal host, or the session's own pid when the chain names none.
///
/// A hook runs under `claude`, which runs under the user's shell, which runs
/// under the terminal — and it is the *terminal's* window that should come
/// forward, not the shell's (which has none). Walking up the chain and taking
/// the last match is deliberately different from taking the first: a terminal
/// that started a nested shell (tmux, a subshell) must still bring the outer
/// window forward, because that is the window the user can see.
pub fn terminal_pid(
    parents: &Parents,
    pid: u32,
    hosts: &[&str],
    names: &BTreeMap<u32, String>,
) -> u32 {
    let mut current = pid;
    let mut best = pid;
    // A chain longer than this is a cycle or a bug; stop rather than spin.
    for _ in 0..64 {
        if let Some(name) = names.get(&current) {
            let name = name.to_ascii_lowercase();
            if hosts
                .iter()
                .any(|host| name.contains(&host.to_ascii_lowercase()))
            {
                best = current;
            }
        }
        match parents.get(&current) {
            Some(parent) if *parent != 0 && *parent != current => current = *parent,
            _ => break,
        }
    }
    best
}

/// What `SHQueryUserNotificationState` reports, and what the island does with it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NotificationState {
    /// `QUNS_NOT_PRESENT`, `QUNS_BUSY`, `QUNS_RUNNING_D3D_FULL_SCREEN`,
    /// `QUNS_PRESENTATION_MODE`, `QUNS_ACCEPTS_NOTIFICATIONS`.
    NotPresent,
    Busy,
    FullScreenD3d,
    Presentation,
    AcceptsNotifications,
    /// `QUNS_QUIET_TIME` and the app's own state: no cards, no toasts.
    QuietTime,
    /// A value this build does not know.
    Unknown,
}

impl NotificationState {
    /// The API's integer, mapped so a new value degrades to `Unknown` instead of
    /// being read as "the user is available".
    pub fn from_code(code: i32) -> Self {
        match code {
            1 => Self::NotPresent,
            2 => Self::Busy,
            3 => Self::FullScreenD3d,
            4 => Self::Presentation,
            5 => Self::AcceptsNotifications,
            6 => Self::QuietTime,
            _ => Self::Unknown,
        }
    }

    /// Whether a fullscreen app is in front, which the island steps around.
    pub fn fullscreen(self) -> bool {
        matches!(self, Self::FullScreenD3d | Self::Presentation)
    }

    /// Whether a card may interrupt: the two states that mean "the user is here
    /// and not fullscreen", plus the unknown case, which is not a reason to
    /// swallow a permission prompt.
    pub fn may_interrupt(self) -> bool {
        matches!(self, Self::AcceptsNotifications | Self::Unknown)
    }
}

/// The value a `HKCU\…\CurrentVersion\Run` entry holds for a program.
///
/// `reg.exe` splits its own arguments on whitespace, so a path with a space has
/// to be quoted once for the registry (which stores a command line) — and the
/// quoting is what Windows' own `CreateProcess` would parse back.
pub fn run_value(executable: &str, args: &[&str]) -> String {
    let mut value = quote(executable);
    for arg in args {
        value.push(' ');
        value.push_str(&quote(arg));
    }
    value
}

/// One argument for a Windows command line: quoted when it has to be, never
/// when it does not (a quoted path with no spaces is still correct, but every
/// extra quote is a chance to be wrong).
fn quote(argument: &str) -> String {
    if !argument.is_empty() && !argument.contains([' ', '\t', '"']) {
        return argument.to_owned();
    }
    // Backslashes before the closing quote are doubled, per `CommandLineToArgvW`:
    // a path ending in `\` would otherwise escape the quote that closes it.
    let mut quoted = String::with_capacity(argument.len() + 2);
    quoted.push('"');
    let mut backslashes = 0;
    for character in argument.chars() {
        match character {
            '\\' => backslashes += 1,
            '"' => {
                quoted.push_str(&"\\".repeat(backslashes * 2 + 1));
                quoted.push('"');
                backslashes = 0;
            }
            other => {
                quoted.push_str(&"\\".repeat(backslashes));
                quoted.push(other);
                backslashes = 0;
            }
        }
    }
    quoted.push_str(&"\\".repeat(backslashes * 2));
    quoted.push('"');
    quoted
}
