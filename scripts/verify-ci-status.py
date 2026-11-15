#!/usr/bin/env python3
"""
CodeIsland CI Status Verification Tool
Queries the GitHub REST API for commit status checks on a commit/branch/PR,
validating whether Woodpecker CI and custom test harnesses are reporting correctly.
"""

import argparse
import json
import os
import subprocess
import sys
import urllib.request
import urllib.error


def resolve_sha(target):
    if target and len(target) == 40 and not any(c in target for c in " \t\n/"):
        return target
    try:
        ref = target if target else "HEAD"
        return subprocess.check_output(["git", "rev-parse", ref]).decode("utf-8").strip()
    except Exception as e:
        print(f"Error resolving git ref '{target}': {e}", file=sys.stderr)
        return None


def fetch_statuses(repo, sha):
    url = f"https://api.github.com/repos/{repo}/commits/{sha}/status"
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "CodeIsland-CI-Verifier",
            "Accept": "application/vnd.github.v3+json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", errors="replace")
        print(f"GitHub API error (HTTP {e.code}): {err}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"Network error querying GitHub API: {e}", file=sys.stderr)
        return None


def main():
    parser = argparse.ArgumentParser(description="Verify GitHub Commit Statuses for CodeIsland CI")
    parser.add_argument("--repo", default=os.environ.get("CI_REPO", "fzrsahi/CodeIsland"), help="GitHub repository (owner/name)")
    parser.add_argument("--sha", default="HEAD", help="Commit SHA or git ref to inspect (default: HEAD)")
    parser.add_argument("--expected-context", help="Check that a specific status context exists and passed")
    args = parser.parse_args()

    full_sha = resolve_sha(args.sha)
    if not full_sha:
        sys.exit(1)

    print(f"🔍 Inspecting GitHub commit statuses for {args.repo} @ {full_sha[:7]} ({full_sha})")
    data = fetch_statuses(args.repo, full_sha)
    if not data:
        sys.exit(1)

    overall_state = data.get("state", "unknown")
    total_count = data.get("total_count", 0)
    statuses = data.get("statuses", [])

    state_icon = {"success": "✅", "pending": "⏳", "failure": "❌", "error": "💥"}.get(overall_state, "❓")
    print(f"\n{state_icon} Overall Status: {overall_state.upper()} ({total_count} checks reported)\n")

    if not statuses:
        print("⚠️  No status checks have been reported for this commit yet.")
        print("   If a pipeline was recently triggered, wait for the runner to pick up the job.")
        sys.exit(1 if args.expected_context else 0)

    print(f"{'State':<10} {'Context':<42} {'Description':<35}")
    print("-" * 90)
    found_expected = False
    for s in statuses:
        st = s.get("state", "")
        ctx = s.get("context", "")
        desc = (s.get("description") or "")[:35]
        icon = {"success": "✅", "pending": "⏳", "failure": "❌", "error": "💥"}.get(st, " ")
        print(f"{icon} {st:<8} {ctx:<42} {desc:<35}")
        if s.get("target_url"):
            print(f"   ↳ URL: {s.get('target_url')}")

        if args.expected_context and args.expected_context == ctx:
            if st == "success":
                found_expected = True

    print("-" * 90)

    if args.expected_context:
        if found_expected:
            print(f"\n✅ Expected check '{args.expected_context}' verified with SUCCESS state!")
            sys.exit(0)
        else:
            print(f"\n❌ Expected check '{args.expected_context}' was NOT found with success state.")
            sys.exit(1)


if __name__ == "__main__":
    main()
