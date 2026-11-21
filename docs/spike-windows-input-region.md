# Spike: the input region on Windows (#106)

Recorded outcome of the "klik di luar island mengenai app di bawahnya" question.
The three candidate mechanisms, why two of them cannot work with WebView2, and
the one thing only a Windows host can confirm.

## What has to be true

The panel window is always on top and as big as the island. Three regions:

1. **On the island** — the click belongs to Morrow (buttons, cards).
2. **In the window but off the island** — a rounded corner, or the margin the
   shadow needs. The click must reach the app *below* the panel.
3. **Outside the window** — already Windows's business; the window is not there.

Region 1 and 3 are free. Region 2 is the spike, and it is small: with
`radius = 17` on a 240 × 34 pill, each corner is a 17 × 17 square of which about
a fifth is not island.

## Candidate A: `SetWindowRgn`

A region clips the window to the shape. It also clips what is *drawn*: the
rounded corners lose their antialiasing, the shadow is cut away, and the region
has to be recomputed on every `fit` — a visible flicker on each resize, for a
window that resizes whenever a card changes height. Rejected.

## Candidate B: layered window with per-pixel alpha

`WS_EX_LAYERED` + `UpdateLayeredWindow` gives exact per-pixel hit testing on
Windows 8+, which is the ideal answer on paper. But a layered window's content
is supplied by the caller through `UpdateLayeredWindow`, and WebView2 does not
render into that path. Rejected: we would be giving up the webview to buy
hit testing.

## Candidate C: answer `WM_NCHITTEST` — chosen

Keep the window a rectangle and answer the question Windows actually asks,
"what is at this point?": `HTTRANSPARENT` for a point inside the window but
off the rounded island, and let the default answer stand everywhere else.

- Nothing about drawing changes, so corners keep their CSS antialiasing and the
  shadow stays.
- The maths is `morrow_platform::panel::contains_rounded`: four corner arcs, a
  clamp for a radius larger than the side allows, and pixel-exact edges.
  `tests/panel_hit_test.rs` pins it (6 tests: pill middle, all four window
  corners, exclusive right/bottom edges, a square with radius 0, a clamped
  radius, an island smaller than its window).
- One integer comparison per click; no allocation, no region handle.

## The one thing W-005 has to confirm

`WM_NCHITTEST` goes to the window **under the cursor**. WebView2 runs in child
HWNDs, and if a child covers the whole window, the parent's procedure is not
asked for points over the child.

Two ways out, and the choice needs a real WebView2 to make:

1. Keep the webview smaller than the window, so the transparent margin belongs
   to the parent — clean, but the frontend has to know the margin.
2. Subclass the child HWND as well (found with `EnumChildWindows`) and answer
   its `WM_NCHITTEST` the same way — no frontend change, one more hook lifetime
   to manage.

`set_panel`/`panel_proc` in `shared/desktop/src-tauri/src/windows_panel.rs`
implement the parent half today, and `is_island_at` exists so a smoke test can
print the answer for a coordinate without a mouse. W-005 decides between 1 and
2, and the loser is deleted rather than left as a comment.

## What is *not* in question

`WS_EX_NOACTIVATE` (through Tauri's `focusable(false)`) plus `MA_NOACTIVATE` on
`WM_MOUSEACTIVATE` for clicks that do land on the island: without the second
one, clicking the webview of a no-activate window still raises the app's taskbar
button over whatever the user had in front. The Question card lifts
`WS_EX_NOACTIVATE` while it is open (`island_question_focus`) because a window
that never activates cannot accept typing.
