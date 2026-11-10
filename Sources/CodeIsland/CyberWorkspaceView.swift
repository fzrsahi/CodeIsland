import SwiftUI
import AppKit
import CodeIslandCore

// MARK: - Minimal Git Diff Proportion Bar

struct CyberDiffBarView: View {
    let insertions: Int
    let deletions: Int
    let accentColor: Color

    var body: some View {
        let total = max(1, insertions + deletions)
        let insFraction = CGFloat(insertions) / CGFloat(total)
        let delFraction = CGFloat(deletions) / CGFloat(total)

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("+\(insertions)")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(accentColor)

                Text("-\(deletions)")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 1.0, green: 0.16, blue: 0.53))

                Spacer()

                Text("\(insertions + deletions) lines")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(Color(white: 0.45))
            }

            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 1.5) {
                    if insertions > 0 {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(accentColor)
                            .frame(width: max(3, w * insFraction - 1), height: 3)
                    }
                    if deletions > 0 {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(red: 1.0, green: 0.16, blue: 0.53))
                            .frame(width: max(3, w * delFraction - 1), height: 3)
                    }
                    if insertions == 0 && deletions == 0 {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(white: 0.15))
                            .frame(height: 3)
                    }
                }
            }
            .frame(height: 3)
        }
    }
}

// MARK: - Minimal Git Commit Timeline Row

private struct MinimalCommitRow: View {
    let commit: GitCommitItem
    let isLatest: Bool
    let accentColor: Color

    @State private var isHovered = false

