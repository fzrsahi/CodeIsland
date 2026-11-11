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

// MARK: - Hero Agent Command Deck (Dominant Left Side)

private struct HeroAgentCommandDeck: View {
    var appState: AppState
    let tokenLabel: String
    let onSelect: () -> Void

    @State private var isHovered = false

    private var sessions: [SessionSnapshot] {
        Array(appState.sessions.values)
    }

    private var needsAttention: SessionSnapshot? {
        sessions.first(where: { $0.status == .waitingApproval || $0.status == .waitingQuestion })
    }

    private var workingSession: SessionSnapshot? {
        sessions.first(where: { $0.status == .running || $0.status == .processing })
    }

    private var activeSession: SessionSnapshot? {
        needsAttention ?? workingSession ?? sessions.first
    }

    @ViewBuilder
    private var statusPill: some View {
        if let _ = needsAttention {
            HStack(spacing: 3) {
                Circle()
                    .fill(Color(red: 0.96, green: 0.62, blue: 0.04))
                    .frame(width: 4, height: 4)
                Text("NEEDS APPROVAL")
                    .font(.system(size: 6.5, weight: .black, design: .monospaced))
                    .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.04))
            }
            .padding(.horizontal, 4.5)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.18)))
        } else if let _ = workingSession {
            HStack(spacing: 3) {
                Circle()
                    .fill(Color(red: 0.0, green: 0.90, blue: 0.46))
                    .frame(width: 4, height: 4)
                Text("WORKING LIVE")
                    .font(.system(size: 6.5, weight: .black, design: .monospaced))
                    .foregroundStyle(Color(red: 0.0, green: 0.90, blue: 0.46))
            }
            .padding(.horizontal, 4.5)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.0, green: 0.90, blue: 0.46).opacity(0.16)))
        } else if !sessions.isEmpty {
            Text("\(sessions.count) AGENTS IDLE")
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(white: 0.5))
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.06)))
        } else {
            Text("STANDBY")
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(white: 0.4))
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.05)))
        }
    }

    @ViewBuilder
    private var consoleExecutionBox: some View {
        if let session = activeSession {
            let headline = session.headline(showProjectName: true)
            let projectTitle = headline.text.uppercased()
            let toolName = session.currentTool ?? "Executing"
            let detail = session.toolDescription ?? (session.model ?? "Processing request")

            VStack(alignment: .leading, spacing: 3) {
                // Project & Model Row
                HStack(spacing: 4) {
                    Text(projectTitle)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let model = session.model, !model.isEmpty {
                        Text(model)
                            .font(.system(size: 6, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(white: 0.5))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 0.5)
                            .background(RoundedRectangle(cornerRadius: 1.5).fill(Color.white.opacity(0.06)))
                    }

                    Spacer(minLength: 0)

                    if session.totalToolCallCount > 0 {
                        Text("\(session.totalToolCallCount) ops")
                            .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(white: 0.45))
                    }
                }

                // Machined Terminal Activity Box
                HStack(spacing: 4) {
                    Text("$")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))

                    Text(toolName)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))

                    Text("•")
                        .font(.system(size: 6.5))
                        .foregroundStyle(Color(white: 0.25))

                    Text(detail)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(Color(white: 0.80))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color(red: 0.03, green: 0.04, blue: 0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2.5)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
                        )
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Autonomous Coding Agents Standby")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.85))

                HStack(spacing: 3) {
                    Text("$")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))
                    Text("Ready for Claude Code, Gemini CLI, or Cursor in Terminal")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(Color(white: 0.5))
                }
            }
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                // Header Row
                HStack(spacing: 5) {
                    Image(systemName: "cpu")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))

                    Text("AGENT COMMAND DECK")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)

                    Spacer(minLength: 0)

                    statusPill

                    // Token consumption telemetry
                    HStack(spacing: 2) {
                        Text("⚡")
                            .font(.system(size: 6))
                        Text(tokenLabel)
                            .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.06)))

                    Image(systemName: "chevron.right")
                        .font(.system(size: 6.5, weight: .semibold))
                        .foregroundStyle(isHovered ? Color.white : Color(white: 0.35))
                }

                // Live Execution Box
                consoleExecutionBox

                Spacer(minLength: 0)

                // Secondary agent strip / hints
                HStack(spacing: 4) {
                    if sessions.count > 1 {
                        Text("\(sessions.count) agents active")
                            .font(.system(size: 6.5, design: .monospaced))
                            .foregroundStyle(Color(white: 0.45))
                    } else {
                        Text("Click deck to open detailed agents view")
                            .font(.system(size: 6.5, design: .monospaced))
                            .foregroundStyle(Color(white: 0.35))
                    }

                    Spacer(minLength: 0)

                    Text("INSPECT AGENTS →")
                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                        .foregroundStyle(isHovered ? Color(red: 0.0, green: 0.96, blue: 0.83) : Color(white: 0.40))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5.5)
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
