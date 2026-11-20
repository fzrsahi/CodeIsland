//! #103's commands: jump to a terminal, notice a session that ended, go quiet
//! while the screen is locked, and post a reminder.
//!
//! Each one is a thin call into `morrow_platform`; the policy lives there.

#[cfg(unix)]
use std::path::PathBuf;

use morrow_platform::process::Watch;
use morrow_platform::terminal::Outcome;
#[cfg(unix)]
use morrow_platform::terminal::Target;
#[cfg(unix)]
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
    // Windows has no app-id protocol to focus by: the window is found through
    // the session's process chain, so that path names the pid instead.
    #[cfg(windows)]
    {
        let _ = (site, app, tty, cwd);
        Outcome::NotPossible(
            "a window on Windows is found through the session's process, not its app id".to_owned(),
        )
    }
    #[cfg(unix)]
    {
        let target = Target {
            app,
            tty,
            cwd: cwd.map(PathBuf::from),
        };
        morrow_platform::terminal::activate(&morrow_platform::runner::SystemRunner, &target)
    }
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
    #[cfg(windows)]
    return morrow_platform::windows::lock::locked();
    #[cfg(unix)]
    return lock::locked(&morrow_platform::runner::SystemRunner);
}

/// Post a reminder through the desktop's notification service.
#[tauri::command]
pub fn notify_send(title: String, body: String) -> Result<(), String> {
    #[cfg(windows)]
    return morrow_platform::windows::toast::notify(&title, &body);
    #[cfg(unix)]
    return notify::notify(&morrow_platform::runner::SystemRunner, &title, &body);
}

/// Whether a fullscreen app is in front, so the island can step around it.
#[tauri::command]
pub fn fullscreen() -> bool {
    #[cfg(windows)]
    return morrow_platform::windows::fullscreen::fullscreen();
    #[cfg(unix)]
    return false;
}

/// The pointer, in screen pixels.
#[tauri::command]
pub fn pointer_position() -> Option<(i32, i32)> {
    #[cfg(windows)]
    return morrow_platform::windows::pointer::position();
    #[cfg(unix)]
    return None;
}
