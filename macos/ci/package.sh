#!/usr/bin/env bash
# CI contract: macOS package (docs/plan-windows-linux.md §8.1).
#
# Usage: macos/ci/package.sh <version>
#
# Builds the DMG with macos/scripts/build-dmg.sh and writes:
#   dist/macos/Morrow.dmg
#   dist/macos/SHA256SUMS
# Exits non-zero unless both exist, the DMG is larger than 1 MB and the
# checksum verifies. SKIP_SIGN, SKIP_NOTARIZE and BUILD_ARCH default to the
# values CI has always used and can be overridden from the environment.
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>" >&2
    exit 2
fi
# x.y.z with an optional pre-release suffix, e.g. 1.0.42 or 1.0.42-dev.17
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?$ ]]; then
    echo "ERROR: version '$VERSION' is not x.y.z or x.y.z-<pre> (e.g. 1.0.42, 1.0.42-dev.17)" >&2
    exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="$REPO_ROOT/dist/macos"
DMG_NAME="Morrow.dmg"
DMG="$OUT_DIR/$DMG_NAME"
SUMS="$OUT_DIR/SHA256SUMS"
MIN_SIZE=1048576

export SKIP_SIGN="${SKIP_SIGN:-1}"
export SKIP_NOTARIZE="${SKIP_NOTARIZE:-1}"
export BUILD_ARCH="${BUILD_ARCH:-arm64}"

cd "$REPO_ROOT"
mkdir -p "$OUT_DIR"
rm -f "$DMG" "$SUMS"

echo "==> Packaging Morrow $VERSION (SKIP_SIGN=$SKIP_SIGN SKIP_NOTARIZE=$SKIP_NOTARIZE BUILD_ARCH=$BUILD_ARCH)"
./macos/scripts/build-dmg.sh "$VERSION"

if [ ! -f macos/.build/Morrow.dmg ]; then
    echo "ERROR: build-dmg.sh finished but macos/.build/Morrow.dmg was not produced" >&2
    exit 1
fi
cp macos/.build/Morrow.dmg "$DMG"

echo "==> Verifying DMG artifact integrity..."
SIZE="$(stat -f%z "$DMG" 2>/dev/null || stat -c%s "$DMG")"
if [ "$SIZE" -le "$MIN_SIZE" ]; then
    echo "ERROR: DMG size ($SIZE bytes) is suspiciously small (<= 1MB)" >&2
    exit 1
fi

# Bare file name so `shasum -c` / `sha256sum -c` works next to the DMG.
(cd "$OUT_DIR" && shasum -a 256 "$DMG_NAME" > SHA256SUMS && shasum -a 256 -c SHA256SUMS >/dev/null)

echo ""
echo "==> macOS package summary"
echo "    $DMG ($SIZE bytes, $((SIZE / 1024 / 1024)) MB)"
echo "    $SUMS: $(cat "$SUMS")"
