#!/usr/bin/env bash
# Lints and tests the desktop shell (`morrow-app`, shared/desktop), which
# needs GTK3 / WebKitGTK dev libraries: run it in the image of
# linux/ci/Dockerfile. linux/ci/test.sh covers every other crate and
# needs no GTK.
#
#   (cd shared/desktop && bun install && bun run build)   # on the host
#   docker run --rm -v "$PWD":/work morrow-tauri-x11:dev linux/ci/test-desktop.sh
#
# Output: dist/linux/test-desktop.log (every step's full output, overwritten).
# Exit:   0 when every step passed, 1 otherwise. Every step runs either way.
# Honours CARGO_BUILD_JOBS and any other cargo environment.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

LOG="$ROOT/dist/linux/test-desktop.log"
mkdir -p "$(dirname "$LOG")"
: >"$LOG"

if [ ! -f shared/desktop/dist/index.html ]; then
  echo "test-desktop: no shared/desktop/dist; build the frontend first" \
    "(cd shared/desktop && bun install && bun run build)" | tee -a "$LOG"
  exit 1
fi

summary=()
failed=0

# step <label> <command…>: as in linux/ci/test.sh.
step() {
  local label="$1"
  shift
  printf '\n==> %s: %s\n' "$label" "$*" | tee -a "$LOG"
  local start=$SECONDS
  if "$@" 2>&1 | tee -a "$LOG"; then
    summary+=("PASS  $label ($((SECONDS - start))s)")
  else
    summary+=("FAIL  $label ($((SECONDS - start))s)")
    failed=1
  fi
}

{
  echo "test-desktop: $(date -u +%Y-%m-%dT%H:%M:%SZ) on $(uname -sm)"
  rustc --version
  cargo --version
  pkg-config --modversion webkit2gtk-4.1 | sed 's/^/webkit2gtk-4.1 /'
} 2>&1 | tee -a "$LOG"

step fmt cargo fmt -p morrow-app --check
step clippy cargo clippy -p morrow-app --all-targets --locked -- -D warnings
step test cargo test -p morrow-app --locked

{
  echo
  echo "Summary:"
  printf '  %s\n' "${summary[@]}"
  if [ "$failed" -eq 0 ]; then
    echo "test-desktop: all steps passed (log: ${LOG#"$ROOT"/})"
  else
    echo "test-desktop: FAILED (log: ${LOG#"$ROOT"/})"
  fi
} | tee -a "$LOG"

exit "$failed"
