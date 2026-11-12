#!/bin/bash
# CodeIsland performance benchmark: idle CPU, wakeups, energy, memory and
# internal event counters per scenario, compared against
# scripts/perf/baseline.json. See CONTRIBUTING.md, "Performance benchmark".
#
#   scripts/perf/bench.sh                    quick suite (idle, idle-prayer, working, music)
#   scripts/perf/bench.sh full               quick + multi, stress, working-expanded, waiting-long
#   scripts/perf/bench.sh --scenario music   one scenario (repeatable)
#   scripts/perf/bench.sh --update-baseline  3 runs per scenario, medians written to baseline.json
#   scripts/perf/bench.sh --soak 24          footprint every 10 min for 24 h, leaks at the end
#
# Options:
#   --no-build          use the existing .build/release/CodeIsland.app
#   --app PATH          measure another .app
#   --keep-installed    leave a running CodeIsland alone (numbers get noisier)
#   --runs N            runs per scenario (default 1, 3 with --update-baseline)
#   --soak-scenario S   scenario for --soak (default stress)
#   --out DIR           where raw files go (default .build/perf/<timestamp>)
#
# Each run launches the app isolated (CODEISLAND_ISOLATED=1, its own hook
# socket, no hooks, no discovery) with --preview <scenario>, settings pinned on
# the command line (argument domain, nothing written to the app's defaults),
# warms up, then measures 60 s with top, takes memory readings, and samples
# the main thread for 10 s. Exit status: 0 pass, 1 regression or enforced
# target missed, 2 usage or setup error.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

BUNDLE_ID="com.codeisland.app"
BASELINE="scripts/perf/baseline.json"
MEASURE_SECONDS=60
SAMPLE_SECONDS=10

SUITE="quick"
SCENARIOS=()
BUILD=1
APP=".build/release/CodeIsland.app"
KEEP_INSTALLED=0
UPDATE_BASELINE=0
RUNS=""
SOAK_HOURS=""
SOAK_SCENARIO="stress"
OUT_DIR=""

usage() { sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "bench: $*" >&2; exit 2; }
log() { echo "[bench] $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    quick|full) SUITE="$1" ;;
    --scenario) [[ $# -ge 2 ]] || die "--scenario needs a name"; SCENARIOS+=("$2"); shift ;;
    --no-build) BUILD=0 ;;
    --app) [[ $# -ge 2 ]] || die "--app needs a path"; APP="$2"; BUILD=0; shift ;;
    --keep-installed) KEEP_INSTALLED=1 ;;
    --update-baseline) UPDATE_BASELINE=1 ;;
    --runs) [[ $# -ge 2 ]] || die "--runs needs a number"; RUNS="$2"; shift ;;
    --soak) [[ $# -ge 2 ]] || die "--soak needs hours"; SOAK_HOURS="$2"; shift ;;
    --soak-scenario) [[ $# -ge 2 ]] || die "--soak-scenario needs a name"; SOAK_SCENARIO="$2"; shift ;;
    --out) [[ $# -ge 2 ]] || die "--out needs a directory"; OUT_DIR="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

QUICK=(idle idle-prayer working music)
FULL=("${QUICK[@]}" multi stress working-expanded waiting-long)
if [[ ${#SCENARIOS[@]} -eq 0 ]]; then
  if [[ "$SUITE" == "full" ]]; then SCENARIOS=("${FULL[@]}"); else SCENARIOS=("${QUICK[@]}"); fi
fi
if [[ -z "$RUNS" ]]; then
  if [[ "$UPDATE_BASELINE" == 1 ]]; then RUNS=3; else RUNS=1; fi
fi
[[ "$RUNS" =~ ^[1-9][0-9]*$ ]] || die "--runs must be a positive number"

# scenario -> "preview-scenario|extra flags|warm-up seconds"
scenario_spec() {
  case "$1" in
    idle)             echo "idle|--collapsed|15" ;;
    idle-prayer)      echo "idle|--collapsed|15" ;;
    working)          echo "working|--collapsed|15" ;;
    music)            echo "music|--collapsed|15" ;;
    multi)            echo "multi|--collapsed|15" ;;
    stress)           echo "stress|--collapsed|15" ;;
    working-expanded) echo "working||15" ;;
    # Waiting > 60 s without interaction (the long-wait state).
    waiting-long)     echo "approval|--collapsed|65" ;;
    *) return 1 ;;
  esac
}
for s in "${SCENARIOS[@]}" ${SOAK_HOURS:+"$SOAK_SCENARIO"}; do
  scenario_spec "$s" >/dev/null || die "unknown scenario: $s"
done

# Settings pinned per run through the argument domain (read-only).
pinned_defaults() {
  local prayer="<false/>"
  [[ "$1" == "idle-prayer" ]] && prayer="<true/>"
  printf '%s\n' \
    -prayerEnabled "$prayer" \
    -prayerLocationMode manual \
    -prayerManualCityId jakarta \
    -detectSpotifyWebInBrowsers "<true/>" \
    -esp32BridgeEnabled "<false/>" \
    -appleCompanionEnabled "<false/>" \
    -hideWhenNoSession "<false/>" \
    -soundEnabled "<false/>"
}

