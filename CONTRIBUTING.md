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

## 📄 License
CodeIsland is licensed under the [MIT License](LICENSE).
Original upstream project by [wxtsky](https://github.com/wxtsky/CodeIsland).
