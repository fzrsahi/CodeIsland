#!/usr/bin/env bash
# Fails when a pure crate (shared/ci/rust-pure-crates.txt) depends on a
# crate that reaches the OS (docs/plan-windows-linux.md §4, "Aturan CI").
# Normal dependencies only, for every target: a `[target.'cfg(windows)']`
# dependency counts on Linux too.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

ALLOWLIST="shared/ci/rust-pure-crates.txt"
FORBIDDEN="windows windows-sys libc nix zbus btleplug tokio mio notify rustix socket2"

failed=0
checked=0
while read -r crate; do
  case "$crate" in '' | '#'*) continue ;; esac
  checked=$((checked + 1))
  # `name@version`, one per package, so `-i` below names one even when two
  # versions of a crate are in the tree.
  deps="$(cargo tree --quiet -e normal --target all --prefix none -p "$crate" </dev/null |
    awk '{ sub(/^v/, "", $2); print $1 "@" $2 }' | sort -u)"
  hits=""
  for name in $FORBIDDEN; do
    hits="$hits $(printf '%s\n' "$deps" | grep -- "^$name@" || true)"
  done
  hits="$(echo $hits)"
  if [ -z "$hits" ]; then
    echo "purity: $crate ok ($(printf '%s\n' "$deps" | wc -l | tr -d ' ') crates, none forbidden)"
    continue
  fi
  failed=1
  for spec in $hits; do
    echo "purity: $crate depends on forbidden crate \`$spec\`, pulled in by:"
    cargo tree --quiet -e normal --target all -p "$crate" -i "$spec" </dev/null
  done
done <"$ALLOWLIST"

if [ "$checked" -eq 0 ]; then
  echo "purity: $ALLOWLIST lists no crate" >&2
  exit 1
fi
exit "$failed"
