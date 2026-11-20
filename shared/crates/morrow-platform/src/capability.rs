//! What each adapter can actually do here (plan §5.2).
//!
//! Every trait gets a `probe()`, and a feature that is not supported **says so
//! in the UI** instead of failing silently. The probe is cheap and touches only
//! what it needs: an environment variable, a path, a `PATH` lookup — never a
//! connection, so Settings opens instantly.

use std::path::Path;

/// The three answers an adapter can give.
#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize)]
pub enum Capability {
    Supported,
    /// Works, with a caveat the user should see (GNOME needs an extension, a
    /// compositor is not one we know…).
    Degraded(String),
    Unsupported(String),
}

impl Capability {
    pub fn is_supported(&self) -> bool {
        matches!(self, Self::Supported)
    }

    /// The short label a Settings row shows.
    pub fn label(&self) -> &'static str {
        match self {
            Self::Supported => "Supported",
            Self::Degraded(_) => "Limited",
            Self::Unsupported(_) => "Not supported",
        }
    }

    /// The sentence under the label, if there is one.
    pub fn reason(&self) -> Option<&str> {
        match self {
            Self::Supported => None,
            Self::Degraded(reason) | Self::Unsupported(reason) => Some(reason),
        }
    }
}

/// The adapters `morrow-platform` owns. Ordered as the plan's table.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Feature {
    NowPlaying,
    Lyrics,
    SystemVolume,
    TerminalActivator,
    TerminalVisibility,
    ProcessTable,
    GlobalHotkey,
    PointerMonitor,
    Fullscreen,
    SessionLock,
    Notifications,
    SyntheticInput,
    SystemStats,
    Geolocation,
    Tray,
    Autostart,
    Secrets,
    ClaudeCredentials,
    Ble,
    Audio,
    Updater,
}

