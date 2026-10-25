import SwiftUI
import AppKit
import CodeIslandCore

// MARK: - Mini Git Graph Node & Line

struct GitGraphNodeView: View {
    let commit: GitCommitItem
    let isLatest: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Visual Git Graph spine
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(isLatest ? Color(red: 0.0, green: 0.90, blue: 0.46) : Color(white: 0.35))
                        .frame(width: 5.5, height: 5.5)
                        .shadow(color: isLatest ? Color(red: 0.0, green: 0.90, blue: 0.46).opacity(0.8) : Color.clear, radius: 2)

                    if isLatest {
                        Circle()
                            .stroke(Color(red: 0.0, green: 0.90, blue: 0.46).opacity(0.4), lineWidth: 1.5)
                            .frame(width: 9, height: 9)
                    }
                }
                .frame(width: 10, height: 10)

                if !isLast {
                    Rectangle()
                        .fill(Color(white: 0.22))
                        .frame(width: 1.2, height: 14)
                }
            }
            .frame(width: 10)

            // Commit SHA, message, and time
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(commit.hash)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.0, green: 0.90, blue: 0.46))

                    Text(commit.timeAgo)
                        .font(.system(size: 6.5, design: .monospaced))
                        .foregroundStyle(Color(white: 0.45))
                }

                Text(commit.message)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

// MARK: - Segmented Cyber Diff Bar

struct CyberDiffBarView: View {
    let insertions: Int
    let deletions: Int

    var body: some View {
        let total = max(1, insertions + deletions)
        let insFraction = CGFloat(insertions) / CGFloat(total)
        let delFraction = CGFloat(deletions) / CGFloat(total)

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("+\(insertions)")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.0, green: 0.90, blue: 0.46))

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
                            .fill(Color(red: 0.0, green: 0.90, blue: 0.46))
                            .frame(width: max(3, w * insFraction - 1), height: 3.5)
                    }
                    if deletions > 0 {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(red: 1.0, green: 0.16, blue: 0.53))
                            .frame(width: max(3, w * delFraction - 1), height: 3.5)
                    }
                    if insertions == 0 && deletions == 0 {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(white: 0.15))
                            .frame(height: 3.5)
                    }
                }
            }
            .frame(height: 3.5)
        }
    }
}

// MARK: - Coding Agent Usage & Quota HUD Card (Universal for all Agents)

struct CyberAgentQuotaHUD: View {
    var appState: AppState

    private var activeSessions: [SessionSnapshot] {
        Array(appState.sessions.values)
    }

    private var primarySession: SessionSnapshot? {
        let sid = appState.rotatingSessionId ?? appState.activeSessionId ?? appState.sessions.keys.sorted().first
        guard let sid else { return nil }
        return appState.sessions[sid]
    }

    private var claudeQuota: ClaudeQuotaSnapshot? {
        appState.claudeQuota.snapshot
    }

    private var todayUsage: ClaudeUsageTotals? {
        appState.claudeUsage?.today
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Row 1: Agent Header & Active Model
            HStack(spacing: 3) {
                Image(systemName: "cpu")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))

