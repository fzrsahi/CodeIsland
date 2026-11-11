import SwiftUI
import AppKit
import CodeIslandCore

// MARK: - Smart Project Environment Badge (Minimalist Retro)

struct ProjectStackBadgeView: View {
    let stack: String
    let accentColor: Color

    private var stackInfo: (color: Color, name: String) {
        switch stack.lowercased() {
        case "swift":
            return (Color(red: 0.98, green: 0.40, blue: 0.16), "SWIFT")
        case "node.js", "nodejs", "node":
            return (Color(red: 0.20, green: 0.82, blue: 0.42), "NODE")
        case "rust":
            return (Color(red: 0.95, green: 0.52, blue: 0.18), "RUST")
        case "python":
            return (Color(red: 0.98, green: 0.78, blue: 0.22), "PY")
        case "go":
            return (Color(red: 0.0, green: 0.78, blue: 0.95), "GO")
        default:
            return (accentColor, stack.uppercased())
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Circle()
                .fill(stackInfo.color)
                .frame(width: 3, height: 3)
            Text(stackInfo.name)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(white: 0.85))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1.5)
        .background(
            RoundedRectangle(cornerRadius: 2)
                .fill(stackInfo.color.opacity(0.16))
        )
        .help("Detected environment: \(stackInfo.name)")
    }
}

// MARK: - Git Workspace Delta Chips (Non-Duplicated, Minimal)

struct GitWorkspaceChipsView: View {
    @ObservedObject var manager: WorkspaceMonitorManager
    let accentColor: Color

    var body: some View {
        HStack(spacing: 3.5) {
            if manager.changedFiles.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 7.5))
                        .foregroundStyle(accentColor)
                    Text("IN SYNC")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(accentColor)
                }
                .padding(.horizontal, 4.5)
                .padding(.vertical, 1.5)
                .background(RoundedRectangle(cornerRadius: 2).fill(accentColor.opacity(0.14)))
            } else {
                // Modified count
                if manager.modifiedCount > 0 {
                    HStack(spacing: 2) {
                        Text("\(manager.modifiedCount)M")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.04))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.16)))
                }

                // Untracked / New count
                if manager.untrackedCount > 0 {
                    HStack(spacing: 2) {
                        Text("\(manager.untrackedCount)A")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.0, green: 0.96, blue: 0.83).opacity(0.16)))
                }

                // Deleted count
                if manager.deletedCount > 0 {
                    HStack(spacing: 2) {
                        Text("\(manager.deletedCount)D")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 1.0, green: 0.16, blue: 0.53))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(RoundedRectangle(cornerRadius: 2).fill(Color(red: 1.0, green: 0.16, blue: 0.53).opacity(0.16)))
                }

                // Line delta counts (+ / -)
                if manager.insertions > 0 || manager.deletions > 0 {
                    HStack(spacing: 2.5) {
                        if manager.insertions > 0 {
                            Text("+\(manager.insertions)")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundStyle(accentColor)
                        }
                        if manager.deletions > 0 {
                            Text("-\(manager.deletions)")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 1.0, green: 0.16, blue: 0.53))
                        }
                    }
                    .padding(.horizontal, 3.5)
                    .padding(.vertical, 1.5)
                    .background(RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.06)))
                }
            }

            Spacer(minLength: 0)

            // Stashes or Project Stack Badge
            if manager.stashCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 6.5))
                        .foregroundStyle(Color(red: 0.69, green: 0.15, blue: 1.0))
                    Text("\(manager.stashCount)s")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.69, green: 0.15, blue: 1.0))
                }
                .padding(.horizontal, 3.5)
                .padding(.vertical, 1.5)
                .background(RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.69, green: 0.15, blue: 1.0).opacity(0.16)))
            } else if !manager.projectType.isEmpty {
                ProjectStackBadgeView(stack: manager.projectType, accentColor: accentColor)
            }
        }
    }
}

// MARK: - Minimal Git Graph Commit Row

private struct GitGraphCommitRow: View {
    let commit: GitCommitItem
    let isHead: Bool
    let accentColor: Color

    @State private var isHovered = false