impl Feature {
    pub const ALL: &'static [Feature] = &[
        Feature::NowPlaying,
        Feature::Lyrics,
        Feature::SystemVolume,
        Feature::TerminalActivator,
        Feature::TerminalVisibility,
        Feature::ProcessTable,
        Feature::GlobalHotkey,
        Feature::PointerMonitor,
        Feature::Fullscreen,
        Feature::SessionLock,
        Feature::Notifications,
        Feature::SyntheticInput,
        Feature::SystemStats,
        Feature::Geolocation,
        Feature::Tray,
        Feature::Autostart,
        Feature::Secrets,
        Feature::ClaudeCredentials,
        Feature::Ble,
        Feature::Audio,
        Feature::Updater,
    ];

    pub fn name(self) -> &'static str {
        match self {
            Self::NowPlaying => "Now Playing",
            Self::Lyrics => "Lyrics",
            Self::SystemVolume => "System volume",
            Self::TerminalActivator => "Jump to terminal",
            Self::TerminalVisibility => "Terminal visibility",
            Self::ProcessTable => "Process table",
            Self::GlobalHotkey => "Global hotkey",
            Self::PointerMonitor => "Pointer outside the island",
            Self::Fullscreen => "Fullscreen detection",
            Self::SessionLock => "Screen lock",
            Self::Notifications => "Notifications",
            Self::SyntheticInput => "Synthetic input",
            Self::SystemStats => "System stats",
            Self::Geolocation => "Geolocation",
            Self::Tray => "Tray icon",
            Self::Autostart => "Start at login",
            Self::Secrets => "Secret storage",
            Self::ClaudeCredentials => "Claude credentials",
            Self::Ble => "Bluetooth (ESP32)",
            Self::Audio => "Sound effects",
            Self::Updater => "Updates",
        }
    }

    /// Probe one feature. `environment` is read once per call site, so a test
    /// can hand in a Wayland session or an empty `PATH` without touching the
    /// process.
    pub fn probe(self, environment: &Environment) -> Capability {
        if environment.os == Os::Windows {
            return windows(self, environment);
        }
        match self {
            // The panel is a window: these need a display to do anything.
            Self::NowPlaying => {
                if !environment.has_bus() {
                    Capability::Unsupported("no D-Bus session: MPRIS needs one".into())
                } else if environment.has("playerctl") {
                    Capability::Supported
                } else {
                    // MPRIS is a bus protocol; `playerctl` is the smallest way
                    // in without a D-Bus library of our own.
                    Capability::Degraded("needs playerctl: MPRIS is read through it".into())
                }
            }
            Self::Lyrics => {
                if environment.has_network_tool() {
                    Capability::Supported
                } else {
                    Capability::Degraded("no HTTP client on PATH: lyrics stay empty".into())
                }
            }
            Self::SystemVolume => {
                if environment.has_any(&["wpctl", "pactl"]) {
                    Capability::Supported
                } else {
                    Capability::Unsupported("needs wpctl (PipeWire) or pactl (PulseAudio)".into())
                }
            }
            Self::TerminalActivator => {
                let window_api = environment.has_any(&["swaymsg", "hyprctl", "wmctrl", "xdotool"]);
                if window_api {
                    Capability::Supported
                } else if environment.has_any(&["wl-copy", "xclip"]) {
                    // L-009: the click still lands somewhere useful.
                    Capability::Degraded(
                        "no window API here: a click copies the session's path instead".into(),
                    )
                } else {
                    Capability::Unsupported("no window API and no clipboard tool".into())
                }
            }
            Self::TerminalVisibility => {
                if environment.is_x11() {
                    Capability::Supported
                } else {
                    Capability::Unsupported("needs _NET_ACTIVE_WINDOW, which Wayland lacks".into())
                }
            }
            Self::ProcessTable => Capability::Supported,
            Self::GlobalHotkey => {
                if environment.is_x11() {
                    Capability::Supported
                } else if environment.has_portal_shortcuts {
                    Capability::Degraded(
                        "through the XDG desktop portal, as the desktop allows".into(),
                    )
                } else {
                    Capability::Unsupported(
                        "Wayland has no XGrabKey: bind `morrow toggle` in the desktop instead"
                            .into(),
                    )
                }
            }
            Self::PointerMonitor => {
                if environment.is_x11() {
                    Capability::Supported
                } else {
                    Capability::Unsupported("Wayland gives no global pointer position".into())
                }
            }
            Self::Fullscreen => {
                if environment.is_x11() {
                    Capability::Supported
                } else {
                    Capability::Unsupported(
                        "needs _NET_WM_STATE_FULLSCREEN on the active window".into(),
                    )
                }
            }
            Self::SessionLock => {
                if environment.has_bus() {
                    Capability::Supported
                } else {
                    Capability::Unsupported("needs logind on the session bus".into())
                }
            }
            Self::Notifications => {
                if environment.has("notify-send") {
                    Capability::Supported
                } else {
                    Capability::Unsupported("needs notify-send for reminders".into())
                }
            }
            Self::SyntheticInput => {
                if environment.is_x11() {
                    Capability::Supported
                } else {
                    Capability::Unsupported("needs the portal's RemoteDesktop permission".into())
                }
            }
            Self::SystemStats => Capability::Supported,
            Self::Geolocation => {
                if environment.has_bus() {
                    Capability::Degraded("through GeoClue when the desktop offers it".into())
                } else {
                    Capability::Degraded("offline city database only: no GeoClue".into())
                }
            }
            Self::Tray => {
                if environment.has("libayatana-appindicator3.so.1")
                    || environment.has("libappindicator3.so.1")
                {
                    Capability::Supported
                } else {
                    // Not a crash: the panel still works without a tray.
                    Capability::Unsupported(
                        "no AppIndicator library: the island has no tray icon".into(),
                    )
                }
            }
            Self::Autostart => {
                if environment.config_home.is_dir() {
                    Capability::Supported
                } else {
                    Capability::Unsupported("no ~/.config to write an autostart entry into".into())
                }
            }
            Self::Secrets => {
                if environment.has_bus() {
                    Capability::Supported
                } else {
                    Capability::Unsupported("secret storage needs the session bus".into())
                }
            }
            Self::ClaudeCredentials => {
                if environment.claude_credentials.is_file() {
                    Capability::Supported
                } else {
                    Capability::Degraded("no ~/.claude/.credentials.json to read".into())
                }
            }
            Self::Ble => {
                if environment.has_bus() {
                    Capability::Degraded(
                        "BlueZ through the system bus, when a adapter is present".into(),
                    )
                } else {
                    Capability::Unsupported("no system bus: Bluetooth unavailable".into())
                }
            }
            Self::Audio => Capability::Supported,
            Self::Updater => {
                if environment.appimage {
                    Capability::Degraded(
                        "an AppImage updates itself; a deb/rpm goes to apt/dnf".into(),
                    )
                } else {
                    Capability::Supported
                }
            }
        }
    }
}

/// One row of the Settings table.
#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize)]
pub struct Row {
    pub feature: &'static str,
    pub capability: Capability,
}

