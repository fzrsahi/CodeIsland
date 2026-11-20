//! #103's commands: jump to a terminal, notice a session that ended, go quiet
//! while the screen is locked, and post a reminder.
//!
//! Each one is a thin call into `morrow_platform`; the policy lives there.

use std::path::PathBuf;

use morrow_platform::process::Watch;
use morrow_platform::terminal::{Outcome, Target};
use morrow_platform::{lock, notify};
use tauri::State;

use crate::HooksSite;

/// Jump to a session's terminal, or hand over its path.
#[tauri::command]
pub fn terminal_activate(
    site: State<'_, HooksSite>,
    app: Option<String>,
    tty: Option<String>,
    cwd: Option<String>,
) -> Outcome {
    let _ = &site;
    let target = Target {
        app,
        tty,
        cwd: cwd.map(PathBuf::from),
    };
    morrow_platform::terminal::activate(&morrow_platform::runner::SystemRunner, &target)
}

/// Remember a session's process so a later call can tell whether it is the same
/// one. `None` when the pid is not running.
#[tauri::command]
pub fn process_watch(pid: i64) -> Option<Watch> {
    Watch::new(pid)
}

/// Whether the process behind a watch is still there.
#[tauri::command]
pub fn process_alive(watch: Watch) -> bool {
    watch.alive()
}

/// Whether the screen is locked. `None` when the session cannot say, which the
/// island treats as unlocked.
#[tauri::command]
pub fn screen_locked() -> Option<bool> {
    lock::locked(&morrow_platform::runner::SystemRunner)
}

/// Post a reminder through the desktop's notification service.
#[tauri::command]
pub fn notify_send(title: String, body: String) -> Result<(), String> {
    notify::notify(&morrow_platform::runner::SystemRunner, &title, &body)
}
