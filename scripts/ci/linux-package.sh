#!/usr/bin/env bash
# Linux package step (docs/plan-windows-linux.md §8.1): one version in, the
# formats out — deb, rpm, AppImage — each with its updater signature, plus
# SHA256SUMS. Moves to linux/ci/package.sh with the monorepo layout (#86).
#
# Usage:   scripts/ci/linux-package.sh <version>          e.g. 0.1.0
# Output:  dist/linux/*.deb|*.rpm|*.AppImage|*.sig, dist/linux/SHA256SUMS
#          dist/linux/package.log
# Exit:    0 only when every format and every signature is present.
#
# Env:     TAURI_SIGNING_PRIVATE_KEY, TAURI_SIGNING_PRIVATE_KEY_PASSWORD
#          (the updater key; read from the environment, never stored or printed)
#
# The bridge is built first and placed where the bundler expects it, so it ships
# beside the app in all three formats. It is copied out of the package to
# ~/.local/bin/morrow-bridge on first run (morrow-platform::bridge), because a
# hook config records an absolute path and an AppImage's mount point changes on
# every launch.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT="$ROOT/dist/linux"
LOG="$OUT/package.log"
mkdir -p "$OUT"
: >"$LOG"

say() { printf '%s\n' "$*" | tee -a "$LOG"; }
die() { say "linux-package: $*"; exit 1; }

VERSION="${1:-}"
[[ -n "$VERSION" ]] || die "usage: scripts/ci/linux-package.sh <version>"
# Semver without a leading `v`: tauri.conf.json, the deb and the updater all
# compare this string, so one spelling only.
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]] \
  || die "version must be bare semver (0.1.0, not v0.1.0 or 0.1): got '$VERSION'"

say "linux-package: $VERSION on $(uname -sm), commit $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

[[ -n "${TAURI_SIGNING_PRIVATE_KEY:-}" ]] \
  || die "TAURI_SIGNING_PRIVATE_KEY is unset: the updater cannot verify unsigned artifacts"
command -v cargo >/dev/null || die "cargo is not on PATH"
cargo tauri --version >/dev/null 2>&1 \
  || die "tauri-cli is missing (cargo install tauri-cli --version '^2' --locked)"

TARGET="$(rustc -vV | awk '/^host:/ {print $2}')"
say "host target: $TARGET"

# 1. The bridge, named the way Tauri's externalBin expects it.
say "==> building morrow-bridge"
cargo build --release --locked -p morrow-bridge 2>&1 | tee -a "$LOG"
BINARIES="$ROOT/shared/desktop/src-tauri/binaries"
mkdir -p "$BINARIES"
install -m 0755 "$ROOT/target/release/morrow-bridge" "$BINARIES/morrow-bridge-$TARGET"

# 2. The bundles. `--config` pins the version so the artifact names, the
#    updater feed and the tag cannot disagree, and names the bridge as an
#    external binary here rather than in tauri.conf.json: the file is built in
#    step 1, and a `cargo check` on a fresh clone would otherwise fail on a
#    sidecar that is not in the tree.
say "==> bundling deb, rpm, appimage"
cargo tauri build --bundles deb,rpm,appimage --config \
  "{\"version\":\"$VERSION\",\"bundle\":{\"externalBin\":[\"binaries/morrow-bridge\"]}}" 2>&1 | tee -a "$LOG"

BUNDLE="$ROOT/target/release/bundle"
MISSING=()
for format in deb rpm appimage; do
  found=()
  while IFS= read -r artifact; do
    found+=("$artifact")
  done < <(find "$BUNDLE/$format" -maxdepth 1 -type f \
    \( -name '*.deb' -o -name '*.rpm' -o -name '*.AppImage' \) 2>/dev/null | sort)
  if [ "${#found[@]}" -eq 0 ]; then
    MISSING+=("$format: no artifact")
    continue
  fi
  for artifact in "${found[@]}"; do
    cp "$artifact" "$OUT/"
    cp "$artifact.sig" "$OUT/" 2>/dev/null || MISSING+=("$(basename "$artifact") without .sig")
  done
done

# 3. Only complete releases leave this script.
if [ "${#MISSING[@]}" -gt 0 ]; then
  say "linux-package: artifacts incomplete:"
  printf '  - %s\n' "${MISSING[@]}" | tee -a "$LOG"
  exit 1
fi

(
  cd "$OUT"
  shasum -a 256 ./*.deb ./*.rpm ./*.AppImage ./*.sig 2>/dev/null \
    || sha256sum ./*.deb ./*.rpm ./*.AppImage ./*.sig
) >"$OUT/SHA256SUMS"
say "==> SHA256SUMS"
cat "$OUT/SHA256SUMS" | tee -a "$LOG"

say "linux-package: $VERSION packaged — $(ls -1 "$OUT" | grep -cE '\.(deb|rpm|AppImage)$') artifacts, $(wc -l <"$OUT/SHA256SUMS" | tr -d ' ') checksums"
