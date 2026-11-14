import SwiftUI
import CodeIslandCore
import AppKit

/// Authentic retro arcade session card for the Agents tab.
/// Harmonizes 100% with Workspace HUD and Music HUD using a single unified accent
/// (Cyber Cyan #00F5D4 by default, or Adaptive Album Palette when playing music).
/// Designed according to anti-slop principles: zero clashing neon colors, zero boxy stroke borders,
/// and high-contrast obsidian dark glass surfaces.
struct PixelRetroSessionCardView: View {
    var appState: AppState
    let sessionId: String
    let session: SessionSnapshot
    var isCompletion: Bool = false
    var isCompactRow: Bool = false
    var compactProjectWidth: CGFloat = 150
    var compactStatusWidth: CGFloat = 64
    var isHovered: Bool = false
    var fontSize: CGFloat = 11

    @AppStorage(SettingsKey.musicHUDProgressColor) private var musicHUDProgressColor = SettingsDefaults.musicHUDProgressColor
    @AppStorage(SettingsKey.syncThemeWithAlbumArt) private var syncThemeWithAlbumArt = SettingsDefaults.syncThemeWithAlbumArt
    @AppStorage(SettingsKey.showAgentDetails) private var showAgentDetails = SettingsDefaults.showAgentDetails
    @AppStorage(SettingsKey.showTaskProgress) private var showTaskProgress = SettingsDefaults.showTaskProgress
    @AppStorage(SettingsKey.showSessionRecap) private var showSessionRecap = SettingsDefaults.showSessionRecap
    @AppStorage(SettingsKey.showModelLabel) private var showModelLabel = SettingsDefaults.showModelLabel
    @AppStorage(SettingsKey.showProjectName) private var showProjectName = SettingsDefaults.showProjectName
    @AppStorage(SettingsKey.aiMessageLines) private var aiMessageLines = SettingsDefaults.aiMessageLines

    @ObservedObject private var nowPlaying = NowPlayingManager.shared
    @State private var deleteHovered = false
    @State private var approveHovered = false
    @State private var denyHovered = false

    private var cardStatus: SessionCardStatus { SessionCardStatus(session) }
    private var aiLineLimit: Int? { aiMessageLines > 0 ? aiMessageLines : nil }

    private var approvalQueueIndex: Int? {
        appState.permissionQueue.firstIndex { ($0.event.sessionId ?? "default") == sessionId }
    }

    private var showsExternalCursorQuestion: Bool {
        session.status == .waitingQuestion && session.cursorPendingQuestion != nil
    }

    private var showsQuestionWaitingRow: Bool {
        session.status == .waitingQuestion
            && !showsExternalCursorQuestion
            && appState.pendingQuestion(forSession: sessionId) != nil
            && appState.surface.questionSessionId != sessionId
    }

    /// Single unified accent: Adaptive album palette or Cyber Cyan #00F5D4
    private var accentColor: Color {
        if (syncThemeWithAlbumArt || musicHUDProgressColor == "album") && nowPlaying.isPlaying && nowPlaying.artworkImage != nil {
            return nowPlaying.albumPalette.primary
        }
        let pc = MusicProgressColor(rawValue: musicHUDProgressColor) ?? .theme
        switch pc {
        case .album:
            if nowPlaying.isPlaying && nowPlaying.artworkImage != nil {
                return nowPlaying.albumPalette.primary
            }
            return Color(red: 0.0, green: 0.96, blue: 0.83)
        case .theme, .cyan: return Color(red: 0.0, green: 0.96, blue: 0.83) // Cyber Cyan
        case .white: return .white
        case .pink: return Color(red: 1.0, green: 0.16, blue: 0.53)
        case .green: return Color(red: 0.12, green: 0.84, blue: 0.38)
        case .amber: return Color(red: 1.0, green: 0.72, blue: 0.20)
        }
    }

    /// Strict single-accent palette hierarchy: No clashing green + cyan neons!
    private var statusColor: Color {
        switch cardStatus {
        case .working, .thinking:
            return accentColor
        case .needsYou:
            return Color(red: 1.0, green: 0.72, blue: 0.20)
        case .done:
            return Color.white.opacity(0.85)
        case .stopped, .error:
            return Color(red: 0.95, green: 0.40, blue: 0.40)
        case .idle:
            return Color.white.opacity(0.40)
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = max(0, Int(-date.timeIntervalSinceNow))
        if seconds < 60 { return "NOW" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)M" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)H" }
        return "\(hours / 24)D"
    }

    var body: some View {
        Group {
            if isCompactRow {
                compactView
            } else {
                comfortableView
            }
        }
    }

    // MARK: - 1. Comfortable View (Seamless Arcade Card)

