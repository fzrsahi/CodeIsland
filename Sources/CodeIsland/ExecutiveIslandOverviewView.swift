import SwiftUI
import AppKit
import CodeIslandCore

// MARK: - Executive Island Overview (Mission Control for the ALL tab)

struct ExecutiveIslandOverviewView: View {
    var appState: AppState
    @ObservedObject var workspaceManager: WorkspaceMonitorManager
    @ObservedObject var nowPlaying: NowPlayingManager
    @Binding var expandedTab: ExpandedContentTab

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
        HStack(alignment: .center, spacing: 8) {
            // HERO DECK (LEFT): Live Coding Agent Command Deck (~60% space)
            HeroAgentCommandDeck(
                appState: appState,
                tokenLabel: tokenLabel,
                onSelect: {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                        expandedTab = .agents
                    }
                }
            )
            .frame(maxWidth: .infinity)

            // TELEMETRY WINGS (RIGHT): Live Git HUD & Music Capsules (~40% space)
            VStack(spacing: 5) {
                // Top: Git & Workspace HUD Capsule
                MiniWorkspaceCapsule(
                    manager: workspaceManager,
                    accentColor: activeWorkspaceColor,
                    onSelect: {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                            expandedTab = .workspace
                        }
                    }
                )

                // Bottom: Now Playing Music Capsule
                MiniMusicCapsule(
                    nowPlaying: nowPlaying,
                    onSelect: {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                            expandedTab = .music
                        }
                    }
                )
            }
            .frame(width: 250)
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

// MARK: - Hero Agent Command Deck (Dominant Left Side, styled like SessionCard)

private struct HeroAgentCommandDeck: View {
    var appState: AppState
    let tokenLabel: String
    let onSelect: () -> Void

    @State private var isHovered = false

