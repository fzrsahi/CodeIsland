#!/usr/bin/env bash
# Replayable monorepo move for #86: macos/ shared/ linux/ windows/
#
# Replayed on 2026-11-21 and merged as 35017d1 (#171). The pipeline half is NOT
# produced by this script any more: `.woodpecker.yaml` follows the move in its own
# PR, because CODEOWNERS gives that file to @aazhrt. Rerunning this script on a
# tree where the move has happened fails at the first check, by design.
# (docs/plan-windows-linux.md §4, spec #82).
#
# Usage (from a clean checkout of a fresh main):
#   scripts/dev/monorepo-move.sh
#   git add -A && git commit -m 'chore(#86): move the Swift package and macOS assets under macos/'
#
# The script only moves files (git mv) and rewrites the paths that depend on
# the repo root. It changes no runtime behaviour: nothing under macos/Sources
# is edited, so the app, the bridge and the bundled hook plugins are
# byte-identical apart from their location.
#
# Replay safety:
#   - refuses to run when macos/Package.swift exists or the tree is dirty;
#   - optional paths from open PRs (#50, #114, #115) are moved only if present;
#   - every coupling fix is an exact old -> new string with an expected count.
#     All edits are checked in memory first; if any expected string is missing
#     (main changed since this script was written) nothing is rewritten, the
#     failures are listed and the script exits 1. The git mv's are already
#     staged at that point, so run it on a throwaway branch or worktree: undo
#     with `git restore --source=HEAD --staged --worktree :/` and delete the
#     new macos/ shared/ linux/ directories, then update the edit table below;
#   - fails when scripts/ gains a file this table has not decided on, or when
#     a Swift/plist/appcast file is left at the root.
#
# Where each root script goes (decided by reading it):
#
#   script                               -> destination     why
#   build.sh                             -> macos/          builds the .app from the Swift package
#   scripts/build-dmg.sh                 -> macos/scripts/  DMG from the Swift package, Info.plist, assets
#   scripts/swiftpm-release.sh           -> macos/scripts/  sourced by build.sh / build-dmg.sh
#   scripts/update-appcast.sh            -> macos/scripts/  Sparkle appcast (macOS updater only)
#   scripts/dev-hot-restart.sh           -> macos/scripts/  watches Sources/Tests, relaunches the Mac app
#   scripts/perf/                        -> macos/scripts/  benchmarks the Mac app bundle
#   scripts/check-companion-ui-regressions.sh -> macos/scripts/  greps Sources/ + ../ios/
#   scripts/smoke-companion.sh           -> macos/scripts/  swift test + iOS companion build
#   scripts/smoke-companion-ui.sh        -> macos/scripts/  iOS simulator smoke (Apple companion)
#   scripts/smoke-companion-watch-ui.sh  -> macos/scripts/  watchOS simulator smoke (Apple companion)
#   scripts/run-macos-builder.sh         stays scripts/    launches the macOS CI runner VM (CODEOWNERS)
#   scripts/setup-macos-runner.sh        stays scripts/    CommandLineTools/XCTest on that runner (CODEOWNERS)
#   scripts/run-xctest-runner.py         -> macos/scripts/  XCTest harness for the Swift package
#   scripts/report-status.py             stays scripts/     GitHub commit status, any platform's CI
#   scripts/report-pr-failure.py         stays scripts/     posts a CI log excerpt to the PR, any platform
#   scripts/upload-github-release.py     stays scripts/     uploads release assets, any platform
#   scripts/extract-changelog.sh         stays scripts/     reads the root CHANGELOG.md; not macOS-specific
#   scripts/dev/monorepo-move.sh         stays scripts/     this script
#   (the port's lane scripts, #101-#109)
#   scripts/ci/linux-test.sh            -> linux/ci/test.sh      Linux lane (purity + every crate)
#   scripts/ci/linux-package.sh         -> linux/ci/package.sh   Linux packaging
#   scripts/ci/linux-smoke.sh           -> linux/ci/smoke.sh     L-011 install-and-launch
#   scripts/ci/linux-manifest.sh        -> linux/ci/manifest.sh  Linux update feed
#   scripts/ci/windows-check.sh         -> windows/ci/check.sh   Windows lane (type-check)
#   scripts/ci/rust-purity.sh           -> shared/ci/rust-purity.sh + rust-pure-crates.txt
#   (stays: runner infra and verify-local are DevOps' zone, CODEOWNERS pins their paths)
#   (optional, from open PRs)
#   scripts/ci/macos-test.sh             -> macos/ci/test.sh        CI contract (#114)
#   scripts/ci/macos-package.sh          -> macos/ci/package.sh     CI contract (#114)
#   scripts/ci/manifest.sh               -> shared/ci/manifest.sh   CI contract (#114)
#   scripts/validate-*.py, requirements-*.txt -> shared/contract/   contract validators (#50, #115)
set -euo pipefail

