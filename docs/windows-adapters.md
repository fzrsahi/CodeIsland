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

## The installer and the hook (#108)

NSIS, per-user (`installMode: currentUser`): no administrator prompt, and the app
writes only inside `%LOCALAPPDATA%`, `%USERPROFILE%` and `HKCU`. That is also why
start-at-login is a `Run` value rather than a scheduled task or a service.

**Beta is unsigned.** There is no Authenticode certificate, so SmartScreen shows
"Windows protected your PC" until the user picks *More info → Run anyway*. This is
a decision recorded for #70, and it is documented on the download page rather than
worked around: the updater's own Ed25519 signature is separate and cannot be
switched off.

The hook installer (`morrow-platform::hooks_windows`) writes:

| path | what |
|---|---|
| `%USERPROFILE%\.codeisland\morrow-hook.cmd` | the script every hook command names |
| `%USERPROFILE%\.local\bin\morrow-bridge.exe` | the bridge, copied out of the package |
| `%CLAUDE_CONFIG_DIR%\settings.json` (or `%USERPROFILE%\.claude\settings.json`) | the user's file, backed up once, never rewritten when it does not parse |

The command recorded in `settings.json` is the **absolute, quoted** path of the
`.cmd`: Claude Code hands the string to `cmd.exe`, which splits on spaces, and a
profile folder can contain one. `%USERPROFILE%` would work in most contexts and
fail in the one nobody tested.

Only Claude Code is hooked by this build. The other eight CLIs' files are read by
the same core policy, but their Windows locations are a follow-up: a path of
`~/.codex/config.toml` on Windows names a file that does not exist, and Settings
says so in a sentence rather than showing eight rows that do nothing.
