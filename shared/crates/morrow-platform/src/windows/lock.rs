//! Screen lock through WTS (#107).
//!
//! `WTSSessionInfoEx` reports the session's connection state, and a locked
//! workstation is `WTS_SESSIONSTATE_LOCK` in its flags. `loginctl`'s
//! `LockedHint` on Linux is the same question; this is the Windows way to ask
//! it, and it needs no service beyond the one Windows always runs.

use windows::Win32::System::RemoteDesktop::{
    WTS_CURRENT_SESSION, WTSFreeMemory, WTSINFOEXW, WTSQuerySessionInformationW, WTSSessionInfoEx,
};
use windows::core::PWSTR;

/// `WTS_SESSIONSTATE_LOCK` is 0 and `WTS_SESSIONSTATE_UNLOCK` is 1 in
/// `WTSINFOEX_LEVEL1_W::SessionFlags`: the state is the whole value, not a bit.
const WTS_SESSIONSTATE_UNLOCK: i32 = 1;

/// Whether the screen is locked. `None` when the session cannot say, which the
/// caller treats as unlocked — a machine where WTS answers nothing still has a
/// working island.
pub fn locked() -> Option<bool> {
    unsafe {
        let mut buffer = PWSTR::null();
        let mut bytes = 0u32;
        WTSQuerySessionInformationW(
            None,
            WTS_CURRENT_SESSION,
            WTSSessionInfoEx,
            &mut buffer,
            &mut bytes,
        )
        .ok()?;
        if buffer.is_null() || (bytes as usize) < size_of::<WTSINFOEXW>() {
            if !buffer.is_null() {
                WTSFreeMemory(buffer.0.cast());
            }
            return None;
        }
        let info = &*(buffer.0.cast::<WTSINFOEXW>());
        let flags = info.Data.WTSInfoExLevel1.SessionFlags;
        WTSFreeMemory(buffer.0.cast());
        // Anything other than "unlocked" counts as locked: a screensaver or a
        // session that has not settled is not a good moment for a card either.
        Some(flags != WTS_SESSIONSTATE_UNLOCK)
    }
}