    var body: some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(commit.hash, forType: .string)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }) {
            HStack(alignment: .center, spacing: 4.5) {
                Circle()
                    .fill(isLatest ? accentColor : Color(white: 0.35))
                    .frame(width: 4, height: 4)

                Text(commit.hash)
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(isLatest ? accentColor : Color(white: 0.75))

                Text("• \(commit.timeAgo)")
                    .font(.system(size: 6.5, design: .monospaced))
                    .foregroundStyle(Color(white: 0.45))

                if !commit.author.isEmpty {
                    Text("(\(commit.author))")
                        .font(.system(size: 6.5, design: .monospaced))
                        .foregroundStyle(Color(white: 0.35))
                }

                Text("•")
                    .font(.system(size: 6.5, design: .monospaced))
                    .foregroundStyle(Color(white: 0.25))

                Text(commit.message)
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(isHovered ? 1.0 : 0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(isHovered ? Color(white: 0.12) : (isLatest ? Color(white: 0.07) : Color.clear))
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

// MARK: - Taste-Skill Workspace HUD View (Fixed Height 98pt)

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
                    .fill(Color(red: 0.16, green: 0.19, blue: 0.24))
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
            // Active Git Repository State
            HStack(alignment: .center, spacing: 10) {
                // LEFT COLUMN: Repository, Branch, Tree Status, Diff Bar (maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 4.5) {
                    // Row 1: Project Name, Branch Pill, and Action Icons
                    HStack(spacing: 5) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 8.5))
                            .foregroundStyle(accentColor)

                        Text(manager.projectName.uppercased())
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        // Branch Pill
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 6.5, weight: .bold))
                                .foregroundStyle(accentColor)

                            Text(manager.branch.isEmpty ? "main" : manager.branch)
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.95))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(RoundedRectangle(cornerRadius: 2.5).fill(Color(white: 0.12)))

                        Spacer(minLength: 0)

                        // Action Buttons: Refresh, Folder Switch, Terminal, Finder
                        HStack(spacing: 4) {
                            Button(action: {
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                                manager.refresh(force: true)
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 7.5, weight: .semibold))
                                    .foregroundStyle(manager.isRefreshing ? accentColor : Color(white: 0.6))
                                    .frame(width: 16, height: 16)
                                    .background(RoundedRectangle(cornerRadius: 2.5).fill(Color(white: 0.10)))
                            }
                            .buttonStyle(.plain)
                            .help("Refresh Git Status")

                            Button(action: {
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                                manager.chooseWorkspaceFolder()
                            }) {
                                Image(systemName: "folder")
                                    .font(.system(size: 7.5, weight: .semibold))
                                    .foregroundStyle(Color(white: 0.6))
                                    .frame(width: 16, height: 16)
                                    .background(RoundedRectangle(cornerRadius: 2.5).fill(Color(white: 0.10)))
                            }
                            .buttonStyle(.plain)
                            .help("Switch Workspace Directory")

                            Button(action: {
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                                manager.openInTerminal()
                            }) {
                                Image(systemName: "terminal")
                                    .font(.system(size: 7.5, weight: .semibold))
                                    .foregroundStyle(Color(white: 0.6))
                                    .frame(width: 16, height: 16)
                                    .background(RoundedRectangle(cornerRadius: 2.5).fill(Color(white: 0.10)))
                            }
                            .buttonStyle(.plain)
                            .help("Open Directory in Terminal")

                            Button(action: {
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                                manager.openInFinder()
                            }) {
                                Image(systemName: "macwindow")
                                    .font(.system(size: 7.5, weight: .semibold))
                                    .foregroundStyle(Color(white: 0.6))
                                    .frame(width: 16, height: 16)
                                    .background(RoundedRectangle(cornerRadius: 2.5).fill(Color(white: 0.10)))
                            }
                            .buttonStyle(.plain)
                            .help("Reveal Folder in Finder")
                        }
                    }

                    // Row 2: Working Tree Status (Staged/Unstaged or Clean) & Remote Sync Badges
                    HStack(spacing: 4) {
                        Circle()
                            .fill(manager.changedFiles.isEmpty ? accentColor : Color(red: 0.96, green: 0.62, blue: 0.04))
                            .frame(width: 4, height: 4)

                        if manager.changedFiles.isEmpty {
                            Text("Clean Working Tree")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.85))
                        } else {
                            let staged = manager.stagedCount
                            let unstaged = manager.unstagedCount
                            let label = staged > 0 ? "\(staged) staged • \(unstaged) unstaged" : "\(unstaged) unstaged changes"
                            Text(label)
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.white)
                        }

                        Spacer(minLength: 0)

                        // Ahead / Behind badges or In-sync indicator
                        if manager.aheadCount > 0 || manager.behindCount > 0 {
                            HStack(spacing: 3) {
                                if manager.aheadCount > 0 {
                                    Text("↑\(manager.aheadCount)")
                                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                                        .foregroundStyle(accentColor)
                                }
                                if manager.behindCount > 0 {
                                    Text("↓\(manager.behindCount)")
                                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.04))
                                }
                            }
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.12)))
                        } else {
                            Text("In sync")
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundStyle(Color(white: 0.4))
                        }
                    }

                    // Row 3: Diff Summary Proportion Bar
                    if manager.changedFiles.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal")
                                .font(.system(size: 7))
                                .foregroundStyle(accentColor.opacity(0.8))
                            Text("Working tree clean • No pending changes")
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundStyle(Color(white: 0.45))
                            Spacer()
                        }
                    } else {
                        CyberDiffBarView(insertions: manager.insertions, deletions: manager.deletions, accentColor: accentColor)
                    }

                    Spacer(minLength: 0)

                    // Row 4: Path Breadcrumb (Zero commit message duplication!)
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Divider Rule (fixed height 86pt, never stretches)
                Rectangle()
                    .fill(Color(red: 0.16, green: 0.19, blue: 0.24))
                    .frame(width: 1, height: 86)

                // RIGHT COLUMN: Clean Commits / Changed Files Stream
                VStack(alignment: .leading, spacing: 3.5) {
                    // Header Sub-Tab Switcher
                    HStack(spacing: 4) {
                        Button(action: {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                manager.rightPaneTab = .commits
                            }
                        }) {
                            Text("COMMITS (\(manager.recentCommits.count))")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundStyle(manager.rightPaneTab == .commits ? accentColor : Color(white: 0.5))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(RoundedRectangle(cornerRadius: 2).fill(manager.rightPaneTab == .commits ? Color.white.opacity(0.08) : Color.clear))
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                manager.rightPaneTab = .changes
                            }
                        }) {
                            Text("FILES (\(manager.changedFiles.count))")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundStyle(manager.rightPaneTab == .changes ? Color(red: 0.96, green: 0.62, blue: 0.04) : Color(white: 0.5))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(RoundedRectangle(cornerRadius: 2).fill(manager.rightPaneTab == .changes ? Color.white.opacity(0.08) : Color.clear))
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 0)

                        if manager.isRefreshing {
                            ProgressView()
                                .scaleEffect(0.35)
                                .frame(width: 8, height: 8)
                        }
                    }

                    // Content Area (Height: ~62pt)
                    if manager.rightPaneTab == .commits {
                        if manager.recentCommits.isEmpty {
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
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(manager.recentCommits.prefix(3).enumerated()), id: \.element.id) { index, commit in
                                    MinimalCommitRow(commit: commit, isLatest: index == 0, accentColor: accentColor)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
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
                .frame(maxWidth: .infinity, alignment: .leading)
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
