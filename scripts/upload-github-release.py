#!/usr/bin/env python3
"""
GitHub Release Asset Uploader for CodeIsland CI/CD.
Uploads build artifacts (DMG, SHA256SUMS.txt, appcast.xml) to GitHub Releases using standard library.
"""

import os
import sys
import json
import argparse
import urllib.request
import urllib.error

def make_request(url, method="GET", headers=None, data=None):
    req = urllib.request.Request(url, method=method, data=data)
    if headers:
        for k, v in headers.items():
            req.add_header(k, v)
    return req

def get_or_create_release(repo, tag, token):
    api_base = f"https://api.github.com/repos/{repo}"
    auth_headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "CodeIsland-CI-Uploader"
    }

    # 1. Try to fetch existing release
    tag_url = f"{api_base}/releases/tags/{tag}"
    try:
        req = make_request(tag_url, method="GET", headers=auth_headers)
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code != 404:
            print(f"ERROR: Failed to query release for tag {tag}: HTTP {e.code}", file=sys.stderr)
            raise

    # 2. If 404, create the release
    print(f"==> Release for tag '{tag}' does not exist yet. Creating release...")
    create_url = f"{api_base}/releases"
    payload = json.dumps({
        "tag_name": tag,
        "name": tag,
        "draft": False,
        "prerelease": ("dev" in tag.lower() or "beta" in tag.lower()),
        "generate_release_notes": True
    }).encode("utf-8")

    req = make_request(create_url, method="POST", headers=auth_headers, data=payload)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode("utf-8"))

def upload_assets(repo, tag, files, token):
    release = get_or_create_release(repo, tag, token)
    release_id = release["id"]
    upload_url_template = release.get("upload_url", "")
    upload_base = upload_url_template.split("{")[0]

    auth_headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "CodeIsland-CI-Uploader"
    }

    existing_assets = {a["name"]: a["id"] for a in release.get("assets", [])}

    for file_path in files:
        if not os.path.isfile(file_path):
            print(f"Warning: File {file_path} not found, skipping upload.", file=sys.stderr)
            continue

        filename = os.path.basename(file_path)
        file_size = os.path.getsize(file_path)

        # If asset already exists in release, delete it first to allow replacement
        if filename in existing_assets:
            asset_id = existing_assets[filename]
            print(f"==> Deleting prior asset '{filename}' (ID: {asset_id}) before replacement...")
            del_url = f"https://api.github.com/repos/{repo}/releases/assets/{asset_id}"
            del_req = make_request(del_url, method="DELETE", headers=auth_headers)
            try:
                with urllib.request.urlopen(del_req):
                    pass
            except urllib.error.HTTPError as e:
                print(f"Warning: Failed to delete existing asset {filename}: {e.code}", file=sys.stderr)

        print(f"==> Uploading {filename} ({file_size} bytes) to GitHub release '{tag}'...")
        upload_url = f"{upload_base}?name={filename}"
        with open(file_path, "rb") as f:
            file_data = f.read()

        upload_headers = auth_headers.copy()
        upload_headers["Content-Type"] = "application/octet-stream"
        upload_headers["Content-Length"] = str(len(file_data))

        upload_req = make_request(upload_url, method="POST", headers=upload_headers, data=file_data)
        try:
            with urllib.request.urlopen(upload_req) as resp:
                print(f"SUCCESS: Uploaded {filename} (HTTP {resp.status})")
        except urllib.error.HTTPError as e:
            err_body = e.read().decode("utf-8", errors="ignore")
            print(f"ERROR: Failed to upload {filename}: HTTP {e.code} - {err_body}", file=sys.stderr)
            raise

def main():
    parser = argparse.ArgumentParser(description="Upload build assets to GitHub Release")
    parser.add_argument("--repo", required=True, help="GitHub repository (owner/repo)")
    parser.add_argument("--tag", required=True, help="Release tag name (e.g. v1.0.42)")
    parser.add_argument("--files", nargs="+", required=True, help="File paths to upload")
    args = parser.parse_args()

    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        print("Warning: GITHUB_TOKEN environment variable not set. Skipping release asset upload.")
        sys.exit(0)

    try:
        upload_assets(args.repo, args.tag, args.files, token)
        print("==> All release assets uploaded successfully!")
    except Exception as exc:
        print(f"ERROR during release asset upload: {exc}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
