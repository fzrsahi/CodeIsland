#!/usr/bin/env bash
# X11 smoke of the panel (#90): Xvfb + Openbox, a target window that records
# clicks (xev), morrow-app, and two hooks through the release morrow-bridge.
# Checks that the panel is above, out of the taskbar, never focused, sized
# to the island at the top centre, and that clicks outside the island reach
# the target, collapsed and expanded. Prints an Evidence block.
#
# Runs inside the image of linux/ci/Dockerfile, from the repo root:
#   (cd shared/desktop && bun install && bun run build)   # on the host
#   docker run --rm -v "$PWD":/work morrow-tauri-x11:dev linux/ci/smoke-x11.sh
#
# Env: MORROW_APP, MORROW_BRIDGE (binaries; built when unset),
#      SMOKE_SCREEN (default 1920x1080), SMOKE_COMMIT (for the Evidence block
#      when git cannot read the checkout, e.g. a worktree), CARGO_TARGET_DIR.
# Exit: 0 when every check passed, 1 otherwise.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
NAME=smoke-x11
# shellcheck source=linux/ci/x11-lib.sh
. linux/ci/x11-lib.sh

SCREEN="${SMOKE_SCREEN:-1920x1080}"
SW="${SCREEN%x*}"
SH="${SCREEN#*x}"

x11_binaries
x11_workdir
x11_xvfb_openbox
x11_target
x11_start_app

hook() {
  printf '{"session_id":"%s","hook_event_name":"PreToolUse","cwd":"%s","tool_name":"Bash","tool_input":{"command":"ls"}}' "$1" "$2" |
    "$MORROW_BRIDGE"
}
t_hook=$(now_ms)
hook smoke-1 /home/dev/alpha
t_hook1=$(now_ms)
hook smoke-2 /home/dev/beta
t_hook2=$(now_ms)
until_ok 5 grep -q 'pushed sessions=2' "$WORK/app.out" || die "the island never showed 2 sessions: $(cat "$WORK/app.out")"
t_pushed=$(now_ms)
sleep 0.3 # let the frontend lay out and fit

# --- checks -------------------------------------------------------------
fits() { grep -c 'morrow-smoke: fit' "$WORK/app.out" || true; }
# click_island <x> <y>: a click there is the island's: the window is refitted
# (it toggled) and the target saw nothing.
click_island() {
  local before fitted
  before="$(clicks)"
  fitted="$(fits)"
  xdotool mousemove --sync "$1" "$2" click 1
  until_ok 2 sh -c "[ \$(grep -c 'morrow-smoke: fit' '$WORK/app.out') -gt $fitted ]" || return 1
  sleep 0.2
  [ "$(clicks)" = "$before" ]
}
small_top_centre() { # of the last geometry
  [ $((W * H * 20)) -lt $((SW * SH)) ] && [ "$Y" -le 1 ] &&
    [ $(((2 * X + W - SW) * (2 * X + W - SW))) -le 4 ]
}

x11_window_checks

geometry "$ISLAND"
collapsed="${W}x${H}+${X}+${Y}"
check collapsed_small_top_centre "$collapsed on ${SW}x${SH}" small_top_centre
check focus_kept_after_show "active $(xdotool getactivewindow), target $TARGET" focused_is_target

# The macOS panel's rectangle (PanelWindowController.panelSize): 760 wide,
# screen high. A point inside it but outside the island must reach the target.
ox=$((SW / 2 - 300))
oy=$((SH / 2))
check outside_click_reaches_target "click ($ox,$oy), inside a 760x${SH} panel" click_reaches_target "$ox" "$oy"

# Expand: a click on the island grows the window to the list.
cx=$((X + W / 2))
cy=$((Y + H / 2))
check island_click_expands "click ($cx,$cy): refit, target saw nothing" click_island "$cx" "$cy"
geometry "$ISLAND"
expanded="${W}x${H}+${X}+${Y}"
exp_h=$H
check expanded_grows "$collapsed -> $expanded" test "$expanded" != "$collapsed" -a "$H" -gt 34
check expanded_small_top_centre "$expanded" small_top_centre
check focus_kept_after_island_click "active $(xdotool getactivewindow)" focused_is_target
by=$((Y + H + 8))
check click_below_expanded_reaches_target "click ($cx,$by)" click_reaches_target "$cx" "$by"

# Collapse: the window shrinks back, and where the list was is the target's.
check island_click_collapses "click ($cx,$cy): refit, target saw nothing" click_island "$cx" "$cy"
geometry "$ISLAND"
recollapsed="${W}x${H}+${X}+${Y}"
check collapse_shrinks "$expanded -> $recollapsed" test "$recollapsed" = "$collapsed"
gy=$((exp_h - 6))
check click_where_list_was_reaches_target "click ($cx,$gy)" click_reaches_target "$cx" "$gy"
check focus_kept_at_end "active $(xdotool getactivewindow)" focused_is_target

# One island per endpoint: a second morrow-app exits 0 at once.
second_instance_exits() {
  timeout 10 "$MORROW_APP" 2>"$WORK/second.err" && grep -q 'already listens' "$WORK/second.err"
}
check second_instance_exits_0 "same MORROW_SOCKET_PATH" second_instance_exits

# --- Evidence -----------------------------------------------------------
echo
echo "=== Evidence: linux/ci/smoke-x11.sh ==="
echo "date:      $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "commit:    ${SMOKE_COMMIT:-$(git -c safe.directory="$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)}"
echo "display:   Xvfb ${SW}x${SH}x24, $(openbox --version | head -n1), no compositor"
echo "webkit:    WEBKIT_DISABLE_COMPOSITING_MODE=1 LIBGL_ALWAYS_SOFTWARE=1"
echo "windows:   target $TARGET (xev), island $ISLAND"
echo "geometry:  collapsed $collapsed, expanded $expanded, collapsed again $recollapsed"
echo "fits:      $(grep -c 'morrow-smoke: fit' "$WORK/app.out") ($(grep 'morrow-smoke: fit' "$WORK/app.out" | sed 's/morrow-smoke: fit //' | sed -n 's/.*w=\([0-9]*\) h=\([0-9]*\).*/\1x\2/p' | tr '\n' ' '))"
echo "timings:   app start -> island subscribed $((t_shown - t_app)) ms;" \
  "bridge hook 1 $((t_hook1 - t_hook)) ms, hook 2 $((t_hook2 - t_hook1)) ms;" \
  "hooks sent -> sessions=2 pushed $((t_pushed - t_hook)) ms"
echo "clicks on target: $(clicks)"
printf '%s\n' "${results[@]}"
if [ "$failed" -eq 0 ]; then
  echo "result:    PASS (${#results[@]} checks)"
else
  echo "result:    FAIL"
  echo "--- app stderr ---"
  tail -n 20 "$WORK/app.err"
fi
exit "$failed"