die() { printf 'monorepo-move: ERROR: %s\n' "$*" >&2; exit 1; }

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

[ ! -e macos/Package.swift ] || die "macos/Package.swift already exists: the move has been done on this tree"
[ -z "$(git status --porcelain)" ] || die "working tree is not clean (commit or stash first)"
[ -f Package.swift ] || die "no root Package.swift: this is not the pre-move layout"

MOVES="$(mktemp -t monorepo-move.XXXXXX)"
trap 'rm -f "$MOVES"' EXIT

move() { # move <src> <dst>: required path
    [ -e "$1" ] || die "required path missing: $1"
    mkdir -p "$(dirname "$2")"
    git mv "$1" "$2"
    printf '%s\t%s\n' "$1" "$2" >>"$MOVES"
    printf '  moved   %-45s -> %s\n' "$1" "$2"
}
move_optional() { # move_optional <src> <dst>: moved only if present
    if [ -e "$1" ]; then
        move "$1" "$2"
    else
        printf '  absent  %s (skipped)\n' "$1"
    fi
}

echo "==> Moving the Swift package and macOS assets into macos/"
mkdir -p macos/scripts
for p in Package.swift Package.resolved Sources Tests Info.plist Morrow.entitlements \
         Assets.xcassets AppIcon.icon appcast.xml build.sh; do
    move "$p" "macos/$p"
done
move_optional appcast-dev.xml macos/appcast-dev.xml
# run-macos-builder.sh and setup-macos-runner.sh stay in scripts/: CODEOWNERS pins
# them to @aazhrt, and a git mv of an owned file is still an edit of an owned file.
for p in build-dmg.sh swiftpm-release.sh update-appcast.sh dev-hot-restart.sh perf \
         check-companion-ui-regressions.sh smoke-companion.sh smoke-companion-ui.sh \
         smoke-companion-watch-ui.sh run-xctest-runner.py; do
    move "scripts/$p" "macos/scripts/$p"
done

echo "==> Moving the contract and CI scripts (optional, from open PRs)"
move_optional fixtures shared/contract/fixtures
move_optional schemas shared/contract/schemas
move_optional docs/hook-edge-protocol.md shared/contract/hook-edge-protocol.md
move_optional docs/endpoint-contract.md shared/contract/endpoint-contract.md
for f in scripts/validate-*.py scripts/requirements-*.txt; do
    [ -e "$f" ] || continue
    move "$f" "shared/contract/${f#scripts/}"
done
echo "==> Moving the port's lane scripts into their platform directories (\u00a78.1)"
move_optional scripts/ci/linux-test.sh linux/ci/test.sh
move_optional scripts/ci/linux-package.sh linux/ci/package.sh
move_optional scripts/ci/linux-smoke.sh linux/ci/smoke.sh
move_optional scripts/ci/linux-manifest.sh linux/ci/manifest.sh
move_optional scripts/ci/windows-check.sh windows/ci/check.sh
move_optional scripts/ci/rust-purity.sh shared/ci/rust-purity.sh
move_optional scripts/ci/rust-pure-crates.txt shared/ci/rust-pure-crates.txt
move_optional scripts/ci/macos-test.sh macos/ci/test.sh
move_optional scripts/ci/macos-package.sh macos/ci/package.sh
move_optional scripts/ci/manifest.sh shared/ci/manifest.sh

echo "==> Checking nothing was left undecided"
# scripts/ keeps what is not one platform's: the status/release helpers, this
# script, and the DevOps-owned runner and guard scripts. Moving those would edit
# files CODEOWNERS gives to @aazhrt (AGENTS.md \u00a72), so the layout leaves them.
undecided="$(git ls-files scripts | grep -vxE 'scripts/(report-status\.py|report-pr-failure\.py|upload-github-release\.py|extract-changelog\.sh|dev/monorepo-move\.sh|setup-macos-runner\.sh|run-macos-builder\.sh|setup-linux-runner\.sh|ci/verify-local\.sh|ci/test-verify-local\.sh|ci/test-multiplatform-ci\.sh)' || true)"
[ -z "$undecided" ] || die "scripts/ has files this script has not decided on (add them to the table):
$undecided"
leftover_root="$(git ls-files | grep -E '^[^/]+\.(swift|plist|entitlements)$|^appcast[^/]*\.xml$|^(Sources|Tests|Assets\.xcassets|AppIcon\.icon)/' || true)"
[ -z "$leftover_root" ] || die "macOS package files left at the root:
$leftover_root"

echo "==> Adding linux/ and shared/ READMEs"
mkdir -p linux shared
[ ! -e linux/README.md ] || die "linux/README.md already exists"
[ ! -e shared/README.md ] || die "shared/README.md already exists"
cat >linux/README.md <<'EOF'
# linux/