/// The Windows answers (#107). Every row here is a mechanism Windows has and
/// the Linux arms do not: WinRT for media and toasts, Core Audio for the volume,
/// WTS for the lock, `SHQueryUserNotificationState` for fullscreen, the registry
/// for autostart, the Credential Manager for secrets.
fn windows(feature: Feature, environment: &Environment) -> Capability {
    match feature {
        // SMTC through WinRT: no tool to find, no bus to have.
        Feature::NowPlaying => Capability::Supported,
        Feature::Lyrics => {
            if environment.has_network_tool() {
                Capability::Supported
            } else {
                Capability::Unsupported("no curl or wget to fetch lyrics".into())
            }
        }
        // Core Audio's endpoint volume: one COM interface, nothing to install.
        Feature::SystemVolume => Capability::Supported,
        // A window whose process owns the session, then `SetForegroundWindow`.
        Feature::TerminalActivator => Capability::Supported,
        // There is no `_NET_ACTIVE_WINDOW` and no per-terminal title protocol:
        // "is my terminal visible" is not a question Windows answers.
        Feature::TerminalVisibility => Capability::Unsupported(
            "Windows has no cross-application way to say whether a window is visible".into(),
        ),
        Feature::ProcessTable => Capability::Supported,
        Feature::GlobalHotkey => Capability::Supported,
        // `GetCursorPos` is global on Windows, unlike on Wayland.
        Feature::PointerMonitor => Capability::Supported,
        Feature::Fullscreen => Capability::Supported,
        Feature::SessionLock => Capability::Supported,
        Feature::Notifications => Capability::Supported,
        Feature::SyntheticInput => Capability::Supported,
        Feature::SystemStats => Capability::Supported,
        Feature::Geolocation => {
            Capability::Degraded("WinRT Geolocation, subject to the privacy setting".into())
        }
        Feature::Tray => Capability::Supported,
        // `HKCU\\…\\CurrentVersion\\Run`, one value, no administrator.
        Feature::Autostart => Capability::Supported,
        // Credential Manager: per user, no prompt beyond the first write.
        Feature::Secrets => Capability::Supported,
        Feature::ClaudeCredentials => {
            if environment.claude_credentials.is_file() {
                Capability::Supported
            } else {
                Capability::Degraded("no .claude/.credentials.json to read".into())
            }
        }
        Feature::Ble => Capability::Degraded(
            "WinRT Bluetooth LE, when the radio is on and the app is allowed".into(),
        ),
        Feature::Audio => Capability::Supported,
        Feature::Updater => Capability::Supported,
    }
}

/// Every feature, probed. This is what Settings renders.
pub fn table(environment: &Environment) -> Vec<Row> {
    Feature::ALL
        .iter()
        .map(|feature| Row {
            feature: feature.name(),
            capability: feature.probe(environment),
        })
        .collect()
}

/// Which platform's answers apply. A probe reads this instead of `cfg!` so a
/// test can hand in Windows on a Linux machine and check the table it produces.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Os {
    Linux,
    Windows,
}

impl Os {
    pub fn current() -> Self {
        if cfg!(windows) {
            Self::Windows
        } else {
            Self::Linux
        }
    }
}

/// What the probes are allowed to know: read once, from the process, or handed
/// in by a test.
#[derive(Clone, Debug)]
pub struct Environment {
    pub os: Os,
    pub session_type: Option<String>,
    pub has_session_bus: bool,
    pub path_tools: Vec<String>,
    pub config_home: std::path::PathBuf,
    pub claude_credentials: std::path::PathBuf,
    pub has_portal_shortcuts: bool,
    pub appimage: bool,
}

impl Environment {
    /// The real machine.
    pub fn probe() -> Self {
        let home = std::env::var_os("HOME").map_or_else(|| "/".into(), std::path::PathBuf::from);
        let config_home = std::env::var_os("XDG_CONFIG_HOME")
            .map_or_else(|| home.join(".config"), std::path::PathBuf::from);
        let claude_dir = std::env::var_os("CLAUDE_CONFIG_DIR")
            .map_or_else(|| home.join(".claude"), std::path::PathBuf::from);
        let session_type = std::env::var("XDG_SESSION_TYPE").ok();
        Self {
            os: Os::current(),
            session_type,
            has_session_bus: std::env::var_os("DBUS_SESSION_BUS_ADDRESS").is_some(),
            path_tools: std::env::var("PATH")
                .map(|path| path.split(':').map(str::to_owned).collect())
                .unwrap_or_default(),
            config_home,
            claude_credentials: claude_dir.join(".credentials.json"),
            has_portal_shortcuts: Path::new("/usr/share/xdg-desktop-portal/portals").is_dir(),
            appimage: std::env::var_os("APPIMAGE").is_some(),
        }
    }

    fn is_x11(&self) -> bool {
        self.session_type
            .as_deref()
            .is_some_and(|kind| kind.eq_ignore_ascii_case("x11"))
            || (self.session_type.is_none() && std::env::var_os("DISPLAY").is_some())
    }

    fn has_bus(&self) -> bool {
        self.has_session_bus
    }

    fn has(&self, tool: &str) -> bool {
        self.path_tools
            .iter()
            .any(|entry| Path::new(entry).join(tool).is_file())
            || Path::new(tool).exists()
    }

    fn has_any(&self, tools: &[&str]) -> bool {
        tools.iter().any(|tool| self.has(tool))
    }

    fn has_network_tool(&self) -> bool {
        self.has_any(&["curl", "wget"])
    }
}
