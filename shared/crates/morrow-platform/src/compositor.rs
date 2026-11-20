//! Which desktop this is, and whether the panel can anchor itself to the screen
//! (#109, plan §6.4).
//!
//! On a compositor that speaks `wlr-layer-shell` the island is a layer surface:
//! it sits above everything, stays out of the keyboard's way, and survives a
//! fullscreen app. GNOME (Mutter) does not have the protocol, and the plan is
//! explicit that this is **stated** rather than simulated: the panel becomes an
//! ordinary window and Settings says "anchoring is not available here".
//!
//! The detection is environment variables, which is what a Wayland session
//! leaves behind, so all of it is testable on a machine that has never run
//! Wayland.

/// The desktop, as far as anchoring is concerned.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Compositor {
    /// Sway, Hyprland, KDE Plasma (KWin), COSMIC, niri, labwc, Wayfire, river:
    /// every one of them implements `wlr-layer-shell`.
    LayerShell,
    /// Mutter: no layer-shell, so no anchoring.
    Gnome,
    /// A Wayland session we do not know. It may or may not have the protocol,
    /// so the answer says what it is unsure about instead of guessing.
    UnknownWayland,
    /// X11: the panel is placed by the window manager, which is a different
    /// mechanism and not a degraded one.
    X11,
}

impl Compositor {
    /// The compositor named by the session's environment, or `None` for a
    /// session with no display at all (a test harness, a headless CI run).
    pub fn detect(env: &impl Fn(&str) -> Option<String>) -> Option<Self> {
        let session = env("XDG_SESSION_TYPE").map(|value| value.to_ascii_lowercase());
        let desktop = env("XDG_CURRENT_DESKTOP")
            .unwrap_or_default()
            .to_ascii_lowercase();
        let is_wayland = session.as_deref() == Some("wayland")
            || env("WAYLAND_DISPLAY").is_some_and(|value| !value.is_empty());
        if !is_wayland {
            if session.as_deref() == Some("x11") || env("DISPLAY").is_some() {
                return Some(Self::X11);
            }
            return None;
        }
        // One variable per compositor, because `XDG_CURRENT_DESKTOP` is written
        // by the desktop's session script and some compositors leave it empty.
        if env("SWAYSOCK").is_some_and(|value| !value.is_empty()) || desktop.contains("sway") {
            return Some(Self::LayerShell);
        }
        if env("HYPRLAND_INSTANCE_SIGNATURE").is_some_and(|value| !value.is_empty())
            || desktop.contains("hyprland")
        {
            return Some(Self::LayerShell);
        }
        if desktop.contains("kde") || desktop.contains("plasma") {
            return Some(Self::LayerShell);
        }
        if desktop.contains("gnome") || desktop.contains("ubuntu") {
            return Some(Self::Gnome);
        }
        for known in ["cosmic", "niri", "labwc", "wayfire", "river"] {
            if desktop.contains(known) {
                return Some(Self::LayerShell);
            }
        }
        Some(Self::UnknownWayland)
    }
}

/// Whether the island can be a layer surface, and what to tell the user when it
/// cannot.
#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize)]
pub enum Anchoring {
    /// A layer surface: above other windows, out of the keyboard's way, and
    /// above fullscreen apps.
    Available,
    /// An ordinary window that is always on top. The sentence is the one the
    /// Settings row shows, and the one the plan requires us not to paper over.
    Unavailable(String),
}

impl Anchoring {
    pub fn is_available(&self) -> bool {
        matches!(self, Self::Available)
    }

    /// The sentence under the row, if any.
    pub fn reason(&self) -> Option<&str> {
        match self {
            Self::Available => None,
            Self::Unavailable(reason) => Some(reason),
        }
    }

    /// What a non-anchoring session gets instead. One string, so the island and
    /// Settings cannot say two different things.
    pub const WINDOW_ONLY: &'static str = "Anchoring is not available on this desktop (no wlr-layer-shell); the island is a normal always-on-top window";
}

/// The answer for this session.
///
/// `packaged_as_appimage` matters: an AppImage forces `GDK_BACKEND=x11`
/// (tauri#15781), so a Wayland session running the AppImage is *not* a
/// layer-shell candidate even on Sway — the panel would sit in the X11 window
/// list with no way to anchor, and saying `Available` would be a lie the user
/// discovers only by looking at their screen.
pub fn anchoring(compositor: Option<Compositor>, packaged_as_appimage: bool) -> Anchoring {
    match compositor {
        Some(Compositor::LayerShell) if packaged_as_appimage => Anchoring::Unavailable(
            "this AppImage runs through X11 (tauri#15781): install the .deb or .rpm for a Wayland session"
                .to_owned(),
        ),
        Some(Compositor::LayerShell) | Some(Compositor::X11) => Anchoring::Available,
        Some(Compositor::Gnome) => Anchoring::Unavailable(Anchoring::WINDOW_ONLY.to_owned()),
        Some(Compositor::UnknownWayland) => Anchoring::Unavailable(
            "this Wayland session does not say which compositor it is; the island is a normal window until it does"
                .to_owned(),
        ),
        None => Anchoring::Unavailable("no display: nothing to anchor to".to_owned()),
    }
}

/// The answer for the machine this runs on.
pub fn current() -> Anchoring {
    anchoring(
        Compositor::detect(&|name| std::env::var(name).ok()),
        std::env::var_os("APPIMAGE").is_some(),
    )
}
