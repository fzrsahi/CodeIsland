#!/usr/bin/env bash
# The Windows lane's compile step (docs/plan-windows-linux.md §8.1, #105): the
# code Windows will run is type-checked on every PR, even though no Windows
# machine runs the tests until the release build and the W-* gates.
#
# Usage:   scripts/ci/windows-check.sh
# Output:  dist/windows/check.log
# Exit:    0 when every crate checked, ≠0 otherwise.
#
# Wired into .woodpecker.yaml by the pipeline owner; run by hand until then.
# Needs:   rustup target add x86_64-pc-windows-msvc
#          cargo install cargo-xwin --locked        (MSVC headers/libs, no VS)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

LOG="$ROOT/dist/windows/check.log"
mkdir -p "$(dirname "$LOG")"
: >"$LOG"

TARGET="x86_64-pc-windows-msvc"
say() { printf '%s\n' "$*" | tee -a "$LOG"; }
die() { say "windows-check: $*"; exit 1; }

say "windows-check: $TARGET from $(uname -sm), commit $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

rustup target list --installed | grep -qx "$TARGET" \
  || die "$TARGET is not installed: rustup target add $TARGET"
cargo xwin --version >/dev/null 2>&1 \
  || die "cargo-xwin is missing: cargo install cargo-xwin --locked"

# `morrow-app` is not in this list yet: its build script generates a Windows
# resource file and needs `llvm-rc`, which a bare macOS/Linux toolchain does not
# ship. It joins when the shell carries Windows arms (#106/#107) and the lane's
# image has LLVM.
failed=0
for crate in morrow-ipc morrow-bridge morrow-platform morrow-core; do
  printf '\n==> cargo xwin clippy -p %s --all-targets -- -D warnings\n' "$crate" | tee -a "$LOG"
  if cargo xwin clippy -p "$crate" --all-targets --target "$TARGET" --locked -- -D warnings 2>&1 \
      | tee -a "$LOG"; then
    say "PASS  $crate"
  else
    say "FAIL  $crate"
    failed=1
  fi
done

if [ "$failed" -eq 0 ]; then
  say "windows-check: all crates compile for $TARGET (log: ${LOG#"$ROOT"/})"
else
  say "windows-check: FAILED (log: ${LOG#"$ROOT"/})"
fi
exit "$failed"
