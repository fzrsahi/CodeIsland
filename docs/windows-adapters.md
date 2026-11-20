# The Windows adapters (#107)

What each adapter uses on Windows, why that and not something else, and what
only a Windows host can confirm. The Linux answers are in
[`handoff-windows-linux-port.md`](handoff-windows-linux-port.md); the Capability
table that reports these rows is `morrow-platform::capability`, and it is
probed per OS (`Environment::os`), so Settings says the truth on both.

| Ability | Linux ran | Windows uses | Verified by |
|---|---|---|---|
| Now Playing | `playerctl` (MPRIS over D-Bus) | `GlobalSystemMediaTransportControlsSessionManager` (WinRT SMTC) | W-006 |
| Volume | `wpctl` / `pactl` | `IAudioEndpointVolume` (Core Audio) | W-006 |
| Screen lock | `loginctl … LockedHint` | `WTSSessionInfoEx` → `SessionFlags` | W-007 |
| Fullscreen | `_NET_WM_STATE_FULLSCREEN` | `SHQueryUserNotificationState` | W-007 |
| Reminders | `notify-send` | `ToastNotificationManager` | W-009 (installed app) |
| Start at login | `~/.config/autostart/*.desktop` | `HKCU\…\CurrentVersion\Run` via `reg.exe` | W-009 |
| Jump to terminal | `swaymsg`/`hyprctl`/`wmctrl` by app id | the session's process chain, then `SetForegroundWindow` | W-005 |
| Pointer | X11 only | `GetCursorPos`, global here | — |
| Secrets | session bus | Credential Manager | W-008 |

## The three worth arguing about

**Toasts need an installed app.** `CreateToastNotifierWithId` takes an
application id the shell knows; from `cargo run` there is none and Windows drops
the toast silently. That is why the ticket says "test notifications with the app
installed", and why `toast::APP_ID` is the bundle identifier the NSIS installer
registers.

**`SHQueryUserNotificationState` answers two questions.** It reports
`QUNS_RUNNING_D3D_FULL_SCREEN`, `QUNS_PRESENTATION_MODE`, `QUNS_BUSY`,
`QUNS_QUIET_TIME` and `QUNS_ACCEPTS_NOTIFICATIONS`, which covers both "is
something fullscreen in front" and "may I interrupt". One call, two rows in the
table. An unknown value counts as *may interrupt*: a permission prompt that never
appears is worse than one shown a second early.

**A registry value is a command line.** `Run` holds the string Windows will
parse with `CommandLineToArgvW`, so a path with a space is quoted once and a
trailing backslash is doubled — otherwise `"C:\Program Files\Morrow\"` closes its
own quote and the argument runs into the next. `windows_rules::run_value` builds
it and `tests/windows_rules.rs` pins the four cases.

## What a compile lane cannot prove

W-005, W-006, W-007 and W-009 all need a Windows host: SMTC with a real player,
Core Audio on a device with an endpoint, WTS with a session that can actually lock,
toasts from an installed build, and a terminal whose window comes forward. The
lane proves the code compiles against the real headers and types; it cannot prove
the OS agrees.
