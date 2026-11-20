//! The named pipe's two strings, pure (#105).
//!
//! Windows has no socket path: the endpoint *is* a pipe name, and its access
//! control is a descriptor built from the current user's SID. Both are strings,
//! so both can be built and checked on any machine — the OS half only creates
//! the pipe and compares SIDs.

/// `\\.\pipe\morrow-<SID>` — the name `endpoint::resolve` gives on Windows, so a
/// hook and the island cannot spell it differently.
pub fn pipe_name(sid: &str) -> String {
    // The same mapping `endpoint::resolve` applies (contract §4.1), so a hook
    // that resolves the endpoint and a server that was given a SID meet at one
    // name instead of two.
    let name: String = sid
        .chars()
        .map(|value| {
            if value.is_ascii_alphanumeric() {
                value
            } else {
                '-'
            }
        })
        .collect();
    format!(r"\\.\pipe\morrow-{name}")
}

/// The security descriptor that grants this user and nobody else: the SID is
/// owner and group, and one ACE gives it full access.
///
/// `D:(A;;GA;;;<SID>)` is the whole rule — no `WD` (everyone), no `AN`
/// (anonymous), no inheritable ACE a child object could widen. The pipe is
/// created with `FILE_FLAG_FIRST_PIPE_INSTANCE`, so a process that got there
/// first cannot share it either.
pub fn security_descriptor(sid: &str) -> String {
    format!("O:{sid}G:{sid}D:(A;;GA;;;{sid})")
}

/// Whether a string can be a SID: `S-1-` then decimal components. Checked before
/// the string reaches an API, because a malformed descriptor converts into a
/// pipe anyone may open — the failure is silent, so it is caught here.
pub fn is_sid(sid: &str) -> bool {
    let Some(rest) = sid.strip_prefix("S-1-") else {
        return false;
    };
    !rest.is_empty()
        && rest
            .split('-')
            .all(|part| !part.is_empty() && part.bytes().all(|byte| byte.is_ascii_digit()))
}
