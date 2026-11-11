import SwiftUI
import AppKit
import CodeIslandCore

// MARK: - Executive Island Overview (Mission Control for the ALL tab)

struct ExecutiveIslandOverviewView: View {
    var appState: AppState
    @ObservedObject var workspaceManager: WorkspaceMonitorManager
    @ObservedObject var nowPlaying: NowPlayingManager
    @Binding var expandedTab: ExpandedContentTab
    @Binding var groupingMode: String

    @AppStorage(SettingsKey.workspaceAccentColor) private var workspaceAccentColorRaw = SettingsDefaults.workspaceAccentColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activeWorkspaceColor: Color {
        WorkspaceAccentColor(rawValue: workspaceAccentColorRaw)?.color ?? Color(red: 0.0, green: 0.90, blue: 0.46)
    }

    private var tokenSnapshot: ClaudeUsageTotals? {
        appState.claudeUsage?.today
    }

    private var totalTokens: Int {
        guard let s = tokenSnapshot else { return 0 }
        return s.inputTokens + s.outputTokens + s.cacheCreationTokens + s.cacheReadTokens
    }

    private var tokenLabel: String {
        if totalTokens > 0 {
            return ClaudeUsageScanner.formatTokens(totalTokens)
        }
        let totalOps = appState.sessions.values.reduce(0) { $0 + $1.totalToolCallCount }
        if totalOps > 0 {
            return "\(totalOps) ops"
        }
        return "0k"
    }

    var body: some View {
        HStack(spacing: 8) {
            // CARD 1: AGENTS SUMMARY
            AgentsSummaryCard(
                appState: appState,
                tokenLabel: tokenLabel,
                onSelect: {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                        groupingMode = "status"
                    }
                }
            )

            // CARD 2: WORKSPACE & GIT SUMMARY
            WorkspaceSummaryCard(
                manager: workspaceManager,
                accentColor: activeWorkspaceColor,
                onSelect: {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                        expandedTab = .workspace
                    }
                }
            )

            // CARD 3: MUSIC SUMMARY
            MusicSummaryCard(
                nowPlaying: nowPlaying,
                onSelect: {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                        expandedTab = .music
                    }
                }
            )
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
        .padding(.bottom, 6)
    }
}

// MARK: - Card 1: Agents Summary Card

private struct AgentsSummaryCard: View {
    var appState: AppState
    let tokenLabel: String
    let onSelect: () -> Void

    @State private var isHovered = false

    private var sessions: [SessionSnapshot] {
        Array(appState.sessions.values)
    }

    private var needsYouCount: Int {
        sessions.filter { $0.status == .waitingApproval || $0.status == .waitingQuestion }.count
    }

    private var workingCount: Int {
        sessions.filter { $0.status == .running || $0.status == .processing }.count
    }

    private var activeSession: SessionSnapshot? {
        if let needs = sessions.first(where: { $0.status == .waitingApproval || $0.status == .waitingQuestion }) {
            return needs
        }
        if let work = sessions.first(where: { $0.status == .running || $0.status == .processing }) {
            return work
        }
        return sessions.first
    }

