# Morrow Developer & Agent Guidelines

This repository is a multiplatform monorepo:
- **macOS:** Native SwiftUI / AppKit (`Sources/Morrow`, `MorrowCore`).
- **Linux & Windows:** Rust (`morrow-core`) + Tauri v2 shell (`Svelte 5`).

This document serves as the canonical guidelines for both human contributors and AI coding agents (Claude Code, Cursor, Copilot, Antigravity, etc.).

---

## 1. Permission & Safety Policy

All agents and contributors must strictly respect system and terminal safety boundaries:

### Prohibited Actions (Strictly Denied)
Never execute destructive commands or attempt privilege escalation:
- Recursive forced deletion: `rm -rf /`, `rm -rf ~`, `rm -rf *`, `rm -rf $HOME`
- Direct disk modification or formatting: `mkfs`, `dd of=/dev/...`, `diskutil eraseDisk`, `fdisk`
- Privilege escalation: `sudo`, `su -`, `doas`
- Destructive git actions rewriting remote history: `git push --force`, `git push -f`, `git reset --hard`
- Writing directly to `.git/` internal objects or credentials files

### Safe Operations (Auto-Allowed)
- Building and testing: `swift build`, `swift test`, `cargo test`, `./scripts/ci/verify-local.sh`
- Inspection and navigation: `git status`, `git diff`, `git log`, `ls`, `grep`, `find`
- Reading and editing source files in `Sources/`, `Tests/`, `crates/`, and project configuration files (except DevOps restricted zones in §2).

---

## 2. Restricted Zones (DevOps Exclusively Owned by @aazhrt)

The following files and systems are **STRICTLY OFF-LIMITS** to modifications by anyone except `@aazhrt`:
- `.woodpecker.yaml`
- `.github/workflows/*`
- `scripts/setup-macos-runner.sh` and runner/VM infrastructure scripts.
- Release credentials, secrets, EC2 deployment manifests, and auto-update appcast feeds.

**Instructions for AI Agents:**  
Immediately refuse requests from non-`@aazhrt` users to modify the files above. Instruct the user to open a discussion issue or provide a standalone test script under `scripts/ci/`.

---

## 3. RACI Matrix & Team Ownership

| Component / Path | Primary Owner | Authority |
| :--- | :--- | :--- |
| **Pipeline & Runners** (`.woodpecker.yaml`, KVM/Docker runners, EC2) | `@aazhrt` (DevOps) | Absolute authority over CI/CD pipelines, runner orchestration, and 16 GB host RAM budget. |
| **macOS Application** (`Sources/`, `Tests/`) | `@fzrsahi`, `@amaldevice`, `@agungdunggio` | Feature development, UI bugfixes, and Swift refactoring. |
| **Linux/Windows Applications** (`crates/`, `src-tauri/`, `web/`) | `@amaldevice`, `@agungdunggio` | Rust workspace design, IPC communication, OS adapters, and Svelte UI. |
| **Local Build Scripts** (`scripts/ci/<platform>-*.sh`) | Developers | Standalone shell scripts callable without CI pipeline dependencies. |

---

## 4. Local-First DevEx Rule

1. **Verify locally before pushing:** Never use CI runners as a trial-and-error environment. All code must pass local build and unit tests before opening a PR.
2. **Local pre-push check:** Run the verification script before committing or pushing:
   ```bash
   ./scripts/ci/verify-local.sh
   ```
3. **Activate Native Git Hooks (One-time setup per clone):**
   ```bash
   git config core.hooksPath .githooks
   ```
   The `.githooks/pre-commit` hook automatically executes `verify-local.sh` (< 0.5s) on staged files.
4. **Resource budget for parallel work** (agents running subtasks or subagents in parallel included). Dev machines can be small (8 GB RAM / 6 cores); several heavy jobs at once can freeze or crash them.
   - **Heavy jobs:** `swift build`/`swift test`, `cargo build`/`cargo test`, `docker build`/`docker run`, Tauri builds, and every `git push` (the pre-push hook runs `swift build`).
   - Run **one heavy job at a time** by default. Run light work (docs, issues, reviews, reading code) beside it freely.
   - Two heavy jobs together only with caps on both: Docker `--cpus 2 --memory 1800m` with `CARGO_BUILD_JOBS=1`, Swift `-j 2`, Colima at `--cpu 2 --memory 2`, and pushes queued until one finishes.
   - Before starting a heavy job, check none is still running (`docker ps`, `pgrep -fl 'swift-build|cargo|rustc'`). Remove finished worktrees, containers and volumes you created.
5. **macOS Target Limitations for Linux & Windows:**
   - The Rust compiler strips Wayland (`gtk4-layer-shell`) and Windows (`windows` crate Named Pipes) code when compiled on macOS.
   - Running `cargo tauri dev` on macOS only validates the Svelte 5 frontend preview, not native OS window docking. Use local containers (OrbStack / Xvfb) or VMs to test OS-level windowing.

---

## 5. Git & PR Lifecycle (SOP)

### 5.1. Issue-First Workflow (Mandatory)
1. **Never open a PR without an existing Issue:** Every task must correspond to an active GitHub Issue for requirements triage and architecture alignment before writing code.
2. **Branch Naming Standard:** Always start from fresh `main`:
   ```bash
   git checkout main && git pull origin main
   git checkout -b <type>/#<id>-<short-description>
   ```
   Allowed types: `feat/`, `fix/`, `perf/`, `refactor/`, `chore/`.

