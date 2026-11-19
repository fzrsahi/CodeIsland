//! The **endpoint** of Morrow's contract (`docs/endpoint-contract.md`) and
//! the local transport to it.
//!
//! - [`resolve`]: the endpoint rule for macOS, Linux and Windows, pure.
//! - [`unix`] (Unix only): a blocking Unix socket [`unix::Client`] and
//!   [`unix::Server`] that talk only to a peer of the same user, keep one
//!   island per endpoint, and recover from a socket a crashed island left.
//!
//! Bytes in, bytes out: what the bytes mean is `morrow-protocol`'s business.

mod endpoint;
#[cfg(unix)]
pub mod unix;

pub use endpoint::{Endpoint, EndpointKind, Platform, resolve};
