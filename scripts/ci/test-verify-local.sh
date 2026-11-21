#!/usr/bin/env bash
# ==============================================================================
# TDD Test Suite for Morrow scripts/ci/verify-local.sh
# Verifies restricted zones, merge commit exceptions, and conflict detection.
# ==============================================================================

set -eo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ORIGINAL_VERIFY="$REPO_ROOT/scripts/ci/verify-local.sh"

if [ ! -f "$ORIGINAL_VERIFY" ]; then
    echo "ERROR: Cannot find $ORIGINAL_VERIFY"
    exit 1
fi

TMP_DIR=$(mktemp -d /tmp/morrow-tdd-XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "==> Setting up isolated test repository in $TMP_DIR..."
cd "$TMP_DIR"
git init -b main --quiet
git config user.name "DevOps Admin"
git config user.email "aazhrt@users.noreply.github.com"

# Install verify-local.sh into tmp repo
mkdir -p "$TMP_DIR/scripts/ci"
cp "$ORIGINAL_VERIFY" "$TMP_DIR/scripts/ci/verify-local.sh"
chmod +x "$TMP_DIR/scripts/ci/verify-local.sh"
VERIFY_SCRIPT="$TMP_DIR/scripts/ci/verify-local.sh"

# Setup initial commit
echo "initial ci" > .woodpecker.yaml
echo "hello world" > app.txt
git add .
git commit -m "initial commit" --quiet

# Helper to run verify script in this tmp repo
run_guard() {
    "$VERIFY_SCRIPT" >/dev/null 2>&1
}

# ------------------------------------------------------------------------------
# Test 1: Non-restricted file modification by non-DevOps -> PASS
# ------------------------------------------------------------------------------
echo -n "Test 1: Non-restricted modification by developer... "
git checkout -b feat/app --quiet
git config user.name "Amal Device"
git config user.email "amal@example.com"
echo "feature update" >> app.txt
git add app.txt
if run_guard; then
    echo "PASS ✅"
else
    echo "FAIL ❌"
    exit 1
fi
git commit -m "amal feature" --quiet

# ------------------------------------------------------------------------------
# Test 2: Direct .woodpecker.yaml modification by non-DevOps -> BLOCKED
# ------------------------------------------------------------------------------
echo -n "Test 2: Direct restricted file edit by non-DevOps... "
echo "hacked pipeline" >> .woodpecker.yaml
git add .woodpecker.yaml
if ! run_guard; then
    echo "PASS (Blocked as expected) ✅"
else
    echo "FAIL (Allowed unauthorized edit!) ❌"
    exit 1
fi
git restore --staged .woodpecker.yaml
git checkout -- .woodpecker.yaml

# ------------------------------------------------------------------------------
# Test 3: Direct .woodpecker.yaml modification by DevOps (@aazhrt) -> PASS
# ------------------------------------------------------------------------------
echo -n "Test 3: Direct restricted file edit by DevOps (@aazhrt)... "
git config user.name "aazhrt"
git config user.email "aazhrt@users.noreply.github.com"
echo "authorized pipeline update" >> .woodpecker.yaml
git add .woodpecker.yaml
if run_guard; then
    echo "PASS ✅"
else
    echo "FAIL ❌"
    exit 1
fi
git restore --staged .woodpecker.yaml
git checkout -- .woodpecker.yaml

# ------------------------------------------------------------------------------
# Test 4 (Issue #124): Upstream merge bringing .woodpecker.yaml -> MUST PASS
# ------------------------------------------------------------------------------
echo -n "Test 4 (Issue #124): Merge origin/main bringing CI update into feature... "
# DevOps updates .woodpecker.yaml and app.txt on main
git checkout main --quiet
git config user.name "aazhrt"
git config user.email "aazhrt@users.noreply.github.com"
echo "pipeline v2 by aazhrt" > .woodpecker.yaml
echo "conflict line on main" > app.txt
git add .
git commit -m "devops main update" --quiet

# Amal on feature branch merges main
git checkout feat/app --quiet
git config user.name "Amal Device"
git config user.email "amal@example.com"
set +e
git merge main --quiet >/dev/null 2>&1
set -e

# Resolve app.txt conflict and stage it (leaving .woodpecker.yaml unchanged from main)
echo "resolved app conflict" > app.txt
git add app.txt

TEST_4_FAILED=""
if run_guard; then
    echo "PASS ✅"
else
    echo "FAIL (False-positive blocked legitimate merge!) ❌"
    TEST_4_FAILED=1
fi

# ------------------------------------------------------------------------------
# Test 5: Malicious edit to .woodpecker.yaml during merge -> MUST BE BLOCKED
# ------------------------------------------------------------------------------
echo -n "Test 5: Tampering with .woodpecker.yaml during merge conflict... "
echo "tampered during merge" >> .woodpecker.yaml
git add .woodpecker.yaml
if ! run_guard; then
    echo "PASS (Blocked tampering during merge) ✅"
else
    echo "FAIL (Failed to detect tampering during merge!) ❌"
    exit 1
fi

if [ -n "$TEST_4_FAILED" ]; then
    echo ""
    echo "==> TDD RED PHASE CONFIRMED: Test 4 reproduced Issue #124 failure as expected."
    exit 2
fi

echo ""
echo "==> ALL TDD TESTS PASSED SUCCESSFULLY! 🚀"
exit 0