                let sourceName = (primarySession?.mascotSource.isEmpty == false ? primarySession!.mascotSource : (appState.primarySource.isEmpty ? "AGENT" : appState.primarySource)).uppercased()
                Text(sourceName)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white)

                if let model = primarySession?.model, !model.isEmpty {
                    Text("• \(model)")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(Color(white: 0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                // Session Status Dot
                HStack(spacing: 2.5) {
                    Circle()
                        .fill(appState.status == .processing || appState.status == .running ? Color(red: 0.0, green: 0.96, blue: 0.83) : Color(red: 0.0, green: 0.90, blue: 0.46))
                        .frame(width: 3.5, height: 3.5)
                    Text(appState.status == .processing || appState.status == .running ? "BUSY" : "READY")
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(white: 0.75))
                }
                .padding(.horizontal, 3.5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.12)))
            }

            // Row 2: Rate Limit / Quota Window (if available)
            if let quota = claudeQuota, let primaryLimit = quota.ordered.first {
                let remainingPct = max(0, 100 - Int(primaryLimit.percent))
                let color = remainingPct > 35 ? Color(red: 0.0, green: 0.90, blue: 0.46) : (remainingPct > 15 ? Color(red: 0.96, green: 0.62, blue: 0.04) : Color(red: 1.0, green: 0.16, blue: 0.53))
                let windowName = primaryLimit.kind == .session ? "5H SESSION" : (primaryLimit.kind == .weeklyAll ? "WEEKLY" : (primaryLimit.scopeLabel?.uppercased() ?? "PLAN"))

                VStack(alignment: .leading, spacing: 1.5) {
                    HStack {
                        Text("\(windowName):")
                            .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(white: 0.5))

                        Text("\(remainingPct)% SISA")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(color)

                        Spacer()

                        if let resetsAt = primaryLimit.resetsAt {
                            let diff = max(0, Int(resetsAt.timeIntervalSinceNow))
                            let h = diff / 3600
                            let m = (diff % 3600) / 60
                            Text("reset \(h)j \(m)m")
                                .font(.system(size: 6.5, design: .monospaced))
                                .foregroundStyle(Color(white: 0.45))
                        }
                    }

                    // Cyber Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color(white: 0.14))
                                .frame(height: 2.5)

                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(color)
                                .frame(width: max(2, geo.size.width * CGFloat(remainingPct) / 100.0), height: 2.5)
                        }
                    }
                    .frame(height: 2.5)
                }
            }

            // Row 3: Token In/Out Breakdown or Tool Operations
            if let usage = todayUsage, (usage.inputTokens + usage.outputTokens) > 0 {
                let inFormatted = ClaudeUsageScanner.formatTokens(usage.inputTokens + usage.cacheCreationTokens)
                let outFormatted = ClaudeUsageScanner.formatTokens(usage.outputTokens)
                HStack(spacing: 3) {
                    Text("TOKENS:")
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(white: 0.5))
                    Text("\(inFormatted) IN • \(outFormatted) OUT")
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))
                    Spacer()
                }
            } else if let session = primarySession, session.totalToolCallCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(Color(red: 0.0, green: 0.90, blue: 0.46))
                    Text("\(session.totalToolCallCount) tool operations executed")
                        .font(.system(size: 6.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(white: 0.7))
                    Spacer()
                }
            } else if claudeQuota == nil {
                // Clean Connected Status
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 6.5))
                        .foregroundStyle(Color(red: 0.0, green: 0.90, blue: 0.46))
                    Text("AGENT READY & MONITORED")
                        .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(white: 0.65))
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3.5)
        .background(
            RoundedRectangle(cornerRadius: 3.5)
                .fill(Color(white: 0.08))
                .overlay(RoundedRectangle(cornerRadius: 3.5).stroke(Color(white: 0.14), lineWidth: 0.6))
        )
    }
}

// MARK: - Compact Workspace HUD View (Fixed Height 98pt)

struct CyberWorkspaceHUDView: View {
    @ObservedObject var manager: WorkspaceMonitorManager
    var appState: AppState

    private var activeSessionsInWorkspace: [(id: String, session: SessionSnapshot)] {
        let cwd = manager.currentCwd
        guard !cwd.isEmpty else { return [] }
        return appState.sessions.filter { $0.value.cwd == cwd }.map { (id: $0.key, session: $0.value) }
    }

    var body: some View {
        if !manager.isGitRepo {
            VStack(spacing: 5) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(red: 0.0, green: 0.90, blue: 0.46).opacity(0.8))

                Text("NO GIT REPOSITORY DETECTED")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white)

