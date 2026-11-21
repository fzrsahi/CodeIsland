#!/usr/bin/env bash
# ==============================================================================
# TDD Test Suite for Multiplatform CI/CD Pipeline & Runner Configuration
# Tests:
#   1. scripts/setup-linux-runner.sh syntax, flags, and dry-run configuration
#   2. windows/ci/check.sh syntax, flags, and dry-run output
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
echo "--- Suite 2: windows/ci/check.sh ---"
WIN_CHECK_SCRIPT="$ROOT/windows/ci/check.sh"

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
    YAML_REPORT=$(python3 - "$WP_YAML" << 'EOF'
import sys
import yaml

wp_yaml = sys.argv[1]
with open(wp_yaml) as f:
    docs = list(yaml.safe_load_all(f))

# Document count check
if len(docs) != 3:
    print(f'DOCS_COUNT={len(docs)}')
    sys.exit(0)

print(f'DOCS_COUNT={len(docs)}')

# Pipeline 1: Linux
p1 = docs[0]
p1_platform = p1.get('labels', {}).get('platform', '')
p1_steps = {s.get('name'): s for s in p1.get('steps', [])}
p1_step_names = list(p1_steps.keys())
p1_when = p1.get('when', [])
p1_push_has_path = any('path' in c for c in p1_when if c.get('event') == 'push' or ('push' in c.get('event', []) if isinstance(c.get('event'), list) else False))
p1_pr_when = [c for c in p1_when if 'pull_request' in c.get('event', [])]
p1_pr_has_path = any('path' in c for c in p1_pr_when)
p1_test_linux = p1_steps.get('test-linux', {})
p1_check_windows = p1_steps.get('check-windows', {})
p1_test_linux_cmds = "\n".join(str(c) for c in p1_test_linux.get('commands', []))
p1_check_win_cmds = "\n".join(str(c) for c in p1_check_windows.get('commands', []))

print(f'P1_PLATFORM={p1_platform}')
print(f'P1_STEPS={",".join(p1_step_names)}')
print(f'P1_PUSH_PATH_FILTER={"YES" if p1_push_has_path else "NO"}')
print(f'P1_PR_PATH_FILTER={"YES" if p1_pr_has_path else "NO"}')
print(f'P1_TEST_LINUX_IMAGE={p1_test_linux.get("image", "")}')
print(f'P1_LINUX_HARNESS_CONTEXT={"YES" if "Morrow / Linux & Rust Harness" in p1_test_linux_cmds else "NO"}')
print(f'P1_LINUX_DISPATCH={"YES" if "linux/ci/test.sh" in p1_test_linux_cmds else "NO"}')
print(f'P1_TEST_LINUX_POSIX={"YES" if "set -e" in p1_test_linux_cmds and "set -eo pipefail" not in p1_test_linux_cmds else "NO"}')
print(f'P1_LINUX_FAST_BYPASS={"YES" if "Fast-bypass" in p1_test_linux_cmds or "CI_PIPELINE_FILES" in p1_test_linux_cmds else "NO"}')
print(f'P1_WINDOWS_HARNESS_CONTEXT={"YES" if "Morrow / Windows MSVC Check" in p1_check_win_cmds else "NO"}')
print(f'P1_WINDOWS_DISPATCH={"YES" if "windows/ci/check.sh" in p1_check_win_cmds else "NO"}')
print(f'P1_CHECK_WIN_POSIX={"YES" if "set -e" in p1_check_win_cmds and "set -eo pipefail" not in p1_check_win_cmds else "NO"}')
print(f'P1_WINDOWS_FAST_BYPASS={"YES" if "Fast-bypass" in p1_check_win_cmds or "CI_PIPELINE_FILES" in p1_check_win_cmds else "NO"}')

# Pipeline 2: macOS
p2 = docs[1]
p2_platform = p2.get('labels', {}).get('platform', '')
p2_steps = {s.get('name'): s for s in p2.get('steps', [])}
p2_step_names = list(p2_steps.keys())
p2_when = p2.get('when', [])
p2_push_has_path = any('path' in c for c in p2_when if c.get('event') == 'push' or ('push' in c.get('event', []) if isinstance(c.get('event'), list) else False))
p2_pr_when = [c for c in p2_when if 'pull_request' in c.get('event', [])]
p2_pr_has_path = any('path' in c for c in p2_pr_when)
p2_test = p2_steps.get('test', {})
p2_test_cmds = "\n".join(str(c) for c in p2_test.get('commands', []))

print(f'P2_PLATFORM={p2_platform}')
print(f'P2_STEPS={",".join(p2_step_names)}')
print(f'P2_PUSH_PATH_FILTER={"YES" if p2_push_has_path else "NO"}')
print(f'P2_PR_PATH_FILTER={"YES" if p2_pr_has_path else "NO"}')
print(f'P2_MACOS_DISPATCH={"YES" if "macos/ci/test.sh" in p2_test_cmds else "NO"}')
print(f'P2_MACOS_FAST_BYPASS={"YES" if "Fast-bypass" in p2_test_cmds or "CI_PIPELINE_FILES" in p2_test_cmds else "NO"}')

# Pipeline 3: Release
p3 = docs[2]
p3_platform = p3.get('labels', {}).get('platform', '')
p3_steps = {s.get('name'): s for s in p3.get('steps', [])}
p3_step_names = list(p3_steps.keys())
p3_build_dev = p3_steps.get('build-dev-dmg', {})
p3_dev_cmds = "\n".join(str(c) for c in p3_build_dev.get('commands', []))
print(f'P3_PLATFORM={p3_platform}')
print(f'P3_STEPS={",".join(p3_step_names)}')
print(f'P3_MANIFEST_DISPATCH={"YES" if "shared/ci/manifest.sh" in p3_dev_cmds else "NO"}')
print(f'P3_INFO_PLIST={"YES" if "macos/Info.plist" in p3_dev_cmds else "NO"}')
EOF
)
    
    assert_contains "woodpecker config defines exactly 3 pipelines" "DOCS_COUNT=3" "$YAML_REPORT"
    assert_contains "Pipeline 1 targets linux/amd64" "P1_PLATFORM=linux/amd64" "$YAML_REPORT"
    assert_contains "Pipeline 1 has test-linux step" "test-linux" "$YAML_REPORT"
    assert_contains "Pipeline 1 has check-windows step" "check-windows" "$YAML_REPORT"
    assert_contains "Pipeline 1 push event has no path constraint" "P1_PUSH_PATH_FILTER=NO" "$YAML_REPORT"
    assert_contains "Pipeline 1 pull_request event has no path constraint" "P1_PR_PATH_FILTER=NO" "$YAML_REPORT"
    assert_contains "Pipeline 1 test-linux uses rust:1.98-bookworm" "P1_TEST_LINUX_IMAGE=rust:1.98-bookworm" "$YAML_REPORT"
    assert_contains "Pipeline 1 test-linux has smart fast-bypass detection" "P1_LINUX_FAST_BYPASS=YES" "$YAML_REPORT"
    assert_contains "Pipeline 1 check-windows has smart fast-bypass detection" "P1_WINDOWS_FAST_BYPASS=YES" "$YAML_REPORT"
    assert_contains "Pipeline 1 reports Linux & Rust Harness context" "P1_LINUX_HARNESS_CONTEXT=YES" "$YAML_REPORT"
    assert_contains "Pipeline 1 dispatches to linux/ci/test.sh" "P1_LINUX_DISPATCH=YES" "$YAML_REPORT"
    assert_contains "Pipeline 1 reports Windows MSVC Check context" "P1_WINDOWS_HARNESS_CONTEXT=YES" "$YAML_REPORT"
    assert_contains "Pipeline 1 dispatches to windows/ci/check.sh" "P1_WINDOWS_DISPATCH=YES" "$YAML_REPORT"
    assert_contains "Pipeline 1 test-linux complies with POSIX set -e" "P1_TEST_LINUX_POSIX=YES" "$YAML_REPORT"
    assert_contains "Pipeline 1 check-windows complies with POSIX set -e" "P1_CHECK_WIN_POSIX=YES" "$YAML_REPORT"
    assert_contains "Pipeline 2 push event has no path constraint" "P2_PUSH_PATH_FILTER=NO" "$YAML_REPORT"
    assert_contains "Pipeline 2 pull_request event has no path constraint" "P2_PR_PATH_FILTER=NO" "$YAML_REPORT"
    assert_contains "Pipeline 2 targets darwin/amd64" "P2_PLATFORM=darwin/amd64" "$YAML_REPORT"
    assert_contains "Pipeline 2 has test step" "test" "$YAML_REPORT"
    assert_contains "Pipeline 2 dispatches to macos/ci/test.sh" "P2_MACOS_DISPATCH=YES" "$YAML_REPORT"
    assert_contains "Pipeline 2 has smart fast-bypass detection" "P2_MACOS_FAST_BYPASS=YES" "$YAML_REPORT"
    assert_contains "Pipeline 3 targets darwin/amd64" "P3_PLATFORM=darwin/amd64" "$YAML_REPORT"
    assert_contains "Pipeline 3 has build-dev-dmg step" "build-dev-dmg" "$YAML_REPORT"
    assert_contains "Pipeline 3 has build-release-dmg step" "build-release-dmg" "$YAML_REPORT"
    assert_contains "Pipeline 3 dispatches to shared/ci/manifest.sh" "P3_MANIFEST_DISPATCH=YES" "$YAML_REPORT"
    assert_contains "Pipeline 3 reads macos/Info.plist" "P3_INFO_PLIST=YES" "$YAML_REPORT"
