//! The cursor position (#107).
//!
//! Unlike Wayland, Windows answers this for the whole desktop: the island uses
//! it to know whether the pointer is still over the panel, and to keep a card
//! from vanishing under a cursor that is on its way to a button.

use windows::Win32::Foundation::POINT;
use windows::Win32::UI::WindowsAndMessaging::GetCursorPos;

/// The pointer, in virtual-screen pixels, or `None` when the call fails (a
/// session with no input desktop).
pub fn position() -> Option<(i32, i32)> {
    let mut point = POINT::default();
    unsafe { GetCursorPos(&mut point) }.ok()?;
    Some((point.x, point.y))
}