    private var sessions: [SessionSnapshot] {
        Array(appState.sessions.values)
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

    private func formatTimeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "\(max(1, seconds))s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 8) {
                // Left Mascot Column (matches SessionCard)
                VStack(spacing: 3) {
                    if let session = activeSession {
                        MascotView(source: session.mascotSource, status: session.status, size: 28)
                        if !session.subagents.isEmpty {
                            HStack(spacing: 1) {
                                ForEach(Array(session.subagents.values.prefix(4)), id: \.agentId) { sub in
                                    MiniAgentIcon(active: sub.status != .idle, size: 7)
                                }
                            }
                        }
                    } else {
                        MascotView(source: "claude", status: .idle, size: 28)
                    }
                }
                .frame(width: 32)
                .padding(.top, 1)

                // Main Content Column
                VStack(alignment: .leading, spacing: 3.5) {
                    if let session = activeSession {
                        let cardStatus = SessionCardStatus(session)
                        let headline = session.headline(showProjectName: true)
                        let projectTitle = headline.text.uppercased()

                        // Header Row: Status Chip + Project Title + Model Tag + Token Telemetry
                        HStack(alignment: .center, spacing: 4) {
                            SessionStatusChip(status: cardStatus, fontSize: 7)

                            Text(projectTitle)
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            if let model = session.modelLabel ?? session.model, !model.isEmpty {
                                Text(model)
                                    .font(.system(size: 6, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color(white: 0.55))
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 0.5)
                                    .background(RoundedRectangle(cornerRadius: 1.5).fill(Color.white.opacity(0.06)))
                            }

                            Spacer(minLength: 0)

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

                            Image(systemName: "chevron.right")
                                .font(.system(size: 6))
                                .foregroundStyle(isHovered ? Color.white : Color(white: 0.35))
                        }

                        // Live Activity Body: Thinking or Tool Running or Recap (matches SessionCard)
                        liveActivityRow(session: session, cardStatus: cardStatus)

                        Spacer(minLength: 0)

                        // Footer Row: Operation Count + Time Ago + Action Affordance
                        HStack(spacing: 4) {
                            if session.totalToolCallCount > 0 {
                                Text("\(session.totalToolCallCount) ops")
                                    .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color(white: 0.45))
                            }

                            Text("• \(formatTimeAgo(session.lastActivity))")
                                .font(.system(size: 6.5, design: .monospaced))
                                .foregroundStyle(Color(white: 0.35))

                            if sessions.count > 1 {
                                Text("• \(sessions.count) sessions")
                                    .font(.system(size: 6.5, design: .monospaced))
                                    .foregroundStyle(Color(white: 0.40))
                            }

                            Spacer(minLength: 0)

                            Text("INSPECT AGENTS →")
                                .font(.system(size: 6, weight: .bold, design: .monospaced))
                                .foregroundStyle(isHovered ? Color(red: 0.0, green: 0.96, blue: 0.83) : Color(white: 0.40))
                        }
                    } else {
                        // Empty Standby State
                        HStack(spacing: 4) {
                            Text("AUTONOMOUS AGENTS")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white)

                            Text("STANDBY")
                                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(white: 0.4))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.05)))

                            Spacer(minLength: 0)

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
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ready for Claude Code, Gemini CLI, Cursor, or Codex")
                                .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.8))

                            Text("Run an agent in Terminal to monitor live status here")
                                .font(.system(size: 6.5, design: .monospaced))
                                .foregroundStyle(Color(white: 0.45))
                        }

                        Spacer(minLength: 0)

                        HStack {
                            Spacer()
                            Text("OPEN AGENTS TAB →")
                                .font(.system(size: 6, weight: .bold, design: .monospaced))
                                .foregroundStyle(isHovered ? Color(red: 0.0, green: 0.96, blue: 0.83) : Color(white: 0.4))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(white: 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(isHovered ? 0.16 : 0.07), lineWidth: 0.8)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Click to view full Agent Sessions list")
    }

    @ViewBuilder
    private func liveActivityRow(session: SessionSnapshot, cardStatus: SessionCardStatus) -> some View {
        if cardStatus == .thinking || session.status == .processing {
            // Live Thinking with Bouncing Neon Dots
            HStack(spacing: 5) {
                TypingIndicator(fontSize: 7.5, label: "Thinking...", bright: true, color: Color(red: 0.25, green: 0.9, blue: 0.8))

                if let prompt = session.lastUserPrompt, !prompt.isEmpty {
                    Text("• \(prompt)")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(Color(white: 0.65))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color(red: 0.03, green: 0.05, blue: 0.08))
                    .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(Color(red: 0.0, green: 0.96, blue: 0.83).opacity(0.18), lineWidth: 0.6))
            )
        } else if let tool = session.currentTool {
            // Tool Execution Line (matches SessionCard)
            HStack(spacing: 4) {
                SessionToolChip(tool: tool, color: cardStatus.color, fontSize: 7.5)

                if let detail = session.toolDescription, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if let prompt = session.lastUserPrompt {
                    Text(prompt)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(Color(white: 0.65))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color(red: 0.03, green: 0.04, blue: 0.06))
                    .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(Color.white.opacity(0.08), lineWidth: 0.6))
            )
        } else if cardStatus == .needsYou {
            // Waiting for User Input / Approval
            HStack(spacing: 3.5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.04))

                Text("Requires your input or approval")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.04))
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.25), lineWidth: 0.6))
            )
        } else if let recap = session.visibleRecap {
            // Recap of completed turn
            HStack(spacing: 3) {
                Text("✓")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(Color(red: 0.0, green: 0.90, blue: 0.46))
                Text(recap.text)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(Color(white: 0.70))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } else if let prompt = session.lastUserPrompt {
            // Prompt preview
            Text("› \(prompt)")
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(Color(white: 0.65))
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Text("Session idle • Ready for turn")
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(Color(white: 0.45))
        }
    }
}

// MARK: - Mini Workspace Capsule (Upper Right)

