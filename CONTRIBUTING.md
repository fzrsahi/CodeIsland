# Contributing to CodeIsland

Welcome, and thank you for your interest in contributing to **CodeIsland**! 🏝️

CodeIsland transforms the MacBook notch into a living, real-time Dynamic Island for **AI Coding Agents**, **Interactive Git Graphs**, and **Floating Synced Music Lyrics**.

This document provides guidelines and an overview of the codebase to help you get started quickly.

---

## 🛠️ Quick Start & Development Setup

### Prerequisites
- **macOS 14 Sonoma** or later
- **Xcode Command Line Tools** / Swift 5.9+ (Swift 5.10+ recommended)
- Git

### Cloning and Building

1. Clone the repository:
   ```bash
   git clone git@github.com:fzrsahi/CodeIsland.git
   cd CodeIsland
   ```

2. Build and run locally:
   ```bash
   # Quick build and launch
   ./build.sh
   open .build/release/CodeIsland.app
   ```

3. To rebuild during active development:
   ```bash
   swift build
   ```

---

## 🧭 Codebase Architecture Map

All primary Swift source files are located in `Sources/CodeIsland/` and `Sources/CodeIslandCore/`:

| File / Module | Responsibility |
| :--- | :--- |
| **`NotchPanelView.swift`** | Main Dynamic Island notch container. Handles screen detection, physical notch cutout geometry, left/right wings, idle standby states, and sub-notch anchoring. |
| **`CyberMusicView.swift`** | Floating synced lyric capsule (`SubNotchFloatingLyricCapsuleView`), layout presets (`pureText`, `capsule`, `frostedGlass`, `neonHud`), audio spectrum visualizers, and the expanded Cyber Music HUD. |
| **`CyberWorkspaceView.swift`** | Workspace monitor tab, interactive Git Commit Graph spine visualizer, branch badges, and live Git Diff viewer. |
| **`SettingsView.swift`** | App Settings window containing customizable Appearance, Floating Lyric Styles, typography, colors, sound, and agent preferences. |
| **`Settings.swift`** | `SettingsKey`, `SettingsDefaults`, and data types (`FloatingLyricPreset`, `FloatingLyricFontDesign`, `FloatingLyricTextColor`). |
| **`NowPlayingManager.swift`** | System media listener via AppleScript/DistributedNotifications for Spotify & Apple Music, plus real-time synced LRC lyrics fetcher. |
| **`WorkspaceMonitorManager.swift`** | Non-blocking asynchronous workspace detection, git status tailing, and branch discovery. |
| **`AppState.swift`** | Central state manager holding active agent sessions, mascots, and IPC events. |
| **`HookServer.swift`** | Unix domain socket IPC bridge receiving lifecycle events from Claude Code, Cursor, Codex, Gemini CLI, etc. |

---

## 🎨 Design & Style Guidelines

When adding or modifying UI components:
- **macOS Native & Cyber Aesthetics**: Use deep `#000000` pitch black backgrounds paired with high-taste neon accents (Cyan `#00F5D4`, Magenta `#FF2987`, Matrix Green `#00E676`).
- **Zero Horizontal Scrolling for Lyrics**: Floating lyrics should auto-expand with spring physics (`withAnimation(.spring(...))`) to fit line length.
- **Privacy First (No Idle Green Dots)**: Avoid standalone circular green dots near the notch camera cutout to prevent visual confusion with the hardware macOS webcam privacy indicator.
- **Main Thread Hygiene**: Never perform blocking I/O, heavy `lsof`, or disk discovery on the main thread; always dispatch to background tasks or in-memory state.

---

## 🤝 Contribution Workflow

1. **Fork or Branch**: Create a feature branch with a descriptive name:
   ```bash
   git checkout -b feat/my-awesome-feature
   # or
   git checkout -b fix/issue-description
   ```

2. **Commit Conventions**: We use conventional commit messages:
   - `feat(...)`: New features or layouts
   - `fix(...)`: Bug fixes or alignment adjustments
   - `style(...)`: UI polish or aesthetic improvements
   - `refactor(...)`: Code cleanup or performance optimizations

3. **Verify Build**: Ensure the project compiles cleanly before pushing:
   ```bash
   ./build.sh
   ```

4. **Submit a Pull Request**: Push your branch and open a PR against `main`. Provide a concise description of your changes and include screenshots or GIFs for visual changes.

---

## 🔋 Performance benchmark

CodeIsland stays on screen all day, so idle CPU, wakeups and memory matter as much as features. `scripts/perf/bench.sh` measures them against `scripts/perf/baseline.json`.

**When to run it:** before opening a PR that touches views, animations, timers, polling or discovery. Put the before/after tables in the PR description.

```bash
scripts/perf/bench.sh                    # quick suite, ~6 min: idle, idle-prayer, working, music
scripts/perf/bench.sh full               # + multi, stress, working-expanded, waiting-long
scripts/perf/bench.sh --scenario music   # one scenario (repeatable)
scripts/perf/bench.sh --no-build         # reuse .build/release/CodeIsland.app
scripts/perf/bench.sh --soak 24          # footprint every 10 min for 24 h, then `leaks`
```

**What it does:** builds the release app, quits a running CodeIsland (it is relaunched at the end; `--keep-installed` skips this), then for each scenario launches an isolated instance (`CODEISLAND_ISOLATED=1`, its own hook socket, no hooks, no discovery) with `--preview <scenario>` and settings pinned on the command line. After a 15 s warm-up (65 s for `waiting-long`) it records 60 s of `top`, memory from `vmmap`, a 10 s `sample` of the main thread, and the app's internal counters. Keep the Mac otherwise quiet while it runs.

**Reading the report:** per scenario you get CPU %, idle wakeups/s, `top` POWER (the Energy Impact number), main-thread busy %, footprint at start/end/peak, RSS, counters per minute, and where the main thread spends its time.

| Counter | Counts |
| --- | --- |
| `appleScriptExec.<target>` | NowPlaying AppleScript probes per player/browser |
| `cleanupTickWork` / `cleanupTickSkipped` | cleanup ticks that swept / returned early |
| `discoveryScan` | session discovery scans |
| `publishESP32` / `publishCompanion` | device flush attempts, connected or not |
| `hostingLayoutPass` | layout passes of the panel's hosting view (≈ SwiftUI frames) |
| `prayerTick` / `nowPlayingTick` | prayer and NowPlaying timer ticks |

The counters are only on when the app is launched with `CODEISLAND_PERF_COUNTERS=<file.json>`; otherwise each call site is one nil check. Add a case to `PerfCounters.Name` when a new periodic job needs watching.

**Pass/fail:**
- *Regression* (always fails): a metric is above baseline × 1.25 **and** above the noise floor (CPU 0.5 pp, footprint 5 MB, wakeups 20/s, counters 2/min).
- *Target* (✓/✗): fails only when its `"enforce": true` in `baseline.json`. Turn a target on in the PR that reaches it.
- If the Mac model, macOS version or the set of running players/browsers differs from the baseline, regressions are skipped with a warning and only targets are checked. The baseline comes from one maintainer machine.

**Updating the baseline:** after an intended change (or on a new reference machine), run `scripts/perf/bench.sh full --update-baseline`. It does 3 runs per scenario and stores the medians; commit `baseline.json` with the change that moved the numbers.

---

## 📄 License
CodeIsland is licensed under the [MIT License](LICENSE).
Original upstream project by [wxtsky](https://github.com/wxtsky/CodeIsland).
