//! The panel's shape (#106): which points are island and which are window-only,
//! because the corners are round and the window is not.

use morrow_platform::panel::{Panel, Rect, contains_rounded};

fn pill() -> Rect {
    // The collapsed island: 240 × 34, radius half the height.
    Rect::new(0, 0, 240, 34)
}

#[test]
fn the_middle_of_a_pill_is_island() {
    assert!(contains_rounded(pill(), 17, 120, 17));
    assert!(
        contains_rounded(pill(), 17, 0, 17),
        "the straight left edge"
    );
    assert!(
        contains_rounded(pill(), 17, 17, 5),
        "top edge, past the arc"
    );
}

#[test]
fn a_corner_of_the_window_is_not_the_island() {
    // The window's own top-left pixel: inside the box, outside the arc.
    assert!(!contains_rounded(pill(), 17, 0, 0));
    assert!(!contains_rounded(pill(), 17, 3, 1));
    assert!(contains_rounded(pill(), 17, 6, 6), "inside the arc");
    // The same, mirrored to the other three corners.
    assert!(!contains_rounded(pill(), 17, 239, 0));
    assert!(!contains_rounded(pill(), 17, 239, 33));
    assert!(!contains_rounded(pill(), 17, 0, 33));
}

#[test]
fn outside_the_box_is_never_island() {
    assert!(!contains_rounded(pill(), 17, -1, 17));
    assert!(
        !contains_rounded(pill(), 17, 240, 17),
        "right edge is exclusive"
    );
    assert!(!contains_rounded(pill(), 17, 120, 34));
}

#[test]
fn a_square_window_ignores_the_radius() {
    assert!(contains_rounded(Rect::new(0, 0, 10, 10), 0, 0, 0));
    // A radius larger than half the side is clamped to half, never borrowed
    // from the other dimension.
    assert!(contains_rounded(Rect::new(0, 0, 10, 10), 99, 5, 5));
}

#[test]
fn a_panel_offset_in_its_window_maps_the_point() {
    let panel = Panel {
        window: Rect::new(100, 200, 240, 34),
        island: Rect::new(0, 0, 240, 34),
        radius: 17,
    };
    assert!(panel.is_island(120, 17), "island coordinates");
    assert!(!panel.is_island(0, 0), "the window's corner");
}

#[test]
fn an_island_smaller_than_its_window_leaves_a_margin() {
    // The expanded card sits inside a window that has room for the shadow.
    let panel = Panel {
        window: Rect::new(100, 200, 400, 200),
        island: Rect::new(20, 10, 360, 180),
        radius: 12,
    };
    assert!(panel.is_island(300, 100), "on the card");
    assert!(!panel.is_island(5, 5), "in the shadow margin");
    assert!(
        !panel.is_island(395, 100),
        "past the card, inside the window"
    );
}
