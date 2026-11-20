//! The two things only the OS can answer on Windows: this user's SID, and the
//! SID of the process behind a pipe.

use std::io;

use windows::Win32::Foundation::{CloseHandle, HANDLE, HLOCAL, LocalFree};
use windows::Win32::Security::Authorization::ConvertSidToStringSidW;
use windows::Win32::Security::{GetTokenInformation, TOKEN_QUERY, TOKEN_USER, TokenUser};
use windows::Win32::System::Pipes::GetNamedPipeServerProcessId;
use windows::Win32::System::Threading::{
    GetCurrentProcess, OpenProcess, OpenProcessToken, PROCESS_QUERY_LIMITED_INFORMATION,
};

/// This process's user, as `S-1-5-21-…`.
pub fn current_sid() -> io::Result<String> {
    unsafe {
        let mut token = HANDLE::default();
        OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token)?;
        let sid = token_user_sid(token);
        let _ = CloseHandle(token);
        sid
    }
}

/// The user SID of the process that created the pipe end `handle` is attached
/// to. The id is the server's, so this answers "who is listening", not "who
/// called me".
pub fn server_sid(handle: HANDLE) -> io::Result<String> {
    unsafe {
        let mut pid = 0u32;
        GetNamedPipeServerProcessId(handle, &mut pid)?;
        let process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid)?;
        let mut token = HANDLE::default();
        let opened = OpenProcessToken(process, TOKEN_QUERY, &mut token);
        let _ = CloseHandle(process);
        opened?;
        let sid = token_user_sid(token);
        let _ = CloseHandle(token);
        sid
    }
}

/// The SID out of a token, as a string; the caller closes the token.
unsafe fn token_user_sid(token: HANDLE) -> io::Result<String> {
    // Two calls: the first asks how much room the SID needs.
    let mut needed = 0u32;
    let _ = unsafe { GetTokenInformation(token, TokenUser, None, 0, &mut needed) };
    if needed == 0 {
        return Err(io::Error::last_os_error());
    }
    let mut buffer = vec![0u8; needed as usize];
    unsafe {
        GetTokenInformation(
            token,
            TokenUser,
            Some(buffer.as_mut_ptr().cast()),
            needed,
            &mut needed,
        )?;
        let user = &*(buffer.as_ptr().cast::<TOKEN_USER>());
        sid_to_string(user.User.Sid)
    }
}

unsafe fn sid_to_string(sid: windows::Win32::Security::PSID) -> io::Result<String> {
    let mut string = windows::core::PWSTR::null();
    unsafe {
        ConvertSidToStringSidW(sid, &mut string)?;
    }
    let value = unsafe { string.to_string() };
    let _ = unsafe { LocalFree(Some(HLOCAL(string.0.cast()))) };
    value.map_err(|_| io::Error::other("the SID is not valid Unicode"))
}
