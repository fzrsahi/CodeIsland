---
name: pr
description: Format and structure a pull request description according to Matt Pocock's engineering standards (Summary visual shape, Evidence before/after with UI screenshots, Merge Danger assessment).
---

# Pull Request (PR) Body Format (Matt Pocock Standard)

When authoring a pull request description for CodeIsland, follow this strict, high-signal structure:

## 1. Summary
Provide a visual representation of the change rather than dense prose:
- Pick the smallest, most expressive visual representation (ASCII architecture flow, component tree, call tree, or mermaid diagram).
- Highlight only the boundaries, files, and contracts relevant to the reviewer.

## 2. Evidence
Provide concrete proof that the implementation works:
- **UI Changes (Mandatory Visual Proof)**:
  - If there is any UI or visual change (Notch, Dynamic Island, Settings, Mascot, Dialogs), include a **Before vs After screenshot table**.
  - Show the exact visual comparison on screen.
- **Execution Proof**:
  - Unit test execution logs (`swift test --filter ...`).
  - Build and codesign verification (`./macos/build.sh`).

## 3. Merge Danger
Explicitly evaluate risk and blast radius:
- **Door Type**:
  - *Two-way door*: Reversible, isolated, low blast radius.
  - *One-way door*: Hard to roll back, destructive migration, breaking API/ABI change.
- **Blast Radius**: What could break if this fails (e.g. multi-monitor setups, performance/energy impact, background poller, fullscreen transitions).

---

## Workflow Integration
1. Before creating a PR, ensure changes are committed on a designated issue branch (e.g., `fix/#1-...`, `feat/#2-...`, `perf/#1-...`).
2. Check open GitHub issues (`gh issue list --state open -L 30`) and link any matching issue in the PR body (`Closes #<id>` or `Relates to #<id>`).
3. If the PR includes any UI or visual change, prepare **Before vs After** screenshots (uploaded to an `assets/...` orphan ref or GitHub asset URL) and embed them in the PR body and/or PR comment.
4. Submit the PR via `gh pr create` and **always request review from all repository collaborators** (except the PR author):
   - Query collaborators: `gh api repos/:owner/:repo/collaborators --jq '.[].login'`
   - Pass `--reviewer <comma-separated-collaborators>` to `gh pr create` (or `gh pr edit --add-reviewer ...`).
5. Immediately post a structured PR comment (`gh pr comment <number> --body-file ...`) summarizing:
   - What changed per file/component (detailed breakdown),
   - Visual **Before vs After** screenshots (if UI changed),
   - `@mention` of all collaborators requesting review.
6. When the user informs that the PR is merged, execute the Post-Merge Cleanup routine (`git checkout main && git pull origin main && git branch -d <branch> && git fetch --prune`).
