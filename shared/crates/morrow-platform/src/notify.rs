//! Notifications (#103): the reminder the island sends through the desktop.
//!
//! `notify-send` is the one line everyone has; a system without it simply has no
//! reminders, which the Capability table says.

use crate::runner::Runner;

/// How long a reminder stays up, in milliseconds.
pub const TIMEOUT_MS: u64 = 8_000;

/// Post a notification. An error is the sentence the caller logs.
pub fn notify(runner: &dyn Runner, title: &str, body: &str) -> Result<(), String> {
    runner
        .run(
            "notify-send",
            &[
                "--app-name=Morrow",
                // The app's own name is the icon hint, so a themed setup shows
                // the island's mark.
                "--icon=morrow",
                &format!("--expire-time={TIMEOUT_MS}"),
                title,
                body,
            ],
        )
        .map(|_| ())
}
