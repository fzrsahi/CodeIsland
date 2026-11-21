//! Jumping to a session's terminal (#103, L-009).
//!
//! Three ways in, tried in the order that gets closest to the *window*:
//! a compositor that can focus by app id (sway, Hyprland), an X11 window
//! manager (`wmctrl`/`xdotool`), and — always available — copying the working
//! path, which is L-009's floor: a click that does nothing is worse than a
//! click that hands you the path.

use std::path::PathBuf;

use crate::runner::Runner;

/// What a session knows about where it runs.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Target {
    /// The terminal's app id or class, e.g. `Alacritty`, `kitty`, `org.gnome.Terminal`.
    pub app: Option<String>,
    /// The pseudo-terminal, e.g. `/dev/pts/3`.
    pub tty: Option<String>,
    /// What to hand over when a window cannot be focused.
    pub cwd: Option<PathBuf>,
}

impl Target {
    /// What the copy fallback produces: the working directory, then the tty.
    pub fn copy_text(&self) -> Option<String> {
        self.cwd
            .as_ref()
            .map(|cwd| cwd.display().to_string())
            .or_else(|| self.tty.clone())
    }
}

/// What a click achieved.
#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize)]
pub enum Outcome {
    /// The window was focused.
    Focused,
    /// No window could be focused; this text is on the clipboard instead.
    Copied(String),
    /// Neither: the compositor offers no window API and there was nothing to
    /// copy. The card shows this rather than pretending.
    NotPossible(String),
}

/// Jump to the terminal. Never returns an error: every failure ends as a
/// clipboard fallback or an explanation.
pub fn activate(runner: &dyn Runner, target: &Target) -> Outcome {
    let failures = match focus_window(runner, target) {
        Ok(()) => return Outcome::Focused,
        Err(failures) => failures,
    };
    if let Some(text) = target.copy_text() {
        if copy_to_clipboard(runner, &text).is_ok() {
            return Outcome::Copied(text);
        }
    }
    Outcome::NotPossible(failures.join("; "))
}

/// Try each window API, collecting why the ones that failed did.
fn focus_window(runner: &dyn Runner, target: &Target) -> Result<(), Vec<String>> {
    let mut failures: Vec<String> = Vec::new();

    // sway: the tree names a window by app_id and pid.
    if let Ok(tree) = runner.run("swaymsg", &["-t", "get_tree", "-r"]) {
        match sway_window_id(&tree, target) {
            Some(id) => match runner.run("swaymsg", &[&format!("[con_id={id}]"), "focus"]) {
                Ok(_) => return Ok(()),
                Err(error) => failures.push(format!("swaymsg focus: {error}")),
            },
            None => failures.push("sway: no window for this session".to_owned()),
        }
    }

    // Hyprland: clients carry a class and an address.
    if let Ok(clients) = runner.run("hyprctl", &["clients", "-j"]) {
        match hyprland_address(&clients, target) {
            Some(address) => {
                match runner.run(
                    "hyprctl",
                    &["dispatch", "focuswindow", &format!("address:{address}")],
                ) {
                    Ok(_) => return Ok(()),
                    Err(error) => failures.push(format!("hyprctl focuswindow: {error}")),
                }
            }
            None => failures.push("hyprland: no window for this session".to_owned()),
        }
    }

    // X11: wmctrl can activate by class, xdotool by class and window.
    if let Some(app) = target.app.as_deref() {
        if runner.run("wmctrl", &["-a", app]).is_ok() {
            return Ok(());
        }
        if let Ok(windows) = runner.run("xdotool", &["search", "--class", app]) {
            if let Some(id) = windows.split_whitespace().next() {
                if runner.run("xdotool", &["windowactivate", id]).is_ok() {
                    return Ok(());
                }
            }
        }
        failures.push(format!("no window for {app}"));
    } else {
        failures.push("the session named no terminal".to_owned());
    }

    Err(failures)
}

/// The focused candidate in a `swaymsg -t get_tree -r` document: a leaf whose
/// `app_id` (Wayland) or `window_properties.class` (XWayland) matches, and whose
/// pid is the session's when both are known.
pub fn sway_window_id(tree: &str, target: &Target) -> Option<i64> {
    let root: serde_json::Value = serde_json::from_str(tree).ok()?;
    let mut stack = vec![&root];
    while let Some(node) = stack.pop() {
        if matches_id(node, target) {
            if let Some(id) = node.get("id").and_then(serde_json::Value::as_i64) {
                return Some(id);
            }
        }
        if let Some(nodes) = node.get("nodes").and_then(serde_json::Value::as_array) {
            stack.extend(nodes.iter());
        }
        if let Some(nodes) = node
            .get("floating_nodes")
            .and_then(serde_json::Value::as_array)
        {
            stack.extend(nodes.iter());
        }
    }
    None
}

fn matches_id(node: &serde_json::Value, target: &Target) -> bool {
    let Some(app) = target.app.as_deref() else {
        return false;
    };
    let app_id = node.get("app_id").and_then(serde_json::Value::as_str);
    let class = node
        .get("window_properties")
        .and_then(|properties| properties.get("class"))
        .and_then(serde_json::Value::as_str);
    app_id.is_some_and(|value| value.eq_ignore_ascii_case(app))
        || class.is_some_and(|value| value.eq_ignore_ascii_case(app))
}

/// The address of the matching client in `hyprctl clients -j`.
pub fn hyprland_address(clients: &str, target: &Target) -> Option<String> {
    let app = target.app.as_deref()?;
    let list: serde_json::Value = serde_json::from_str(clients).ok()?;
    list.as_array()?
        .iter()
        .find(|client| {
            client
                .get("class")
                .and_then(serde_json::Value::as_str)
                .is_some_and(|class| class.eq_ignore_ascii_case(app))
        })
        .and_then(|client| client.get("address").and_then(serde_json::Value::as_str))
        .map(str::to_owned)
}

fn copy_to_clipboard(runner: &dyn Runner, text: &str) -> Result<(), String> {
    for (program, args) in [
        ("wl-copy", vec![]),
        ("xclip", vec!["-selection", "clipboard"]),
    ] {
        let mut command_args = args.clone();
        command_args.push(text);
        if runner.run(program, &command_args).is_ok() {
            return Ok(());
        }
    }
    Err("no clipboard tool (wl-copy or xclip)".to_owned())
}
