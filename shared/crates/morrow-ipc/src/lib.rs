//! The **endpoint** of Morrow's contract (`shared/contract/endpoint-contract.md`) and
//! the local transport to it.
//!
//! - [`resolve`]: the endpoint rule for macOS, Linux and Windows, pure.
//! - [`unix`] (Unix only): a blocking Unix socket [`unix::Client`] and
//!   [`unix::Server`] that talk only to a peer of the same user, keep one
//!   island per endpoint, and recover from a socket a crashed island left.
//! - [`windows`] (Windows only): the same pair over a named pipe that only this
//!   user can open ([`pipe::security_descriptor`]); the client refuses a server
//!   that is not this user, the way the Unix side refuses a foreign socket.
//!
//! Bytes in, bytes out: what the bytes mean is `morrow-protocol`'s business.

mod endpoint;
pub mod pipe;
#[cfg(unix)]
pub mod unix;
#[cfg(windows)]
pub mod windows;

// The one transport name the rest of the tree uses: a Unix socket on Unix, a
// named pipe on Windows. Both answer the same calls (#105).
#[cfg(unix)]
pub use unix::{Client, Connection, Error, PendingReply, Server, current_endpoint};
#[cfg(windows)]
pub use windows::{Client, Connection, Error, PendingReply, Server, current_endpoint};

pub use endpoint::{Endpoint, EndpointKind, Platform, resolve};