else
    echo "  [FAIL] .woodpecker.yaml does not exist"
    FAILED=$((FAILED + 1))
fi

# ------------------------------------------------------------------------------
# Test Suite 4: Smart Fast-Bypass Monorepo Change Detection Logic
# ------------------------------------------------------------------------------
echo "--- Suite 4: Smart Fast-Bypass Change Detection Logic ---"

LINUX_REGEX='Cargo\.|rust-toolchain|shared/|crates/|linux/|windows/|scripts/ci/(linux|windows|verify|test-multiplatform)|\.woodpecker'
MACOS_REGEX='Sources/|Tests/|macos/|Package\.|Info\.plist|scripts/.*macos|scripts/run-xctest-runner|\.woodpecker'

# Case 1: Swift only PR
SWIFT_FILES='["macos/Sources/Morrow/NotchView.swift","macos/Tests/NotchTests.swift"]'
SWIFT_LINUX_MATCH=$(echo "$SWIFT_FILES" | grep -Eq "$LINUX_REGEX" && echo "YES" || echo "NO")
SWIFT_MACOS_MATCH=$(echo "$SWIFT_FILES" | grep -Eq "$MACOS_REGEX" && echo "YES" || echo "NO")
assert_eq "Swift-only PR triggers fast-bypass on Linux (NO run)" "NO" "$SWIFT_LINUX_MATCH"
assert_eq "Swift-only PR runs on macOS (YES run)" "YES" "$SWIFT_MACOS_MATCH"

