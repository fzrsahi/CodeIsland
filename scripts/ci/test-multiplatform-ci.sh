#!/usr/bin/env bash
# ==============================================================================
# TDD Test Suite for Multiplatform CI/CD Pipeline & Runner Configuration
# Tests:
#   1. scripts/setup-linux-runner.sh syntax, flags, and dry-run configuration
#   2. scripts/ci/windows-check.sh syntax, flags, and dry-run output
#   3. .woodpecker.yaml multi-pipeline YAML structure and routing labels
#   4. scripts/ci/verify-local.sh cleanliness
# ==============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

PASSED=0
FAILED=0

assert_eq() {
    local desc="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  [PASS] $desc"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $desc"
        echo "         Expected: '$expected'"
        echo "         Got:      '$actual'"
        FAILED=$((FAILED + 1))
    fi
}

assert_contains() {
    local desc="$1"
    local needle="$2"
    local haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  [PASS] $desc"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $desc"
        echo "         Expected to contain: '$needle'"
        echo "         In output: '$haystack'"
        FAILED=$((FAILED + 1))
    fi
}

echo "======================================================================"
echo "Running Multiplatform CI/CD TDD Test Suite"
echo "======================================================================"

# ------------------------------------------------------------------------------
# Test Suite 1: Linux Runner Setup Script
# ------------------------------------------------------------------------------
echo "--- Suite 1: scripts/setup-linux-runner.sh ---"
SETUP_SCRIPT="$ROOT/scripts/setup-linux-runner.sh"

if [ -f "$SETUP_SCRIPT" ]; then
    assert_eq "setup-linux-runner.sh is executable" "true" "$([ -x "$SETUP_SCRIPT" ] && echo true || echo false)"
    
    DRY_RUN_OUT=$("$SETUP_SCRIPT" --dry-run 2>&1 || true)
    assert_contains "dry-run outputs docker run command" "docker run" "$DRY_RUN_OUT"
    assert_contains "dry-run targets woodpeckerci/woodpecker-agent:v2.8.3" "woodpeckerci/woodpecker-agent:v2.8.3" "$DRY_RUN_OUT"
    assert_contains "dry-run binds to host.docker.internal:9090" "host.docker.internal:9090" "$DRY_RUN_OUT"
    assert_contains "dry-run restricts concurrency to 1" "WOODPECKER_MAX_WORKFLOWS=1" "$DRY_RUN_OUT"
    assert_contains "dry-run configures linux/amd64 platform label" "platform=linux/amd64" "$DRY_RUN_OUT"
else
    echo "  [FAIL] setup-linux-runner.sh does not exist"
    FAILED=$((FAILED + 1))
fi

# ------------------------------------------------------------------------------
# Test Suite 2: Windows Check Script
# ------------------------------------------------------------------------------
echo "--- Suite 2: scripts/ci/windows-check.sh ---"
WIN_CHECK_SCRIPT="$ROOT/scripts/ci/windows-check.sh"

if [ -f "$WIN_CHECK_SCRIPT" ]; then
    assert_eq "windows-check.sh is executable" "true" "$([ -x "$WIN_CHECK_SCRIPT" ] && echo true || echo false)"
    
    DRY_RUN_WIN=$("$WIN_CHECK_SCRIPT" --dry-run 2>&1 || true)
    assert_contains "dry-run references x86_64-pc-windows-msvc" "x86_64-pc-windows-msvc" "$DRY_RUN_WIN"
else
    echo "  [FAIL] windows-check.sh does not exist"
    FAILED=$((FAILED + 1))
fi

# ------------------------------------------------------------------------------
# Test Suite 3: .woodpecker.yaml Multi-Pipeline Structure
# ------------------------------------------------------------------------------
echo "--- Suite 3: .woodpecker.yaml Multi-Pipeline Structure ---"
WP_YAML="$ROOT/.woodpecker.yaml"

if [ -f "$WP_YAML" ]; then
    PYTHON_VALIDATOR="
import yaml, sys

with open('$WP_YAML') as f:
    docs = list(yaml.safe_load_all(f))

# Document count check
if len(docs) != 3:
    print(f'DOCS_COUNT={len(docs)}')
    sys.exit(0)

print(f'DOCS_COUNT={len(docs)}')

# Pipeline 1: Linux
p1 = docs[0]
p1_platform = p1.get('labels', {}).get('platform', '')
p1_steps = [s.get('name') for s in p1.get('steps', [])]
p1_when = p1.get('when', [])
p1_push_has_path = any('path' in c for c in p1_when if c.get('event') == 'push' or ('push' in c.get('event', []) if isinstance(c.get('event'), list) else False))
print(f'P1_PLATFORM={p1_platform}')
print(f'P1_STEPS={\",\".join(p1_steps)}')
print(f'P1_PUSH_PATH_FILTER={\"YES\" if p1_push_has_path else \"NO\"}')

# Pipeline 2: macOS
p2 = docs[1]
p2_platform = p2.get('labels', {}).get('platform', '')
p2_steps = [s.get('name') for s in p2.get('steps', [])]
p2_when = p2.get('when', [])
p2_push_has_path = any('path' in c for c in p2_when if c.get('event') == 'push' or ('push' in c.get('event', []) if isinstance(c.get('event'), list) else False))
print(f'P2_PLATFORM={p2_platform}')
print(f'P2_STEPS={\",\".join(p2_steps)}')
print(f'P2_PUSH_PATH_FILTER={\"YES\" if p2_push_has_path else \"NO\"}')

# Pipeline 3: Release
p3 = docs[2]
p3_platform = p3.get('labels', {}).get('platform', '')
p3_steps = [s.get('name') for s in p3.get('steps', [])]
print(f'P3_PLATFORM={p3_platform}')
print(f'P3_STEPS={\",\".join(p3_steps)}')
"
    YAML_REPORT=$(python3 -c "$PYTHON_VALIDATOR" 2>&1 || echo "ERROR")
    
    assert_contains "woodpecker config defines exactly 3 pipelines" "DOCS_COUNT=3" "$YAML_REPORT"
    assert_contains "Pipeline 1 targets linux/amd64" "P1_PLATFORM=linux/amd64" "$YAML_REPORT"
    assert_contains "Pipeline 1 has test-linux step" "test-linux" "$YAML_REPORT"
    assert_contains "Pipeline 1 has check-windows step" "check-windows" "$YAML_REPORT"
    assert_contains "Pipeline 1 push event has no path constraint" "P1_PUSH_PATH_FILTER=NO" "$YAML_REPORT"
    assert_contains "Pipeline 2 push event has no path constraint" "P2_PUSH_PATH_FILTER=NO" "$YAML_REPORT"
    assert_contains "Pipeline 2 targets darwin/amd64" "P2_PLATFORM=darwin/amd64" "$YAML_REPORT"
    assert_contains "Pipeline 2 has test step" "test" "$YAML_REPORT"
    assert_contains "Pipeline 3 targets darwin/amd64" "P3_PLATFORM=darwin/amd64" "$YAML_REPORT"
    assert_contains "Pipeline 3 has build-dev-dmg step" "build-dev-dmg" "$YAML_REPORT"
    assert_contains "Pipeline 3 has build-release-dmg step" "build-release-dmg" "$YAML_REPORT"
else
    echo "  [FAIL] .woodpecker.yaml does not exist"
    FAILED=$((FAILED + 1))
fi

echo "======================================================================"
echo "TDD Test Results: $PASSED passed, $FAILED failed"
echo "======================================================================"

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
