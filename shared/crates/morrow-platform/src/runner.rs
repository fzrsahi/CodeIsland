//! Running the tools a desktop already ships.
//!
//! Nothing in `morrow-platform` links a D-Bus, X11 or audio library: it asks
//! `playerctl`, `wpctl`, `swaymsg`, `loginctl`, `notify-send` and friends, which
//! are the same tools the user could type. A missing tool is a capability the
//! UI states, not a crash — and the injected trait keeps every adapter testable
//! without a desktop behind it.

use std::process::Command;

/// Runs a program and gives back its stdout. An error is the sentence the card
/// shows, not a panic.
pub trait Runner {
    fn run(&self, program: &str, args: &[&str]) -> Result<String, String>;
}

/// The real thing.
pub struct SystemRunner;

impl Runner for SystemRunner {
    fn run(&self, program: &str, args: &[&str]) -> Result<String, String> {
        let output = Command::new(program)
            .args(args)
            .output()
            .map_err(|error| format!("{program}: {error}"))?;
        if !output.status.success() {
            return Err(format!(
                "{program} exited {}\n{}",
                output.status,
                String::from_utf8_lossy(&output.stderr).trim()
            ));
        }
        Ok(String::from_utf8_lossy(&output.stdout).into_owned())
    }
}