    var body: some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(commit.hash, forType: .string)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }) {
            HStack(spacing: 4) {
                // Connected Node Dot
                Circle()
                    .fill(isHead ? accentColor : (isHovered ? Color.white : Color(white: 0.35)))
                    .frame(width: isHead ? 4 : 3, height: isHead ? 4 : 3)

                // Commit Details
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text(commit.hash)
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(isHead ? accentColor : (isHovered ? Color.white : Color(white: 0.85)))
                            .shadow(color: isHead ? accentColor.opacity(0.7) : Color.clear, radius: 2)

                        if isHead {
                            Text("HEAD")
                                .font(.system(size: 6, weight: .black, design: .monospaced))
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 2)
                                .padding(.vertical, 0.5)
                                .background(RoundedRectangle(cornerRadius: 1.5).fill(accentColor))
                        }

                        Text(commit.timeAgo)
                            .font(.system(size: 6.5, design: .monospaced))
                            .foregroundStyle(Color(white: 0.40))

                        Spacer(minLength: 0)
                    }

                    Text(commit.message)
                        .font(.system(size: 7.5, weight: isHead ? .medium : .regular, design: .monospaced))
                        .foregroundStyle(isHovered ? Color.white : (isHead ? Color.white.opacity(0.92) : Color(white: 0.65)))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 3.5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
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
            HStack(spacing: 3.5) {
                Text(file.status)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(file.statusColor)
                    .frame(width: 12)
                    .padding(.vertical, 0.5)
                    .background(RoundedRectangle(cornerRadius: 1.5).fill(file.statusColor.opacity(0.16)))

                Text(file.filename)
                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(isHovered ? 1.0 : 0.88))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 2)

                Text(file.path)
                    .font(.system(size: 6.5, design: .monospaced))
                    .foregroundStyle(Color(white: 0.38))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .padding(.horizontal, 3.5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.02))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Click to reveal \(file.path) in Finder")
    }
}

// MARK: - Minimal Action Dock Button

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
                .font(.system(size: 7.5, weight: .medium))
                .foregroundStyle(isAccent ? accentColor : (isHovered ? Color.white : Color(white: 0.50)))
                .frame(width: 16, height: 16)
                .background(
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(tooltip)
    }
}

