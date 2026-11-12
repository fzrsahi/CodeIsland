#!/bin/bash
# PROTOTYPE — throwaway (branch prototype/ca-music-visuals). Launches an isolated
# release build playing a simulated track, with the Core Animation variant
# switcher panel at the bottom of the screen. Ctrl-C to stop; a CodeIsland
# that was running is quit first and reopened afterwards.
#
#   scripts/prototype-ca-visuals.sh            build, then start on variant A
#   scripts/prototype-ca-visuals.sh --no-build B
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD=1
VARIANT=A
for arg in "$@"; do
  case "$arg" in
    --no-build) BUILD=0 ;;
    0|A|B|C) VARIANT="$arg" ;;
    *) echo "usage: $0 [--no-build] [0|A|B|C]" >&2; exit 2 ;;
  esac
done

[[ "$BUILD" == 1 ]] && ./build.sh >/dev/null
APP=".build/release/CodeIsland.app"

RELAUNCH=()
while read -r pid; do
  [[ -n "$pid" ]] || continue
  exe="$(ps -o comm= -p "$pid" 2>/dev/null || true)"
  [[ "$exe" == *.app/Contents/MacOS/CodeIsland ]] && RELAUNCH+=("${exe%/Contents/MacOS/CodeIsland}")
done < <(pgrep -x CodeIsland || true)
for _ in 1 2 3 4 5; do
  pgrep -x CodeIsland >/dev/null || break
  osascript -e 'tell application id "com.codeisland.app" to quit' >/dev/null 2>&1 || true
  sleep 2
done

cleanup() {
  [[ -n "${PID:-}" ]] && kill "$PID" 2>/dev/null || true
  for app in "${RELAUNCH[@]+"${RELAUNCH[@]}"}"; do open "$app" || true; done
}
trap cleanup EXIT

echo "Prototype running (variant $VARIANT). Switch variants with ◀ ▶ in the panel. Ctrl-C to stop."
CODEISLAND_ISOLATED=1 \
CODEISLAND_SOCKET_PATH="/tmp/codeisland-prototype-$$.sock" \
CODEISLAND_PERF_COUNTERS="/tmp/codeisland-prototype-counters.json" \
  "$APP/Contents/MacOS/CodeIsland" --preview music --collapsed --proto-visuals --proto-variant "$VARIANT" \
  -soundEnabled '<false/>' -prayerEnabled '<false/>' -hideWhenNoSession '<false/>' &
PID=$!
wait "$PID"