Linux packaging and the Linux-only CI scripts: `.deb`, `.rpm` and `.AppImage` builds, the `.desktop` entry, and `linux/ci/test.sh` / `linux/ci/package.sh` once they exist. The Linux app has no shell code of its own here: it is the shared Tauri app in `shared/desktop/` with the Linux backends selected by `#[cfg]` in `morrow-platform` (see `docs/plan-windows-linux.md` §4).
EOF
cat >shared/README.md <<'EOF'
# shared/

Code and contracts used by more than one OS. `shared/contract/` holds the hook-edge protocol, the JSON schemas, the golden fixtures and their validators that the Swift (macOS), Rust and C# edges are all tested against; `shared/ci/` holds CI scripts that are not tied to one platform. The Rust crates (`shared/crates/`), the Tauri app for Windows and Linux (`shared/desktop/`), the hook plugins and the BLE protocol move in here in later PRs (see `docs/plan-windows-linux.md` §4).
EOF
git add linux/README.md shared/README.md

echo "==> Rewriting root-path couplings"
python3 - "$MOVES" <<'PY'
import os
import re
import subprocess
import sys

moves = [tuple(line.rstrip("\n").split("\t")) for line in open(sys.argv[1]) if line.strip()]
moved_from = {old for old, _ in moves}
failures = []
contents = {}   # path -> current text (in memory until every edit has passed)
originals = {}


def text(path):
    if path not in contents:
        with open(path, encoding="utf-8") as f:
            contents[path] = originals[path] = f.read()
    return contents[path]


def edit(path, old, new, count=1):
    """Replace exactly `count` occurrences of `old` (count=None: all, at least one)."""
    if not os.path.exists(path):
        failures.append(f"{path}: file not found (expected edit {old!r})")
        return
    body = text(path)
    found = body.count(old)
    if found == 0 or (count is not None and found != count):
        want = "at least 1" if count is None else count
        failures.append(f"{path}: expected {want} x {old!r}, found {found}")
        return
    contents[path] = body.replace(old, new)


def map_path(path):
    """Pre-move repo path -> post-move repo path."""
    best = None
    for old, new in moves:
        if path == old or path.startswith(old + "/"):
            if best is None or len(old) > len(best[0]):
                best = (old, new)
    return path if best is None else best[1] + path[len(best[0]):]


def unmap_path(path):
    """Post-move repo path -> pre-move repo path."""
    best = None
    for old, new in moves:
        if path == new or path.startswith(new + "/"):
            if best is None or len(new) > len(best[1]):
                best = (old, new)
    return path if best is None else best[0] + path[len(best[1]):]


def exists(rel):
    return os.path.exists(rel)


# ---------------------------------------------------------------------------
# 1. Build, release and dev scripts (now under macos/)
# ---------------------------------------------------------------------------
# build.sh used paths relative to the cwd (the repo root). It now runs from
# its own directory, the Swift package root.
edit("macos/build.sh",
     "set -euo pipefail\n\n",
     "set -euo pipefail\n\n# Paths below are relative to the Swift package root (macos/).\ncd \"$(dirname \"$0\")\"\n\n")
edit("macos/build.sh", 'WATCH_DIR="android-watch"', 'WATCH_DIR="../android-watch"')
edit("macos/build.sh", '".signing.local"', '"../.signing.local"', count=2)

# build-dmg.sh / update-appcast.sh: REPO_ROOT is the script's parent's parent,
# which is now macos/ — exactly where Info.plist, Assets.xcassets,
# AppIcon.icon, Morrow.entitlements, appcast*.xml, Sources/ and .build/ live.
# Only the comments and the printed release checklist name the repo root.
ROOT_COMMENT = ("# macos/, the Swift package root: Info.plist, the assets, appcast*.xml,\n"
                "# Sources/ and .build/ all live here.\n")
