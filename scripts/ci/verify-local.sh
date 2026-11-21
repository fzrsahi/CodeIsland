#!/usr/bin/env bash
# ==============================================================================
# Morrow Local Pre-Push & Pre-Commit Verification Guard
# Fast (< 5s), zero-dependency sanity check for staged & modified files.
# ==============================================================================

set -eo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

echo "==> Running Morrow local verification guard..."

# Determine files to inspect: staged files if any, otherwise modified tracked files
TARGET_FILES=$(git diff --cached --name-only --diff-filter=ACM)
if [ -z "$TARGET_FILES" ]; then
    TARGET_FILES=$(git diff --name-only --diff-filter=ACM)
fi

if [ -z "$TARGET_FILES" ]; then
    echo "Notice: No staged or modified files detected. Working tree clean."
    exit 0
fi

# 1. Check for unresolved merge conflict markers
CONFLICT_FILES=$(echo "$TARGET_FILES" | while read -r f; do
    if [ -f "$f" ] && grep -En "^(<<<<<<<|=======|>>>>>>>)" "$f" >/dev/null 2>&1; then
        echo "$f"
    fi
done)
if [ -n "$CONFLICT_FILES" ]; then
    echo "ERROR: Unresolved merge conflict markers found in:"
    echo "$CONFLICT_FILES"
    echo "Resolve all conflict markers before proceeding."
    exit 1
fi

# 2. Check for oversized assets (> 5MB)
MAX_BYTES=5242880
OVERSIZED=$(echo "$TARGET_FILES" | while read -r f; do
    if [ -f "$f" ]; then
        size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0)
        if [ "$size" -gt "$MAX_BYTES" ]; then echo "$f ($((size/1024/1024))MB)"; fi
    fi
done)
if [ -n "$OVERSIZED" ]; then
    echo "ERROR: The following files exceed 5MB limit:"
    echo "$OVERSIZED"
    echo "Avoid committing large binary assets into git history."
    exit 1
fi

# 3. Guardrail: Protect CI/CD configurations from unauthorized modification
RESTRICTED_FILES=$(echo "$TARGET_FILES" | grep -E "^(\.woodpecker\.yaml|\.github/workflows/)" || true)
if [ -n "$RESTRICTED_FILES" ]; then
    # If a merge is in progress, ignore restricted files whose staged content matches MERGE_HEAD
    # (i.e. brought in cleanly from the merged branch such as origin/main without local alteration)
    if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
        FILTERED_RESTRICTED=""
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            if ! git diff --quiet --cached MERGE_HEAD -- "$f"; then
                FILTERED_RESTRICTED="${FILTERED_RESTRICTED}${f}"$'\n'
            fi
        done <<< "$RESTRICTED_FILES"
        RESTRICTED_FILES=$(printf "%s" "$FILTERED_RESTRICTED" | sed '/^$/d')
    fi
fi

if [ -n "$RESTRICTED_FILES" ]; then
    CURRENT_USER=$(git config user.name 2>/dev/null || echo "")
    CURRENT_EMAIL=$(git config user.email 2>/dev/null || echo "")
    CURRENT_ACTOR="${GITHUB_ACTOR:-$CURRENT_USER}"

    if [[ "$CURRENT_ACTOR" != *"aazhrt"* && "$CURRENT_EMAIL" != *"aazhrt"* && "$CURRENT_EMAIL" != *"muhammadazharr"* ]]; then
        echo "======================================================================"
        echo "BLOCKED: Restricted file modification detected!"
        echo "Files:"
        echo "$RESTRICTED_FILES"
        echo ""
        echo "Policy: CI/CD pipelines (.woodpecker.yaml, .github/) are managed"
        echo "exclusively by DevOps (@aazhrt). Refer to AGENTS.md §2."
        echo ""
        echo "To add or modify test steps, provide an independent test script in"
        echo "'scripts/ci/' or coordinate via a GitHub RFC issue."
        echo "======================================================================"
        exit 1
    fi
fi

# 4. Fast Swift syntax verification (if Swift files changed and swiftc available)
SWIFT_FILES=$(echo "$TARGET_FILES" | grep -E '\.swift$' || true)
if [ -n "$SWIFT_FILES" ] && command -v swiftc >/dev/null 2>&1; then
    for sf in $SWIFT_FILES; do
        if [ -f "$sf" ]; then
            swiftc -parse "$sf" 2>/dev/null || {
                echo "ERROR: Swift syntax error in $sf"
                exit 1
            }
        fi
    done
fi

# 5. Fast Rust workspace check (if Cargo.toml exists and cargo available)
if [ -f "Cargo.toml" ] && command -v cargo >/dev/null 2>&1; then
    cargo check --quiet --workspace 2>/dev/null || {
        echo "ERROR: 'cargo check' failed on local workspace."
        exit 1
    }
fi

echo "✅ Local verification passed. Clean to commit & push."
exit 0
