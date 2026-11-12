#!/bin/bash
# PROTOTYPE — throwaway. CPU and layout passes per variant × scene, no panel.
# Output: TSV on stdout. Quit any running CodeIsland first.
set -euo pipefail
cd "$(dirname "$0")/.."
EXE=".build/release/CodeIsland.app/Contents/MacOS/CodeIsland"
WARM=12
WINDOW=40
F=/tmp/codeisland-proto-measure.json
secs() { awk -F: '{ t = 0; for (i = 1; i <= NF; i++) t = t * 60 + $i; print t }' <<<"$1"; }
layouts() { python3 -c "import json;print(json.load(open('$F'))['counters'].get('hostingLayoutPass',0))"; }
COMBOS=("$@")
[[ ${#COMBOS[@]} -gt 0 ]] || COMBOS=("music modern" "music retro" "breath modern" "waiting modern")
printf 'scene\ttheme\tvariant\tcpu%%\tlayout/min\n'
for combo in "${COMBOS[@]}"; do
  read -r scene theme <<<"$combo"
  for v in 0 A B C; do
    rm -f "$F"
    CODEISLAND_ISOLATED=1 CODEISLAND_SOCKET_PATH="/tmp/cip-$$.sock" CODEISLAND_PERF_COUNTERS="$F" \
      "$EXE" --preview music --collapsed --proto-visuals --proto-no-panel \
      --proto-variant "$v" --proto-scene "$scene" --proto-theme "$theme" \
      -soundEnabled '<false/>' -prayerEnabled '<false/>' -hideWhenNoSession '<false/>' >/dev/null 2>&1 &
    pid=$!
    sleep "$WARM"
    c0=$(secs "$(ps -o time= -p $pid | tr -d ' ')"); l0=$(layouts)
    sleep 5; c0=$(secs "$(ps -o time= -p $pid | tr -d ' ')"); l0=$(layouts); t0=$(date +%s)
    sleep "$WINDOW"
    sleep 5   # counter file is written every 5 s
    c1=$(secs "$(ps -o time= -p $pid | tr -d ' ')"); l1=$(layouts); t1=$(date +%s)
    kill $pid 2>/dev/null || echo "  (app crashed during run: $scene $theme $v)" >&2
    wait $pid 2>/dev/null || true
    python3 -c "print('$scene\t$theme\t$v\t%.2f\t%.0f' % (100*($c1-$c0)/($t1-$t0), ($l1-$l0)*60/($t1-$t0)))"
  done
done