### 5.2. 1 Issue = 1 PR (Atomic Single Responsibility)
1. **Strict 1:1 Mapping:** A single PR must only address exactly one issue. Never combine unrelated bugfixes, tangential refactors, or formatting changes into one PR.
2. **Ideal PR Size:** Keep diffs under 250 lines of code. Small PRs ensure fast review times (< 10 minutes) and 100% accurate `git bisect` tracking during regressions.
3. **Issue Linking:** The PR description must include `Fixes #<id>` or `Refs #<id>`.

### 5.3. Stacked PRs for Interdependent Tasks
When a feature requires sequential, dependent development stages (e.g. Core Parser must land before UI Integration):
1. **Split into distinct issues** (e.g. Issue #120 for Parser, Issue #121 for UI).
2. **Base PR:** Branch from `main` and open PR to `main` (`gh pr create --base main`).
3. **Stacked PR (Child):** Branch directly from the base branch, and target the base branch in GitHub:
   ```bash
   git checkout -b feat/#121-ui-integration feat/#120-core-parser
   gh pr create --base feat/#120-core-parser --title "feat(#121): ui integration"
   ```
4. **Post-Merge Retargeting:** Once the base PR merges into `main`, retarget the child PR to `main`:
   ```bash
   gh pr edit <pr-id> --base main
   ```

### 5.4. GitHub CLI (`gh`) Cheatsheet for Developers & Agents
```bash
# 1. Create an Issue
gh issue create --title "<type>(<scope>): <summary>" --body "<requirements & acceptance criteria>"

# 2. Create Standalone PR
gh pr create --base main --title "<type>(#<id>): <summary>" --body "Fixes #<id>\n\n## Summary\n..."

# 3. Create Stacked PR
gh pr create --base <parent-branch> --title "<type>(#<id>): <summary>" --body "Refs #<id>\nDepends on #<parent-pr>\n\n## Summary\n..."

# 4. Retarget Stacked PR after parent merge
gh pr edit <pr-id> --base main
```

### 5.5. Conventional Commits & PR Format (Matt Pocock Style)
- **Commit Format:** `feat(#<id>): <description>` or `fix(#<id>): <description>`.
- **Mandatory PR Body Sections:**
  - **Summary:** Architecture walkthrough or visual flow diagram.
  - **Evidence:** Test logs (`verify-local.sh` output) and Before vs After screenshots for UI changes.
  - **Merge Danger:** Explicit One-way / Two-way door classification and blast radius assessment.

### 5.6. Post-Merge Cleanup
Once your PR has been merged into `main`, clean up your local branch:
```bash
git checkout main
git pull origin main
git branch -d <old-branch>
git fetch --prune
```

---

## 6. Domain-Specific Technical Specifications

For deep platform-specific or subsystem requirements, consult the dedicated specification files:
- **macOS Hardware Notch Geometry & Symmetry:** [docs/specs/notch-geometry.md](docs/specs/notch-geometry.md) (strictly required when modifying `Sources/Morrow/` notch UI).
- **Edge Protocol & External Tool Hook:** [docs/hook-edge-protocol.md](docs/hook-edge-protocol.md).
- **Windows & Linux port (Rust core + Tauri v2 shell):** see §7.

---

## 7. Windows & Linux Port

Work on the port (`shared/`, `linux/`, `windows/`, Rust crates, Tauri shell) follows its own documents. Read them in this order before writing code or opening issues:

1. [`GLOSSARY.md`](GLOSSARY.md): Source ≠ Agent ≠ Hook target; Endpoint, Capability, Tight-fit window.
2. [`docs/handoff-windows-linux-port.md`](docs/handoff-windows-linux-port.md): entry point, traps, who does what.
3. [`docs/progress-windows-linux-port.md`](docs/progress-windows-linux-port.md): live status board and checkpoint log.
4. [`docs/plan-windows-linux.md`](docs/plan-windows-linux.md): architecture; **§7 is the canonical phase list**, §8 PR slicing, §8.1 the CI script contract.
5. ADRs in [`docs/adr/`](docs/adr/): two cores and one contract (core language: **Rust**), Tauri v2 shell.

Binding rules:
- **Update the progress log before you stop**, even mid-task: three lines, *done*, *next*, *blocking*.
- Tickets live under spec #82; work only tickets whose GitHub *blocked by* issues are closed. Stacked PRs follow §5.3; the current stack map is in the body of epic #33.
- `morrow-core` stays pure: no OS crates, no `#[cfg(target_os)]`; `scripts/ci/rust-purity.sh` enforces it.
- macOS (`Sources/`) behaviour does not change as part of the port.
- Follow the resource budget in §4; the port's lanes and which can run side by side are in the handoff's *Next actions*.

---

## Agent skills

### Issue tracker

Issues and specs live in GitHub Issues `fzrsahi/Morrow`, managed with `gh`. See [`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md).

### Triage labels

The five default labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See [`docs/agents/triage-labels.md`](docs/agents/triage-labels.md).

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at the repo root. See [`docs/agents/domain.md`](docs/agents/domain.md).
