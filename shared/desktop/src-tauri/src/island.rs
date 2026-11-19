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
    if smoke {
        println!("morrow-smoke: fit x={x} y={y} w={w} h={h}");
    }
    Ok(())
}

fn pixels(px: u32) -> PixelUnit {
    PixelUnit::Physical(PhysicalUnit::new(i32::try_from(px).unwrap_or(i32::MAX)))
}
