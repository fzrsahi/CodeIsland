//! Which desktop this is and whether the island can anchor (#109), checked on a
//! machine that need not have Wayland: the answers come from environment
//! variables.

use std::collections::BTreeMap;

use morrow_platform::compositor::{Anchoring, Compositor, anchoring};

fn env(pairs: &[(&str, &str)]) -> impl Fn(&str) -> Option<String> {
    let map: BTreeMap<String, String> = pairs
        .iter()
        .map(|(key, value)| ((*key).to_owned(), (*value).to_owned()))
        .collect();
    move |name| map.get(name).cloned()
}

#[test]
fn sway_is_recognised_by_its_socket_and_its_desktop_name() {
    assert_eq!(
        Compositor::detect(&env(&[
            ("XDG_SESSION_TYPE", "wayland"),
            ("SWAYSOCK", "/run/user/1000/sway-ipc.sock")
        ])),
        Some(Compositor::LayerShell)
    );
    // Some compositors leave `XDG_CURRENT_DESKTOP` empty; Sway sets SWAYSOCK.
    assert_eq!(
        Compositor::detect(&env(&[
            ("WAYLAND_DISPLAY", "wayland-1"),
            ("XDG_CURRENT_DESKTOP", "sway")
        ])),
        Some(Compositor::LayerShell)
    );
}

#[test]
fn every_desktop_the_plan_lists_anchors() {
    // Sway, Hyprland, KDE, COSMIC, niri, labwc, Wayfire, river.
    for desktop in [
        "sway", "Hyprland", "KDE", "plasma", "COSMIC", "niri", "labwc", "Wayfire", "river",
    ] {
        assert_eq!(
            Compositor::detect(&env(&[
                ("XDG_SESSION_TYPE", "wayland"),
                ("XDG_CURRENT_DESKTOP", desktop)
            ])),
            Some(Compositor::LayerShell),
            "{desktop}"
        );
    }
    assert_eq!(
        Compositor::detect(&env(&[
            ("XDG_SESSION_TYPE", "wayland"),
            ("HYPRLAND_INSTANCE_SIGNATURE", "abc")
        ])),
        Some(Compositor::LayerShell)
    );
}

#[test]
fn gnome_is_named_not_simulated() {
    let gnome = Compositor::detect(&env(&[
        ("XDG_SESSION_TYPE", "wayland"),
        ("XDG_CURRENT_DESKTOP", "ubuntu:GNOME"),
    ]));
    assert_eq!(gnome, Some(Compositor::Gnome));
    match anchoring(gnome, false) {
        Anchoring::Unavailable(reason) => {
            assert!(reason.contains("Anchoring is not available"), "{reason}");
            assert!(reason.contains("normal always-on-top window"), "{reason}");
        }
        Anchoring::Available => panic!("GNOME has no wlr-layer-shell"),
    }
}

#[test]
fn an_appimage_on_wayland_says_why_it_is_not_anchored() {
    // tauri#15781: the AppImage forces GDK_BACKEND=x11, so the layer-shell code
    // would never run — claiming otherwise is the lie the user finds by looking.
    let answer = anchoring(Some(Compositor::LayerShell), true);
    assert!(!answer.is_available());
    assert!(answer.reason().unwrap().contains("AppImage"), "{answer:?}");
    // The same session from a deb/rpm does anchor.
    assert!(anchoring(Some(Compositor::LayerShell), false).is_available());
}

#[test]
fn x11_places_the_window_and_that_is_not_a_degradation() {
    let x11 = Compositor::detect(&env(&[("DISPLAY", ":0")]));
    assert_eq!(x11, Some(Compositor::X11));
    assert_eq!(anchoring(x11, false), Anchoring::Available);
    assert_eq!(
        anchoring(x11, true),
        Anchoring::Available,
        "an AppImage is the norm here"
    );
}

#[test]
fn an_unknown_wayland_says_so_rather_than_guessing() {
    let unknown = Compositor::detect(&env(&[("WAYLAND_DISPLAY", "wayland-0")]));
    assert_eq!(unknown, Some(Compositor::UnknownWayland));
    let answer = anchoring(unknown, false);
    assert!(!answer.is_available());
    assert!(
        answer.reason().unwrap().contains("does not say"),
        "{answer:?}"
    );
}

#[test]
fn no_display_at_all_has_no_answer_to_give() {
    assert_eq!(Compositor::detect(&env(&[])), None);
    assert!(!anchoring(None, false).is_available());
}

#[test]
fn the_two_strings_the_ui_shows_agree() {
    // Settings and the island must not disagree about what is missing.
    assert!(Anchoring::WINDOW_ONLY.contains("wlr-layer-shell"));
    assert_eq!(
        anchoring(Some(Compositor::Gnome), false).reason(),
        Some(Anchoring::WINDOW_ONLY)
    );
}