                Text(manager.currentCwd.isEmpty ? "No folder currently active in workspace" : manager.currentCwd)
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 16)

                Button(action: {
                    manager.chooseWorkspaceFolder()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 8))
                        Text("SELECT WORKSPACE FOLDER")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3.5)
                    .background(RoundedRectangle(cornerRadius: 3.5).fill(Color(red: 0.0, green: 0.90, blue: 0.46)))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 92)
            .padding(.horizontal, 8)
        } else {
            HStack(alignment: .top, spacing: 8) {
                // COLUMN 1: Git Status & Diff Summary (Width ~150pt)
                VStack(alignment: .leading, spacing: 4) {
                    // Header & Branch Pill
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(Color(red: 0.0, green: 0.90, blue: 0.46))

                        Text(manager.branch.isEmpty ? "main" : manager.branch)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button(action: { manager.chooseWorkspaceFolder() }) {
                            Image(systemName: "folder")
                                .font(.system(size: 7))
                                .foregroundStyle(Color.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        .help("Switch Workspace Directory")

                        Spacer()

                        // Ahead / Behind badges
                        if manager.aheadCount > 0 || manager.behindCount > 0 {
                            HStack(spacing: 2) {
                                if manager.aheadCount > 0 {
                                    Text("↑\(manager.aheadCount)")
                                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color(red: 0.0, green: 0.90, blue: 0.46))
                                }
                                if manager.behindCount > 0 {
                                    Text("↓\(manager.behindCount)")
                                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.04))
                                }
                            }
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 2.5).fill(Color(white: 0.12)))
                        }
                    }

                // Changed Files Counter
                HStack(spacing: 4) {
                    Circle()
                        .fill(manager.changedFiles.isEmpty ? Color(white: 0.3) : Color(red: 0.96, green: 0.62, blue: 0.04))
                        .frame(width: 4, height: 4)

                    Text(manager.changedFiles.isEmpty ? "Clean Working Tree" : "\(manager.changedFiles.count) files modified")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(manager.changedFiles.isEmpty ? Color(white: 0.5) : Color.white.opacity(0.85))
                        .lineLimit(1)
                }

                // Diff Bar
                CyberDiffBarView(insertions: manager.insertions, deletions: manager.deletions)

                Spacer(minLength: 0)

                // Head commit reference (clean, lightweight)
                if let latest = manager.recentCommits.first {
                    HStack(spacing: 3) {
                        Image(systemName: "circle.circle")
                            .font(.system(size: 6.5))
                            .foregroundStyle(Color(red: 0.0, green: 0.90, blue: 0.46))
                        Text("\(latest.hash) • \(latest.timeAgo)")
                            .font(.system(size: 6.5, design: .monospaced))
                            .foregroundStyle(Color(white: 0.5))
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: 140)

            // Vertical Divider
            Rectangle()
                .fill(Color(red: 0.16, green: 0.19, blue: 0.24))
                .frame(width: 1, height: 86)

            // COLUMN 2: Mini Git Graph / Recent Commits (Width ~155pt)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("RECENT COMMITS")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.0, green: 0.90, blue: 0.46))

                    Spacer()

                    if manager.isRefreshing {
                        ProgressView()
                            .scaleEffect(0.4)
                            .frame(width: 10, height: 10)
                    }
                }

                if manager.recentCommits.isEmpty {
                    VStack(spacing: 2) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(white: 0.35))
                        Text("No commits recorded")
                            .font(.system(size: 7.5, design: .monospaced))
                            .foregroundStyle(Color(white: 0.45))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(manager.recentCommits.prefix(3).enumerated()), id: \.element.id) { index, commit in
                            GitGraphNodeView(
                                commit: commit,
                                isLatest: index == 0,
                                isLast: index == min(2, manager.recentCommits.count - 1)
                            )
                        }
                    }
                }
            }
            .frame(width: 155)

            // Vertical Divider
            Rectangle()
                .fill(Color(red: 0.16, green: 0.19, blue: 0.24))
                .frame(width: 1, height: 86)

            // COLUMN 3: Coding Agent Quota & Usage + Expand (Flexible)
            VStack(alignment: .leading, spacing: 3.5) {
                // Universal Coding Agent Quota & Token Usage Card
                CyberAgentQuotaHUD(appState: appState)

                Spacer(minLength: 0)

                // Expand / Collapse Full Details Button
                Button(action: {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        manager.isExpandedDetail.toggle()
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: manager.isExpandedDetail ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                            .font(.system(size: 7.5, weight: .bold))
                        Text(manager.isExpandedDetail ? "COLLAPSE" : "INSPECT DIFF")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2.5)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.0, green: 0.90, blue: 0.46)))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
        }
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
        }
    }
}

