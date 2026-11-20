//! The panel's Windows half (#106).
//!
//! Tauri already gives the window the shape the ticket asks for: no decorations,
//! transparent, always on top, out of the taskbar, `focusable(false)` — which
//! tao maps to `WS_EX_NOACTIVATE` — and an island-sized rectangle. Three things
//! a window rectangle cannot do are left, and they are what this file is:
//!
//! 1. **A click on a rounded corner must reach the app behind it.** The window
//!    is a rectangle; the island is not. `WM_NCHITTEST` says `HTTRANSPARENT` for
//!    a point inside the window but outside the rounded island, so the click
//!    falls through to whatever is below ([`panel::Panel::is_island`]).
//! 2. **A click must not activate the panel.** `WS_EX_NOACTIVATE` stops the
//!    window manager, but WebView2 is a child window and clicking it asks the
//!    parent `WM_MOUSEACTIVATE`; answering `MA_NOACTIVATE` keeps the taskbar
//!    button of the app in front from being replaced by Morrow's.
//! 3. **A question must still be typable.** A no-activate window cannot take
//!    keyboard focus, so [`set_question_focus`] lifts `WS_EX_NOACTIVATE` while a
//!    Question card is open and puts it back when the card closes.
//!
//! Everything here is called from the main thread with the window's own
//! messages; the geometry itself is `morrow_platform::panel`'s, and is tested
//! where it can be.

// Every call below is Win32; the workspace denies `unsafe_code` everywhere else
// and stays that way.
#![allow(unsafe_code)]

use std::sync::Mutex;

use morrow_platform::panel::{Panel, Rect};
use tauri::WebviewWindow;
use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, POINT, WPARAM};
use windows::Win32::Graphics::Gdi::ScreenToClient;
use windows::Win32::UI::WindowsAndMessaging::{
    CallWindowProcW, DefWindowProcW, GWL_EXSTYLE, GWLP_WNDPROC, GetCursorPos, GetWindowLongPtrW,
    HTTRANSPARENT, MA_NOACTIVATE, SW_SHOWNOACTIVATE, SetForegroundWindow, SetWindowLongPtrW,
    ShowWindow, WM_MOUSEACTIVATE, WM_NCHITTEST, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW,
};

/// The island's shape inside the window, as the last `fit` left it. A
/// `Mutex<Option<…>>` rather than an atomic: the value is four numbers and the
/// window procedure reads it on the same thread that writes it.
static PANEL: Mutex<Option<Panel>> = Mutex::new(None);

/// The window procedure a subclass has to forward to.
static PREVIOUS: Mutex<Option<isize>> = Mutex::new(None);

/// Remember where the island is, before any click arrives.
pub fn set_panel(panel: Panel) {
    if let Ok(mut current) = PANEL.lock() {
        *current = Some(panel);
    }
}

/// The panel's shape now, for the window procedure and for tests.
pub fn panel() -> Option<Panel> {
    PANEL.lock().ok().and_then(|current| *current)
}

/// Take over the window's messages: hit testing, activation and the ex-style
/// flags that keep it out of the taskbar and out of the way.
pub fn install(window: &WebviewWindow) -> Result<(), String> {
    let hwnd = window.hwnd().map_err(|error| error.to_string())?;
    unsafe {
        let ex_style = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
        SetWindowLongPtrW(
            hwnd,
            GWL_EXSTYLE,
            ex_style | (WS_EX_NOACTIVATE.0 as isize) | (WS_EX_TOOLWINDOW.0 as isize),
        );
        let previous = SetWindowLongPtrW(hwnd, GWLP_WNDPROC, panel_proc as *const () as isize);
        if previous == 0 {
            return Err("the window procedure could not be replaced".to_owned());
        }
        if let Ok(mut slot) = PREVIOUS.lock() {
            *slot = Some(previous);
        }
        // `SW_SHOWNOACTIVATE`: showing the window is not a reason to take focus.
        let _ = ShowWindow(hwnd, SW_SHOWNOACTIVATE);
    }
    Ok(())
}

/// Keyboard for the Question card, and only for as long as it is open.
pub fn set_question_focus(window: &WebviewWindow, focused: bool) -> Result<(), String> {
    let hwnd = window.hwnd().map_err(|error| error.to_string())?;
    unsafe {
        let ex_style = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
        if focused {
            SetWindowLongPtrW(hwnd, GWL_EXSTYLE, ex_style & !(WS_EX_NOACTIVATE.0 as isize));
            let _ = SetForegroundWindow(hwnd);
            window.set_focus().map_err(|error| error.to_string())?;
        } else {
            SetWindowLongPtrW(hwnd, GWL_EXSTYLE, ex_style | (WS_EX_NOACTIVATE.0 as isize));
        }
    }
    Ok(())
}

/// The window procedure: answer the two questions Windows asks about a panel
/// that is not quite there, and forward everything else untouched.
unsafe extern "system" fn panel_proc(
    hwnd: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    match message {
        WM_NCHITTEST => {
            if let Some(panel) = panel() {
                let mut point = POINT::default();
                if unsafe { GetCursorPos(&mut point) }.is_ok() {
                    let mut local = point;
                    let _ = unsafe { ScreenToClient(hwnd, &mut local) };
                    if !panel.is_island(local.x, local.y) {
                        // Inside the window, outside the island: the click is
                        // not ours, so Windows hands it to what is below.
                        return LRESULT(HTTRANSPARENT as isize);
                    }
                }
            }
        }
        WM_MOUSEACTIVATE => {
            // WebView2 asks on every click; the panel never takes activation
            // for a click, or the app in front loses its taskbar.
            return LRESULT(MA_NOACTIVATE as isize);
        }
        _ => {}
    }
    let previous = PREVIOUS.lock().ok().and_then(|slot| *slot).unwrap_or(0);
    if previous == 0 {
        return unsafe { DefWindowProcW(hwnd, message, wparam, lparam) };
    }
    let previous: unsafe extern "system" fn(HWND, u32, WPARAM, LPARAM) -> LRESULT =
        unsafe { std::mem::transmute(previous) };
    unsafe { CallWindowProcW(Some(previous), hwnd, message, wparam, lparam) }
}

/// Whether a screen point is on the island, given where the window is. Exposed
/// so the shell can answer a smoke test without a click (W-005); until that
/// harness exists, nothing calls it.
#[allow(dead_code)]
pub fn is_island_at(window: Rect, island: Rect, radius: i32, x: i32, y: i32) -> bool {
    Panel {
        window,
        island,
        radius,
    }
    .is_island(x - window.x, y - window.y)
}