    @ViewBuilder
    private var statusBadge: some View {
        if needsYouCount > 0 {
            HStack(spacing: 2.5) {
                Circle()
                    .fill(Color(red: 0.96, green: 0.62, blue: 0.04))
                    .frame(width: 3.5, height: 3.5)
                Text("ATTN (\(needsYouCount))")
                    .font(.system(size: 6, weight: .black, design: .monospaced))
                    .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.04))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.16)))
        } else if workingCount > 0 {
            HStack(spacing: 2.5) {
                Circle()
                    .fill(Color(red: 0.0, green: 0.90, blue: 0.46))
                    .frame(width: 3.5, height: 3.5)
                Text("BUSY (\(workingCount))")
                    .font(.system(size: 6, weight: .black, design: .monospaced))
                    .foregroundStyle(Color(red: 0.0, green: 0.90, blue: 0.46))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.0, green: 0.90, blue: 0.46).opacity(0.14)))
        } else if !sessions.isEmpty {
            Text("\(sessions.count) IDLE")
                .font(.system(size: 6, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(white: 0.5))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.06)))
        } else {
            Text("STANDBY")
                .font(.system(size: 6, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(white: 0.4))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.05)))
        }
    }

    @ViewBuilder
    private var cardBody: some View {
        if let session = activeSession {
            let headline = session.headline(showProjectName: true)
            let titleText = headline.text.uppercased()
            let subText = session.currentTool ?? session.toolDescription ?? session.sourceLabel

            Text(titleText)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(subText)
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(Color(white: 0.65))
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Text("No active sessions")
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(white: 0.70))
                .lineLimit(1)

            Text("Run Claude Code or Gemini in Terminal")
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(Color(white: 0.45))
                .lineLimit(1)
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 3.5) {
                // Header
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))

                    Text("AGENTS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)

                    Spacer(minLength: 0)

                    statusBadge

                    Image(systemName: "chevron.right")
                        .font(.system(size: 6.5, weight: .semibold))
                        .foregroundStyle(isHovered ? Color.white : Color(white: 0.35))
                }

                cardBody

                Spacer(minLength: 0)

                // Footer Telemetry
                HStack(spacing: 4) {
                    HStack(spacing: 2) {
                        Text("⚡")
                            .font(.system(size: 6))
                        Text(tokenLabel)
                            .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))
                    }
                    .padding(.horizontal, 3.5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.06)))

                    Spacer(minLength: 0)

                    Text("DETAILS →")
                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                        .foregroundStyle(isHovered ? Color(red: 0.0, green: 0.96, blue: 0.83) : Color(white: 0.4))
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(white: 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(isHovered ? 0.15 : 0.07), lineWidth: 0.8)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Click to inspect active coding agents")
    }
}

// MARK: - Card 2: Workspace & Git Summary Card

private struct WorkspaceSummaryCard: View {
    @ObservedObject var manager: WorkspaceMonitorManager
    let accentColor: Color
    let onSelect: () -> Void

    @State private var isHovered = false

    @ViewBuilder
    private var headerTrailing: some View {
        if manager.isGitRepo {
            HStack(spacing: 2.5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 5.5, weight: .bold))
                    .foregroundStyle(accentColor)
                Text(manager.branch.isEmpty ? "main" : manager.branch)
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
            }
            .padding(.horizontal, 3.5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08)))
        }

        Image(systemName: "chevron.right")
            .font(.system(size: 6.5, weight: .semibold))
            .foregroundStyle(isHovered ? Color.white : Color(white: 0.35))
    }

    @ViewBuilder
    private var cardBody: some View {
        if !manager.isGitRepo {
            Text("No Git Repository")
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(white: 0.65))

            Text("Choose directory to monitor")
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(Color(white: 0.45))
        } else if manager.changedFiles.isEmpty {
            HStack(spacing: 3) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 6.5))
                    .foregroundStyle(accentColor)
                Text("Tree Clean • Up to date")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.9))
            }

            if let commit = manager.recentCommits.first {
                HStack(spacing: 3) {
                    Text(commit.hash)
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(accentColor)
                    Text("• \(commit.message)")
                        .font(.system(size: 6.5, design: .monospaced))
                        .foregroundStyle(Color(white: 0.5))
                        .lineLimit(1)
                }
            }
        } else {
            Text("\(manager.changedFiles.count) Uncommitted Changes")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white)

            HStack(spacing: 3) {
                if manager.modifiedCount > 0 {
                    Text("\(manager.modifiedCount) mod")
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.04))
                }
                if manager.untrackedCount > 0 {
                    Text("\(manager.untrackedCount) new")
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))
                }
                if manager.deletedCount > 0 {
                    Text("\(manager.deletedCount) del")
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 1.0, green: 0.16, blue: 0.53))
                }
            }
        }
    }

    @ViewBuilder
    private var footerStack: some View {
        HStack(spacing: 4) {
            if manager.stashCount > 0 {
                HStack(spacing: 2.5) {
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 5.5))
                        .foregroundStyle(Color(red: 0.69, green: 0.15, blue: 1.0))
                    Text("\(manager.stashCount) stash")
                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.69, green: 0.15, blue: 1.0))
                }
                .padding(.horizontal, 3.5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.69, green: 0.15, blue: 1.0).opacity(0.14)))
            } else if !manager.projectType.isEmpty {
                ProjectStackBadgeView(stack: manager.projectType, accentColor: accentColor)
            }

            Spacer(minLength: 0)

            Text("GRAPH →")
                .font(.system(size: 6, weight: .bold, design: .monospaced))
                .foregroundStyle(isHovered ? accentColor : Color(white: 0.4))
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 3.5) {
                // Header
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(accentColor)

                    Text(manager.projectName.isEmpty ? "WORKSPACE" : manager.projectName.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    headerTrailing
                }

                cardBody

                Spacer(minLength: 0)

                footerStack
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(white: 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(isHovered ? 0.15 : 0.07), lineWidth: 0.8)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Click to view full Git Graph Spine & diff changes")
    }
}