    private var comfortableView: some View {
        HStack(alignment: .top, spacing: 10) {
            // A. Mascot Pedestal Column
            mascotPedestal

            // B. Content Rows
            VStack(alignment: .leading, spacing: 5) {
                // Header Bar (Status, Source, Repo, Tags, Dismiss)
                headerRow

                // Inline Approval Block
                if session.status == .waitingApproval, let idx = approvalQueueIndex {
                    retroApprovalBlock(queueIndex: idx)
                }

                // Cursor external question
                if showsExternalCursorQuestion {
                    retroCursorQuestionBlock
                }

                // Question waiting row
                if showsQuestionWaitingRow {
                    retroQuestionWaitingRow
                }

                // Stepped Task Progress Bar
                if showTaskProgress && !session.agentTasks.isEmpty {
                    retroTaskProgressBar
                }

                // User's first prompt (when no recent messages shown)
                if let prompt = session.lastUserPrompt, session.recentMessages.isEmpty {
                    HStack(alignment: .top, spacing: 5) {
                        Text("›")
                            .font(.system(size: 9.5, weight: .black, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.50))
                        Text(prompt)
                            .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineLimit(2)
                    }
                }

                // Live Tool Execution or Thinking Row
                liveActivityRow

                // Recent Chat Messages
                if !session.recentMessages.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        let visible = session.status != .idle
                            ? Array(session.recentMessages.suffix(2))
                            : session.recentMessages
                        ForEach(visible) { msg in
                            HStack(alignment: .top, spacing: 5) {
                                Text(msg.isUser ? "›" : "●")
                                    .font(.system(size: 9, weight: .black, design: .monospaced))
                                    .foregroundStyle(msg.isUser ? Color.white.opacity(0.5) : statusColor)
                                Text(msg.text)
                                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                                    .foregroundStyle(msg.isUser ? Color.white.opacity(0.75) : Color.white.opacity(0.92))
                                    .lineLimit(aiLineLimit ?? 2)
                            }
                        }
                    }
                }

                // Idle Turn Recap
                if showSessionRecap, let recap = session.visibleRecap {
                    HStack(alignment: .top, spacing: 5) {
                        Text("↻")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundStyle(statusColor)
                        Text(recap.text)
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.80))
                            .lineLimit(aiLineLimit ?? 2)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.06 : 0.025))

                // Left 2px status rail
                Rectangle()
                    .fill(statusColor)
                    .frame(width: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        )
        .padding(.horizontal, 4)
    }

    // MARK: - Mascot Pedestal

    private var mascotPedestal: some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 34, height: 34)

                MascotView(source: session.mascotSource, status: session.status, size: 28)
            }

            if showAgentDetails && !session.subagents.isEmpty {
                let count = min(session.subagents.count, 6)
                HStack(spacing: 2) {
                    ForEach(0..<count, id: \.self) { _ in
                        Rectangle()
                            .fill(accentColor.opacity(0.8))
                            .frame(width: 3.5, height: 3.5)
                    }
                }
            }
        }
        .frame(width: 36)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 6) {
            // 1. Status Chip (Seamless Frosted)
            HStack(spacing: 4) {
                Rectangle()
                    .fill(statusColor)
                    .frame(width: 3.5, height: 3.5)
                Text(cardStatus.label.uppercased())
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(statusColor)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(statusColor.opacity(0.14))
            )

            // 2. Source Badge
            Text(session.source.uppercased())
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.75))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )

            // 3. Project Name & Branch
            let headline = session.headline(showProjectName: showProjectName)
            HStack(spacing: 3) {
                WorkspacePixelIcon(glyph: .folder, color: Color.white.opacity(0.60), pixelSize: 0.85)
                Text(headline.text.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .lineLimit(1)

                if let branch = session.gitBranch, !branch.isEmpty {
                    Text("//")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.35))
                    WorkspacePixelIcon(glyph: .branch, color: statusColor, pixelSize: 0.85)
                    Text(branch)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 4. Metadata Tags & Dismiss
            HStack(spacing: 4) {
                if !session.subagents.isEmpty {
                    Text("+\(session.subagents.count) SUB")
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(accentColor.opacity(0.14))
                }

                if session.isYoloMode == true {
                    Text("YOLO")
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                        .foregroundStyle(Color(red: 1.0, green: 0.35, blue: 0.35))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Color(red: 1.0, green: 0.35, blue: 0.35).opacity(0.15))
                }

                if showModelLabel, let modelLabel = session.modelLabel {
                    Text(modelLabel.uppercased())
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.50))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Color.white.opacity(0.04))
                }

                Text(timeAgo(session.startTime))
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.40))

                // Delete button
                Button(action: {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    withAnimation(NotchAnimation.micro) {
                        appState.removeSession(sessionId)
                    }
                }) {
                    Text("✕")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(deleteHovered ? Color(red: 1.0, green: 0.38, blue: 0.38) : Color.white.opacity(isHovered ? 0.45 : 0.15))
                        .frame(width: 14, height: 14)
                        .background(deleteHovered ? Color(red: 1.0, green: 0.38, blue: 0.38).opacity(0.15) : Color.clear)
                }
                .buttonStyle(.plain)
                .onHover { deleteHovered = $0 }
                .help("Dismiss / remove agent session")
            }
        }
    }

    // MARK: - Stepped Task Progress Bar

    private var retroTaskProgressBar: some View {
        let items = session.agentTasks.items
        let doneCount = session.agentTasks.completedCount
        let totalCount = items.count

        return HStack(spacing: 6) {
            Text("[\(doneCount)/\(totalCount) TASKS]")
                .font(.system(size: 7.5, weight: .black, design: .monospaced))
                .foregroundStyle(doneCount == totalCount ? accentColor : Color.white.opacity(0.85))

            // Stepped blocks matching Music HUD scrubber
            HStack(spacing: 2) {
                ForEach(0..<min(totalCount, 12), id: \.self) { i in
                    let isDone = i < doneCount
                    let isCurrent = (i == doneCount && session.status != .idle)
                    Rectangle()
                        .fill(isDone ? accentColor : (isCurrent ? Color(red: 1.0, green: 0.72, blue: 0.20) : Color.white.opacity(0.12)))
                        .frame(height: 2.5)
                }
            }
            .frame(maxWidth: 80)

            if let active = session.agentTasks.current {
                Text("▶ \(active.title.uppercased())")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }

    // MARK: - Live Activity Row

    @ViewBuilder
    private var liveActivityRow: some View {
        if let tool = session.currentTool {
            HStack(spacing: 5) {
                Text("▸ [\(tool.uppercased())]")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(statusColor.opacity(0.14))
                    )

                if let detail = session.toolDescription, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        } else if cardStatus == .thinking {
            HStack(spacing: 4) {
                Text("■ ■ ■")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(accentColor)
                Text("THINKING...")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(accentColor)
            }
        }
    }

    // MARK: - Retro Approval Prompt Block

    @ViewBuilder
    private func retroApprovalBlock(queueIndex idx: Int) -> some View {
        let event = appState.permissionQueue[idx].event
        let tool = event.toolName ?? session.currentTool ?? "COMMAND"

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("[!]")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.20))
                Text("APPROVAL REQUIRED:")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.20))
                Text(tool.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white)
            }

            HStack(spacing: 6) {
                Button(action: {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    appState.approvePermission(always: false, expectedSessionId: sessionId)
                }) {
                    HStack(spacing: 3) {
                        Text("✓")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                        Text("APPROVE")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                    }
                    .foregroundStyle(approveHovered ? Color.white : Color.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(approveHovered ? accentColor.opacity(0.85) : accentColor)
                    )
                }
                .buttonStyle(.plain)
                .onHover { approveHovered = $0 }

                Button(action: {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    appState.denyPermission(expectedSessionId: sessionId)
                }) {
                    HStack(spacing: 3) {
                        Text("✕")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                        Text("DENY")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(denyHovered ? Color(red: 0.95, green: 0.30, blue: 0.30) : Color(red: 0.80, green: 0.20, blue: 0.20))
                    )
                }
                .buttonStyle(.plain)
                .onHover { denyHovered = $0 }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(red: 1.0, green: 0.72, blue: 0.20).opacity(0.08))
        )
    }

    private var retroCursorQuestionBlock: some View {
        HStack(spacing: 4) {
            Text("[?]")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.20))
            Text("WAITING FOR ANSWER IN CURSOR")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(red: 1.0, green: 0.72, blue: 0.20).opacity(0.10))
        )
    }

    private var retroQuestionWaitingRow: some View {
        Button(action: {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            withAnimation(NotchAnimation.open) {
                appState.surface = .questionCard(sessionId: sessionId)
            }
        }) {
            HStack(spacing: 4) {
                Text("[?]")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.20))
                Text("QUESTION PENDING — CLICK TO ANSWER")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.20))
                Spacer()
                Text("▸")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.20))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.72, blue: 0.20).opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. Compact View (Single-Row Arcade Tape Strip)

    private var compactView: some View {
        HStack(alignment: .center, spacing: 6) {
            // Mini 2px Rail
            Rectangle()
                .fill(statusColor)
                .frame(width: 2, height: 16)

            // Mini Mascot
            MascotView(source: session.mascotSource, status: session.status, size: 16)

            // Status tag
            Text(cardStatus.label.uppercased())
                .font(.system(size: 7.5, weight: .black, design: .monospaced))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(statusColor.opacity(0.12))
                )

            // Source
            Text(session.source.uppercased())
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.60))

            // Project Name & Branch
            let headline = session.headline(showProjectName: showProjectName)
            HStack(spacing: 2) {
                Text(headline.text.uppercased())
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .lineLimit(1)

                if let branch = session.gitBranch, !branch.isEmpty {
                    Text("// \(branch)")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: compactProjectWidth, alignment: .leading)

            // Compact Live Tool / Prompt / Recap
            HStack(spacing: 4) {
                if let tool = session.currentTool {
                    Text("▸ [\(tool.uppercased())]")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(statusColor)
                } else if cardStatus == .thinking {
                    Text("■ ■ ■")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(accentColor)
                } else if let prompt = session.lastUserPrompt {
                    Text("› \(prompt)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Time
            Text(timeAgo(session.startTime))
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.40))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.06 : 0.02))

                Rectangle()
                    .fill(statusColor)
                    .frame(width: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        )
        .padding(.horizontal, 4)
    }
}
