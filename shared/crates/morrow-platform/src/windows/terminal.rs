//! Jumping to a session's terminal on Windows (#107).
//!
//! There is no app-id protocol to focus by, so the window is found the way a user
//! would: the session runs under a process, that process's chain ends in a
//! terminal (Windows Terminal, `conhost`, WezTerm…), and that terminal's window
//! is raised. Which pid to look for is `windows_rules::terminal_pid`, tested on
//! any machine; this file is the window enumeration.

use std::collections::BTreeMap;

use windows::Win32::Foundation::{HWND, LPARAM};
use windows::Win32::UI::WindowsAndMessaging::{
    EnumWindows, GetWindowTextW, GetWindowThreadProcessId, IsWindowVisible, SW_RESTORE,
    SetForegroundWindow, ShowWindow,
};
use windows::core::BOOL;

use crate::windows_rules::{Parents, terminal_pid};

/// The processes a session's terminal is likely to be.
pub const HOSTS: [&str; 6] = [
    "windows terminal",
    "windowsterminal",
    "conhost",
    "wezterm",
    "alacritty",
    "kitty",
];

/// What a click achieved, mirroring `terminal::Outcome` on Unix.
pub fn activate(parents: &Parents, pid: u32, names: &BTreeMap<u32, String>) -> Result<(), String> {
    let target = terminal_pid(parents, pid, &HOSTS, names);
    let window = find_window(target).ok_or_else(|| format!("no window for process {target}"))?;
    unsafe {
        // `SW_RESTORE` also un-minimises, which is what "bring my terminal back"
        // means; `SetForegroundWindow` is allowed here because the click came
        // from a foreground process.
        let _ = ShowWindow(window, SW_RESTORE);
        SetForegroundWindow(window)
            .ok()
            .map_err(|error| error.message())
    }
}

/// The first visible, titled top-level window owned by `pid`.
fn find_window(pid: u32) -> Option<HWND> {
    struct Search {
        pid: u32,
        found: Option<HWND>,
    }
    unsafe extern "system" fn visit(window: HWND, lparam: LPARAM) -> BOOL {
        let search = unsafe { &mut *(lparam.0 as *mut Search) };
        let mut owner = 0u32;
        unsafe {
            GetWindowThreadProcessId(window, Some(&mut owner));
            if owner == search.pid && IsWindowVisible(window).as_bool() && !title(window).is_empty()
            {
                search.found = Some(window);
                // Stop enumerating: the first window is the one.
                return BOOL(0);
            }
        }
        BOOL(1)
    }
    let mut search = Search { pid, found: None };
    unsafe {
        let _ = EnumWindows(Some(visit), LPARAM((&raw mut search) as isize));
    }
    search.found
}

fn title(window: HWND) -> String {
    let mut buffer = [0u16; 256];
    let length = unsafe { GetWindowTextW(window, &mut buffer) };
    String::from_utf16_lossy(&buffer[..length as usize])
}
