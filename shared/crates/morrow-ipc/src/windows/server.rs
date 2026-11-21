use std::io;
use std::time::Duration;

use windows::Win32::Foundation::{
    CloseHandle, ERROR_ACCESS_DENIED, ERROR_PIPE_CONNECTED, HANDLE, HLOCAL, LocalFree,
};
use windows::Win32::Security::Authorization::ConvertStringSecurityDescriptorToSecurityDescriptorW;
use windows::Win32::Security::SECURITY_ATTRIBUTES;
use windows::Win32::Storage::FileSystem::{
    FILE_FLAG_FIRST_PIPE_INSTANCE, PIPE_ACCESS_DUPLEX, ReadFile, WriteFile,
};
use windows::Win32::System::Pipes::{
    ConnectNamedPipe, CreateNamedPipeW, DisconnectNamedPipe, GetNamedPipeClientProcessId,
    PIPE_READMODE_MESSAGE, PIPE_REJECT_REMOTE_CLIENTS, PIPE_TYPE_MESSAGE, PIPE_WAIT,
};
use windows::core::HSTRING;

use super::{Error, MAX_MESSAGE, io_error, pipe_name, sys};
use crate::Endpoint;
use crate::pipe::{is_sid, security_descriptor};

/// The island's listener at an endpoint (contract §2.3, §3.2).
///
/// One pipe instance at a time, as the Unix server accepts one connection at a
/// time: a second client waits in the pipe's queue rather than being refused.
/// The instance is created with `FILE_FLAG_FIRST_PIPE_INSTANCE` and a
/// descriptor that names this user only, so a process that got the name first
/// keeps it and one running as another user cannot open ours.
#[derive(Debug)]
pub struct Server {
    handle: HANDLE,
    path: String,
    /// The client SID of the connection currently accepted, if any.
    connected: bool,
}

/// An accepted connection whose server-verified client we do not need: the
/// descriptor already admits this user only, and the client checks *us*.
#[derive(Debug)]
pub struct Connection {
    handle: HANDLE,
    peer_pid: u32,
}

impl Server {
    pub fn bind(endpoint: &Endpoint) -> Result<Self, Error> {
        let path = pipe_name(endpoint)?.to_owned();
        // The SID comes from the token, not from the endpoint's text: an
        // override may name a pipe anywhere, but the descriptor is always ours.
        let sid = sys::current_sid().map_err(|source| Error::NoSid { source })?;
        if !is_sid(&sid) {
            return Err(Error::NoSid {
                source: io::Error::other("the token's SID is not a SID"),
            });
        }
        let descriptor = security_descriptor(&sid);

        unsafe {
            let mut attributes = SECURITY_ATTRIBUTES {
                nLength: size_of::<SECURITY_ATTRIBUTES>() as u32,
                lpSecurityDescriptor: std::ptr::null_mut(),
                bInheritHandle: windows::core::BOOL::from(false),
            };
            let sddl = HSTRING::from(descriptor);
            let mut raw = windows::Win32::Security::PSECURITY_DESCRIPTOR::default();
            ConvertStringSecurityDescriptorToSecurityDescriptorW(
                &sddl, 1, // SDDL_REVISION_1
                &mut raw, None,
            )
            .map_err(|error| Error::NoSid {
                source: io::Error::other(format!("the security descriptor was refused: {error}")),
            })?;
            attributes.lpSecurityDescriptor = raw.0;

            let name = HSTRING::from(path.as_str());
            let handle = CreateNamedPipeW(
                &name,
                PIPE_ACCESS_DUPLEX | FILE_FLAG_FIRST_PIPE_INSTANCE,
                PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
                1,
                MAX_MESSAGE as u32,
                MAX_MESSAGE as u32,
                0,
                Some(&attributes),
            );
            let _ = LocalFree(Some(HLOCAL(raw.0)));

            if handle.is_invalid() {
                let source = io::Error::last_os_error();
                // ERROR_ACCESS_DENIED is what a name already held by a first
                // instance answers: either our own earlier island or another
                // user's pipe, and both mean "do not start a second one".
                if source.raw_os_error() == Some(ERROR_ACCESS_DENIED.0 as i32) {
                    return Err(Error::AlreadyRunning { path });
                }
                return Err(io_error("create", &path, source));
            }
            Ok(Self {
                handle,
                path,
                connected: false,
            })
        }
    }

    /// The pipe name, for the log and for tests.
    pub fn path(&self) -> &str {
        &self.path
    }

    /// Waits for a client, blocking as `accept(2)` does.
    pub fn accept(&mut self) -> Result<Connection, Error> {
        if self.connected {
            // One instance serves one connection: close the last one first.
            unsafe {
                let _ = DisconnectNamedPipe(self.handle);
            }
            self.connected = false;
        }
        match unsafe { ConnectNamedPipe(self.handle, None) } {
            Ok(()) => {}
            Err(error) if error.code() == ERROR_PIPE_CONNECTED.to_hresult() => {}
            Err(error) => {
                return Err(io_error("accept on", &self.path, io::Error::other(error)));
            }
        }
        self.connected = true;
        let mut peer_pid = 0u32;
        let _ = unsafe { GetNamedPipeClientProcessId(self.handle, &mut peer_pid) };
        Ok(Connection {
            handle: self.handle,
            peer_pid,
        })
    }
}

// A Win32 handle is valid in any thread of the process: the shell accepts on a
// thread of its own, so both of these have to cross.
unsafe impl Send for Server {}
unsafe impl Send for Connection {}

impl Drop for Server {
    fn drop(&mut self) {
        unsafe {
            if self.connected {
                let _ = DisconnectNamedPipe(self.handle);
            }
            let _ = CloseHandle(self.handle);
        }
    }
}

impl Connection {
    /// The process at the other end, for the log.
    pub fn peer_pid(&self) -> u32 {
        self.peer_pid
    }

    /// Reads the request: one message, which is where the client's write ended.
    pub fn read_request(&mut self) -> io::Result<Vec<u8>> {
        let mut buffer = vec![0u8; MAX_MESSAGE];
        let mut read = 0u32;
        match unsafe {
            ReadFile(
                self.handle,
                Some(buffer.as_mut_slice()),
                Some(&mut read),
                None,
            )
        } {
            Ok(()) => {}
            Err(error) => return Err(io::Error::other(error)),
        }
        buffer.truncate(read as usize);
        Ok(buffer)
    }

    /// Writes the whole reply as one message and closes the connection.
    pub fn reply(self, reply: &[u8]) -> io::Result<()> {
        let mut written = 0u32;
        unsafe {
            WriteFile(self.handle, Some(reply), Some(&mut written), None)
                .map_err(io::Error::other)?;
        }
        Ok(())
    }

    /// Whether the client has gone. A pipe has no `poll`; asking for the
    /// client's process id fails once the connection is torn down, which is the
    /// same answer at the same cost.
    pub fn peer_gone(&self) -> bool {
        let mut pid = 0u32;
        unsafe { GetNamedPipeClientProcessId(self.handle, &mut pid) }.is_err()
    }

    /// No-op: a named pipe has no per-call timeout to set, and the caller's own
    /// deadline covers the wait. Present so the shell reads the same on both.
    pub fn set_read_timeout(&self, _timeout: Option<Duration>) -> io::Result<()> {
        Ok(())
    }
}
