//! Fullscreen detection through `SHQueryUserNotificationState` (#107).
//!
//! The shell API has promised this since Windows 7: it answers whether a
//! fullscreen Direct3D app, a presentation, or quiet time is in front. It is the
//! only cross-application answer Windows gives, and it is exactly the question
//! the island asks before interrupting — so one call serves both "is something
//! fullscreen" and "may I show a card".

use crate::windows_rules::NotificationState as State;

/// The state Windows reports now, or `Unknown` when the shell will not say (a
/// session without Explorer, for instance).
pub fn state() -> State {
    let query = unsafe { windows::Win32::UI::Shell::SHQueryUserNotificationState() };
    match query {
        Ok(value) => State::from_code(value.0),
        Err(_) => State::Unknown,
    }
}

/// Whether a fullscreen app is in front, which the island steps around.
pub fn fullscreen() -> bool {
    state().fullscreen()
}

/// Whether a card may interrupt. Unknown counts as yes: a permission prompt that
/// never appears is worse than one shown a second early.
pub fn may_interrupt() -> bool {
    state().may_interrupt()
}