private struct MiniWorkspaceCapsule: View {
    @ObservedObject var manager: WorkspaceMonitorManager
    let accentColor: Color
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 2) {
                // Row 1: Repo, Branch, Stack
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 7.5))
                        .foregroundStyle(accentColor)

                    Text(manager.projectName.isEmpty ? "WORKSPACE" : manager.projectName.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if manager.isGitRepo {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 5.5, weight: .bold))
                                .foregroundStyle(accentColor)
                            Text(manager.branch.isEmpty ? "main" : manager.branch)
                                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.9))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08)))
                    }

                    Spacer(minLength: 0)

                    if manager.stashCount > 0 {
                        Text("\(manager.stashCount) stash")
                            .font(.system(size: 6, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.69, green: 0.15, blue: 1.0))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 0.5)
                            .background(RoundedRectangle(cornerRadius: 1.5).fill(Color(red: 0.69, green: 0.15, blue: 1.0).opacity(0.15)))
                    } else if !manager.projectType.isEmpty {
                        ProjectStackBadgeView(stack: manager.projectType, accentColor: accentColor)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 6))
                        .foregroundStyle(isHovered ? Color.white : Color(white: 0.35))
                }

                // Row 2: Status Line
                if !manager.isGitRepo {
                    Text("No Git repo detected")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(Color(white: 0.5))
                } else if manager.changedFiles.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(accentColor)
                        Text("Tree clean • In sync")
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.85))

                        if let commit = manager.recentCommits.first {
                            Text("• \(commit.hash)")
                                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(accentColor)
                        }
                    }
                } else {
                    HStack(spacing: 3) {
                        Text("\(manager.changedFiles.count) changes:")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white)

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
            .padding(.horizontal, 6)
            .padding(.vertical, 4.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(Color(white: 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3.5)
                            .stroke(Color.white.opacity(isHovered ? 0.16 : 0.07), lineWidth: 0.8)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Click to open Git Graph & Workspace monitor")
    }
}

// MARK: - Mini Music Capsule (Lower Right)

private struct MiniMusicCapsule: View {
    @ObservedObject var nowPlaying: NowPlayingManager
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                // Artwork or Waveform
                ZStack {
                    if let art = nowPlaying.artworkImage {
                        Image(nsImage: art)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(red: 0.08, green: 0.09, blue: 0.12))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(red: 1.0, green: 0.16, blue: 0.53))
                            )
                    }
                }

                // Middle: Track & Artist
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text(nowPlaying.player.isEmpty ? "MUSIC" : nowPlaying.player.uppercased())
                            .font(.system(size: 6, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 1.0, green: 0.16, blue: 0.53))

                        if nowPlaying.isPlaying {
                            Circle()
                                .fill(Color(red: 1.0, green: 0.16, blue: 0.53))
                                .frame(width: 3, height: 3)
                        }
                    }

                    Text(nowPlaying.title.isEmpty ? "No track playing" : nowPlaying.title)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(nowPlaying.artist.isEmpty ? "Idle" : nowPlaying.artist)
                        .font(.system(size: 6.5, design: .monospaced))
                        .foregroundStyle(Color(white: 0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                // Play / Pause Quick Button
                Button(action: {
                    nowPlaying.togglePlayPause()
                }) {
                    Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.16, blue: 0.53))
                        .frame(width: 18, height: 18)
                        .background(RoundedRectangle(cornerRadius: 2.5).fill(Color(red: 1.0, green: 0.16, blue: 0.53).opacity(0.15)))
                }
                .buttonStyle(.plain)

                // Next Track Button
                Button(action: {
                    nowPlaying.nextTrack()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 6.5, weight: .bold))
                        .foregroundStyle(Color(white: 0.7))
                        .frame(width: 16, height: 18)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(Color(white: 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3.5)
                            .stroke(Color.white.opacity(isHovered ? 0.16 : 0.07), lineWidth: 0.8)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Click to open full Music HUD and live karaoke lyrics")
    }
}
