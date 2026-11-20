//! Screen lock (#103): the island goes quiet while the screen is locked.
//!
//! Asked through `loginctl`, which every systemd-logind desktop has. Reading one
//! property is cheap enough to poll, and the answer is a plain `LockedHint=yes`.

use crate::runner::Runner;

/// Whether the screen is locked right now. `None` when the session cannot say —
/// which the caller treats as "not locked", so a machine without logind keeps a
/// working island.
pub fn locked(runner: &dyn Runner) -> Option<bool> {
    let session = std::env::var("XDG_SESSION_ID").ok();
    let mut args: Vec<&str> = vec!["show-session"];
    if let Some(session) = session.as_deref() {
        args.push(session);
    } else {
        args.push("auto");
    }
    args.push("--property=LockedHint");
    let output = runner.run("loginctl", &args).ok()?;
    parse_locked_hint(&output)
}

/// `LockedHint=yes` / `no`, or `LockedHint=unknown` on a session that does not
/// report it.
pub fn parse_locked_hint(output: &str) -> Option<bool> {
    let value = output
        .lines()
        .find_map(|line| line.trim().strip_prefix("LockedHint="))?;
    match value.trim().to_ascii_lowercase().as_str() {
        "yes" => Some(true),
        "no" => Some(false),
        _ => None,
    }
}