# Players and browsers NowPlaying would probe; part of the environment because
# each running one costs an AppleScript per poll.
running_players() {
  local ids=(com.spotify.client com.apple.Music com.apple.Safari com.brave.Browser
             com.google.Chrome company.thebrowser.Browser com.microsoft.edgemac)
  local found=()
  for id in "${ids[@]}"; do
    [[ -n "$(lsappinfo find bundleid="$id" 2>/dev/null)" ]] && found+=("$id")
  done
  printf '%s\n' "${found[@]+"${found[@]}"}"
}

write_env() {
  local commit
  commit="$(git rev-parse --short HEAD)"
  git diff --quiet HEAD -- Sources Package.swift 2>/dev/null || commit="$commit-dirty"
  python3 - "$1" "$(sysctl -n hw.model)" "$(sw_vers -productVersion)" "$commit" "$(running_players)" <<'EOF'
import json, sys, datetime
path, model, macos, commit, players = sys.argv[1:6]
json.dump({
    "macModel": model,
    "macOS": macos,
    "commit": commit,
    "date": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
    "players": sorted(p for p in players.splitlines() if p),
}, open(path, "w"), indent=2)
EOF
}

# MB values from vmmap: current and peak physical footprint.
footprint_mb() {
  vmmap --summary "$1" 2>/dev/null | python3 -c '
import re, sys
units = {"K": 1/1024, "M": 1, "G": 1024}
cur = peak = None
for line in sys.stdin:
    m = re.match(r"Physical footprint( \(peak\))?:\s+([\d.]+)([KMG])", line)
    if m:
        v = round(float(m.group(2)) * units[m.group(3)], 1)
        if m.group(1): peak = v
        else: cur = v
print(cur if cur is not None else "null", peak if peak is not None else "null")'
}

# ------------------------------------------------------------------ setup

if [[ "$BUILD" == 1 ]]; then
  log "Building release app (./build.sh)…"
  ./build.sh >&2
fi
EXE="$APP/Contents/MacOS/CodeIsland"
[[ -x "$EXE" ]] || die "no app at $APP (build it, or pass --app)"

OUT_DIR="${OUT_DIR:-.build/perf/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