edit("macos/scripts/build-dmg.sh",
     'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"\n',
     ROOT_COMMENT + 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"\n')
edit("macos/scripts/build-dmg.sh", "./scripts/build-dmg.sh", "./macos/scripts/build-dmg.sh", count=3)
edit("macos/scripts/build-dmg.sh", "# Write Info.plist (use the root Info.plist as base",
     "# Write Info.plist (use macos/Info.plist as base")
edit("macos/scripts/build-dmg.sh", 'echo "    2. ./scripts/update-appcast.sh',
     'echo "    2. ./macos/scripts/update-appcast.sh')
edit("macos/scripts/build-dmg.sh", "git add appcast.xml &&", "git add macos/appcast.xml &&")

edit("macos/scripts/update-appcast.sh",
     'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"\n',
     ROOT_COMMENT + 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"\n')
edit("macos/scripts/update-appcast.sh", "# Usage: ./scripts/update-appcast.sh <version> <dmg-path> [appcast-file]",
     "# Usage: ./macos/scripts/update-appcast.sh <version> <dmg-path> [appcast-file]")
edit("macos/scripts/update-appcast.sh", "# Example: ./scripts/update-appcast.sh 1.0.22 .build/Morrow.dmg",
     "# Example: ./macos/scripts/update-appcast.sh 1.0.22 macos/.build/Morrow.dmg")
edit("macos/scripts/update-appcast.sh",
     "# Example: ./scripts/update-appcast.sh 1.0.42-dev .build/Morrow.dmg appcast-dev.xml",
     "# Example: ./macos/scripts/update-appcast.sh 1.0.42-dev macos/.build/Morrow.dmg appcast-dev.xml\n"
     "# (<dmg-path> is relative to the cwd; [appcast-file] to macos/.)")
edit("macos/scripts/update-appcast.sh", "# Produces / updates appcast.xml at the repo root.",
     "# Produces / updates macos/appcast.xml.")

# run-xctest-runner.py defaulted to the cwd (the repo root, from CI). It now
# defaults to the package root next to it, so CI's call needs no --repo-root.
edit("macos/scripts/run-xctest-runner.py",
     'parser.add_argument("--repo-root", default=os.getcwd(), help="Repository root")',
     'parser.add_argument("--repo-root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),\n'
     '                        help="Swift package root (default: macos/, the parent of this script\'s directory)")')

# dev-hot-restart.sh (REPO_ROOT = script_dir/..) and perf/bench.sh
# (REPO_ROOT = script_dir/../..) already resolve to macos/; their watch paths,
# .build/ paths and `git diff -- Sources Package.swift` are relative to it.

# Companion scripts cd to ROOT = script_dir/.., now macos/, so their swift
# commands and Sources/ paths still work; the paths into ios/ gain ../.
# (Simulator derived data and screenshots now land in macos/.build/.)
edit("macos/scripts/check-companion-ui-regressions.sh", '"ios/', '"../ios/', count=21)
edit("macos/scripts/smoke-companion.sh", "-project ios/MorrowCompanion/", "-project ../ios/MorrowCompanion/")
edit("macos/scripts/smoke-companion-ui.sh", 'PROJECT="ios/', 'PROJECT="../ios/')
edit("macos/scripts/smoke-companion-watch-ui.sh", 'PROJECT="ios/', 'PROJECT="../ios/')

# Opt-in screenshot harnesses: `swift test` now runs from macos/, and their
# output still belongs in the root docs/images/ (doc comments only).
edit("macos/Tests/MorrowTests/ReadmeScreenshotHarness.swift",
     "README_SHOT_DIR=docs/images swift test", "README_SHOT_DIR=../docs/images swift test")
edit("macos/Tests/MorrowTests/ReadmeScreenshotHarness.swift",
     "glob.glob('docs/images/readme-*.png')", "glob.glob('../docs/images/readme-*.png')")
edit("macos/Tests/MorrowTests/MascotRenderHarness.swift",
     "`MASCOT_GIF_DIR=docs/images/mascots`", "`MASCOT_GIF_DIR=../docs/images/mascots`")

# ---------------------------------------------------------------------------
# 2. Git hooks
# ---------------------------------------------------------------------------
edit(".githooks/pre-push",
     'echo "==> [Pre-Push Hook] Verifying build & unit tests locally..."\n',
     '# The Swift package lives in macos/ (hooks run from the repo root).\n'
     'cd "$(git rev-parse --show-toplevel)/macos" || exit 1\n\n'
     'echo "==> [Pre-Push Hook] Verifying build & unit tests locally..."\n')
edit(".githooks/pre-push", "Run 'swift build --build-tests' to view", "Run 'cd macos && swift build --build-tests' to view")
# .githooks/pre-commit works on `git diff --cached --name-only` paths from the
# repo root and is layout-independent: no change.

# ---------------------------------------------------------------------------
# 3. Woodpecker CI. Its path filters and its three macos/ calls move with the
#    package, but **this script does not write .woodpecker.yaml**: CODEOWNERS
#    and AGENTS.md §2 give the pipeline to @aazhrt, so the same substitutions are
#    computed in memory and written as a patch, `docs/ci/woodpecker-monorepo-paths.patch`.
#    One `git apply` and the pipeline follows the move; merging this PR without
#    it leaves CI calling files that are no longer at the root, which is why the
#    PR stays a draft until its owner applies it.
# ---------------------------------------------------------------------------
WP = ".woodpecker.yaml"
edit(WP, '        - "Info.plist"', '        - "macos/Info.plist"', count=2)
edit(WP, '        - "scripts/run-xctest-runner.py"', '        - "macos/scripts/run-xctest-runner.py"', count=2)
edit(WP, "' Info.plist 2>/dev/null", "' macos/Info.plist 2>/dev/null")
edit(WP, "./scripts/ci/macos-test.sh", "./macos/ci/test.sh")
edit(WP, "./scripts/ci/macos-package.sh", "./macos/ci/package.sh", count=2)
edit(WP, "./scripts/ci/manifest.sh", "./shared/ci/manifest.sh", count=2)
# The Linux and Windows lanes moved into linux/ci and windows/ci; the filters
# follow the directories and the two steps follow the scripts.
edit(WP, '        - "scripts/ci/linux*"', '        - "linux/ci/**"', count=2)
edit(WP, '        - "scripts/ci/windows*"', '        - "windows/ci/**"', count=2)
edit(WP, '        - "scripts/ci/rust*"', '        - "shared/ci/**"', count=2)
edit(WP, 'if [ -f "./scripts/ci/linux-test.sh" ]; then\n          ./scripts/ci/linux-test.sh',
        'if [ -f "./linux/ci/test.sh" ]; then\n          ./linux/ci/test.sh')
edit(WP, "./scripts/ci/windows-check.sh", "./windows/ci/check.sh")
edit(WP, '        - "Sources/**"', '        - "macos/Sources/**"', count=2)
edit(WP, '        - "Tests/**"', '        - "macos/Tests/**"', count=2)

# ---------------------------------------------------------------------------
# 4. CI-contract scripts (#114), if present. REPO_ROOT (script_dir/../..) is
#    still the repo root from macos/ci and shared/ci; dist/ stays at the root.
# ---------------------------------------------------------------------------
if exists("macos/ci/test.sh"):
    f = "macos/ci/test.sh"
    edit(f, "# Usage: scripts/ci/macos-test.sh", "# Usage: macos/ci/test.sh")
    edit(f, "# exits non-zero if the build or any test fails. Interim location until the\n"
            "# monorepo move, after which this becomes macos/ci/test.sh.\n",
         "# exits non-zero if the build or any test fails.\n")
    edit(f, "python3 ./scripts/run-xctest-runner.py", "python3 ./macos/scripts/run-xctest-runner.py")
if exists("macos/ci/package.sh"):
    f = "macos/ci/package.sh"
    edit(f, "# Usage: scripts/ci/macos-package.sh <version>", "# Usage: macos/ci/package.sh <version>")
    edit(f, "# Builds the DMG with scripts/build-dmg.sh", "# Builds the DMG with macos/scripts/build-dmg.sh")
    edit(f, "# Interim location until the monorepo move (then macos/ci/package.sh).\n", "")
    edit(f, './scripts/build-dmg.sh "$VERSION"', './macos/scripts/build-dmg.sh "$VERSION"')
    edit(f, ".build/Morrow.dmg", "macos/.build/Morrow.dmg", count=3)
if exists("shared/ci/manifest.sh"):
    f = "shared/ci/manifest.sh"
    edit(f, "# Usage: scripts/ci/manifest.sh <version>", "# Usage: shared/ci/manifest.sh <version>")
    edit(f, "with scripts/update-appcast.sh", "with macos/scripts/update-appcast.sh")
    edit(f, "from the repo-root appcast of the same name", "from macos/'s appcast of the same name")
    edit(f, " Interim location until the monorepo move (then\n# shared/ci/manifest.sh).\n", "\n")
    edit(f, "Run scripts/ci/macos-package.sh $VERSION first.", "Run macos/ci/package.sh $VERSION first.")
    edit(f, '"$REPO_ROOT/$APPCAST_NAME"', '"$REPO_ROOT/macos/$APPCAST_NAME"', count=2)
    edit(f, './scripts/update-appcast.sh "$VERSION"', './macos/scripts/update-appcast.sh "$VERSION"')

# ---------------------------------------------------------------------------
# 4b. The lane scripts themselves: their usage lines name themselves, and the
#     few cross-calls (linux/ci/test.sh runs the purity gate) follow the move.
#     Every script resolves REPO_ROOT as script_dir/../.., which is the repo root
#     from macos/ci, linux/ci, windows/ci and shared/ci alike: no path logic
#     changes, only the names they print.
# ---------------------------------------------------------------------------
for f, old, new in [
    ("linux/ci/test.sh", "step purity scripts/ci/rust-purity.sh", "step purity shared/ci/rust-purity.sh"),
    ("linux/ci/smoke.sh", "scripts/ci/linux-smoke.sh", "linux/ci/smoke.sh"),
    ("linux/ci/manifest.sh", "scripts/ci/linux-manifest.sh", "linux/ci/manifest.sh"),
    ("linux/ci/package.sh", "scripts/ci/linux-package.sh", "linux/ci/package.sh"),
    ("linux/ci/test-desktop.sh", "scripts/ci/linux-test.sh", "linux/ci/test.sh"),
    ("windows/ci/check.sh", "scripts/ci/windows-check.sh", "windows/ci/check.sh"),
    ("shared/ci/rust-purity.sh", "scripts/ci/rust-pure-crates.txt", "shared/ci/rust-pure-crates.txt"),
    ("shared/ci/rust-pure-crates.txt", "scripts/ci/rust-purity.sh", "shared/ci/rust-purity.sh"),
    # The "interim location" notes are now false: this is the final location.
    ("linux/ci/test.sh", "\n# Moves to linux/ci/test.sh with the monorepo layout (#86).", ""),
    ("linux/ci/package.sh", " Moves to linux/ci/package.sh with the monorepo layout (#86).", ""),
]:
    if exists(f):
        edit(f, old, new, count=None)

# The Rust tests reach the golden fixtures through CARGO_MANIFEST_DIR, which is
# three levels under the repo root either way (shared/crates/<crate>), so only
# the last components move. Every test crate does it the same way.
import glob as _glob
for f in _glob.glob("shared/crates/*/tests/**/*.rs", recursive=True) + _glob.glob("shared/crates/*/src/**/*.rs", recursive=True):
    if not os.path.isfile(f):
        continue
    if '"../../../fixtures' in text(f):
        edit(f, '"../../../fixtures', '"../../../shared/contract/fixtures', count=None)
    if '"../../../schemas' in text(f):
        edit(f, '"../../../schemas', '"../../../shared/contract/schemas', count=None)

# This one names the table as a constant and joins it onto ../../.. itself, so
# only the constant moves (and the comment that predicted this move retires).
edit("shared/crates/morrow-ipc/tests/endpoint_cases.rs",
     'const CASES_PATH: &str = "fixtures/endpoint/cases.json";',
     'const CASES_PATH: &str = "shared/contract/fixtures/endpoint/cases.json";')
edit("shared/crates/morrow-protocol/tests/conformance.rs",
     '/// Where the golden fixtures live, from the repository root. The monorepo\n'
     '/// move (#86) changes this to `shared/contract/fixtures`; nothing else\n'
     '/// names the path.\n'
     'const FIXTURE_ROOT: &str = "fixtures";',
     '/// Where the golden fixtures live, from the repository root (#86 moved them\n'
     '/// under shared/). Nothing else names the path.\n'
     'const FIXTURE_ROOT: &str = "shared/contract/fixtures";')
edit("shared/crates/morrow-ipc/tests/endpoint_cases.rs",
     "/// The case table, from the repository root. The monorepo move (#86)\n"
     "/// changes this to `shared/contract/fixtures/endpoint/cases.json`; nothing\n"
     "/// else names the path.\n",
     "/// The case table, from the repository root (#86 moved it under shared/).\n")

# The root-kept CI tests name the scripts they exercise.
edit("scripts/ci/test-multiplatform-ci.sh", "scripts/ci/windows-check.sh", "windows/ci/check.sh", count=None)

# ---------------------------------------------------------------------------
# 5. Contract validators and the tests reading fixtures (#50, #115), if present.
#    The validators now sit next to fixtures/ and schemas/.
# ---------------------------------------------------------------------------
if exists("shared/contract/validate-fixtures.py"):
    f = "shared/contract/validate-fixtures.py"
    edit(f, "root = Path(__file__).resolve().parent.parent", "root = Path(__file__).resolve().parent")
    edit(f, "scripts/requirements-fixtures.txt", "shared/contract/requirements-fixtures.txt", count=None)
if exists("shared/contract/validate-endpoint-cases.py"):
    f = "shared/contract/validate-endpoint-cases.py"
    edit(f, "ROOT = pathlib.Path(__file__).resolve().parent.parent", "ROOT = pathlib.Path(__file__).resolve().parent")
    edit(f, "scripts/requirements-endpoint-cases.txt", "shared/contract/requirements-endpoint-cases.txt", count=None)
if "fixtures" in moved_from:
    if exists("macos/Tests/MorrowCoreTests/BridgeGoldenJSONExporter.swift"):
        edit("macos/Tests/MorrowCoreTests/BridgeGoldenTests.swift",
             '.appendingPathComponent("fixtures", isDirectory: true)',
             '.deletingLastPathComponent().appendingPathComponent("shared/contract/fixtures", isDirectory: true)')
    if exists("macos/Tests/MorrowCoreTests/EndpointContractTests.swift"):
        edit("macos/Tests/MorrowCoreTests/EndpointContractTests.swift",
             '.appendingPathComponent("fixtures/endpoint/cases.json")',
             '.deletingLastPathComponent().appendingPathComponent("shared/contract/fixtures/endpoint/cases.json")')
    if exists("shared/contract/fixtures/README.md"):
        f = "shared/contract/fixtures/README.md"
        edit(f, 'CODEISLAND_GOLDEN_EXPORT_JSON="$(pwd)/fixtures" swift test --filter',
             'CODEISLAND_GOLDEN_EXPORT_JSON="$(pwd)/shared/contract/fixtures" swift test --package-path macos --filter')
        edit(f, "\nswift test --filter BridgeGoldenTests\n", "\nswift test --package-path macos --filter BridgeGoldenTests\n")

# ---------------------------------------------------------------------------
# 6. iOS companion project, deploy fallback, docs that run commands
# ---------------------------------------------------------------------------
edit("ios/MorrowCompanion/project.yml", "../../Sources/Morrow/", "../../macos/Sources/Morrow/", count=None)
edit("ios/MorrowCompanion/MorrowCompanion.xcodeproj/project.pbxproj",
     "path = ../../Sources/Morrow;", "path = ../../macos/Sources/Morrow;")
edit("ios/MorrowCompanion/Shared/L10n.swift", "`Sources/Morrow/L10n.swift`", "`macos/Sources/Morrow/L10n.swift`")
edit("deploy/debian/deploy-morrow.sh", "/main/appcast.xml", "/main/macos/appcast.xml")

edit("README.md", "\ncd morrow\n", "\ncd morrow/macos\n")
edit("README.zh-CN.md", "\ncd morrow\n", "\ncd morrow/macos\n")
edit("CONTRIBUTING.md", "   ./build.sh\n   open .build/release/Morrow.app",
     "   ./macos/build.sh\n   open macos/.build/release/Morrow.app")
edit("CONTRIBUTING.md", "   ```bash\n   swift build\n   ```", "   ```bash\n   swift build --package-path macos\n   ```")
edit("CONTRIBUTING.md", "pushing:\n   ```bash\n   ./build.sh\n", "pushing:\n   ```bash\n   ./macos/build.sh\n")
edit(".agents/skills/pr/SKILL.md", "(`./build.sh`)", "(`./macos/build.sh`)")
edit("apple-companion/APP_STORE_RELEASE.md", "swift test --filter AppleCompanionPayloadTests",
     "swift test --package-path macos --filter AppleCompanionPayloadTests")
edit("apple-companion/DEVICE_TESTING.md", "swift test -c release", "swift test --package-path macos -c release")
edit("apple-companion/README.md", "# Swift 单元测试\nswift test\n", "# Swift 单元测试\nswift test --package-path macos\n")

# ---------------------------------------------------------------------------
# 7. Markdown links and path mentions (mechanical, logged per file)
# ---------------------------------------------------------------------------
tracked = subprocess.run(["git", "ls-files", "-z"], check=True, capture_output=True).stdout.decode().split("\0")
markdown = [p for p in tracked if p.endswith(".md") and os.path.isfile(p)]

# 7a. Relative links (](x), src="x", href="x") whose source or target moved.
LINK = re.compile(r'(\]\(|src="|href=")([^)"\s#?]+)')
link_log = {}
for path in markdown:
    old_src = unmap_path(path)
    def fix(m):
        target = m.group(2)
        if re.match(r"^[a-z][a-z0-9+.-]*:", target, re.I) or target.startswith("/"):
            return m.group(0)
        old_target = os.path.normpath(os.path.join(os.path.dirname(old_src), target))
        if old_target.startswith(".."):
            return m.group(0)
        new_target = map_path(old_target)
        if new_target == old_target and path == old_src:
            return m.group(0)
        if not os.path.exists(new_target):
            return m.group(0)  # link was already broken; leave it for a human
        rel = os.path.relpath(new_target, os.path.dirname(path) or ".")
        if target.endswith("/") and not rel.endswith("/"):
            rel += "/"
        if rel == target:
            return m.group(0)
        link_log[path] = link_log.get(path, 0) + 1
        return m.group(1) + rel
    body = text(path)
    contents[path] = LINK.sub(fix, body)

# 7b. Root-relative path mentions (`Sources/...`, scripts/build-dmg.sh, ...)
#     in living docs outside macos/. Historical records keep the paths they
#     were written with: the changelogs, ADRs, the plan (§4 lists the pre-move
#     couplings on purpose), the progress log, research notes and archives.
HISTORICAL = re.compile(r"^(CHANGELOG\.md|CHANGES-cline\.md|docs/plan-windows-linux\.md|"
                        r"docs/progress-windows-linux-port\.md|docs/adr/|docs/archive/|docs/research-|"
                        r"docs/experiments/|windows/Morrow-Windows-Complete-Development-Plan\.md|\.omg/|macos/|"
                        r"scripts/dev/monorepo-move\.sh$)")  # never rewrite this script while bash reads it
BARE_ROOT_FILES = {"Package.swift", "Package.resolved", "Info.plist", "Morrow.entitlements",
                   "Assets.xcassets", "AppIcon.icon", "appcast.xml", "appcast-dev.xml", "build.sh"}
tokens = []
for old, new in moves:
    if old in BARE_ROOT_FILES:
        continue  # ordinary words in prose; command mentions are edited above
    if os.path.isdir(new):
        tokens.append((re.escape(old) + "/", new + "/"))
    else:
        tokens.append((re.escape(old) + r"(?=$|[\s`'\")\].,:;])", new))
mention_log = {}
for path in markdown:
    if HISTORICAL.match(path):
        continue
    body = text(path)
    for pattern, new in tokens:
        rx = re.compile(r"(^|[\s`'\"(\[|*])(\./)?" + pattern, re.M)
        body, n = rx.subn(lambda m, new=new: m.group(1) + (m.group(2) or "") + new, body)
        if n:
            mention_log[path] = mention_log.get(path, 0) + n
    contents[path] = body

# 7c. The moved contract docs are also named in code comments and fixture
#     data (windows/*.cs, shared/contract/fixtures, schemas). macos/ is left
#     alone: a comment in a bundled hook plugin is part of the shipped bytes.
doc_moves = [(old, new) for old, new in moves if old.startswith("docs/") and old.endswith(".md")]
for path in tracked:
    if not os.path.isfile(path) or path.endswith(".md") or HISTORICAL.match(path):
        continue
    try:
        body = text(path)
    except UnicodeDecodeError:
        continue
    for old, new in doc_moves:
        body, n = re.subn(r"(?<![\w/.-])" + re.escape(old), new, body)
        if n:
            mention_log[path] = mention_log.get(path, 0) + n
    contents[path] = body

# ---------------------------------------------------------------------------
# 7d. Code comments and include_str! that point at the Swift tree. The Rust
#     crates were ported file by file and each module's header names the Swift
#     file it came from; those names are how the next reader finds the original,
#     so they follow the move. macos/ is skipped: a comment inside a bundled hook
#     plugin is part of the bytes we ship.
# ---------------------------------------------------------------------------
code_dirs = ("shared/", "linux/", "windows/", "deploy/", "ios/", "apple-companion/", "android-watch/", "hardware/")
for path in tracked:
    if not path.startswith(code_dirs) or path.endswith(".md") or HISTORICAL.match(path) or not os.path.isfile(path):
        continue
    try:
        body = text(path)
    except UnicodeDecodeError:
        continue
    before = body
    for old, new in (('Sources/', 'macos/Sources/'), ('Tests/', 'macos/Tests/')):
        body = re.sub(r"(?<![\w/.-])" + re.escape(old), new, body)
    # include_str!/include_bytes! resolve against the file's own directory, so a
    # relative reference just gains the directory it now lives under.
    body = body.replace('include_str!("../../../Sources/', 'include_str!("../../../macos/Sources/')
    body = body.replace('include_str!("../../../../Sources/', 'include_str!("../../../../macos/Sources/')
    if body != before:
        contents[path] = body
        mention_log[path] = mention_log.get(path, 0) + 1

# ---------------------------------------------------------------------------
# 8. Fail before writing anything if an expected string was missing
# ---------------------------------------------------------------------------
if failures:
    print("monorepo-move: ERROR: these expected strings were not found; nothing was rewritten:", file=sys.stderr)
    for line in failures:
        print("  - " + line, file=sys.stderr)
    print("main changed since the script was written: update the edit table, then rerun on a clean tree "
          "(git restore --source=HEAD --staged --worktree :/ undoes the staged moves).", file=sys.stderr)
    sys.exit(1)

# Woodpecker must not call a moved script or read a root .build/ any more
# (a `(cd macos && ...)` subshell is the one place .build/ is package-relative).
wp = re.sub(r"\(cd macos && [^)]*\)", "", contents.get(WP, ""))  # the patched text
stale = re.findall(r"(?<![\w/])(?:\./)?scripts/(?!report-status\.py|report-pr-failure\.py|upload-github-release\.py)[\w./-]+"
                   r"|(?<![\w/.])\.build/", wp)
if stale:
    print(f"monorepo-move: ERROR: {WP} still uses root paths: {sorted(set(stale))}", file=sys.stderr)
    sys.exit(1)

changed = [p for p in contents if contents[p] != originals[p] and p != WP]
for path in sorted(changed):
    with open(path, "w", encoding="utf-8") as f:
        f.write(contents[path])
print(f"  edited  {len(changed)} files")

if WP in originals and contents.get(WP) != originals[WP]:
    import difflib
    patch = "".join(difflib.unified_diff(
        originals[WP].splitlines(True), contents[WP].splitlines(True),
        fromfile="a/" + WP, tofile="b/" + WP, n=3))
    os.makedirs("docs/ci", exist_ok=True)
    with open("docs/ci/woodpecker-monorepo-paths.patch", "w", encoding="utf-8") as f:
        f.write(patch)
    print("  patch   docs/ci/woodpecker-monorepo-paths.patch (for @aazhrt; not applied)")
for path in sorted(link_log):
    print(f"  links   {path}: {link_log[path]}")
for path in sorted(mention_log):
    print(f"  paths   {path}: {mention_log[path]}")
PY

git add -A

echo "==> Remaining root-path mentions outside macos/ (review; historical docs are expected)"
git grep -n -E '(^|[^/.A-Za-z_-])(Sources|Tests)/(Morrow|GoldenAncestryStub|TestDefaultsReset)|(^|[^/A-Za-z_-])scripts/(build-dmg|swiftpm-release|update-appcast|dev-hot-restart|perf/|check-companion|smoke-companion|run-macos-builder|setup-macos-runner|run-xctest-runner)|docs/(hook-edge-protocol|endpoint-contract)\.md' \
    -- ':!macos' ':!scripts/dev/monorepo-move.sh' | cut -c1-160 || true

echo "==> Done. Review with: git status && git diff --cached -M --stat"
