import SwiftUI
import AppKit
import CodeIslandCore

// MARK: - Smart Project Environment Badge

struct ProjectStackBadgeView: View {
    let stack: String
    let accentColor: Color

    private var stackInfo: (color: Color, name: String) {
        switch stack.lowercased() {
        case "swift":
            return (Color(red: 0.98, green: 0.40, blue: 0.16), "SWIFT")
        case "node.js", "nodejs", "node":
            return (Color(red: 0.20, green: 0.82, blue: 0.42), "NODE.JS")
        case "rust":
            return (Color(red: 0.95, green: 0.52, blue: 0.18), "RUST")
        case "python":
            return (Color(red: 0.98, green: 0.78, blue: 0.22), "PYTHON")
        case "go":
            return (Color(red: 0.0, green: 0.78, blue: 0.95), "GO")
        default:
            return (accentColor, stack.uppercased())
        }
    }

    var body: some View {
        HStack(spacing: 3.5) {
            Circle()
                .fill(stackInfo.color)
                .frame(width: 4.5, height: 4.5)
            Text(stackInfo.name)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(white: 0.92))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 3.5)
                .fill(stackInfo.color.opacity(0.18))
        )
        .help("Detected project environment: \(stackInfo.name)")
    }
}

// MARK: - Git Workspace Status Chips

struct GitWorkspaceChipsView: View {
    @ObservedObject var manager: WorkspaceMonitorManager
    let accentColor: Color

    var body: some View {
        HStack(spacing: 4.5) {
            if manager.changedFiles.isEmpty {
                HStack(spacing: 4.5) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(accentColor)
                    Text("Working tree clean • Up to date")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.90))
                }
            } else {
                // Modified chip
                if manager.modifiedCount > 0 {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color(red: 0.96, green: 0.62, blue: 0.04))
                            .frame(width: 4, height: 4)
                        Text("\(manager.modifiedCount) mod")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.04))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.18))
                    )
                }

                // Untracked / New chip
                if manager.untrackedCount > 0 {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color(red: 0.0, green: 0.96, blue: 0.83))
                            .frame(width: 4, height: 4)
                        Text("\(manager.untrackedCount) untracked")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(red: 0.0, green: 0.96, blue: 0.83).opacity(0.18))
                    )
                }

                // Deleted chip
                if manager.deletedCount > 0 {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.16, blue: 0.53))
                            .frame(width: 4, height: 4)
                        Text("\(manager.deletedCount) del")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 1.0, green: 0.16, blue: 0.53))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(red: 1.0, green: 0.16, blue: 0.53).opacity(0.18))
                    )
                }

                // Staged chip (if any)
                if manager.stagedCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(accentColor)
                        Text("\(manager.stagedCount) staged")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(accentColor)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(accentColor.opacity(0.18)))
                }

                // Line delta counts
                if manager.insertions > 0 || manager.deletions > 0 {
                    HStack(spacing: 3.5) {
                        if manager.insertions > 0 {
                            Text("+\(manager.insertions)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(accentColor)
                        }
                        if manager.deletions > 0 {
                            Text("-\(manager.deletions)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 1.0, green: 0.16, blue: 0.53))
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08)))
                }
            }

            Spacer(minLength: 0)

            // Stashes badge OR Smart Project Stack Badge
            if manager.stashCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Color(red: 0.69, green: 0.15, blue: 1.0))
                    Text("\(manager.stashCount) stash\(manager.stashCount > 1 ? "es" : "")")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.69, green: 0.15, blue: 1.0))
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 2.5).fill(Color(red: 0.69, green: 0.15, blue: 1.0).opacity(0.18)))
                .help("\(manager.stashCount) stashed changes in git")
            } else if !manager.projectType.isEmpty {
                ProjectStackBadgeView(stack: manager.projectType, accentColor: accentColor)
            }
        }
    }
}

// MARK: - Visual Git Graph Spine Row

private struct GitGraphCommitRow: View {
    let commit: GitCommitItem
    let isHead: Bool
    let isLast: Bool
    let accentColor: Color

    @State private var isHovered = false

    var body: some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(commit.hash, forType: .string)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }) {
            HStack(spacing: 8) {
                // Connected Node Dot
                Circle()
                    .fill(isHead ? accentColor : (isHovered ? Color.white : Color(white: 0.45)))
                    .frame(width: isHead ? 6 : 5, height: isHead ? 6 : 5)

                // Commit Details
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4.5) {
                        Text(commit.hash)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(isHead ? accentColor : (isHovered ? Color.white : Color(white: 0.90)))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(isHead ? accentColor.opacity(0.18) : Color.white.opacity(0.08))
                            )

                        if isHead {
                            Text("HEAD")
                                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 3.5)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 2).fill(accentColor))
                        }

                        Text(commit.timeAgo)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Color(white: 0.55))

                        if !commit.author.isEmpty {
                            Text("• \(commit.author)")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(Color(white: 0.45))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }

                    Text(commit.message)
                        .font(.system(size: 10.5, weight: isHead ? .semibold : .regular, design: .monospaced))
                        .foregroundStyle(isHovered ? Color.white : (isHead ? Color.white.opacity(0.96) : Color(white: 0.78)))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Click to copy commit hash \(commit.hash)")
    }
}