// MARK: - Interactive Syntax-Highlighted Git Diff View

struct CyberDiffLineView: View {
    let line: String

    private var lineType: DiffLineType {
        if line.hasPrefix("+++") || line.hasPrefix("---") { return .meta }
        if line.hasPrefix("+") { return .addition }
        if line.hasPrefix("-") { return .deletion }
        if line.hasPrefix("@@") { return .hunkHeader }
        return .context
    }

    private enum DiffLineType {
        case addition, deletion, hunkHeader, meta, context
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(line)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(textColor)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 0.5)
        .background(bgColor)
    }

    private var textColor: Color {
        switch lineType {
        case .addition: return Color(red: 0.2, green: 1.0, blue: 0.4)
        case .deletion: return Color(red: 1.0, green: 0.3, blue: 0.4)
        case .hunkHeader: return Color(red: 0.0, green: 0.96, blue: 0.83)
        case .meta: return Color(white: 0.6)
        case .context: return Color(white: 0.75)
        }
    }

    private var bgColor: Color {
        switch lineType {
        case .addition: return Color(red: 0.0, green: 0.4, blue: 0.1).opacity(0.25)
        case .deletion: return Color(red: 0.5, green: 0.0, blue: 0.1).opacity(0.25)
        case .hunkHeader: return Color(red: 0.0, green: 0.2, blue: 0.3).opacity(0.3)
        case .meta: return Color(white: 0.12)
        case .context: return Color.clear
        }
    }
}

// MARK: - Full Interactive Git Graph Detail View

struct CyberGitGraphDetailView: View {
    @ObservedObject var manager: WorkspaceMonitorManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("COMMIT GRAPH (\(manager.recentCommits.count))")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(white: 0.5))

                Spacer()

                Text("Branch: \(manager.branch)")
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.0, green: 0.90, blue: 0.46))
            }
            .padding(.horizontal, 4)

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(manager.recentCommits.enumerated()), id: \.element.id) { index, commit in
                        HStack(alignment: .top, spacing: 6) {
                            // Graph Spine node
                            VStack(spacing: 0) {
                                ZStack {
                                    Circle()
                                        .fill(index == 0 ? Color(red: 0.0, green: 0.90, blue: 0.46) : Color(white: 0.35))
                                        .frame(width: 6, height: 6)
                                        .shadow(color: index == 0 ? Color(red: 0.0, green: 0.90, blue: 0.46).opacity(0.8) : Color.clear, radius: 2)

                                    if index == 0 {
                                        Circle()
                                            .stroke(Color(red: 0.0, green: 0.90, blue: 0.46).opacity(0.4), lineWidth: 1.5)
                                            .frame(width: 10, height: 10)
                                    }
                                }
                                .frame(width: 10, height: 10)

                                if index < manager.recentCommits.count - 1 {
                                    Rectangle()
                                        .fill(Color(white: 0.22))
                                        .frame(width: 1.2, height: 16)
                                }
                            }
                            .frame(width: 10)

                            // Commit metadata & message
                            VStack(alignment: .leading, spacing: 1.5) {
                                HStack(spacing: 4) {
                                    Text(commit.hash)
                                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color(red: 0.0, green: 0.90, blue: 0.46))

                                    if !commit.refs.isEmpty {
                                        Text(commit.refs)
                                            .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                                            .foregroundStyle(Color.black)
                                            .padding(.horizontal, 3.5)
                                            .padding(.vertical, 0.5)
                                            .background(RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.0, green: 0.96, blue: 0.83)))
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Text(commit.author)
                                        .font(.system(size: 6.5, design: .monospaced))
                                        .foregroundStyle(Color(white: 0.5))

                                    Text("• \(commit.timeAgo)")
                                        .font(.system(size: 6.5, design: .monospaced))
                                        .foregroundStyle(Color(white: 0.4))
                                }

                                Text(commit.message)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(Color.white.opacity(0.9))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 3).fill(index == 0 ? Color(white: 0.08) : Color.clear))
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 106)
            .background(Color(red: 0.04, green: 0.04, blue: 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }
}