BENCH_PID=""
RELAUNCH=()
cleanup() {
  local status=$?
  if [[ -n "$BENCH_PID" ]] && kill -0 "$BENCH_PID" 2>/dev/null; then
    kill "$BENCH_PID" 2>/dev/null || true
    wait "$BENCH_PID" 2>/dev/null || true
  fi
  for app in "${RELAUNCH[@]+"${RELAUNCH[@]}"}"; do
    log "Relaunching $app"
    open "$app" || log "could not relaunch $app; open it yourself"
  done
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

if [[ "$KEEP_INSTALLED" == 0 ]]; then
  # Remember every running CodeIsland's bundle, then quit them the normal way
  # so they save their sessions.
  while read -r pid; do
    [[ -n "$pid" ]] || continue
    exe="$(ps -o comm= -p "$pid" 2>/dev/null || true)"
    [[ "$exe" == *.app/Contents/MacOS/CodeIsland ]] && RELAUNCH+=("${exe%/Contents/MacOS/CodeIsland}")
  done < <(pgrep -x CodeIsland || true)
  if [[ ${#RELAUNCH[@]} -gt 0 ]]; then
    log "Quitting the running CodeIsland (relaunched at the end; --keep-installed skips this)"
    for _ in 1 2 3 4 5; do
      pgrep -x CodeIsland >/dev/null || break
      osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
      sleep 2
    done
    pgrep -x CodeIsland >/dev/null && die "a CodeIsland is still running; quit it and retry"
  fi
fi

ENV_JSON="$OUT_DIR/env.json"
write_env "$ENV_JSON"
log "Environment: $(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["macModel"], "macOS", d["macOS"], d["commit"], "players:", ",".join(d["players"]) or "none")' "$ENV_JSON")"

launch() {  # launch <scenario> <run dir>
  local scenario="$1" dir="$2" spec preview flags
  spec="$(scenario_spec "$scenario")"
  preview="${spec%%|*}"; flags="${spec#*|}"; flags="${flags%|*}"
  local args=(--preview "$preview")
  [[ -n "$flags" ]] && args+=($flags)
  local pinned=()
  while IFS= read -r line; do pinned+=("$line"); done < <(pinned_defaults "$scenario")
  CODEISLAND_ISOLATED=1 \
  CODEISLAND_SOCKET_PATH="/tmp/codeisland-bench-$$.sock" \
  CODEISLAND_PERF_COUNTERS="$dir/counters.json" \
    "$EXE" "${args[@]}" "${pinned[@]}" >"$dir/app.log" 2>&1 &
  BENCH_PID=$!
}

stop_app() {
  if [[ -n "$BENCH_PID" ]]; then
    kill "$BENCH_PID" 2>/dev/null || true
    wait "$BENCH_PID" 2>/dev/null || true
    BENCH_PID=""
  fi
}

ensure_alive() {
  kill -0 "$BENCH_PID" 2>/dev/null || die "app exited during $1 (see $2/app.log)"
}

# ------------------------------------------------------------------ soak

if [[ -n "$SOAK_HOURS" ]]; then
  dir="$OUT_DIR/soak-$SOAK_SCENARIO"
  mkdir -p "$dir"
  warm="$(scenario_spec "$SOAK_SCENARIO")"; warm="${warm##*|}"
  launch "$SOAK_SCENARIO" "$dir"
  log "Soak: $SOAK_SCENARIO for $SOAK_HOURS h (pid $BENCH_PID), footprint every 10 min → $dir/footprint.csv"
  sleep "$warm"
  ensure_alive soak "$dir"
  echo "elapsed_min,footprint_mb,peak_mb" >"$dir/footprint.csv"
  read -r start _ <<<"$(footprint_mb "$BENCH_PID")"
  end_at=$(( $(date +%s) + $(python3 -c "print(int(float('$SOAK_HOURS') * 3600))") ))
  t0=$(date +%s)
  while :; do
    ensure_alive soak "$dir"
    read -r cur peak <<<"$(footprint_mb "$BENCH_PID")"
    echo "$(( ($(date +%s) - t0) / 60 )),$cur,$peak" >>"$dir/footprint.csv"
    [[ $(date +%s) -ge $end_at ]] && break
    sleep 600
  done
  leaks "$BENCH_PID" >"$dir/leaks.txt" 2>&1 || true
  leak_count="$(grep -Eo '[0-9]+ leaks? for' "$dir/leaks.txt" 2>/dev/null | head -1 | grep -Eo '^[0-9]+' || echo "?")"
  stop_app
  python3 - "$start" "$cur" "$leak_count" <<'EOF'
import sys
start, end, leaks = float(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
growth = 100 * (end - start) / start
ok = growth <= 10 and leaks == "0"
print(f"Soak: footprint {start:.1f} → {end:.1f} MB ({growth:+.1f}%, target ≤ +10%), leaks {leaks} (target 0): {'PASS' if ok else 'FAIL'}")
sys.exit(0 if ok else 1)
EOF
  exit $?
fi

# ------------------------------------------------------------------ runs

RUN_DIRS=()
total=$(( ${#SCENARIOS[@]} * RUNS ))
n=0
for run in $(seq 1 "$RUNS"); do
  for scenario in "${SCENARIOS[@]}"; do
    n=$(( n + 1 ))
    dir="$OUT_DIR/$scenario-$run"
    mkdir -p "$dir"
    warm="$(scenario_spec "$scenario")"; warm="${warm##*|}"
    log "[$n/$total] $scenario run $run: warm-up ${warm}s, measure ${MEASURE_SECONDS}s, sample ${SAMPLE_SECONDS}s"
    launch "$scenario" "$dir"
    sleep "$warm"
    ensure_alive "$scenario" "$dir"
    [[ -f "$dir/counters.json" ]] || die "no counter file from the app (is this build older than the harness?)"

    cp "$dir/counters.json" "$dir/counters-start.json"
    read -r fp_start _ <<<"$(footprint_mb "$BENCH_PID")"
    /usr/bin/top -l $(( MEASURE_SECONDS + 1 )) -s 1 -pid "$BENCH_PID" -stats pid,cpu,idlew,power,mem >"$dir/top.txt" 2>&1
    ensure_alive "$scenario" "$dir"
    # The counter file is rewritten every 5 s; wait for the next write so the
    # window ends on a snapshot taken after the measurement.
    sleep 5
    cp "$dir/counters.json" "$dir/counters-end.json"
    read -r fp_end fp_peak <<<"$(footprint_mb "$BENCH_PID")"
    rss_kb="$(ps -o rss= -p "$BENCH_PID" | tr -d ' ')"
    pid="$BENCH_PID"
    sample "$BENCH_PID" "$SAMPLE_SECONDS" -file "$dir/sample.txt" >/dev/null 2>&1 || log "sample failed for $scenario"
    stop_app

    python3 - "$dir" "$scenario" "$pid" "$fp_start" "$fp_end" "$fp_peak" "$rss_kb" <<'EOF'
import json, sys, os
d, scenario, pid, start, end, peak, rss = sys.argv[1:8]
json.dump({"scenario": scenario, "pid": int(pid)}, open(os.path.join(d, "run.json"), "w"))
json.dump({"footprintStartMB": float(start), "footprintEndMB": float(end),
           "footprintPeakMB": float(peak), "rssMB": round(int(rss) / 1024, 1)},
          open(os.path.join(d, "memory.json"), "w"))
EOF
    python3 scripts/perf/compare.py summarize "$dir"
    RUN_DIRS+=("$dir")
  done
done

report_args=(--baseline "$BASELINE" --env "$ENV_JSON")
[[ "$UPDATE_BASELINE" == 1 ]] && report_args+=(--update)
set +e
python3 scripts/perf/compare.py report "${report_args[@]}" "${RUN_DIRS[@]}" | tee "$OUT_DIR/report.txt"
status=${PIPESTATUS[0]}
set -e
log "Raw files: $OUT_DIR"
exit "$status"
