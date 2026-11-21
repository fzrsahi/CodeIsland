//! Where the panel is, and whether a point on screen is on it (#106).
//!
//! Windows has to answer that question itself: the island's corners are round,
//! and a window rectangle cannot be round, so the last few pixels of each corner
//! are window but not island. Without this, a click aimed at the app *behind* a
//! corner is swallowed by an invisible part of the panel — the ticket's
//! "klik di luar island mengenai app di bawahnya" failing at the corners only,
//! which is exactly the kind of bug that survives a manual test.

/// A rectangle in one space (physical pixels, screen or window).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

impl Rect {
    pub fn new(x: i32, y: i32, width: i32, height: i32) -> Self {
        Self {
            x,
            y,
            width,
            height,
        }
    }

    pub fn right(self) -> i32 {
        self.x.saturating_add(self.width)
    }

    pub fn bottom(self) -> i32 {
        self.y.saturating_add(self.height)
    }

    /// Whether a point is inside, edges included.
    pub fn contains(self, x: i32, y: i32) -> bool {
        x >= self.x && x < self.right() && y >= self.y && y < self.bottom()
    }
}

/// Whether `(x, y)` is on a rounded rectangle: inside the box, and inside the
/// corner arcs when it falls in one of the four corner squares.
///
/// The radius is clamped to half the shorter side, which is what a pill
/// (`radius = height / 2`) already asks for, so a caller cannot describe a shape
/// its own rectangle does not have.
pub fn contains_rounded(rect: Rect, radius: i32, x: i32, y: i32) -> bool {
    if !rect.contains(x, y) {
        return false;
    }
    let radius = radius.clamp(0, rect.width.min(rect.height) / 2);
    if radius == 0 {
        return true;
    }
    let (left, right) = (x < rect.x + radius, x >= rect.right() - radius);
    let (top, bottom) = (y < rect.y + radius, y >= rect.bottom() - radius);
    // Only a point inside one of the four corner squares can be outside a
    // rounded box: every other point is in the straight middle of a side.
    let centre = match (left, right, top, bottom) {
        (true, _, true, _) => (rect.x + radius, rect.y + radius),
        (true, _, _, true) => (rect.x + radius, rect.bottom() - radius),
        (_, true, true, _) => (rect.right() - radius, rect.y + radius),
        (_, true, _, true) => (rect.right() - radius, rect.bottom() - radius),
        _ => return true,
    };
    let (dx, dy) = (i64::from(x - centre.0), i64::from(y - centre.1));
    dx * dx + dy * dy <= i64::from(radius) * i64::from(radius)
}

/// Where the island sits inside its window, and its shape there.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Panel {
    pub window: Rect,
    pub island: Rect,
    pub radius: i32,
}

impl Panel {
    /// Whether a point in *window* coordinates is on the island. A point on the
    /// window but not the island is where a click must reach what is below.
    ///
    /// `island` is already in window coordinates; `window` is only here so a
    /// caller can say where the window is on screen without converting twice.
    pub fn is_island(self, x: i32, y: i32) -> bool {
        contains_rounded(self.island, self.radius, x, y)
    }
}