// MARK: - Card 3: Music Summary Card

private struct MusicSummaryCard: View {
    @ObservedObject var nowPlaying: NowPlayingManager
    let onSelect: () -> Void

    @State private var isHovered = false

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    @ViewBuilder
    private var playStatusBadge: some View {
        if nowPlaying.isPlaying {
            HStack(spacing: 2.5) {
                Circle()
                    .fill(Color(red: 1.0, green: 0.16, blue: 0.53))
                    .frame(width: 3.5, height: 3.5)
                Text("PLAYING")
                    .font(.system(size: 6, weight: .black, design: .monospaced))
                    .foregroundStyle(Color(red: 1.0, green: 0.16, blue: 0.53))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 2).fill(Color(red: 1.0, green: 0.16, blue: 0.53).opacity(0.14)))
        } else if !nowPlaying.title.isEmpty {
            Text("PAUSED")
                .font(.system(size: 6, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(white: 0.45))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.06)))
        } else {
            Text("IDLE")
                .font(.system(size: 6, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(white: 0.4))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.05)))
        }
    }

    @ViewBuilder
    private var cardBody: some View {
        if !nowPlaying.title.isEmpty {
            Text(nowPlaying.title)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(nowPlaying.artist.isEmpty ? "Unknown Artist" : nowPlaying.artist)
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(Color(white: 0.65))
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Text("No track playing")
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(white: 0.70))

            Text("Spotify or Apple Music")
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(Color(white: 0.45))
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 3.5) {
                // Header
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.system(size: 8))
                        .foregroundStyle(Color(red: 1.0, green: 0.16, blue: 0.53))

                    Text(nowPlaying.player.isEmpty ? "MUSIC" : nowPlaying.player.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 1.0, green: 0.16, blue: 0.53))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    playStatusBadge

                    Image(systemName: "chevron.right")
                        .font(.system(size: 6.5, weight: .semibold))
                        .foregroundStyle(isHovered ? Color.white : Color(white: 0.35))
                }

                cardBody

                Spacer(minLength: 0)

                // Mini Scrubber Bar & Playback Controls
                HStack(spacing: 4) {
                    if nowPlaying.trackDuration > 0 {
                        let progress = min(1.0, max(0.0, CGFloat(nowPlaying.playerPosition / nowPlaying.trackDuration)))
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.white.opacity(0.12))
                                    .frame(height: 2.5)

                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color(red: 1.0, green: 0.16, blue: 0.53))
                                    .frame(width: geo.size.width * progress, height: 2.5)
                            }
                        }
                        .frame(height: 3)

                        Text(formatTime(nowPlaying.playerPosition))
                            .font(.system(size: 6, design: .monospaced))
                            .foregroundStyle(Color(white: 0.45))
                    } else {
                        Spacer(minLength: 0)
                    }

                    // Mini Play/Pause button
                    Button(action: {
                        nowPlaying.togglePlayPause()
                    }) {
                        Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 6.5, weight: .bold))
                            .foregroundStyle(Color(red: 1.0, green: 0.16, blue: 0.53))
                            .frame(width: 14, height: 14)
                            .background(RoundedRectangle(cornerRadius: 2).fill(Color(red: 1.0, green: 0.16, blue: 0.53).opacity(0.14)))
                    }
                    .buttonStyle(.plain)

                    Text("LYRICS →")
                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                        .foregroundStyle(isHovered ? Color(red: 1.0, green: 0.16, blue: 0.53) : Color(white: 0.4))
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(white: 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(isHovered ? 0.15 : 0.07), lineWidth: 0.8)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Click to view full Music HUD and live karaoke lyrics")
    }
}
