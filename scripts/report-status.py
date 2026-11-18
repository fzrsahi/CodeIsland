#!/usr/bin/env python3
"""
Morrow Granular GitHub Status Reporter
Zero-dependency CLI tool to publish granular commit statuses to the GitHub REST API.
Enables multi-check branch protection rules without relying on GitHub Actions.
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


def resolve_token(arg_token=None):
    if arg_token:
        return arg_token
    env_token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if env_token:
        return env_token
    creds_path = os.path.expanduser("~/.git-credentials")
    if os.path.exists(creds_path):
        try:
            with open(creds_path, "r", encoding="utf-8") as f:
                for line in f:
                    if "github.com" in line:
                        parsed = urllib.parse.urlparse(line.strip())
                        if parsed.password:
                            return parsed.password
        except Exception:
            pass
    return None


def post_status(repo, sha, context, state, description=None, target_url=None, token=None):
    if not token:
        print("⚠️  [report-status] No GitHub token found. Skipping status update.", file=sys.stderr)
        return False

    url = f"https://api.github.com/repos/{repo}/statuses/{sha}"
    payload = {
        "state": state,
        "context": context,
    }
    if description:
        # GitHub limits description to 140 chars
        payload["description"] = description[:140]
    if target_url:
        payload["target_url"] = target_url

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github.v3+json",
            "Content-Type": "application/json",
            "User-Agent": "Morrow-CI",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            if resp.status in (200, 201):
                print(f"✅ [report-status] {context} -> {state}")
                return True
            print(f"⚠️  [report-status] HTTP {resp.status} while reporting {context}", file=sys.stderr)
            return False
    except urllib.error.HTTPError as e:
        err_msg = e.read().decode("utf-8", errors="replace")
        print(f"⚠️  [report-status] GitHub API error ({e.code}): {err_msg}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"⚠️  [report-status] Network error: {e}", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(description="Report granular commit status to GitHub")
    parser.add_argument("--context", required=True, help="Status context name (e.g. 'Morrow / XCTest')")
    parser.add_argument("--state", required=True, choices=["pending", "success", "failure", "error"], help="Check state")
    parser.add_argument("--description", help="Short summary text (max 140 chars)")
    parser.add_argument("--url", help="Target URL (e.g. CI pipeline link)")
    parser.add_argument("--repo", help="GitHub repo owner/name (defaults to CI_REPO or fzrsahi/morrow)")
    parser.add_argument("--sha", help="Commit SHA (defaults to CI_COMMIT_SHA)")
    parser.add_argument("--token", help="GitHub API personal access token")
    parser.add_argument("--strict", action="store_true", help="Exit non-zero if status update fails")

    args = parser.parse_args()

    repo = args.repo or os.environ.get("CI_REPO") or "fzrsahi/morrow"
    sha = args.sha or os.environ.get("CI_COMMIT_SHA")
    if not sha or len(sha) < 40:
        # Resolve to full 40-char SHA if short or absent
        try:
            import subprocess
            ref = sha if sha else "HEAD"
            sha = subprocess.check_output(["git", "rev-parse", ref]).decode("utf-8").strip()
        except Exception:
            if not sha or len(sha) != 40:
                print("❌ [report-status] Could not determine full 40-char commit SHA.", file=sys.stderr)
                sys.exit(1 if args.strict else 0)

    target_url = args.url or os.environ.get("CI_PIPELINE_URL") or os.environ.get("CI_BUILD_LINK")
    token = resolve_token(args.token)

    success = post_status(
        repo=repo,
        sha=sha,
        context=args.context,
        state=args.state,
        description=args.description,
        target_url=target_url,
        token=token,
    )

    if args.strict and not success:
        sys.exit(1)


if __name__ == "__main__":
    main()
