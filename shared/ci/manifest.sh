#!/usr/bin/env bash
# CI contract: update manifests (docs/plan-windows-linux.md §8.1).
#
# Usage: shared/ci/manifest.sh <version> [--channel stable|dev]
#
# Signs dist/macos/Morrow.dmg with macos/scripts/update-appcast.sh and writes the
# Sparkle appcast to dist/appcast.xml (stable, default) or dist/appcast-dev.xml
# (dev). The feed is built from macos/'s appcast of the same name when one
# exists, so earlier releases stay in it. The result is validated before it is
# moved into dist/. Needs SPARKLE_PRIVATE_KEY in the environment; the key is
# never printed.
#
# TODO(#70): also write dist/latest.json (Tauri updater feed) once the Linux and
# Windows packages exist.
set -euo pipefail

usage() {
    echo "Usage: $0 <version> [--channel stable|dev]" >&2
    exit 2
}

VERSION="${1:-}"
[ -n "$VERSION" ] || usage
shift
CHANNEL="stable"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --channel)
            [ "$#" -ge 2 ] || usage
            CHANNEL="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?$ ]]; then
    echo "ERROR: version '$VERSION' is not x.y.z or x.y.z-<pre> (e.g. 1.0.42, 1.0.42-dev.17)" >&2
    exit 2
fi
case "$CHANNEL" in
    stable) APPCAST_NAME="appcast.xml" ;;
    dev)    APPCAST_NAME="appcast-dev.xml" ;;
    *)
        echo "ERROR: --channel must be 'stable' or 'dev' (got '$CHANNEL')" >&2
        exit 2
        ;;
esac

if [ -z "${SPARKLE_PRIVATE_KEY:-}" ]; then
    echo "ERROR: SPARKLE_PRIVATE_KEY is not set. The appcast must be signed with the Sparkle EdDSA key;" >&2
    echo "       provide it through the CI secret store (Woodpecker secret 'sparkle_private_key')." >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST="$REPO_ROOT/dist"
DMG="$DIST/macos/Morrow.dmg"
OUT="$DIST/$APPCAST_NAME"

if [ ! -f "$DMG" ]; then
    echo "ERROR: $DMG not found. Run macos/ci/package.sh $VERSION first." >&2
    exit 1
fi

cd "$REPO_ROOT"
# Work on a copy with the final basename: update-appcast.sh uses the basename
# in the feed's <link> when it creates a new file.
WORK_DIR="$(mktemp -d "$DIST/.manifest.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
WORK="$WORK_DIR/$APPCAST_NAME"
if [ -f "$REPO_ROOT/macos/$APPCAST_NAME" ]; then
    cp "$REPO_ROOT/macos/$APPCAST_NAME" "$WORK"
fi

echo "==> Writing $CHANNEL appcast for $VERSION"
./macos/scripts/update-appcast.sh "$VERSION" "$DMG" "$WORK" || {
    status=$?
    echo "ERROR: update-appcast.sh failed (exit $status); is SPARKLE_PRIVATE_KEY a valid Sparkle EdDSA key?" >&2
    exit "$status"
}

echo "==> Validating $APPCAST_NAME"
python3 - "$WORK" "$VERSION" <<'PY'
import sys
import xml.etree.ElementTree as ET

path, version = sys.argv[1], sys.argv[2]
ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
try:
    root = ET.parse(path).getroot()
except ET.ParseError as e:
    sys.exit(f"ERROR: {path} is not well-formed XML: {e}")
for item in root.iterfind("./channel/item"):
    if item.findtext("sparkle:version", namespaces=ns) != version:
        continue
    enc = item.find("enclosure")
    sig = enc.get(f"{{{ns['sparkle']}}}edSignature") if enc is not None else None
    if not sig:
        sys.exit(f"ERROR: item {version} in {path} has no signed <enclosure>")
    sys.exit(0)
sys.exit(f"ERROR: {path} has no <item> with sparkle:version {version}")
PY

mv "$WORK" "$OUT"
SIZE="$(stat -f%z "$OUT" 2>/dev/null || stat -c%s "$OUT")"
echo ""
echo "==> Manifest summary"
echo "    $OUT ($SIZE bytes, $(grep -c '<item>' "$OUT") items, channel $CHANNEL, version $VERSION)"
