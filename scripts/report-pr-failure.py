#!/usr/bin/env python3
"""
Automated GitHub PR Failure Reporting for Morrow CI/CD.
Extracts relevant compiler/test failure logs and posts or updates
a single sticky comment on the GitHub Pull Request thread.
"""

import os
import sys
import json
import argparse
import urllib.request
import urllib.error

MARKER = "<!-- morrow-ci-status -->"

def make_request(url, method="GET", headers=None, data=None):
    req = urllib.request.Request(url, method=method, data=data)
    if headers:
        for k, v in headers.items():
            req.add_header(k, v)
    return req

def extract_failure_snippet(log_path, max_lines=25):
    """Extract high-signal compiler or test errors from test log."""
    if not os.path.isfile(log_path):
        return "Log file not found at " + log_path

    try:
        with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
    except Exception as e:
        return f"Unable to read log file: {e}"

    if not lines:
        return "Log file is empty."

    # Look for error signatures
    error_indices = []
    keywords = ["error:", "fatal error:", "failed (", "the compiler is unable", "XCTAssertEqual failed", "threw error"]
    for i, line in enumerate(lines):
        line_lower = line.lower()
        if any(kw.lower() in line_lower for kw in keywords):
            error_indices.append(i)

    if error_indices:
        # Pick the first significant error block
        first_err = error_indices[0]
        start = max(0, first_err - 2)
        end = min(len(lines), start + max_lines)
        snippet = "".join(lines[start:end]).strip()
        if len(snippet) > 2500:
            snippet = snippet[:2500] + "\n... [truncated]"
        return snippet

    # Fallback to tail lines
    tail = "".join(lines[-max_lines:]).strip()
    return tail if tail else "No explicit error details extracted from log."

def upsert_pr_comment(repo, pr_number, token, body):
    api_base = f"https://api.github.com/repos/{repo}"
    auth_headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "Morrow-CI-Notifier",
        "Content-Type": "application/json"
    }

    # 1. Search for existing bot comment with MARKER
    comments_url = f"{api_base}/issues/{pr_number}/comments?per_page=100"
    existing_comment_id = None

    try:
        req = make_request(comments_url, method="GET", headers=auth_headers)
        with urllib.request.urlopen(req) as resp:
            comments = json.loads(resp.read().decode("utf-8"))
            for c in comments:
                if MARKER in c.get("body", ""):
                    existing_comment_id = c.get("id")
                    break
    except Exception as e:
        print(f"Warning: Failed to fetch existing PR comments: {e}", file=sys.stderr)

    payload = json.dumps({"body": body}).encode("utf-8")

    # 2. Update or create comment
    if existing_comment_id:
        update_url = f"{api_base}/issues/comments/{existing_comment_id}"
        print(f"==> Updating existing failure comment #{existing_comment_id} on PR #{pr_number}...")
        req = make_request(update_url, method="PATCH", headers=auth_headers, data=payload)
    else:
        create_url = f"{api_base}/issues/{pr_number}/comments"
        print(f"==> Posting new failure comment to PR #{pr_number}...")
        req = make_request(create_url, method="POST", headers=auth_headers, data=payload)

    try:
        with urllib.request.urlopen(req) as resp:
            res = json.loads(resp.read().decode("utf-8"))
            print(f"SUCCESS: Comment updated/created at {res.get('html_url')}")
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="ignore")
        print(f"ERROR: GitHub API call failed: HTTP {e.code} - {err_body}", file=sys.stderr)
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Report CI failure directly to GitHub PR")
    parser.add_argument("log_file", help="Path to build or test output log")
    parser.add_argument("--repo", default=os.environ.get("CI_REPO", "fzrsahi/morrow"), help="Repository (owner/repo)")
    parser.add_argument("--pr", default=os.environ.get("CI_COMMIT_PULL_REQUEST"), help="Pull Request number")
    parser.add_argument("--commit", default=os.environ.get("CI_COMMIT_SHA", ""), help="Commit SHA")
    parser.add_argument("--pipeline", default=os.environ.get("CI_PIPELINE_NUMBER", ""), help="Pipeline number")
    parser.add_argument("--pipeline-url", default=None, help="Pipeline web URL")
    args = parser.parse_args()

    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        print("Notice: GITHUB_TOKEN not set. Skipping PR failure comment.")
        sys.exit(0)

    if not args.pr:
        print("Notice: Not a pull_request event (CI_COMMIT_PULL_REQUEST empty). Skipping PR comment.")
        sys.exit(0)

    repo = args.repo
    if "codeisland" in repo.lower():
        repo = "fzrsahi/Morrow"
    pr_number = args.pr
    commit_sha = args.commit
    commit_short = commit_sha[:7] if commit_sha else "unknown"
    pipeline_num = args.pipeline or "N/A"
    pipeline_url = args.pipeline_url or f"https://ci-codeisland.azhr.cloud/{repo}/pipeline/{pipeline_num}"

    snippet = extract_failure_snippet(args.log_file)

    body = f"""### ❌ CI Test Suite Failed (Commit `{commit_short}`)

The automated test suite failed on the macOS Sonoma runner:

```text
{snippet}
```

📋 **Pipeline Details:** [Woodpecker Pipeline #{pipeline_num}]({pipeline_url})  
💡 *Please fix the compilation or unit test failure and verify locally using `swift build --build-tests` before pushing again.*

{MARKER}"""

    upsert_pr_comment(repo, pr_number, token, body)

if __name__ == "__main__":
    main()
