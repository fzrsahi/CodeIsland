use std::io::{Read, Write};
use std::net::Shutdown;
use std::os::fd::OwnedFd;
use std::os::unix::net::UnixStream;
use std::time::Duration;

use socket2::{Domain, SockAddr, Socket, Type};

use super::{
    Error, check_private_dir, io_error, require_own_socket, socket_path, sys, verify_peer,
};
use crate::Endpoint;

/// A connection to the island at an endpoint, made only after the checks of
/// contract §2.2 / §3.2 pass. One request, one reply (`send_and_wait`).
#[derive(Debug)]
pub struct Client {
    stream: UnixStream,
    path: String,
}

impl Client {
    /// Connects as this process's user. See [`Client::connect_as`].
    pub fn connect(endpoint: &Endpoint, timeout: Duration) -> Result<Self, Error> {
        Self::connect_as(endpoint, timeout, sys::current_uid())
    }

    /// Connects to `endpoint` if, and only if, it is `uid`'s:
    ///
    /// 1. For `$XDG_RUNTIME_DIR/morrow/island.sock`, the folder is a real
    ///    directory `uid` owns with mode `0700`.
    /// 2. `lstat` says the path is a socket `uid` owns; a symlink is refused
    ///    even when it points to `uid`'s socket.
    /// 3. The connect completes within `timeout`.
    /// 4. The kernel says the listener is `uid` (`SO_PEERCRED` /
    ///    `getpeereid`), which covers a file swapped after step 2.
    ///
    /// Any error means: send nothing (for a hook, exit 0).
    pub fn connect_as(endpoint: &Endpoint, timeout: Duration, uid: u32) -> Result<Self, Error> {
        let path = socket_path(endpoint)?;
        if let Some(dir) = endpoint.private_dir() {
            check_private_dir(dir, uid)?;
        }
        require_own_socket(path, uid)?;
        let stream =
            connect_stream(path, timeout).map_err(|source| io_error("connect", path, source))?;
        verify_peer(&stream, path, uid)?;
        Ok(Self {
            stream,
            path: path.to_owned(),
        })
    }

    /// Writes all of `request`, half-closes the write side so the island
    /// reads EOF, then reads the reply until the island closes.
    ///
    /// `io_timeout` bounds each read and write call, not the whole exchange:
    /// a request that waits for the user (a permission prompt) passes a long
    /// one or `None`. An empty reply is a valid answer.
    pub fn send_and_wait(
        self,
        request: &[u8],
        io_timeout: Option<Duration>,
    ) -> Result<Vec<u8>, Error> {
        self.send(request, io_timeout)?.wait(io_timeout)
    }

    /// The first half of [`Client::send_and_wait`]: writes all of `request`
    /// and half-closes, each write bounded by `write_timeout`. A caller
    /// with a deadline for the send but none for the reply (a hook that
    /// waits for the user) lifts its deadline in between.
    pub fn send(
        mut self,
        request: &[u8],
        write_timeout: Option<Duration>,
    ) -> Result<PendingReply, Error> {
        let path = self.path.as_str();
        let io = |op| move |source| io_error(op, path, source);
        self.stream
            .set_write_timeout(write_timeout)
            .map_err(io("set write timeout on"))?;
        self.stream.write_all(request).map_err(io("write to"))?;
        self.stream
            .shutdown(Shutdown::Write)
            .map_err(io("half-close"))?;
        Ok(PendingReply {
            stream: self.stream,
            path: self.path,
        })
    }
}

/// A request [`Client::send`] wrote and half-closed, its reply not read yet.
#[derive(Debug)]
pub struct PendingReply {
    stream: UnixStream,
    path: String,
}

impl PendingReply {
    /// Reads the reply until the island closes, each read bounded by
    /// `read_timeout` (`None`: as long as it takes). An empty reply is a
    /// valid answer.
    pub fn wait(mut self, read_timeout: Option<Duration>) -> Result<Vec<u8>, Error> {
        let path = self.path.as_str();
        let io = |op| move |source| io_error(op, path, source);
        self.stream
            .set_read_timeout(read_timeout)
            .map_err(io("set read timeout on"))?;
        let mut reply = Vec::new();
        self.stream
            .read_to_end(&mut reply)
            .map_err(io("read reply from"))?;
        Ok(reply)
    }
}

/// `connect(2)` that gives up after `timeout`, blocking again once
/// connected. A listener whose queue is full fails at once on Linux
/// (`EAGAIN`) rather than waiting.
pub(super) fn connect_stream(path: &str, timeout: Duration) -> std::io::Result<UnixStream> {
    let socket = Socket::new(Domain::UNIX, Type::STREAM, None)?;
    socket.connect_timeout(&SockAddr::unix(path)?, timeout)?;
    socket.set_nonblocking(false)?;
    Ok(UnixStream::from(OwnedFd::from(socket)))
}