# Case 2: Rust only PR
RUST_FILES='["crates/morrow-core/src/lib.rs","linux/src/main.rs"]'
RUST_LINUX_MATCH=$(echo "$RUST_FILES" | grep -Eq "$LINUX_REGEX" && echo "YES" || echo "NO")
RUST_MACOS_MATCH=$(echo "$RUST_FILES" | grep -Eq "$MACOS_REGEX" && echo "YES" || echo "NO")
assert_eq "Rust-only PR runs on Linux (YES run)" "YES" "$RUST_LINUX_MATCH"
assert_eq "Rust-only PR triggers fast-bypass on macOS (NO run)" "NO" "$RUST_MACOS_MATCH"

# Case 3: Shared monorepo change (.woodpecker.yaml or shared/crates)
SHARED_FILES='[".woodpecker.yaml"]'
SHARED_LINUX_MATCH=$(echo "$SHARED_FILES" | grep -Eq "$LINUX_REGEX" && echo "YES" || echo "NO")
SHARED_MACOS_MATCH=$(echo "$SHARED_FILES" | grep -Eq "$MACOS_REGEX" && echo "YES" || echo "NO")
assert_eq ".woodpecker.yaml change runs on Linux (YES run)" "YES" "$SHARED_LINUX_MATCH"
assert_eq ".woodpecker.yaml change runs on macOS (YES run)" "YES" "$SHARED_MACOS_MATCH"

echo "======================================================================"
echo "TDD Test Results: $PASSED passed, $FAILED failed"
echo "======================================================================"

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
