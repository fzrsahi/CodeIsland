//! The Windows adapters' decisions, checked on a machine that is not Windows
//! (#107): which process owns the terminal, what a notification state means, and
//! how a path survives being written into the registry.

use std::collections::BTreeMap;

use morrow_platform::capability::{Capability, Environment, Os, table};
use morrow_platform::windows_rules::{NotificationState, Parents, run_value, terminal_pid};

fn parents(pairs: &[(u32, u32)]) -> Parents {
    pairs.iter().copied().collect()
}

fn names(pairs: &[(u32, &str)]) -> BTreeMap<u32, String> {
    pairs
        .iter()
        .map(|(pid, name)| (*pid, (*name).to_owned()))
        .collect()
}

// MARK: - Which window is the terminal

#[test]
fn the_outermost_terminal_wins_not_the_nearest_shell() {
    // claude(300) → zsh(200) → tmux(150) → iTerm/WezTerm(100) → explorer(4)
    let parents = parents(&[(300, 200), (200, 150), (150, 100), (100, 4)]);
    let names = names(&[
        (300, "claude.exe"),
        (200, "zsh.exe"),
        (150, "tmux.exe"),
        (100, "wezterm-gui.exe"),
        (4, "explorer.exe"),
    ]);
    assert_eq!(
        terminal_pid(&parents, 300, &["wezterm"], &names),
        100,
        "the window the user can see is the terminal's, not the shell's"
    );
}

#[test]
fn a_chain_with_no_terminal_names_the_session_itself() {
    let parents = parents(&[(300, 4)]);
    let names = names(&[(300, "claude.exe"), (4, "explorer.exe")]);
    assert_eq!(
        terminal_pid(&parents, 300, &["wezterm", "conhost"], &names),
        300
    );
}

#[test]
fn a_cycle_stops_instead_of_spinning() {
    let parents = parents(&[(1, 2), (2, 1)]);
    let names = names(&[(1, "a.exe"), (2, "b.exe")]);
    assert_eq!(terminal_pid(&parents, 1, &["wezterm"], &names), 1);
}

#[test]
fn the_match_is_case_insensitive_because_process_names_are() {
    let parents = parents(&[(10, 1)]);
    let names = names(&[(10, "WindowsTerminal.exe")]);
    assert_eq!(terminal_pid(&parents, 10, &["windowsterminal"], &names), 10);
}

// MARK: - The shell's notification state

#[test]
fn a_fullscreen_app_is_stepped_around() {
    assert!(
        NotificationState::from_code(3).fullscreen(),
        "QUNS_RUNNING_D3D_FULL_SCREEN"
    );
    assert!(
        NotificationState::from_code(4).fullscreen(),
        "QUNS_PRESENTATION_MODE"
    );
    assert!(
        !NotificationState::from_code(5).fullscreen(),
        "QUNS_ACCEPTS_NOTIFICATIONS"
    );
    assert!(!NotificationState::from_code(2).fullscreen(), "QUNS_BUSY");
}

#[test]
fn a_card_may_interrupt_only_when_the_user_is_actually_there() {
    assert!(NotificationState::from_code(5).may_interrupt());
    assert!(!NotificationState::from_code(2).may_interrupt(), "busy");
    assert!(
        !NotificationState::from_code(6).may_interrupt(),
        "quiet time"
    );
    assert!(
        !NotificationState::from_code(1).may_interrupt(),
        "not present"
    );
    assert!(
        NotificationState::from_code(99).may_interrupt(),
        "a value this build does not know is not a reason to swallow a permission prompt"
    );
}

// MARK: - The registry value

#[test]
fn a_path_without_spaces_is_left_alone() {
    assert_eq!(
        run_value(r"C:\Morrow\Morrow.exe", &["--minimised"]),
        r"C:\Morrow\Morrow.exe --minimised"
    );
}

#[test]
fn a_path_with_a_space_is_quoted_for_the_registry() {
    assert_eq!(
        run_value(r"C:\Program Files\Morrow\Morrow.exe", &[]),
        "\"C:\\Program Files\\Morrow\\Morrow.exe\""
    );
}

#[test]
fn a_trailing_backslash_does_not_escape_the_closing_quote() {
    // `CommandLineToArgvW` reads `"C:\dir\"` as a literal `"`, so the backslash
    // is doubled — but only when the path has to be quoted at all, which is why
    // a bare `C:\dir\` is left alone above.
    assert_eq!(
        run_value(r"C:\Program Files\dir\", &[]),
        "\"C:\\Program Files\\dir\\\\\""
    );
}

#[test]
fn an_empty_argument_is_still_an_argument() {
    assert_eq!(run_value("morrow.exe", &[""]), "morrow.exe \"\"");
}

// MARK: - The capability table, as Windows

fn windows_environment() -> Environment {
    Environment {
        os: Os::Windows,
        session_type: None,
        has_session_bus: false,
        path_tools: vec![r"C:\Windows\System32".into()],
        config_home: std::path::PathBuf::from(r"C:\Users\u\.config"),
        claude_credentials: std::path::PathBuf::from(r"C:\Users\u\.claude\.credentials.json"),
        has_portal_shortcuts: false,
        appimage: false,
    }
}

#[test]
fn windows_answers_the_rows_linux_cannot() {
    let environment = windows_environment();
    let capability = |name: &str| -> Capability {
        table(&environment)
            .into_iter()
            .find(|row| row.feature == name)
            .unwrap_or_else(|| panic!("no row named {name}"))
            .capability
    };
    // The rows the Linux table refuses or degrades, and Windows does not.
    assert!(capability("Fullscreen detection").is_supported());
    assert!(capability("Screen lock").is_supported());
    assert!(capability("Notifications").is_supported());
    assert!(
        capability("Now Playing").is_supported(),
        "SMTC, no playerctl"
    );
    assert!(
        capability("System volume").is_supported(),
        "Core Audio, no wpctl"
    );
    assert!(capability("Jump to terminal").is_supported());
    assert!(
        capability("Start at login").is_supported(),
        "the registry, not ~/.config"
    );
}

#[test]
fn windows_says_what_it_cannot_do_too() {
    let environment = windows_environment();
    let row = table(&environment)
        .into_iter()
        .find(|row| row.feature == "Terminal visibility")
        .expect("a row");
    assert!(!row.capability.is_supported());
    assert!(
        row.capability
            .reason()
            .is_some_and(|reason| reason.contains("visible")),
        "{:?}",
        row.capability
    );
}

#[test]
fn lyrics_still_need_a_network_tool_on_windows() {
    let mut environment = windows_environment();
    environment.path_tools.clear();
    let row = table(&environment)
        .into_iter()
        .find(|row| row.feature == "Lyrics")
        .expect("a row");
    assert!(!row.capability.is_supported(), "no curl, no lrclib");
}
