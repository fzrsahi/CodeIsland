//! Start at login through the registry (#107).
//!
//! `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` is the per-user place for
//! this: one value, no administrator, and Task Manager shows it to the user as a
//! startup app they can switch off — which is the behaviour a user expects, and
//! the reason not to use a scheduled task or a service.
//!
//! `reg.exe` rather than the registry API: it is the same tool the user would
//! type, it needs no `unsafe`, and every call is a value this module can be
//! tested against with a scripted runner.

use crate::runner::Runner;
use crate::windows_rules::run_value;

/// The key every per-user startup entry lives in.
pub const KEY: &str = r"HKCU\Software\Microsoft\Windows\CurrentVersion\Run";
/// The value Morrow writes. One, so uninstalling is one deletion.
pub const VALUE: &str = "Morrow";

/// The command line the key holds: the executable, quoted as Windows parses it.
pub fn command(executable: &str) -> String {
    run_value(executable, &["--minimised"])
}

/// Whether the value is there, and what it runs.
pub fn status(runner: &dyn Runner) -> Result<Option<String>, String> {
    let output = runner.run("reg", &["query", KEY, "/v", VALUE])?;
    Ok(parse_query(&output))
}

/// Writes the value, replacing whatever it held.
pub fn install(runner: &dyn Runner, executable: &str) -> Result<(), String> {
    runner
        .run(
            "reg",
            &[
                "add",
                KEY,
                "/v",
                VALUE,
                "/t",
                "REG_SZ",
                "/d",
                &command(executable),
                "/f",
            ],
        )
        .map(|_| ())
}

/// Removes the value. A missing value is not an error: the goal is that it is
/// gone, and it is.
pub fn uninstall(runner: &dyn Runner) -> Result<(), String> {
    match runner.run("reg", &["delete", KEY, "/v", VALUE, "/f"]) {
        Ok(_) => Ok(()),
        Err(error) if error.contains("unable to find") || error.contains("not exist") => Ok(()),
        Err(error) => Err(error),
    }
}

/// The data out of `reg query`'s output:
/// ```text
/// HKEY_CURRENT_USER\...\Run
///     Morrow    REG_SZ    "C:\…\Morrow.exe" --minimised
/// ```
pub fn parse_query(output: &str) -> Option<String> {
    output.lines().find_map(|line| {
        let line = line.trim();
        let rest = line.strip_prefix(VALUE)?.trim_start();
        let rest = rest.strip_prefix("REG_SZ")?;
        let value = rest.trim();
        (!value.is_empty()).then(|| value.to_owned())
    })
}
