#!/usr/bin/env bash
# ==============================================================================
# Fast compilation check for Windows targets using cargo check
# Target: x86_64-pc-windows-msvc
#
# Validates Windows syntax, Win32 Named Pipes, and WinRT bindings on Linux
# without requiring a full Windows VM (Ponytail / TCO minimal).
# ==============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

LOG="$ROOT/dist/windows/check.log"
mkdir -p "$(dirname "$LOG")"
: >"$LOG"

echo "==> Checking Windows targets compilation (x86_64-pc-windows-msvc)..." | tee -a "$LOG"

if [ "${1:-}" = "--dry-run" ]; then
    echo "Dry-run: cargo check --workspace --target x86_64-pc-windows-msvc" | tee -a "$LOG"
    exit 0
fi

if [ ! -f "$ROOT/Cargo.toml" ]; then
    echo "Notice: Cargo.toml not found. Skipping Windows compilation check." | tee -a "$LOG"
    exit 0
fi

cargo check --workspace --target x86_64-pc-windows-msvc --locked 2>&1 | tee -a "$LOG"
echo "windows-check: all checks passed (log: ${LOG#"$ROOT"/})" | tee -a "$LOG"