// MARK: - Minimal Modified File Row

private struct MinimalFileRow: View {
    let file: GitFileChange
    let cwd: String

    @State private var isHovered = false

    var body: some View {
        Button(action: {
            let fullPath = cwd.isEmpty ? file.path : "\(cwd)/\(file.path)"
            NSWorkspace.shared.selectFile(fullPath, inFileViewerRootedAtPath: cwd)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }) {
            HStack(spacing: 5) {
                Text(file.status)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(file.statusColor)
                    .frame(width: 18)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 2.5).fill(file.statusColor.opacity(0.18)))

                Text(file.filename)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(isHovered ? 1.0 : 0.90))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                Text(file.path)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Color(white: 0.45))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Click to reveal \(file.path) in Finder")
    }
}

// MARK: - Machined Action Dock Button

private struct MachinedActionButton: View {
    let icon: String
    let tooltip: String
    let isAccent: Bool
    let accentColor: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isAccent ? accentColor : (isHovered ? Color.white : Color(white: 0.70)))
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered ? Color.white.opacity(0.16) : Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(tooltip)
    }
}

// MARK: - Unified Taste-Skill Workspace HUD View

struct CyberWorkspaceHUDView: View {
    @ObservedObject var manager: WorkspaceMonitorManager
    var appState: AppState

    @AppStorage(SettingsKey.workspaceAccentColor) private var workspaceAccentColorRaw = SettingsDefaults.workspaceAccentColor

    private var accentColor: Color {
        WorkspaceAccentColor(rawValue: workspaceAccentColorRaw)?.color ?? Color(red: 0.0, green: 0.90, blue: 0.46)
    }

    var body: some View {
        if !manager.isGitRepo {
            // Empty / Non-Git Workspace State
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.04))

