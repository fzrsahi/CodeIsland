#!/usr/bin/env bash
# Linux test step (docs/plan-windows-linux.md §8.1): formats, lints and tests
# the Rust workspace, then checks the pure crates' dependencies.
# Moves to linux/ci/test.sh with the monorepo layout (#86).
#
# Output: dist/linux/test.log (every step's full output, overwritten).
# Exit:   0 when every step passed, 1 otherwise. Every step runs either way.
# Honours CARGO_BUILD_JOBS and any other cargo environment.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

LOG="$ROOT/dist/linux/test.log"
mkdir -p "$(dirname "$LOG")"
: >"$LOG"

summary=()
failed=0

# step <label> <command…>: runs the command, its output to the terminal and
# the log; pipefail keeps tee from hiding its exit status.
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
  echo "linux-test: $(date -u +%Y-%m-%dT%H:%M:%SZ) on $(uname -sm)"
  echo "commit: $(git -c safe.directory="$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  rustc --version
  cargo --version
} 2>&1 | tee -a "$LOG"

step fmt cargo fmt --all --check
# morrow-app needs GTK / WebKitGTK: linux/ci/test-desktop.sh, in its image.
step clippy cargo clippy --workspace --exclude morrow-app --all-targets --locked -- -D warnings
step test cargo test --workspace --exclude morrow-app --locked
step purity scripts/ci/rust-purity.sh

{
  echo
  echo "Summary:"
  printf '  %s\n' "${summary[@]}"
  if [ "$failed" -eq 0 ]; then
    echo "linux-test: all steps passed (log: ${LOG#"$ROOT"/})"
  else
    echo "linux-test: FAILED (log: ${LOG#"$ROOT"/})"
  fi
} | tee -a "$LOG"

exit "$failed"
