//! The endpoint rule of the contract (`docs/endpoint-contract.md`), as a pure
//! function of what it reads: the environment, the user's id and, on macOS,
//! whether two fixed paths exist. No I/O here; the caller passes those in.

/// The two overrides, in the order they apply (contract §1.4).
const OVERRIDES: [&str; 2] = ["MORROW_SOCKET_PATH", "CODEISLAND_SOCKET_PATH"];

/// The OS whose rule applies, with the user id that rule reads: a uid on
/// macOS and Linux, the SID string on Windows. One value, so a uid can never
/// reach the Windows rule or a SID the Unix ones.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Platform<'a> {
    Macos {
        uid: u32,
    },
    Linux {
        uid: u32,
    },
    /// `sid` is the string form of the current user's SID (`S-1-5-21-…`).
    /// When it cannot be read there is no endpoint (contract §4.1): do not
    /// call [`resolve`] with a placeholder.
    Windows {
        sid: &'a str,
    },
}

/// Which branch of the rule gave an [`Endpoint`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EndpointKind {
    /// `MORROW_SOCKET_PATH` or `CODEISLAND_SOCKET_PATH`, used as is.
    Override,
    /// Linux: `$XDG_RUNTIME_DIR/morrow/island.sock`. Its folder
    /// ([`Endpoint::private_dir`]) must be this user's, mode `0700`.
    RuntimeDir,
    /// `/tmp/morrow-<uid>.sock` (macOS, and Linux without `XDG_RUNTIME_DIR`).
    Tmp,
    /// macOS only: `/tmp/codeisland-<uid>.sock`, chosen when it exists and
    /// the morrow socket does not.
    LegacyTmp,
    /// Windows: `\\.\pipe\morrow-<SID>`.
    NamedPipe,
}

/// The address an edge sends envelopes to, exactly as the rule gives it: no
/// tilde expansion, no `realpath`, no making a relative override absolute.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Endpoint {
    path: String,
    kind: EndpointKind,
}

impl Endpoint {
    /// The endpoint string, compared byte for byte by the case table.
    pub fn as_str(&self) -> &str {
        &self.path
    }

    pub fn kind(&self) -> EndpointKind {
        self.kind
    }

    /// The folder that must be private to this user before the endpoint is
    /// trusted or bound: `$XDG_RUNTIME_DIR/morrow` for
    /// [`EndpointKind::RuntimeDir`], `None` for every other kind (`/tmp` is
    /// shared and sticky; an override's folder is the user's choice).
    pub fn private_dir(&self) -> Option<&str> {
        match self.kind {
            EndpointKind::RuntimeDir => self.path.strip_suffix("/island.sock"),
            _ => None,
        }
    }
}

impl std::fmt::Display for Endpoint {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.path)
    }
}

/// Resolves the endpoint for `platform`.
///
/// `env` returns a variable's value, `None` when it is unset. `exists` says
/// whether a path exists, following symlinks (`stat(2)`); only the macOS
/// rule calls it. Resolve each time an edge is about to connect, never once
/// at load (contract §1.1).
pub fn resolve(
    platform: Platform<'_>,
    env: impl Fn(&str) -> Option<String>,
    exists: impl Fn(&str) -> bool,
) -> Endpoint {
    match platform {
        Platform::Macos { uid } => macos(uid, &env, &exists),
        Platform::Linux { uid } => linux(uid, &env),
        Platform::Windows { sid } => windows(sid, &env),
    }
}

/// Contract §2.1, as Swift behaves today: an override that is *set* wins,
/// even when empty (OQ-1).
fn macos(
    uid: u32,
    env: &impl Fn(&str) -> Option<String>,
    exists: &impl Fn(&str) -> bool,
) -> Endpoint {
    if let Some(path) = OVERRIDES.iter().find_map(|name| env(name)) {
        return endpoint(path, EndpointKind::Override);
    }
    let morrow = format!("/tmp/morrow-{uid}.sock");
    let legacy = format!("/tmp/codeisland-{uid}.sock");
    if !exists(&morrow) && exists(&legacy) {
        return endpoint(legacy, EndpointKind::LegacyTmp);
    }
    endpoint(morrow, EndpointKind::Tmp)
}

/// Contract §3.1: empty counts as unset; `XDG_RUNTIME_DIR` only when
/// absolute, trailing slashes removed; no legacy path, no file check.
fn linux(uid: u32, env: &impl Fn(&str) -> Option<String>) -> Endpoint {
    if let Some(path) = non_empty_override(env) {
        return endpoint(path, EndpointKind::Override);
    }
    if let Some(xdg) = env("XDG_RUNTIME_DIR").filter(|xdg| xdg.starts_with('/')) {
        let path = format!("{}/morrow/island.sock", xdg.trim_end_matches('/'));
        return endpoint(path, EndpointKind::RuntimeDir);
    }
    endpoint(format!("/tmp/morrow-{uid}.sock"), EndpointKind::Tmp)
}

/// Contract §4.1: every character outside ASCII `[A-Za-z0-9]` becomes `-`.
fn windows(sid: &str, env: &impl Fn(&str) -> Option<String>) -> Endpoint {
    if let Some(path) = non_empty_override(env) {
        return endpoint(path, EndpointKind::Override);
    }
    let name: String = sid
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .collect();
    endpoint(format!(r"\\.\pipe\morrow-{name}"), EndpointKind::NamedPipe)
}

fn non_empty_override(env: &impl Fn(&str) -> Option<String>) -> Option<String> {
    OVERRIDES
        .iter()
        .find_map(|name| env(name).filter(|value| !value.is_empty()))
}

fn endpoint(path: String, kind: EndpointKind) -> Endpoint {
    Endpoint { path, kind }
}
