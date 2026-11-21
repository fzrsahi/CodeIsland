#!/usr/bin/env bash
# Linux update feed (docs/plan-windows-linux.md §8.1, §9): one latest.json per
# format, validated before any of them is written.
#
# Usage:   TAURI_UPDATE_BASE_URL=https://… linux/ci/manifest.sh <version>
# Output:  dist/linux/feed/{deb,rpm,appimage}/latest.json, dist/linux/manifest.log
# Exit:    0 when every feed was written and re-parsed; ≠0 on anything else.
#
# A feed per format, not one feed with three entries: Tauri validates the whole
# document, so one broken entry breaks every client, and a deb client handed an
# AppImage entry fails to update (plan §9). Hence also all-or-nothing: every
# format is checked first, and nothing is written until all three pass, so a
# failed release leaves the previous feeds intact instead of a half-new set.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT="$ROOT/dist/linux"
LOG="$OUT/manifest.log"
mkdir -p "$OUT"
: >"$LOG"

say() { printf '%s\n' "$*" | tee -a "$LOG"; }
die() { say "linux-manifest: $*"; exit 1; }

VERSION="${1:-}"
[[ -n "$VERSION" ]] || die "usage: linux/ci/manifest.sh <version>"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]] \
  || die "version must be bare semver, got '$VERSION'"

BASE_URL="${TAURI_UPDATE_BASE_URL:-}"
[[ -n "$BASE_URL" ]] || die "TAURI_UPDATE_BASE_URL is unset: a feed without a reachable url is a 404 for every client"
[[ "$BASE_URL" == https://* ]] || die "TAURI_UPDATE_BASE_URL must be https, got '$BASE_URL'"
BASE_URL="${BASE_URL%/}"

PUB_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
say "linux-manifest: $VERSION for linux-x86_64 from $BASE_URL at $PUB_DATE"

# Pass 1: check every format. Nothing is written here.
FORMATS=()
FILES=()
SIGNATURES=()
for format in deb rpm appimage; do
  glob="*.$format"
  [ "$format" = "appimage" ] && glob="*.AppImage"
  artifacts=()
  while IFS= read -r artifact; do
    artifacts+=("$artifact")
  done < <(find "$OUT" -maxdepth 1 -type f -name "$glob" | sort)
  [ "${#artifacts[@]}" -eq 1 ] \
    || die "$format: expected exactly one $glob in dist/linux, found ${#artifacts[@]}"
  artifact="${artifacts[0]}"
  signature="$(cat "$artifact.sig" 2>/dev/null || true)"
  [[ -n "$signature" ]] \
    || die "$format: $(basename "$artifact") has no .sig: the updater would reject it"
  FORMATS+=("$format")
  FILES+=("$(basename "$artifact")")
  SIGNATURES+=("$signature")
done

# Pass 2: write. Each document is built beside its destination, validated by
# re-parsing, and only then renamed into place.
for index in "${!FORMATS[@]}"; do
  format="${FORMATS[$index]}"
  feed_dir="$OUT/feed/$format"
  mkdir -p "$feed_dir"
  temporary="$feed_dir/.latest.json.tmp"
  VERSION="$VERSION" PUB_DATE="$PUB_DATE" BASE_URL="$BASE_URL" \
  FILE="${FILES[$index]}" SIGNATURE="${SIGNATURES[$index]}" \
  python3 - "$temporary" <<'PY'
import json, os, sys

version = os.environ["VERSION"]
document = {
    "version": version,
    "notes": os.environ.get("MORROW_RELEASE_NOTES", f"Morrow {version}"),
    "pub_date": os.environ["PUB_DATE"],
    "platforms": {
        "linux-x86_64": {
            "signature": os.environ["SIGNATURE"],
            "url": f'{os.environ["BASE_URL"]}/{os.environ["FILE"]}',
        },
    },
}
# The checks the client's updater applies, done before the file exists.
platform = document["platforms"]["linux-x86_64"]
assert platform["url"].startswith("https://"), platform
assert platform["signature"].strip(), platform
assert document["version"] == version, document
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2, ensure_ascii=False)
    handle.write("\n")
PY
  # Re-parse what was written: the assertions above can pass while the file on
  # disk does not parse.
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$temporary" \
    || die "$format: the written feed does not parse"
  mv -f "$temporary" "$feed_dir/latest.json"
  say "  $format: ${FILES[$index]} → feed/$format/latest.json"
done

say "linux-manifest: $VERSION — ${#FORMATS[@]} feeds written"