                        Text("NO GIT REPOSITORY")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white)
                    }

                    Text(manager.currentCwd.isEmpty ? "No active workspace folder selected" : manager.currentCwd)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color(white: 0.55))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 0)

                    Button(action: {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        manager.chooseWorkspaceFolder()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 8.5))
                            Text("CHOOSE FOLDER")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(RoundedRectangle(cornerRadius: 3.5).fill(accentColor))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text("WORKSPACE MONITOR")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(accentColor)

                    Text("CodeIsland automatically monitors Git branch, uncommitted diffs, and commit history for your active workspace.")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(Color(white: 0.55))
                        .lineSpacing(2)

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        Button(action: {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            manager.openInTerminal()
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "terminal")
                                    .font(.system(size: 8))
                                Text("OPEN TERMINAL")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(Color.white.opacity(0.85))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.12)))
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            manager.resolveAndRefreshWorkspace(appState: appState)
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 8))
                                Text("DETECT")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(Color(white: 0.7))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 92)
        } else {
            // Active Git Repository State - Sculpted Borderless Cockpit
            HStack(alignment: .top, spacing: 14) {
                // LEFT PANEL: Repository & Working Tree Cockpit (~52% width)
                VStack(alignment: .leading, spacing: 6) {
                    // Row 1: Project Name, Branch Pill, Ahead/Behind, and In-Sync indicator
                    HStack(spacing: 5) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(accentColor)

                        Text(manager.projectName.uppercased())
                            .font(.system(size: 13.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        // Branch Capsule
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(accentColor)

                            Text(manager.branch.isEmpty ? "main" : manager.branch)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.95))
                                .lineLimit(1)

                            if manager.aheadCount > 0 || manager.behindCount > 0 {
                                HStack(spacing: 2.5) {
                                    if manager.aheadCount > 0 {
                                        Text("↑\(manager.aheadCount)")
                                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                            .foregroundStyle(accentColor)
                                    }
                                    if manager.behindCount > 0 {
                                        Text("↓\(manager.behindCount)")
                                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                            .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.04))
                                    }
                                }
                                .padding(.horizontal, 3.5)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08)))
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3.5)
                                .fill(Color.white.opacity(0.10))
                        )

                        Spacer(minLength: 0)

                        if manager.aheadCount == 0 && manager.behindCount == 0 {
                            Text("in sync")
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color(white: 0.45))
                        }
                    }

                    // Row 2: Status chips & Smart Project Stack Badge
                    GitWorkspaceChipsView(manager: manager, accentColor: accentColor)

                    Spacer(minLength: 0)

                    // Row 3: Breadcrumb path & Machined Action Dock
                    HStack(spacing: 4) {
                        HStack(spacing: 3.5) {
                            Image(systemName: "terminal")
                                .font(.system(size: 8.5))
                                .foregroundStyle(Color(white: 0.45))
                            Text(manager.currentCwd)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(Color(white: 0.55))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer(minLength: 4)

                        // Machined Action Dock
                        HStack(spacing: 4) {
                            MachinedActionButton(
                                icon: "arrow.clockwise",
                                tooltip: "Refresh Git Status",
                                isAccent: manager.isRefreshing,
                                accentColor: accentColor
                            ) {
                                manager.refresh(force: true)
                            }

                            MachinedActionButton(
                                icon: "folder",
                                tooltip: "Switch Workspace Folder",
                                isAccent: false,
                                accentColor: accentColor
                            ) {
                                manager.chooseWorkspaceFolder()
                            }

                            MachinedActionButton(
                                icon: "terminal",
                                tooltip: "Open Directory in Terminal",
                                isAccent: false,
                                accentColor: accentColor
                            ) {
                                manager.openInTerminal()
                            }

                            MachinedActionButton(
                                icon: "macwindow",
                                tooltip: "Reveal Folder in Finder",
                                isAccent: false,
                                accentColor: accentColor
                            ) {
                                manager.openInFinder()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // RIGHT PANEL: Git Graph Spine / Changes Stream Inspector (~48% width, Organic Flow)
                VStack(alignment: .leading, spacing: 5) {
                    // Header Segmented Tab Switcher
                    HStack(spacing: 5) {
                        Button(action: {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                manager.rightPaneTab = .commits
                            }
                        }) {
                            HStack(spacing: 3.5) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 8.5, weight: .bold))
                                Text("GRAPH (\(manager.recentCommits.count))")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(manager.rightPaneTab == .commits ? accentColor : Color(white: 0.55))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(manager.rightPaneTab == .commits ? Color.white.opacity(0.12) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                manager.rightPaneTab = .changes
                            }
                        }) {
                            HStack(spacing: 3.5) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 8))
                                Text("CHANGES (\(manager.changedFiles.count))")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(manager.rightPaneTab == .changes ? Color(red: 0.96, green: 0.62, blue: 0.04) : Color(white: 0.55))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(manager.rightPaneTab == .changes ? Color.white.opacity(0.12) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 0)

                        if manager.isRefreshing {
                            ProgressView()
                                .scaleEffect(0.40)
                                .frame(width: 9, height: 9)
                        }
                    }

                    // Content Area
                    if manager.rightPaneTab == .commits {
                        if manager.recentCommits.isEmpty {
                            VStack(spacing: 3) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(white: 0.35))
                                Text("No recent commits recorded")
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(Color(white: 0.45))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                let displayCommits = Array(manager.recentCommits.prefix(3))
                                ForEach(Array(displayCommits.enumerated()), id: \.element.id) { index, commit in
                                    GitGraphCommitRow(
                                        commit: commit,
                                        isHead: index == 0,
                                        isLast: index == displayCommits.count - 1,
                                        accentColor: accentColor
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    } else {
                        if manager.changedFiles.isEmpty {
                            VStack(spacing: 3) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(accentColor.opacity(0.85))
                                Text("Working tree is completely clean")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color(white: 0.55))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVStack(alignment: .leading, spacing: 2.5) {
                                    ForEach(manager.changedFiles) { file in
                                        MinimalFileRow(file: file, cwd: manager.currentCwd)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 94)
        }
    }
}

// MARK: - Combined Cyber Workspace Main View

struct CyberWorkspaceView: View {
    @ObservedObject var manager: WorkspaceMonitorManager
    var appState: AppState

    @AppStorage(SettingsKey.workspaceAccentColor) private var workspaceAccentColorRaw = SettingsDefaults.workspaceAccentColor
    @State private var isCardHovered = false

    private var accentColor: Color {
        WorkspaceAccentColor(rawValue: workspaceAccentColorRaw)?.color ?? Color(red: 0.0, green: 0.90, blue: 0.46)
    }

    init(manager: WorkspaceMonitorManager, appState: AppState) {
        self.manager = manager
        self.appState = appState
    }

    var body: some View {
        CyberWorkspaceHUDView(manager: manager, appState: appState)
            .frame(height: 108)
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
            .background(
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isCardHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.05))
                    Rectangle()
                        .fill(accentColor)
                        .frame(width: 3.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            )
            .contentShape(Rectangle())
            .onHover { isCardHovered = $0 }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
            .onAppear {
                manager.resolveAndRefreshWorkspace(appState: appState)
            }
    }
}
