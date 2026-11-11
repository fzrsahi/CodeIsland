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
        HStack(spacing: 3) {
            Circle()
                .fill(stackInfo.color)
                .frame(width: 3.5, height: 3.5)
            Text(stackInfo.name)
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(white: 0.82))
        }
        .padding(.horizontal, 4.5)
        .padding(.vertical, 1.5)
        .background(
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(white: 0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 2.5)
                        .stroke(stackInfo.color.opacity(0.35), lineWidth: 0.7)
                )
        )
        .help("Detected project environment: \(stackInfo.name)")
    }
}

// MARK: - Git Workspace Status Chips (Replaces empty bars & duplicate info)

struct GitWorkspaceChipsView: View {
    @ObservedObject var manager: WorkspaceMonitorManager
    let accentColor: Color

    var body: some View {
        HStack(spacing: 4) {
            if manager.changedFiles.isEmpty {
                HStack(spacing: 3.5) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(accentColor)
                    Text("Working tree clean • Up to date")
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(white: 0.55))
                }
            } else {
                // Modified chip
                if manager.modifiedCount > 0 {
                    HStack(spacing: 2.5) {
                        Circle()
                            .fill(Color(red: 0.96, green: 0.62, blue: 0.04))
                            .frame(width: 3, height: 3)
                        Text("\(manager.modifiedCount) mod")
                            .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.04))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.14))
                    )
                }

                // Untracked / New chip
                if manager.untrackedCount > 0 {
                    HStack(spacing: 2.5) {
                        Circle()
                            .fill(Color(red: 0.0, green: 0.96, blue: 0.83))
                            .frame(width: 3, height: 3)
                        Text("\(manager.untrackedCount) untracked")
                            .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 0.0, green: 0.96, blue: 0.83).opacity(0.14))
                    )
                }

                // Deleted chip
                if manager.deletedCount > 0 {
                    HStack(spacing: 2.5) {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.16, blue: 0.53))
                            .frame(width: 3, height: 3)
                        Text("\(manager.deletedCount) del")
                            .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 1.0, green: 0.16, blue: 0.53))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 1.0, green: 0.16, blue: 0.53).opacity(0.14))
                    )
                }

                // Staged chip (if any)
                if manager.stagedCount > 0 {
                    HStack(spacing: 2.5) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 5.5, weight: .bold))
                            .foregroundStyle(accentColor)
                        Text("\(manager.stagedCount) staged")
                            .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(accentColor)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(RoundedRectangle(cornerRadius: 2).fill(accentColor.opacity(0.14)))
                }

                // Line delta counts (ONLY when actual non-zero insertions or deletions exist!)
                if manager.insertions > 0 || manager.deletions > 0 {
                    HStack(spacing: 2.5) {
                        if manager.insertions > 0 {
                            Text("+\(manager.insertions)")
                                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(accentColor)
                        }
                        if manager.deletions > 0 {
                            Text("-\(manager.deletions)")
                                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 1.0, green: 0.16, blue: 0.53))
                        }
                    }
                    .padding(.horizontal, 3.5)
                    .padding(.vertical, 1.5)
                    .background(RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.10)))
                }
            }

            Spacer(minLength: 0)

            // Stashes badge OR Smart Project Stack Badge
            if manager.stashCount > 0 {
                HStack(spacing: 2.5) {
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 6.5))
                        .foregroundStyle(Color(red: 0.69, green: 0.15, blue: 1.0))
                    Text("\(manager.stashCount) stash\(manager.stashCount > 1 ? "es" : "")")
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.69, green: 0.15, blue: 1.0))
                }
                .padding(.horizontal, 4.5)
                .padding(.vertical, 1.5)
                .background(RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.69, green: 0.15, blue: 1.0).opacity(0.14)))
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
            HStack(alignment: .top, spacing: 5.5) {
                // Visual Git Graph Spine Track
                ZStack(alignment: .top) {
                    // Continuous vertical rail line
                    VStack(spacing: 0) {
                        if !isHead {
                            Rectangle()
                                .fill(Color(white: 0.22))
                                .frame(width: 1.5, height: 4)
                        } else {
                            Spacer().frame(height: 4)
                        }

                        // Gap where the node circle sits
                        Spacer().frame(height: 7)

                        if !isLast {
                            Rectangle()
                                .fill(Color(white: 0.22))
                                .frame(width: 1.5)
                        }
                    }

                    // Node Dot / Ring
                    Group {
                        if isHead {
                            ZStack {
                                Circle()
                                    .stroke(accentColor.opacity(0.4), lineWidth: 1.5)
                                    .frame(width: 8.5, height: 8.5)
                                Circle()
                                    .fill(accentColor)
                                    .frame(width: 4.5, height: 4.5)
                            }
                        } else {
                            Circle()
                                .fill(isHovered ? accentColor : Color(white: 0.40))
                                .frame(width: 5, height: 5)
                                .overlay(Circle().stroke(Color(white: 0.16), lineWidth: 0.8))
                        }
                    }
                    .padding(.top, 2.5)
                }
                .frame(width: 10, height: 21)

                // Commit Details
                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 3.5) {
                        Text(commit.hash)
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(isHead ? accentColor : (isHovered ? Color.white : Color(white: 0.85)))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 0.5)
                            .background(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(isHead ? accentColor.opacity(0.14) : Color.white.opacity(0.06))
                            )

                        if isHead {
                            Text("HEAD")
                                .font(.system(size: 5.5, weight: .black, design: .monospaced))
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 2.5)
                                .padding(.vertical, 0.5)
                                .background(RoundedRectangle(cornerRadius: 1.5).fill(accentColor))
                        }

                        Text(commit.timeAgo)
                            .font(.system(size: 6.5, design: .monospaced))
                            .foregroundStyle(Color(white: 0.45))

                        if !commit.author.isEmpty {
                            Text("• \(commit.author)")
                                .font(.system(size: 6.5, design: .monospaced))
                                .foregroundStyle(Color(white: 0.35))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }

                    Text(commit.message)
                        .font(.system(size: 7.5, weight: isHead ? .medium : .regular, design: .monospaced))
                        .foregroundStyle(isHovered ? Color.white : (isHead ? Color.white.opacity(0.92) : Color(white: 0.70)))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Click to copy commit hash \(commit.hash)")
    }
}

