#!/usr/bin/env bash
# CI contract: macOS test (docs/plan-windows-linux.md §8.1).
#
# Usage: scripts/ci/macos-test.sh
#
# Runs the core XCTest suite, writes the full log to dist/macos/test.log and
# exits non-zero if the build or any test fails. Interim location until the
# monorepo move, after which this becomes macos/ci/test.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="$REPO_ROOT/dist/macos"
LOG="$OUT_DIR/test.log"

cd "$REPO_ROOT"
mkdir -p "$OUT_DIR"

echo "==> Running core XCTest suite (log: $LOG)"
status=0
# pipefail makes the pipeline report the runner's exit code, not tee's.
python3 ./scripts/run-xctest-runner.py --target core 2>&1 | tee "$LOG" || status=$?

echo ""
echo "==> macOS test summary"
echo "    log:    $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
result_line="$(grep -E 'Executed [0-9]+ tests?' "$LOG" | tail -n 1 || true)"
echo "    result: ${result_line:-no XCTest summary line found}"
if [ "$status" -eq 0 ]; then
    echo "    status: PASS"
else
    echo "    status: FAIL (exit $status)"
fi
exit "$status"
