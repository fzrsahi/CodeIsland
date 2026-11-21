//! The panel window (GLOSSARY.md: Panel, Tight-fit window): frameless,
//! transparent, always on top, out of the taskbar, never focused, and
//! exactly as big as the island, at the top centre of the primary monitor.
//! Clicks outside the island land on the app underneath because the window
//! is not there; no click-through API is used.

use tauri::{
    App, Manager, PhysicalPosition, PhysicalSize, PhysicalUnit, PixelUnit, Runtime, State,
    WebviewUrl, WebviewWindow, WebviewWindowBuilder, WindowSizeConstraints,
};

pub const LABEL: &str = "island";

/// The collapsed pill before the frontend has measured it, in logical
/// pixels: about the macOS collapsed island on a screen without a notch
/// (`NotchPanelView.effectiveNotchHeight`, 34 pt).
const COLLAPSED: (f64, f64) = (240.0, 34.0);

/// `MORROW_SMOKE=1`: print each fit and each card's buttons on stdout for
/// linux/ci/smoke-x11.sh and linux/ci/e2e1.sh.
pub struct Smoke(pub bool);

/// Whether the island is a layer surface or an ordinary always-on-top window,
/// and the sentence the UI shows when it is the latter (#109).
///
/// On a compositor with `wlr-layer-shell` this *is* the seam a layer surface
/// would be created at: tao upstream closed both PRs (plan §6.4), so a build
/// that anchors needs the pinned patch, and until that decision is made the
/// window path stays and the reason is reported instead of guessed at.
#[tauri::command]
pub fn anchoring() -> morrow_platform::compositor::Anchoring {
    morrow_platform::compositor::current()
}

pub fn create(app: &App) -> tauri::Result<()> {
    let window = WebviewWindowBuilder::new(app, LABEL, WebviewUrl::default())
        .title("Morrow")
        .decorations(false)
        .transparent(true)
        .always_on_top(true)
        .skip_taskbar(true)
        // tao: GTK accept-focus false, so the window manager never gives it
        // focus, when it maps or when it is clicked (plan §6.2).
        .focusable(false)
        .focused(false)
        // GTK keeps a non-resizable window at its natural size and ignores
        // resizes, so the window is resizable and `fit` pins it instead:
        // minimum = maximum = the island, which the user cannot resize.
        .resizable(true)
        .inner_size(COLLAPSED.0, COLLAPSED.1)
        .visible(false)
        .build()?;
    fit(&window, COLLAPSED.0, COLLAPSED.1, app.state::<Smoke>().0)?;
    // A panel without its Windows hooks still shows; it only behaves like an
    // ordinary window, which is worth a log line rather than no island at all.
    // Where the island lives on this desktop, said once at startup so a log
    // answers "why is it not above my fullscreen app?" (#109).
    if let Some(reason) = morrow_platform::compositor::current().reason() {
        println!("morrow: {reason}");
    }
    #[cfg(windows)]
    if let Err(error) = crate::windows_panel::install(&window) {
        eprintln!("morrow: the panel's Windows hooks were not installed: {error}");
    }
    window.show()
}

/// The frontend's measure of the island, in logical pixels: the window
/// takes that size and is centred again.
#[tauri::command]
pub fn set_island_size(
    window: WebviewWindow,
    smoke: State<'_, Smoke>,
    width: f64,
    height: f64,
) -> Result<(), String> {
    if !(width.is_finite() && height.is_finite() && width >= 1.0 && height >= 1.0) {
        return Err(format!("not an island size: {width}×{height}"));
    }
    fit(&window, width, height, smoke.0).map_err(|e| e.to_string())
}

/// A rectangle in the window, in logical pixels.
#[derive(serde::Deserialize)]
pub struct Rect {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
}

/// A Question card opened or closed: on Windows the panel takes keyboard focus
/// for as long as it is open, and gives it back when it closes (#106). On other
/// platforms the window can always be focused, so this is a no-op.
#[tauri::command]
pub fn island_question_focus(window: WebviewWindow, open: bool) -> Result<(), String> {
    #[cfg(windows)]
    return crate::windows_panel::set_question_focus(&window, open);
    #[cfg(not(windows))]
    {
        let _ = (window, open);
        Ok(())
    }
}

/// The frontend laid out card `id` and fitted the window to it. Smoke mode
/// prints the Approve and Deny buttons in window pixels and the time, so
/// the E2E-1 gate clicks them and times the card. Otherwise nothing.
#[tauri::command]
pub fn smoke_card(
    window: WebviewWindow,
    smoke: State<'_, Smoke>,
    id: u64,
    approve: Rect,
    deny: Rect,
) {
    if !smoke.0 {
        return;
    }
    let at = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_millis());
    let scale = window.scale_factor().unwrap_or(1.0);
    let px = |r: &Rect| {
        let p = |v: f64| (v * scale).round() as i64;
        format!("{},{},{},{}", p(r.x), p(r.y), p(r.width), p(r.height))
    };
    println!(
        "morrow-smoke: card id={id} approve={} deny={} at={at}",
        px(&approve),
        px(&deny)
    );
}

fn fit<R: Runtime>(
    window: &WebviewWindow<R>,
    width: f64,
    height: f64,
    smoke: bool,
) -> tauri::Result<()> {
    let monitor = match window.primary_monitor()? {
        Some(monitor) => Some(monitor),
        None => window.current_monitor()?,
    };
    let Some(monitor) = monitor else {
        // No monitor to centre on: keep the size, leave the position.
        return window.set_size(tauri::LogicalSize::new(width, height));
    };
    let scale = monitor.scale_factor();
    let area = monitor.size();
    let origin = monitor.position();
    let to_px = |logical: f64, max: u32| ((logical * scale).ceil() as u32).clamp(1, max);
    let (w, h) = (to_px(width, area.width), to_px(height, area.height));
    let x = origin.x + i32::try_from((area.width - w) / 2).unwrap_or(0);
    let y = origin.y;
    let (pw, ph) = (pixels(w), pixels(h));
    window.set_size_constraints(WindowSizeConstraints {
        min_width: Some(pw),
        min_height: Some(ph),
        max_width: Some(pw),
        max_height: Some(ph),
    })?;
    window.set_size(PhysicalSize::new(w, h))?;
    window.set_position(PhysicalPosition::new(x, y))?;
    // Windows hit-tests the rounded shape itself (#106); the island fills the
    // window here, and the two numbers travel together so a click can never be
    // answered with a stale rectangle.
    #[cfg(windows)]
    crate::windows_panel::set_panel(morrow_platform::panel::Panel {
        window: morrow_platform::panel::Rect::new(
            x,
            y,
            i32::try_from(w).unwrap_or(i32::MAX),
            i32::try_from(h).unwrap_or(i32::MAX),
        ),
        island: morrow_platform::panel::Rect::new(
            0,
            0,
            i32::try_from(w).unwrap_or(i32::MAX),
            i32::try_from(h).unwrap_or(i32::MAX),
        ),
        radius: i32::try_from(h / 2).unwrap_or(i32::MAX),
    });
    if smoke {
        println!("morrow-smoke: fit x={x} y={y} w={w} h={h}");
    }
    Ok(())
}

fn pixels(px: u32) -> PixelUnit {
    PixelUnit::Physical(PhysicalUnit::new(i32::try_from(px).unwrap_or(i32::MAX)))
}
