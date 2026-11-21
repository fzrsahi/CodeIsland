//! The adapters' Windows half (#107): the same abilities the Unix modules get by
//! running a tool, reached through the API Windows actually offers.
//!
//! | Unix ran | Windows uses | module |
//! |---|---|---|
//! | `playerctl` (MPRIS) | SMTC through WinRT | [`media`] |
//! | `wpctl`/`pactl` | Core Audio's endpoint volume | [`volume`] |
//! | `loginctl` `LockedHint` | WTS session information | [`lock`] |
//! | `_NET_WM_STATE_FULLSCREEN` | `SHQueryUserNotificationState` | [`fullscreen`] |
//! | `notify-send` | WinRT toasts | [`toast`] |
//! | `~/.config/autostart/*.desktop` | `HKCU\…\Run` through `reg.exe` | [`autostart`] |
//! | `swaymsg`/`wmctrl` by class | a window whose process owns the session | [`terminal`] |
//! | `GetCursorPos` under X11 | `GetCursorPos`, which is always global here | [`pointer`] |
//!
//! The pure parts — which window belongs to a session, what a notification state
//! means, how a path is quoted into a registry value — live in
//! `morrow_platform::windows_rules`, so they are tested on any machine. What is
//! left here needs Windows, and is compile-checked by
//! `scripts/ci/windows-check.sh`.

// Every call in this module is Win32/WinRT; the workspace denies `unsafe_code`
// everywhere else and stays that way.
#![allow(unsafe_code)]

pub mod autostart;
pub mod fullscreen;
pub mod lock;
pub mod media;
pub mod pointer;
pub mod terminal;
pub mod toast;
pub mod volume;
