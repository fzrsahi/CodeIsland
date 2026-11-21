//! #103's four adapters with a scripted runner: jumping to a terminal (and
//! falling back to the path), a process that is gone, a locked screen, a
//! reminder.

use std::cell::RefCell;
use std::collections::BTreeMap;
use std::path::PathBuf;

use morrow_platform::lock::{locked, parse_locked_hint};
use morrow_platform::notify::{TIMEOUT_MS, notify};
use morrow_platform::process::{Watch, parse_start_time};
use morrow_platform::runner::Runner;
use morrow_platform::terminal::{Outcome, Target, activate, hyprland_address, sway_window_id};

struct Fake {
    answers: BTreeMap<String, String>,
    asked: RefCell<Vec<String>>,
}

impl Fake {
    fn new(answers: &[(&str, &str)]) -> Self {
        Self {
            answers: answers
                .iter()
                .map(|(command, output)| ((*command).to_owned(), (*output).to_owned()))
                .collect(),
            asked: RefCell::new(Vec::new()),
        }
    }

    fn asked(&self) -> Vec<String> {
        self.asked.borrow().clone()
    }
}

impl Runner for Fake {
    fn run(&self, program: &str, args: &[&str]) -> Result<String, String> {
        let command = format!("{program} {}", args.join(" "));
        self.asked.borrow_mut().push(command.clone());
        self.answers
            .get(&command)
            .cloned()
            .ok_or_else(|| format!("{program}: not scripted ({command})"))
    }
}

fn target() -> Target {
    Target {
        app: Some("Alacritty".into()),
        tty: Some("/dev/pts/3".into()),
        cwd: Some(PathBuf::from("/home/u/project")),
    }
}

// MARK: - Terminal jump

const SWAY_TREE: &str = r#"{"id":1,"type":"root","nodes":[{"id":9,"app_id":"Alacritty","nodes":[]},{"id":11,"app_id":"firefox","nodes":[]}]}"#;

#[test]
fn sway_is_asked_first_and_focused_by_id() {
    let fake = Fake::new(&[
        ("swaymsg -t get_tree -r", SWAY_TREE),
        ("swaymsg [con_id=9] focus", ""),
    ]);
    assert_eq!(activate(&fake, &target()), Outcome::Focused);
    assert_eq!(
        fake.asked(),
        vec!["swaymsg -t get_tree -r", "swaymsg [con_id=9] focus"]
    );
}

#[test]
fn a_nested_xwayland_window_is_found_by_its_class() {
    let tree = r#"{"id":1,"nodes":[{"id":4,"nodes":[{"id":7,"app_id":null,"window_properties":{"class":"Alacritty"}}]}]}"#;
    assert_eq!(sway_window_id(tree, &target()), Some(7));
    assert_eq!(sway_window_id(tree, &Target::default()), None);
    assert_eq!(sway_window_id("not json", &target()), None);
}

#[test]
fn hyprland_is_the_second_choice() {
    let clients =
        r#"[{"address":"0x55a","class":"firefox"},{"address":"0x99b","class":"Alacritty"}]"#;
    assert_eq!(
        hyprland_address(clients, &target()).as_deref(),
        Some("0x99b")
    );

    let fake = Fake::new(&[
        ("hyprctl clients -j", clients),
        ("hyprctl dispatch focuswindow address:0x99b", ""),
    ]);
    assert_eq!(activate(&fake, &target()), Outcome::Focused);
}

#[test]
fn x11_falls_back_to_wmctrl() {
    let fake = Fake::new(&[("wmctrl -a Alacritty", "")]);
    assert_eq!(activate(&fake, &target()), Outcome::Focused);
}

#[test]
fn no_window_still_hands_over_the_path() {
    // L-009: the copy fallback is always attempted before giving up.
    let fake = Fake::new(&[("wl-copy /home/u/project", "")]);
    assert_eq!(
        activate(&fake, &target()),
        Outcome::Copied("/home/u/project".into())
    );
}

#[test]
fn without_a_clipboard_tool_the_click_explains_itself() {
    let target = Target {
        app: Some("Alacritty".into()),
        tty: None,
        cwd: None,
    };
    match activate(&Fake::new(&[]), &target) {
        Outcome::NotPossible(reason) => assert!(!reason.is_empty(), "{reason}"),
        other => panic!("expected an explanation, got {other:?}"),
    }
}

#[test]
fn a_session_without_a_terminal_still_copies_its_tty() {
    let target = Target {
        app: None,
        tty: Some("/dev/pts/7".into()),
        cwd: None,
    };
    let fake = Fake::new(&[("xclip -selection clipboard /dev/pts/7", "")]);
    assert_eq!(
        activate(&fake, &target),
        Outcome::Copied("/dev/pts/7".into())
    );
}

// MARK: - Process table

#[test]
fn start_time_skips_a_command_name_full_of_parens() {
    // `state` onwards; the 22nd field overall is the start time.
    let stat = "4242 (weird) name) S 1 4242 4242 0 -1 4194560 100 0 0 0 5 3 0 0 20 0 1 0 987654 1000 100 184 0 0 0";
    assert_eq!(parse_start_time(stat), Some(987_654));
    assert_eq!(parse_start_time("garbage"), None);
    assert_eq!(parse_start_time("1 (x) S"), None);
}

#[test]
fn a_watch_notices_a_pid_that_is_gone() {
    // A pid that cannot exist on Linux: `Watch::new` answers None.
    assert_eq!(Watch::new(i64::MAX / 2), None);
}

// MARK: - Screen lock

#[test]
fn locked_hint_is_read_as_a_plain_yes_or_no() {
    assert_eq!(parse_locked_hint("LockedHint=yes\n"), Some(true));
    assert_eq!(parse_locked_hint("LockedHint=no\n"), Some(false));
    assert_eq!(parse_locked_hint("LockedHint=unknown\n"), None);
    assert_eq!(parse_locked_hint("nothing here\n"), None);
}

#[test]
fn loginctl_is_asked_for_just_that_property() {
    let fake = Fake::new(&[(
        "loginctl show-session auto --property=LockedHint",
        "LockedHint=yes\n",
    )]);
    // No XDG_SESSION_ID in the test process: `auto` names the caller's session.
    assert_eq!(locked(&fake), Some(true));
    assert_eq!(
        fake.asked(),
        vec!["loginctl show-session auto --property=LockedHint"]
    );
}

#[test]
fn a_session_that_cannot_say_is_not_locked() {
    let fake = Fake::new(&[]);
    assert_eq!(locked(&fake), None);
}

// MARK: - Notifications

#[test]
fn a_reminder_goes_through_notify_send() {
    let fake = Fake::new(&[(
        "notify-send --app-name=Morrow --icon=morrow --expire-time=8000 Stretch Stand up",
        "",
    )]);
    notify(&fake, "Stretch", "Stand up").expect("sent");
    assert_eq!(TIMEOUT_MS, 8_000);
    assert_eq!(
        fake.asked(),
        vec!["notify-send --app-name=Morrow --icon=morrow --expire-time=8000 Stretch Stand up"]
    );
}

#[test]
fn a_missing_notify_send_is_an_error_the_caller_logs() {
    assert!(notify(&Fake::new(&[]), "Stretch", "Stand up").is_err());
}
