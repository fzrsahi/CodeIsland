# Helpers shared by linux/ci/smoke-x11.sh and linux/ci/e2e1.sh. Sourced, not
# run: the caller sets `set -euo pipefail`, ROOT (the repo root, the current
# directory) and NAME (its name in messages).

TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/target}"

die() {
  echo "$NAME: $*" >&2
  exit 1
}
now_ms() { echo $(($(date +%s%N) / 1000000)); }

# until_ok <seconds> <command…>: polls every 50 ms.
until_ok() {
  local deadline=$(($(now_ms) + $1 * 1000))
  shift
  until "$@" >/dev/null 2>&1; do
    [ "$(now_ms)" -lt "$deadline" ] || return 1
    sleep 0.05
  done
}

# Sets MORROW_APP (debug) and MORROW_BRIDGE (release), building the ones unset.
x11_binaries() {
  [ -f shared/desktop/dist/index.html ] ||
    die "no shared/desktop/dist: build the frontend first (cd shared/desktop && bun install && bun run build)"
  if [ -z "${MORROW_APP:-}" ]; then
    cargo build --locked -p morrow-app
    MORROW_APP="$TARGET_DIR/debug/morrow-app"
  fi
  if [ -z "${MORROW_BRIDGE:-}" ]; then
    cargo build --locked --release -p morrow-bridge
    MORROW_BRIDGE="$TARGET_DIR/release/morrow-bridge"
  fi
}

# A scratch folder (WORK) with the endpoint in it, never the user's own, and
# a trap that kills every pid in `pids` and removes it.
x11_workdir() {
  WORK="$(mktemp -d "/tmp/$NAME.XXXXXX")"
  export MORROW_SOCKET_PATH="$WORK/island.sock"
  pids=()
  trap x11_cleanup EXIT
}
x11_cleanup() {
  for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
  wait 2>/dev/null || true
  rm -rf "$WORK"
}

# Xvfb at SW×SH on :99, then Openbox (an EWMH window manager, so
# _NET_WM_STATE and _NET_ACTIVE_WINDOW mean what they mean on a desktop).
x11_xvfb_openbox() {
  # WebKitGTK without a GPU: no accelerated compositing, software GL.
  export WEBKIT_DISABLE_COMPOSITING_MODE=1
  export LIBGL_ALWAYS_SOFTWARE=1
  export DISPLAY=:99
  Xvfb "$DISPLAY" -screen 0 "${SW}x${SH}x24" -nolisten tcp >"$WORK/xvfb.log" 2>&1 &
  pids+=($!)
  until_ok 10 xdpyinfo || die "Xvfb did not start: $(cat "$WORK/xvfb.log")"
  # Openbox runs --startup once it manages windows; a window mapped before
  # that can be missed.
  openbox --startup "touch $WORK/openbox.ready" >"$WORK/openbox.log" 2>&1 &
  pids+=($!)
  until_ok 10 test -e "$WORK/openbox.ready" || die "openbox did not start: $(cat "$WORK/openbox.log")"
}

# The target window (TARGET): xev over the whole screen, recording clicks in
# $WORK/xev.log, and holding focus.
x11_target() {
  xev -geometry "${SW}x${SH}+0+0" >"$WORK/xev.log" 2>&1 &
  pids+=($!)
  TARGET="$(xdotool search --sync --name '^Event Tester$' | head -n1)"
  # Managed once the window manager has given it a desktop.
  until_ok 5 sh -c "xprop -id $TARGET _NET_WM_DESKTOP | grep -q '= '" || die "the window manager never managed the target"
  xdotool windowactivate --sync "$TARGET"
  until_ok 5 sh -c "[ \"\$(xdotool getactivewindow)\" = $TARGET ]" || die "the target never got focus"
}

# Starts morrow-app in smoke mode (stdout $WORK/app.out) and waits for the
# frontend's first push; sets ISLAND, t_app, t_shown.
x11_start_app() {
  t_app=$(now_ms)
  MORROW_SMOKE=1 "$MORROW_APP" >"$WORK/app.out" 2>"$WORK/app.err" &
  pids+=($!)
  until_ok 30 grep -q 'pushed sessions=0' "$WORK/app.out" ||
    die "the frontend never subscribed. stdout: $(cat "$WORK/app.out") stderr: $(cat "$WORK/app.err")"
  ISLAND="$(xdotool search --sync --onlyvisible --name '^Morrow$' | head -n1)"
  t_shown=$(now_ms)
}

# --- checks -------------------------------------------------------------
results=()
failed=0
check() { # check <name> <detail> <command…>
  local name="$1" detail="$2"
  shift 2
  if "$@" >/dev/null 2>&1; then
    results+=("PASS  $name  ($detail)")
  else
    results+=("FAIL  $name  ($detail)")
    failed=1
  fi
}

geometry() { # sets X Y W H of window $1, as the X server has it
  local g
  g="$(xdotool getwindowgeometry --shell "$1")"
  X="$(sed -n 's/^X=//p' <<<"$g")"
  Y="$(sed -n 's/^Y=//p' <<<"$g")"
  W="$(sed -n 's/^WIDTH=//p' <<<"$g")"
  H="$(sed -n 's/^HEIGHT=//p' <<<"$g")"
}
focused_is_target() {
  [ "$(xdotool getactivewindow)" = "$TARGET" ] && [ "$(xdotool getwindowfocus -f)" = "$TARGET" ]
}
clicks() { grep -c '^ButtonPress event' "$WORK/xev.log" || true; }
# click_reaches_target <x> <y>: a click there lands on the target.
click_reaches_target() {
  local before
  before="$(clicks)"
  xdotool mousemove --sync "$1" "$2" click 1
  until_ok 2 sh -c "[ \$(grep -c '^ButtonPress event' '$WORK/xev.log') -gt $before ]" &&
    grep -A1 '^ButtonPress event' "$WORK/xev.log" | tail -n1 | grep -q "root:($1,$2)"
}

# The panel's window manager properties: above, out of the taskbar, not
# resizable, never given input focus.
x11_window_checks() {
  local state hints actions
  state="$(xprop -id "$ISLAND" _NET_WM_STATE)"
  hints="$(xprop -id "$ISLAND" WM_HINTS)"
  actions="$(xprop -id "$ISLAND" _NET_WM_ALLOWED_ACTIONS)"
  check net_wm_state_above "$state" grep -q _NET_WM_STATE_ABOVE <<<"$state"
  check net_wm_state_skip_taskbar "$state" grep -q _NET_WM_STATE_SKIP_TASKBAR <<<"$state"
  check not_user_resizable "no _NET_WM_ACTION_RESIZE in allowed actions" eval '! grep -q _NET_WM_ACTION_RESIZE <<<"$actions"'
  check wm_hints_no_input "$(tr -s '\n\t ' ' ' <<<"$hints")" grep -q 'input focus: False' <<<"$hints"
}
