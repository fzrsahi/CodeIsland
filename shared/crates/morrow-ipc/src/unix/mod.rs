//! A Unix socket transport for the endpoint (contract §2.2–2.3, §3.2):
//! blocking, std-based, one request and one reply per connection.
//!
//! Every check compares against an expected uid. [`Client::connect`] and
//! [`Server::bind`] use this process's; the `_as` variants take one, so
//! tests can stand in for another user, which they cannot create.

mod client;
mod server;
mod sys;

use std::fs::{self, Metadata};
use std::io;
use std::os::unix::fs::{FileTypeExt, MetadataExt};
use std::os::unix::net::UnixStream;
use std::path::Path;

pub use client::{Client, PendingReply};
pub use server::{Connection, Server};

use crate::{Endpoint, EndpointKind, Platform, resolve};

/// Why the transport refused an endpoint, a peer or a request.
#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum Error {
    #[error("`{endpoint}` is a named pipe, not a Unix socket path")]
    NotAUnixEndpoint { endpoint: String },

    #[error("`{path}` cannot be a Unix socket address: {source}")]
    InvalidPath { path: String, source: io::Error },

    #[error("nothing at `{path}`")]
    NotFound { path: String },

    #[error("`{path}` is not a socket (a symlink, file or folder); leaving it alone")]
    NotASocket { path: String },

    #[error("`{path}` belongs to uid {owner}, not this user (uid {expected})")]
    OtherUser {
        path: String,
        owner: u32,
        expected: u32,
    },

    #[error("folder `{path}` is not private to this user: {reason}")]
    UnsafeDir { path: String, reason: String },

    #[error("the process at the other end is uid {peer}, not this user (uid {expected})")]
    PeerNotUser { peer: u32, expected: u32 },

    #[error("an island of this user already listens at `{path}`")]
    AlreadyRunning { path: String },

    #[error("{op} `{path}`: {source}")]
    Io {
        op: &'static str,
        path: String,
        source: io::Error,
    },
}

/// The endpoint for this process, resolved now from its environment and
/// uid: the macOS rule on macOS, the Linux rule on every other Unix. A
/// variable that is not valid UTF-8 counts as unset.
pub fn current_endpoint() -> Endpoint {
    let uid = sys::current_uid();
    let platform = if cfg!(target_os = "macos") {
        Platform::Macos { uid }
    } else {
        Platform::Linux { uid }
    };
    resolve(
        platform,
        |name| std::env::var(name).ok(),
        |path| Path::new(path).exists(),
    )
}

/// The socket path of `endpoint`, or an error for a named pipe.
fn socket_path(endpoint: &Endpoint) -> Result<&str, Error> {
    match endpoint.kind() {
        EndpointKind::NamedPipe => Err(Error::NotAUnixEndpoint {
            endpoint: endpoint.as_str().to_owned(),
        }),
        _ => Ok(endpoint.as_str()),
    }
}

/// Who holds a path, as `lstat(2)` sees it (Swift `SocketPath.Holder`).
enum Holder {
    Nobody,
    /// A socket `uid` owns, with what `lstat` said about it.
    ThisUser(Metadata),
    /// Something `uid` owns that is not a socket, a symlink included: whoever
    /// owns a symlink can point it elsewhere.
    NotASocket,
    OtherUser(u32),
}

fn holder(path: &str, uid: u32) -> Result<Holder, Error> {
    let meta = match fs::symlink_metadata(path) {
        Ok(meta) => meta,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(Holder::Nobody),
        Err(source) => return Err(io_error("lstat", path, source)),
    };
    if meta.uid() != uid {
        return Ok(Holder::OtherUser(meta.uid()));
    }
    if meta.file_type().is_socket() {
        Ok(Holder::ThisUser(meta))
    } else {
        Ok(Holder::NotASocket)
    }
}

/// `holder`, as an error unless the path is a socket `uid` owns.
fn require_own_socket(path: &str, uid: u32) -> Result<Metadata, Error> {
    match holder(path, uid)? {
        Holder::ThisUser(meta) => Ok(meta),
        Holder::Nobody => Err(Error::NotFound { path: path.into() }),
        Holder::NotASocket => Err(Error::NotASocket { path: path.into() }),
        Holder::OtherUser(owner) => Err(Error::OtherUser {
            path: path.into(),
            owner,
            expected: uid,
        }),
    }
}

/// Contract §3.2: the folder is a real directory (not a symlink), owned by
/// `uid`, with no group or other permission bits.
fn check_private_dir(dir: &str, uid: u32) -> Result<(), Error> {
    let meta = match fs::symlink_metadata(dir) {
        Ok(meta) => meta,
        Err(e) if e.kind() == io::ErrorKind::NotFound => {
            return Err(Error::NotFound { path: dir.into() });
        }
        Err(source) => return Err(io_error("lstat", dir, source)),
    };
    let unsafe_dir = |reason: String| {
        Err(Error::UnsafeDir {
            path: dir.into(),
            reason,
        })
    };
    if meta.file_type().is_symlink() {
        return unsafe_dir("it is a symlink".into());
    }
    if !meta.is_dir() {
        return unsafe_dir("it is not a folder".into());
    }
    if meta.uid() != uid {
        return unsafe_dir(format!("it belongs to uid {}, not uid {uid}", meta.uid()));
    }
    let mode = meta.mode() & 0o777;
    if mode & 0o077 != 0 {
        return unsafe_dir(format!("its mode is {mode:04o}, it must be 0700"));
    }
    Ok(())
}

/// Refuses a connected stream unless the kernel says its peer is `uid`.
fn verify_peer(stream: &UnixStream, path: &str, uid: u32) -> Result<(), Error> {
    let peer =
        sys::peer_uid(stream).map_err(|source| io_error("peer credentials of", path, source))?;
    if peer == uid {
        Ok(())
    } else {
        Err(Error::PeerNotUser {
            peer,
            expected: uid,
        })
    }
}

fn io_error(op: &'static str, path: &str, source: io::Error) -> Error {
    Error::Io {
        op,
        path: path.into(),
        source,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn verify_peer_refuses_a_peer_of_another_uid() {
        let (a, _b) = UnixStream::pair().unwrap();
        let me = sys::current_uid();
        assert!(verify_peer(&a, "pair", me).is_ok());
        let other = me.wrapping_add(1);
        match verify_peer(&a, "pair", other) {
            Err(Error::PeerNotUser { peer, expected }) => {
                assert_eq!((peer, expected), (me, other));
            }
            result => panic!("expected PeerNotUser, got {result:?}"),
        }
    }
}