// MARK: - Git Graph Spine Container View

private struct GitGraphSpineView: View {
    let commits: [GitCommitItem]
    let accentColor: Color

    var body: some View {
        if commits.isEmpty {
            VStack(spacing: 3) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.35))
                Text("No recent commits recorded")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(Color(white: 0.45))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                let displayCommits = Array(commits.prefix(3))
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
            HStack(spacing: 4.5) {
                Text(file.status)
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(file.statusColor)
                    .frame(width: 14)
                    .padding(.vertical, 0.5)
                    .background(RoundedRectangle(cornerRadius: 2).fill(file.statusColor.opacity(0.12)))

                Text(file.filename)
                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(isHovered ? 1.0 : 0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                Text(file.path)
                    .font(.system(size: 6.5, design: .monospaced))
                    .foregroundStyle(Color(white: 0.38))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(isHovered ? Color(white: 0.12) : Color(white: 0.06))
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
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(isAccent ? accentColor : (isHovered ? Color.white : Color(white: 0.55)))
                .frame(width: 15, height: 15)
                .background(
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2.5)
                                .stroke(Color.white.opacity(isHovered ? 0.16 : 0.06), lineWidth: 0.6)
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(tooltip)
    }
}

// MARK: - Taste-Skill Workspace HUD View (Fixed Height 86pt inside 98pt panel)

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
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.04))

                        Text("NO GIT REPOSITORY")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white)
                    }

                    Text(manager.currentCwd.isEmpty ? "No active workspace folder selected" : manager.currentCwd)
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundStyle(Color(white: 0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 0)

                    Button(action: {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        manager.chooseWorkspaceFolder()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 7.5))
                            Text("CHOOSE FOLDER")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 3).fill(accentColor))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Divider Rule
                Rectangle()
                    .fill(Color(white: 0.12))
                    .frame(width: 1, height: 86)

                VStack(alignment: .leading, spacing: 4) {
                    Text("WORKSPACE MONITOR")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(accentColor)

                    Text("CodeIsland automatically monitors Git branch, uncommitted diffs, and commit history for your active workspace.")
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundStyle(Color(white: 0.5))
                        .lineSpacing(2)

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        Button(action: {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            manager.openInTerminal()
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "terminal")
                                    .font(.system(size: 7))
                                Text("OPEN TERMINAL")
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(Color.white.opacity(0.85))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.12)))
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            manager.resolveAndRefreshWorkspace(appState: appState)
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 7))
                                Text("DETECT")
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(Color(white: 0.7))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 86)
        } else {
            // Active Git Repository State - Sculpted Two-Panel Cockpit
            HStack(alignment: .center, spacing: 8) {
                // LEFT PANEL: Repository & Working Tree Cockpit
                VStack(alignment: .leading, spacing: 4) {
                    // Row 1: Project Name, Branch Pill, Ahead/Behind, and In-Sync indicator
                    HStack(spacing: 5) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(accentColor)

                        Text(manager.projectName.uppercased())
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        // Branch Capsule
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 6.5, weight: .bold))
                                .foregroundStyle(accentColor)

                            Text(manager.branch.isEmpty ? "main" : manager.branch)
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.95))
                                .lineLimit(1)

                            if manager.aheadCount > 0 || manager.behindCount > 0 {
                                HStack(spacing: 2) {
                                    if manager.aheadCount > 0 {
                                        Text("↑\(manager.aheadCount)")
                                            .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                                            .foregroundStyle(accentColor)
                                    }
                                    if manager.behindCount > 0 {
                                        Text("↓\(manager.behindCount)")
                                            .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                                            .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.04))
                                    }
                                }
                                .padding(.horizontal, 2.5)
                                .padding(.vertical, 0.5)
                                .background(RoundedRectangle(cornerRadius: 1.5).fill(Color.white.opacity(0.08)))
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(Color(white: 0.10))
                                .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(Color.white.opacity(0.08), lineWidth: 0.8))
                        )

                        Spacer(minLength: 0)

                        if manager.aheadCount == 0 && manager.behindCount == 0 {
                            Text("in sync")
                                .font(.system(size: 6.5, design: .monospaced))
                                .foregroundStyle(Color(white: 0.38))
                        }
                    }

                    // Row 2: Status chips & Smart Project Stack Badge
                    GitWorkspaceChipsView(manager: manager, accentColor: accentColor)

                    Spacer(minLength: 0)

                    // Row 3: Breadcrumb path & Machined Action Dock
                    HStack(spacing: 4) {
                        HStack(spacing: 3) {
                            Image(systemName: "terminal")
                                .font(.system(size: 6))
                                .foregroundStyle(Color(white: 0.35))
                            Text(manager.currentCwd)
                                .font(.system(size: 6.5, design: .monospaced))
                                .foregroundStyle(Color(white: 0.4))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer(minLength: 4)

                        // Machined Action Dock
                        HStack(spacing: 3.5) {
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
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(white: 0.04))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.07), lineWidth: 0.8))
                )

                // Divider Rule
                Rectangle()
                    .fill(Color(white: 0.12))
                    .frame(width: 1, height: 86)

                // RIGHT PANEL: Git Graph Spine / Changes Stream Inspector
                VStack(alignment: .leading, spacing: 3) {
                    // Header Segmented Tab Switcher
                    HStack(spacing: 3) {
                        Button(action: {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                manager.rightPaneTab = .commits
                            }
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 6.5, weight: .bold))
                                Text("GRAPH (\(manager.recentCommits.count))")
                                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(manager.rightPaneTab == .commits ? accentColor : Color(white: 0.5))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(manager.rightPaneTab == .commits ? Color.white.opacity(0.10) : Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .stroke(manager.rightPaneTab == .commits ? Color.white.opacity(0.12) : Color.clear, lineWidth: 0.8)
                                    )
                            )
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                manager.rightPaneTab = .changes
                            }
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 6))
                                Text("CHANGES (\(manager.changedFiles.count))")
                                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(manager.rightPaneTab == .changes ? Color(red: 0.96, green: 0.62, blue: 0.04) : Color(white: 0.5))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(manager.rightPaneTab == .changes ? Color.white.opacity(0.10) : Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .stroke(manager.rightPaneTab == .changes ? Color.white.opacity(0.12) : Color.clear, lineWidth: 0.8)
                                    )
                            )
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 0)

                        if manager.isRefreshing {
                            ProgressView()
                                .scaleEffect(0.35)
                                .frame(width: 8, height: 8)
                        }
                    }

                    // Content Area
                    if manager.rightPaneTab == .commits {
                        GitGraphSpineView(commits: manager.recentCommits, accentColor: accentColor)
                    } else {
                        if manager.changedFiles.isEmpty {
                            VStack(spacing: 3) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(accentColor.opacity(0.8))
                                Text("Working tree is completely clean")
                                    .font(.system(size: 7, design: .monospaced))
                                    .foregroundStyle(Color(white: 0.45))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVStack(alignment: .leading, spacing: 2) {
                                    ForEach(manager.changedFiles) { file in
                                        MinimalFileRow(file: file, cwd: manager.currentCwd)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(white: 0.03))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.06), lineWidth: 0.8))
                )
            }
            .frame(height: 86)
        }
    }
}

// MARK: - Combined Cyber Workspace Main View

struct CyberWorkspaceView: View {
    @ObservedObject var manager: WorkspaceMonitorManager
    var appState: AppState

    init(manager: WorkspaceMonitorManager, appState: AppState) {
        self.manager = manager
        self.appState = appState
    }

    var body: some View {
        CyberWorkspaceHUDView(manager: manager, appState: appState)
            .frame(height: 98)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(red: 0.05, green: 0.06, blue: 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color(red: 0.16, green: 0.19, blue: 0.24), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
            .onAppear {
                manager.resolveAndRefreshWorkspace(appState: appState)
            }
    }
}
