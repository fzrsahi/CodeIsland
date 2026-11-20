//! A named pipe transport for the endpoint (contract §2.2–2.3, §3.2), the
//! Windows half of [`crate::unix`]: blocking, byte for byte the same calls, one
//! request and one reply per connection.
//!
//! Two things replace what the kernel does on Unix:
//!
//! - **Access control.** A Unix socket gets a mode and an owner; a pipe gets a
//!   security descriptor. The descriptor is built from this user's SID
//!   ([`crate::pipe::security_descriptor`]), and the server asks for the first
//!   instance so nothing else can host the same name.
//! - **Peer identity.** `SO_PEERCRED` has no pipe equivalent: the client asks
//!   the pipe for its server's process id (`GetNamedPipeServerProcessId`), opens
//!   that process's token, and compares the token's user SID with its own. A
//!   pipe another user created under this name is refused before a byte is sent.
//!
//! The pipe is in **message mode**, which is this platform's `half-close`:
//! one `WriteFile` is one message, so the request ends where the message ends
//! and neither side needs a length prefix or a shutdown that pipes do not have.

// Every call below is a Win32 function; the blocks are the FFI, reviewed as
// such. The workspace denies `unsafe_code` everywhere else, and stays that way.
#![allow(unsafe_code)]

mod client;
mod server;
mod sys;

use std::io;

pub use client::{Client, PendingReply};
pub use server::{Connection, Server};

use crate::{Endpoint, EndpointKind, Platform, resolve};

/// The largest message either side will carry. A hook request is a JSON object
/// of a few kilobytes; the island's reply is a decision. Anything larger is a
/// bug rather than a payload, and is refused instead of truncated.
pub const MAX_MESSAGE: usize = 64 * 1024;

/// Why the transport refused an endpoint, a peer or a request.
#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum Error {
    #[error("`{endpoint}` is a Unix socket path, not a named pipe")]
    NotANamedPipe { endpoint: String },

    #[error("cannot read this user's SID: {source}")]
    NoSid { source: io::Error },

    #[error("an island of this user already listens at `{path}`")]
    AlreadyRunning { path: String },

    #[error("the server on `{path}` is not this user's (its SID is not ours)")]
    PeerNotUser { path: String },

    #[error("`{path}` carried a message larger than {MAX_MESSAGE} bytes")]
    TooLarge { path: String },

    #[error("{op} `{path}`: {source}")]
    Io {
        op: &'static str,
        path: String,
        source: io::Error,
    },
}

/// The endpoint for this process, resolved now from its environment and its
/// user's SID. An endpoint that cannot name a pipe is left to [`Client`] and
/// [`Server`] to refuse, as on Unix.
pub fn current_endpoint() -> Endpoint {
    let sid = sys::current_sid().unwrap_or_default();
    // Same three inputs the Unix side reads: the environment, and a file
    // probe that only macOS's rule uses.
    resolve(
        Platform::Windows { sid: &sid },
        |name| std::env::var(name).ok(),
        |path| std::path::Path::new(path).exists(),
    )
}

/// The pipe name of an endpoint, or the error a caller reports instead of
/// connecting to a path that is not a pipe.
pub(crate) fn pipe_name(endpoint: &Endpoint) -> Result<&str, Error> {
    match endpoint.kind() {
        EndpointKind::NamedPipe | EndpointKind::Override => {
            if endpoint.as_str().starts_with(r"\\.\pipe\") {
                Ok(endpoint.as_str())
            } else {
                Err(Error::NotANamedPipe {
                    endpoint: endpoint.as_str().to_owned(),
                })
            }
        }
        _ => Err(Error::NotANamedPipe {
            endpoint: endpoint.as_str().to_owned(),
        }),
    }
}

pub(crate) fn io_error(op: &'static str, path: &str, source: io::Error) -> Error {
    Error::Io {
        op,
        path: path.to_owned(),
        source,
    }
}
