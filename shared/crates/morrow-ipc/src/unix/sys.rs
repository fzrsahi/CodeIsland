//! The calls std does not offer on stable: the process's uid, the umask,
//! the credentials of the process at the other end of a Unix socket, and
//! whether that process has closed it. Every unsafe block of the crate is
//! here.
#![allow(unsafe_code)]

use std::io;
use std::os::fd::AsRawFd;
use std::os::unix::net::UnixStream;

/// The real uid of this process.
pub(crate) fn current_uid() -> u32 {
    // SAFETY: getuid(2) takes no arguments, cannot fail and touches no memory.
    unsafe { libc::getuid() }
}

/// Runs `f` with the process umask set to `mask`, then puts the old one
/// back. The umask is process-wide: a file another thread creates meanwhile
/// gets `mask` too, which can only make it more private.
pub(crate) fn with_umask<T>(mask: libc::mode_t, f: impl FnOnce() -> T) -> T {
    // SAFETY: umask(2) only swaps an integer in the process; it cannot fail.
    let previous = unsafe { libc::umask(mask) };
    let result = f();
    // SAFETY: as above.
    unsafe { libc::umask(previous) };
    result
}

/// The uid the peer of `stream` had when it called `connect` or `listen`,
/// as the kernel recorded it: `SO_PEERCRED` on Linux.
#[cfg(any(target_os = "linux", target_os = "android"))]
pub(crate) fn peer_uid(stream: &UnixStream) -> io::Result<u32> {
    let mut cred = libc::ucred {
        pid: 0,
        uid: 0,
        gid: 0,
    };
    let mut len = std::mem::size_of::<libc::ucred>() as libc::socklen_t;
    // SAFETY: the fd is a live socket borrowed from `stream`; `cred` and
    // `len` are valid for writes and `len` holds `cred`'s size.
    let rc = unsafe {
        libc::getsockopt(
            stream.as_raw_fd(),
            libc::SOL_SOCKET,
            libc::SO_PEERCRED,
            (&raw mut cred).cast(),
            &mut len,
        )
    };
    if rc != 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(cred.uid)
}

/// The uid the peer of `stream` had when it called `connect` or `listen`,
/// as the kernel recorded it: `getpeereid` (macOS and the BSDs).
#[cfg(not(any(target_os = "linux", target_os = "android")))]
pub(crate) fn peer_uid(stream: &UnixStream) -> io::Result<u32> {
    let mut uid: libc::uid_t = 0;
    let mut gid: libc::gid_t = 0;
    // SAFETY: the fd is a live socket borrowed from `stream`; `uid` and
    // `gid` are valid for writes.
    let rc = unsafe { libc::getpeereid(stream.as_raw_fd(), &mut uid, &mut gid) };
    if rc != 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(uid)
}

/// Whether the peer of `stream` has closed its end, without waiting:
/// `POLLHUP` or `POLLERR`. A peer that only half-closed (`shutdown(SHUT_WR)`,
/// a bridge waiting for its answer) sets neither (Swift
/// `HookConnection.finishIfPeerGone`).
pub(crate) fn peer_closed(stream: &UnixStream) -> io::Result<bool> {
    let mut check = libc::pollfd {
        fd: stream.as_raw_fd(),
        events: libc::POLLOUT,
        revents: 0,
    };
    // SAFETY: `check` is one valid pollfd for a live socket borrowed from
    // `stream`; the count is 1 and the timeout 0, so poll(2) never blocks.
    let rc = unsafe { libc::poll(&raw mut check, 1, 0) };
    if rc < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(rc > 0 && check.revents & (libc::POLLHUP | libc::POLLERR) != 0)
}
