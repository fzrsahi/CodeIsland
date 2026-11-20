use std::io;
use std::time::{Duration, Instant};

use windows::Win32::Foundation::{
    CloseHandle, ERROR_PIPE_BUSY, GENERIC_READ, GENERIC_WRITE, HANDLE,
};
use windows::Win32::Storage::FileSystem::{
    CreateFileW, FILE_ATTRIBUTE_NORMAL, FILE_SHARE_NONE, OPEN_EXISTING, ReadFile, WriteFile,
};
use windows::Win32::System::Pipes::WaitNamedPipeW;
use windows::core::HSTRING;

use super::{Error, MAX_MESSAGE, io_error, pipe_name, sys};
use crate::Endpoint;

/// A connection to the island at an endpoint, made only after the checks of
/// contract §2.2 / §3.2 pass. One request, one reply (`send_and_wait`).
#[derive(Debug)]
pub struct Client {
    handle: HANDLE,
    path: String,
}

impl Client {
    /// Connects as this process's user. See [`Client::connect_as`].
    pub fn connect(endpoint: &Endpoint, timeout: Duration) -> Result<Self, Error> {
        Self::connect_as(endpoint, timeout, &sys::current_sid().unwrap_or_default())
    }

    /// Connects to `endpoint` if, and only if, the server behind it is `sid`'s:
    ///
    /// 1. The name is a pipe (`\\.\pipe\…`).
    /// 2. A busy pipe is waited on, but not past `timeout`.
    /// 3. The server's process token carries `sid`. A pipe another user created
    ///    under this name is refused here, before a byte is sent — the
    ///    counterpart of the Unix `SO_PEERCRED` check, and it covers a server
    ///    that started after the descriptor was written.
    ///
    /// Any error means: send nothing (for a hook, exit 0).
    pub fn connect_as(endpoint: &Endpoint, timeout: Duration, sid: &str) -> Result<Self, Error> {
        let path = pipe_name(endpoint)?.to_owned();
        let handle = open(&path, timeout)?;
        let server = sys::server_sid(handle)
            .map_err(|source| io_error("read the token of", &path, source))?;
        if !sid.is_empty() && server != sid {
            unsafe {
                let _ = CloseHandle(handle);
            }
            return Err(Error::PeerNotUser { path });
        }
        Ok(Self { handle, path })
    }

    /// The pipe name, for the log.
    pub fn path(&self) -> &str {
        &self.path
    }

    /// Writes the request as one message, then reads the one reply.
    pub fn send_and_wait(
        self,
        request: &[u8],
        io_timeout: Option<Duration>,
    ) -> Result<Vec<u8>, Error> {
        self.send(request, io_timeout)?.wait(io_timeout)
    }

    /// The first half of [`send_and_wait`](Self::send_and_wait): one write,
    /// which ends the request because the pipe is in message mode.
    pub fn send(
        self,
        request: &[u8],
        _write_timeout: Option<Duration>,
    ) -> Result<PendingReply, Error> {
        if request.len() > MAX_MESSAGE {
            unsafe {
                let _ = CloseHandle(self.handle);
            }
            return Err(Error::TooLarge { path: self.path });
        }
        let mut written = 0u32;
        match unsafe { WriteFile(self.handle, Some(request), Some(&mut written), None) } {
            Ok(()) => {}
            Err(error) => {
                unsafe {
                    let _ = CloseHandle(self.handle);
                }
                return Err(io_error("write to", &self.path, io::Error::other(error)));
            }
        }
        Ok(PendingReply {
            handle: self.handle,
            path: self.path,
        })
    }
}

/// A request [`Client::send`] wrote, its reply not read yet.
#[derive(Debug)]
pub struct PendingReply {
    handle: HANDLE,
    path: String,
}

impl PendingReply {
    /// Reads the reply, one message. An empty reply is a valid answer.
    pub fn wait(self, _read_timeout: Option<Duration>) -> Result<Vec<u8>, Error> {
        let mut buffer = vec![0u8; MAX_MESSAGE];
        let mut read = 0u32;
        let result = unsafe {
            ReadFile(
                self.handle,
                Some(buffer.as_mut_slice()),
                Some(&mut read),
                None,
            )
        };
        unsafe {
            let _ = CloseHandle(self.handle);
        }
        result.map_err(|error| io_error("read reply from", &self.path, io::Error::other(error)))?;
        buffer.truncate(read as usize);
        Ok(buffer)
    }
}

/// Opens the pipe, waiting while it is busy but no longer than `timeout` — the
/// counterpart of a connect with a deadline.
fn open(path: &str, timeout: Duration) -> Result<HANDLE, Error> {
    let name = HSTRING::from(path);
    let deadline = Instant::now() + timeout;
    loop {
        let handle = unsafe {
            CreateFileW(
                &name,
                (GENERIC_READ | GENERIC_WRITE).0,
                FILE_SHARE_NONE,
                None,
                OPEN_EXISTING,
                FILE_ATTRIBUTE_NORMAL,
                None,
            )
        };
        match handle {
            Ok(handle) if !handle.is_invalid() => return Ok(handle),
            Ok(_) | Err(_) => {
                let source = io::Error::last_os_error();
                let busy = source.raw_os_error() == Some(ERROR_PIPE_BUSY.0 as i32);
                let remaining = deadline.saturating_duration_since(Instant::now());
                if !busy || remaining.is_zero() {
                    return Err(io_error("open", path, source));
                }
                unsafe {
                    let _ = WaitNamedPipeW(&name, remaining.as_millis() as u32);
                }
            }
        }
    }
}