// MARK: - Minimalist Cyber Workspace HUD View

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
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 3.5) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.04))

                        Text("NO GIT REPOSITORY")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white)
                    }

                    Text(manager.currentCwd.isEmpty ? "No active workspace folder selected" : manager.currentCwd)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(Color(white: 0.45))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 0)

                    Button(action: {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        manager.chooseWorkspaceFolder()
                    }) {
                        HStack(spacing: 2.5) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 6.5))
                            Text("CHOOSE FOLDER")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 2.5).fill(accentColor))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 3) {
                        Button(action: {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            manager.openInTerminal()
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "terminal")
                                    .font(.system(size: 6.5))
                                Text("TERMINAL")
                                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                            }
                            .foregroundStyle(Color.white.opacity(0.80))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.10)))
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            manager.resolveAndRefreshWorkspace(appState: appState)
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 6.5))
                                Text("DETECT")
                                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                            }
                            .foregroundStyle(Color(white: 0.65))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 74)
        } else {
            // Active Git Repository State - Clean Minimalist Dual Cockpit
            HStack(alignment: .top, spacing: 8) {
                // LEFT PANEL: Identity, Status, Breadcrumb & Actions (~45% width)
                VStack(alignment: .leading, spacing: 3.5) {
                    // Row 1: Project Name, Branch Pill, Ahead/Behind
                    HStack(spacing: 3.5) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 8.5))
                            .foregroundStyle(accentColor)

                        Text(manager.projectName.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        // Branch Pill
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 6.5, weight: .bold))
                                .foregroundStyle(accentColor)

                            Text(manager.branch.isEmpty ? "main" : manager.branch)
                                .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.90))
                                .lineLimit(1)

                            if manager.aheadCount > 0 || manager.behindCount > 0 {
                                HStack(spacing: 1.5) {
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
                                .padding(.horizontal, 2)
                                .padding(.vertical, 0.5)
                                .background(RoundedRectangle(cornerRadius: 1.5).fill(Color.white.opacity(0.06)))
                            }
                        }
                        .padding(.horizontal, 3.5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.07))
                        )

                        Spacer(minLength: 0)
                    }

                    // Row 2: Status chips & Delta overview
                    GitWorkspaceChipsView(manager: manager, accentColor: accentColor)

                    Spacer(minLength: 0)

                    // Row 3: Breadcrumb path & Action Dock
                    HStack(spacing: 2.5) {
                        HStack(spacing: 2) {
                            Image(systemName: "terminal")
                                .font(.system(size: 6.5))
                                .foregroundStyle(Color(white: 0.35))
                            Text(manager.currentCwd)
                                .font(.system(size: 6.5, design: .monospaced))
                                .foregroundStyle(Color(white: 0.42))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer(minLength: 2)

                        // 3 Action Buttons
                        HStack(spacing: 2) {
                            MachinedActionButton(
                                icon: "arrow.clockwise",
                                tooltip: "Refresh Git Status",
                                isAccent: manager.isRefreshing,
                                accentColor: accentColor
                            ) {
                                manager.refresh(force: true)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // Hairline Column Divider
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 0.75)
                    .padding(.vertical, 1)

                // RIGHT PANEL: Stream Inspector (Top Anchored with ScrollView) (~55% width)
                VStack(alignment: .leading, spacing: 3) {
                    // Header Retro Tab Switcher
                    HStack(spacing: 3) {
                        Button(action: {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                manager.rightPaneTab = .commits
                            }
                        }) {
                            HStack(spacing: 1.5) {
                                Text("[")
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                                    .foregroundStyle(manager.rightPaneTab == .commits ? accentColor.opacity(0.7) : Color(white: 0.30))
                                if manager.rightPaneTab == .commits {
                                    Text("►")
                                        .font(.system(size: 5.5))
                                        .foregroundStyle(accentColor)
                                }
                                Text("COMMITS:\(manager.recentCommits.count)")
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                                    .foregroundStyle(manager.rightPaneTab == .commits ? accentColor : Color(white: 0.45))
                                    .shadow(color: manager.rightPaneTab == .commits ? accentColor.opacity(0.8) : Color.clear, radius: 2)
                                Text("]")
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                                    .foregroundStyle(manager.rightPaneTab == .commits ? accentColor.opacity(0.7) : Color(white: 0.30))
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(manager.rightPaneTab == .commits ? accentColor.opacity(0.14) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                manager.rightPaneTab = .changes
                            }
                        }) {
                            HStack(spacing: 1.5) {
                                Text("[")
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                                    .foregroundStyle(manager.rightPaneTab == .changes ? Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.7) : Color(white: 0.30))
                                if manager.rightPaneTab == .changes {
                                    Text("►")
                                        .font(.system(size: 5.5))
                                        .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.04))
                                }
                                Text("CHANGES:\(manager.changedFiles.count)")
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                                    .foregroundStyle(manager.rightPaneTab == .changes ? Color(red: 0.96, green: 0.62, blue: 0.04) : Color(white: 0.45))
                                    .shadow(color: manager.rightPaneTab == .changes ? Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.8) : Color.clear, radius: 2)
                                Text("]")
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                                    .foregroundStyle(manager.rightPaneTab == .changes ? Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.7) : Color(white: 0.30))
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(manager.rightPaneTab == .changes ? Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.14) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 0)

                        if manager.isRefreshing {
                            ProgressView()
                                .scaleEffect(0.32)
                                .frame(width: 7, height: 7)
                        }
                    }

                    // Content Area: ALWAYS top-anchored in ScrollView so it NEVER pushes the panel upwards!
                    if manager.rightPaneTab == .commits {
                        if manager.recentCommits.isEmpty {
                            VStack(spacing: 2) {
                                Text("No commits recorded")
                                    .font(.system(size: 7, design: .monospaced))
                                    .foregroundStyle(Color(white: 0.40))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        } else {
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVStack(alignment: .leading, spacing: 1) {
                                    ForEach(manager.recentCommits) { commit in
                                        GitGraphCommitRow(
                                            commit: commit,
                                            isHead: commit.id == manager.recentCommits.first?.id,
                                            accentColor: accentColor
                                        )
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    } else {
                        if manager.changedFiles.isEmpty {
                            VStack(spacing: 2) {
                                Text("No modified files")
                                    .font(.system(size: 7, design: .monospaced))
                                    .foregroundStyle(Color(white: 0.40))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        } else {
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVStack(alignment: .leading, spacing: 1) {
                                    ForEach(manager.changedFiles) { file in
                                        MinimalFileRow(file: file, cwd: manager.currentCwd)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: 74)
        }
    }
}

// MARK: - Minimalist Cyber Workspace Main View

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
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCardHovered ? Color.black.opacity(0.55) : Color.black.opacity(0.40))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isCardHovered ? accentColor.opacity(0.35) : Color.white.opacity(0.08), lineWidth: 0.75)
                    )
            )
            .contentShape(Rectangle())
            .onHover { isCardHovered = $0 }
            .padding(.horizontal, 8)
            .padding(.top, 11)     // Generous top clearance ensuring zero collision with hardware notch!
            .padding(.bottom, 7)
            .onAppear {
                manager.resolveAndRefreshWorkspace(appState: appState)
            }
    }
}