// MARK: - Expanded Workspace Detail Inspector

struct CyberWorkspaceDetailView: View {
    @ObservedObject var manager: WorkspaceMonitorManager

    var body: some View {
        VStack(spacing: 5) {
            // Sub-Tab Switcher: GIT DIFF vs GIT GRAPH
            HStack(spacing: 4) {
                ForEach(WorkspaceDetailTab.allCases, id: \.self) { tab in
                    let isSelected = manager.detailTab == tab
                    Button(action: {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            manager.detailTab = tab
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: tab == .diff ? "doc.text.magnifyingglass" : "point.topleft.down.to.point.bottomright.curvepath")
                                .font(.system(size: 6.5))
                            Text(tab.rawValue)
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(isSelected ? Color.black : Color(white: 0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 2.5).fill(isSelected ? Color(red: 0.0, green: 0.90, blue: 0.46) : Color(white: 0.10)))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(action: { manager.refresh(force: true) }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 6.5))
                        Text("REFRESH")
                            .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(Color(white: 0.6))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 2.5).fill(Color(white: 0.09)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)

            if manager.detailTab == .graph {
                CyberGitGraphDetailView(manager: manager)
            } else {
                HStack(spacing: 8) {
                    // LEFT PANE: Modified Files List (Width 135pt)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CHANGED FILES (\(manager.changedFiles.count))")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(white: 0.5))

                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 2) {
                                ForEach(manager.changedFiles) { file in
                                    let isSelected = manager.selectedFilePath == file.path
                                    Button(action: {
                                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                                        manager.fetchDiff(for: file.path)
                                    }) {
                                        HStack(spacing: 4) {
                                            Text(file.status)
                                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                                .foregroundStyle(file.statusColor)
                                                .frame(width: 10)

                                            Text(file.filename)
                                                .font(.system(size: 8, weight: isSelected ? .bold : .regular, design: .monospaced))
                                                .foregroundStyle(isSelected ? Color.white : Color(white: 0.75))
                                                .lineLimit(1)
                                                .truncationMode(.middle)

                                            Spacer()
                                        }
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(isSelected ? Color(red: 0.0, green: 0.90, blue: 0.46).opacity(0.18) : Color(white: 0.07))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(height: 100)
                    }
                    .frame(width: 135)

                    // Vertical Divider
                    Rectangle()
                        .fill(Color(red: 0.16, green: 0.19, blue: 0.24))
                        .frame(width: 1, height: 110)

                    // RIGHT PANE: Live Git Diff Preview
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(manager.selectedFilePath ?? "Select a file to inspect diff")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.0, green: 0.90, blue: 0.46))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            if manager.isDiffLoading {
                                ProgressView()
                                    .scaleEffect(0.4)
                                    .frame(width: 10, height: 10)
                            }
                        }

                        ScrollView([.vertical, .horizontal], showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                let lines = manager.selectedFileDiff.components(separatedBy: "\n")
                                ForEach(Array(lines.prefix(120).enumerated()), id: \.offset) { _, line in
                                    CyberDiffLineView(line: line)
                                }
                            }
                        }
                        .frame(height: 100)
                        .background(Color(red: 0.04, green: 0.04, blue: 0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(red: 0.05, green: 0.06, blue: 0.08))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(red: 0.0, green: 0.90, blue: 0.46).opacity(0.3), lineWidth: 1))
        )
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }
}

// MARK: - Combined Cyber Workspace Main View

struct CyberWorkspaceView: View {
    @ObservedObject var manager: WorkspaceMonitorManager
    var appState: AppState

    var body: some View {
        VStack(spacing: 4) {
            CyberWorkspaceHUDView(manager: manager, appState: appState)

            if manager.isExpandedDetail {
                CyberWorkspaceDetailView(manager: manager)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear {
            manager.resolveAndRefreshWorkspace(appState: appState)
        }
    }
}
