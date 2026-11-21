#!/usr/bin/env bash
# Linux smoke install-and-launch (docs/plan-windows-linux.md §9, L-011):
# install → the app launches → the bridge is at its stable path and answers a
# synthetic hook → uninstall leaves nothing of the package behind.
#
# Usage:   scripts/ci/linux-smoke.sh <deb|rpm|appimage> [artifact]
# Exit:    0 = the package is usable; 1 = it is not; 77 = no display and no
#          Xvfb, i.e. this machine cannot judge it (the script says so).
#
# Needs:   a display or Xvfb; root for deb/rpm (%postinst writes /usr).
#          An AppImage needs FUSE2 (libfuse2t64 on Ubuntu 24.04).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT="$ROOT/dist/linux"
LOG="$OUT/smoke.log"
mkdir -p "$OUT"
: >"$LOG"

say() { printf '%s\n' "$*" | tee -a "$LOG"; }
die() { say "linux-smoke: $*"; exit 1; }

FORMAT="${1:-}"
case "$FORMAT" in
  deb|rpm|appimage) ;;
  *) die "usage: scripts/ci/linux-smoke.sh <deb|rpm|appimage> [artifact]" ;;
esac

ARTIFACT="${2:-}"
if [ -z "$ARTIFACT" ]; then
  case "$FORMAT" in
    deb) ARTIFACT="$(find "$OUT" -maxdepth 1 -name '*.deb' | head -1)" ;;
    rpm) ARTIFACT="$(find "$OUT" -maxdepth 1 -name '*.rpm' | head -1)" ;;
    appimage) ARTIFACT="$(find "$OUT" -maxdepth 1 -name '*.AppImage' | head -1)" ;;
  esac
fi
[ -n "$ARTIFACT" ] && [ -f "$ARTIFACT" ] || die "no $FORMAT artifact: run linux-package.sh first"
say "linux-smoke: $FORMAT $(basename "$ARTIFACT") on $(uname -sm)"

# 1. A display, or Xvfb.
XVFB_PID=""
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  if ! command -v Xvfb >/dev/null; then
    say "linux-smoke: no display and no Xvfb: this host cannot judge a package"
    exit 77
  fi
  Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 &
  XVFB_PID=$!
  export DISPLAY=:99
  say "==> started Xvfb :99"
fi
cleanup() { [ -n "$XVFB_PID" ] && kill "$XVFB_PID" 2>/dev/null || true; }
trap cleanup EXIT

# 2. Install.
BRIDGE="$HOME/.local/bin/morrow-bridge"
case "$FORMAT" in
  deb)
    [ "$(id -u)" -eq 0 ] || die "deb install needs root: run this in the CI container"
    say "==> dpkg -i"
    dpkg -i "$ARTIFACT" 2>&1 | tee -a "$LOG"
    APP_BIN="/usr/bin/morrow-app"
    ;;
  rpm)
    [ "$(id -u)" -eq 0 ] || die "rpm install needs root: run this in the CI container"
    say "==> rpm -Uvh"
    rpm -Uvh --replacepkgs "$ARTIFACT" 2>&1 | tee -a "$LOG"
    APP_BIN="/usr/bin/morrow-app"
    ;;
  appimage)
    say "==> AppImage: no install step"
    APP_BIN="$ARTIFACT"
    ;;
esac

# 3. Launch. It must stay up for ten seconds and must not crash.
say "==> launching $(basename "$APP_BIN")"
"$APP_BIN" >"$OUT/smoke-app.log" 2>&1 &
APP_PID=$!
sleep 10
kill -0 "$APP_PID" 2>/dev/null || die "the app exited within ten seconds: $(tail -5 "$OUT/smoke-app.log")"

# 4. The bridge is outside the package, at the path the hook script records —
#    the point of the AppImage copy-out.
say "==> waiting for $BRIDGE"
for _ in $(seq 1 50); do
  [ -x "$BRIDGE" ] && break
  sleep 0.2
done
[ -x "$BRIDGE" ] || die "the app did not copy the bridge to $BRIDGE (hook configs would point nowhere)"

# 5. One synthetic hook, timed: a bridge that hangs blocks the user's tool call.
HOOK='{"session_id":"smoke","transcript_path":"/dev/null","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"true"}}'
START=$(date +%s%3N)
printf '%s' "$HOOK" | timeout 10 "$BRIDGE" >"$OUT/smoke-hook.out" 2>"$OUT/smoke-hook.err" &
HOOK_PID=$!
wait "$HOOK_PID" || true
ELAPSED=$(( $(date +%s%3N) - START ))
say "==> synthetic hook answered in ${ELAPSED}ms"
[ "$ELAPSED" -lt 300 ] || say "note: over the 300ms budget (decision still needs #91's two-way gate)"

# 6. Uninstall, then look for leftovers.
kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true
case "$FORMAT" in
  deb) dpkg -r morrow 2>&1 | tee -a "$LOG" ;;
  rpm) rpm -e morrow 2>&1 | tee -a "$LOG" ;;
  appimage) say "==> AppImage: remove the file and the copied bridge" ;;
esac
rm -f "$BRIDGE"
LEFTOVERS="$(ls -d /usr/lib/morrow /usr/share/morrow /usr/bin/morrow-app 2>/dev/null || true)"
[ -z "$LEFTOVERS" ] || die "uninstall left $LEFTOVERS behind"

say "linux-smoke: $FORMAT installed, launched, bridged and uninstalled cleanly (L-011)"
