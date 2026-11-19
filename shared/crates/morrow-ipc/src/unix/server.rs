use std::fs::{self, DirBuilder, Permissions};
use std::io::{self, Read, Write};
use std::os::unix::fs::{DirBuilderExt, FileTypeExt, MetadataExt, PermissionsExt};
use std::os::unix::net::{SocketAddr, UnixListener, UnixStream};
use std::time::Duration;

use super::client::connect_stream;
use super::{Error, Holder, check_private_dir, holder, io_error, socket_path, sys, verify_peer};
use crate::Endpoint;

/// How long `bind` waits for an existing socket to answer before it decides.
const PROBE_TIMEOUT: Duration = Duration::from_secs(1);

/// The island's listener at an endpoint (contract §2.3, §3.2). Dropping it
/// closes the socket and removes the socket file it made, and no other file.
#[derive(Debug)]
pub struct Server {
    listener: UnixListener,
    path: String,
    uid: u32,
    /// Device and inode of the socket file `bind` made.
    made: (u64, u64),
}

/// An accepted connection whose peer the kernel says is this user.
#[derive(Debug)]
pub struct Connection {
    stream: UnixStream,
    peer_uid: u32,
}

impl Server {
    /// Binds as this process's user. See [`Server::bind_as`].
    pub fn bind(endpoint: &Endpoint) -> Result<Self, Error> {
        Self::bind_as(endpoint, sys::current_uid())
    }

    /// Listens at `endpoint` for `uid`:
    ///
    /// 1. A path no socket address can hold is refused before anything is
    ///    touched.
    /// 2. For `$XDG_RUNTIME_DIR/morrow/island.sock`, the folder is made with
    ///    mode `0700` if absent, then must be a real directory `uid` owns
    ///    with no group or other bits. It is never `chmod`ed.
    /// 3. Something already at the path is probed before anything is
    ///    removed. A socket of `uid`'s that answers, from a listener the
    ///    kernel says is `uid`: [`Error::AlreadyRunning`] (one island per
    ///    endpoint). One that refuses the connection is stale (its island
    ///    crashed) and is removed. Anything that is not `uid`'s socket is
    ///    refused and left alone.
    /// 4. Binds with umask `077`, then sets the socket file to `0600`.
    ///
    /// The probe opens a connection and sends nothing; a running island
    /// reads an empty request and should drop it.
    pub fn bind_as(endpoint: &Endpoint, uid: u32) -> Result<Self, Error> {
        let path = socket_path(endpoint)?;
        let address = SocketAddr::from_pathname(path).map_err(|source| Error::InvalidPath {
            path: path.into(),
            source,
        })?;
        if let Some(dir) = endpoint.private_dir() {
            ensure_private_dir(dir, uid)?;
        }
        match holder(path, uid)? {
            Holder::Nobody => {}
            Holder::NotASocket => return Err(Error::NotASocket { path: path.into() }),
            Holder::OtherUser(owner) => {
                return Err(Error::OtherUser {
                    path: path.into(),
                    owner,
                    expected: uid,
                });
            }
            Holder::ThisUser(found) => match connect_stream(path, PROBE_TIMEOUT) {
                Ok(stream) => {
                    verify_peer(&stream, path, uid)?;
                    return Err(Error::AlreadyRunning { path: path.into() });
                }
                Err(e) if e.kind() == io::ErrorKind::ConnectionRefused => {
                    remove_if_same_socket(path, &found)?;
                }
                // Gone between lstat and connect: nothing to remove.
                Err(e) if e.kind() == io::ErrorKind::NotFound => {}
                // A timeout or a full queue is a listener that is alive.
                Err(source) => return Err(io_error("probe", path, source)),
            },
        }

        let listener = sys::with_umask(0o077, || UnixListener::bind_addr(&address))
            .map_err(|source| io_error("bind", path, source))?;
        fs::set_permissions(path, Permissions::from_mode(0o600))
            .map_err(|source| io_error("chmod", path, source))?;
        let made = fs::symlink_metadata(path).map_err(|source| io_error("lstat", path, source))?;
        Ok(Self {
            listener,
            path: path.to_owned(),
            uid,
            made: (made.dev(), made.ino()),
        })
    }

    /// Waits for the next connection. A peer the kernel says is not this
    /// server's uid is closed at once and returned as
    /// [`Error::PeerNotUser`] for the caller to log; the listener is fine,
    /// keep accepting.
    pub fn accept(&self) -> Result<Connection, Error> {
        let (stream, _) = self
            .listener
            .accept()
            .map_err(|source| io_error("accept on", &self.path, source))?;
        verify_peer(&stream, &self.path, self.uid)?;
        Ok(Connection {
            stream,
            peer_uid: self.uid,
        })
    }

    /// The socket path, as resolved.
    pub fn path(&self) -> &str {
        &self.path
    }
}

impl Drop for Server {
    /// Removes the socket file `bind` made, and not a file that has taken its
    /// place since (contract §2.3 step 4).
    fn drop(&mut self) {
        let ours = fs::symlink_metadata(&self.path).is_ok_and(|meta| {
            meta.file_type().is_socket() && (meta.dev(), meta.ino()) == self.made
        });
        if ours {
            let _ = fs::remove_file(&self.path);
        }
    }
}

impl Connection {
    /// The peer's uid (always the server's: anyone else is refused).
    pub fn peer_uid(&self) -> u32 {
        self.peer_uid
    }

    /// The stream, to set timeouts on.
    pub fn stream(&self) -> &UnixStream {
        &self.stream
    }

    /// Reads the request: everything until the client half-closes.
    pub fn read_request(&mut self) -> io::Result<Vec<u8>> {
        let mut request = Vec::new();
        self.stream.read_to_end(&mut request)?;
        Ok(request)
    }

    /// Writes the whole reply and closes the connection.
    pub fn reply(mut self, reply: &[u8]) -> io::Result<()> {
        self.stream.write_all(reply)?;
        self.stream.flush()
    }
}

/// Makes `dir` with mode `0700` if it is absent, then checks it, whoever
/// made it.
fn ensure_private_dir(dir: &str, uid: u32) -> Result<(), Error> {
    match DirBuilder::new().mode(0o700).create(dir) {
        Ok(()) => {}
        Err(e) if e.kind() == io::ErrorKind::AlreadyExists => {}
        Err(source) => return Err(io_error("create folder", dir, source)),
    }
    check_private_dir(dir, uid)
}

/// Removes the stale socket at `path` if it is still the file the probe
/// looked at: never one another island bound in the meantime.
fn remove_if_same_socket(path: &str, found: &fs::Metadata) -> Result<(), Error> {
    let now = match fs::symlink_metadata(path) {
        Ok(now) => now,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(source) => return Err(io_error("lstat", path, source)),
    };
    if !now.file_type().is_socket() || (now.dev(), now.ino()) != (found.dev(), found.ino()) {
        return Err(io_error(
            "remove stale socket",
            path,
            io::Error::other("the file changed while it was probed"),
        ));
    }
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(source) => Err(io_error("remove stale socket", path, source)),
    }
}
