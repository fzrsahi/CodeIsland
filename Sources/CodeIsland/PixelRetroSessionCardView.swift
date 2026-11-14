import SwiftUI
import CodeIslandCore
import AppKit

/// 16-Bit Cyber-Retro Arcade Session Card for the Agents tab.
/// Crafted with authentic 16-bit cyberdeck hardware aesthetics (SNES/Sega/Amiga/Neo-Geo era):
/// - 16-bit tactile beveled chassis with micro-highlights and drop-shadows.
/// - Recessed cartridge slot for agent mascots with micro status LEDs.
/// - Stepped 16-bit LED task gauges.
/// - Unified 16-bit color hierarchy (Laser Cyan / Adaptive Album primary, Warm Amber, Crisp White).
/// - Completely cleans up compact row layout: NO double-rails or clashing colors sandwiching the mascot icon.
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

    /// Single unified 16-bit accent: Laser Cyan #00F5D4 or Adaptive Album art primary
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
            return Pixel16Palette.cyan
        case .theme, .cyan: return Pixel16Palette.cyan
        case .white: return Pixel16Palette.textWhite
        case .pink: return Color(red: 1.0, green: 0.16, blue: 0.53)
        case .green: return Color(red: 0.12, green: 0.84, blue: 0.38)
        case .amber: return Pixel16Palette.amber
        }
    }

    /// 16-bit status color hierarchy
    private var statusColor: Color {
        switch cardStatus {
        case .working, .thinking:
            return accentColor
        case .needsYou:
            return Pixel16Palette.amber
        case .done:
            return Pixel16Palette.textWhite.opacity(0.85)
        case .stopped, .error:
            return Pixel16Palette.red
        case .idle:
            return Pixel16Palette.textMuted
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
                compact16BitView
            } else {
                comfortable16BitView
            }
        }
    }

    // MARK: - 1. 16-Bit Comfortable Cyberdeck Card

    private var comfortable16BitView: some View {
        HStack(alignment: .top, spacing: 10) {
            // A. Recessed 16-Bit Cartridge Slot (Mascot Pedestal)
            mascotCartridgeSlot

            // B. Content Deck
            VStack(alignment: .leading, spacing: 5) {
                // Header (Status, Source, Project, Branch, Metadata)
                header16BitRow

                // Inline Approval Block
                if session.status == .waitingApproval, let idx = approvalQueueIndex {
                    approval16BitBlock(queueIndex: idx)
                }

                // Cursor external question
                if showsExternalCursorQuestion {
                    cursorQuestion16BitBlock
                }

                // Question waiting row
                if showsQuestionWaitingRow {
                    questionWaiting16BitRow
                }

                // Stepped 16-Bit Task Gauge
                if showTaskProgress && !session.agentTasks.isEmpty {
                    taskProgress16BitGauge
                }

                // User's first prompt (when no recent messages shown)
                if let prompt = session.lastUserPrompt, session.recentMessages.isEmpty {
                    HStack(alignment: .top, spacing: 5) {
                        Text("›")
                            .font(.system(size: 9.5, weight: .black, design: .monospaced))
                            .foregroundStyle(accentColor.opacity(0.8))
                        Text(prompt)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Pixel16Palette.textWhite)
                            .lineLimit(2)
                    }
                }

                // Live Tool Execution or Thinking Row
                liveActivity16BitRow

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
                                    .foregroundStyle(msg.isUser ? Pixel16Palette.textDim : statusColor)
                                Text(msg.text)
                                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                                    .foregroundStyle(msg.isUser ? Pixel16Palette.textMuted : Pixel16Palette.textWhite)
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
                            .foregroundStyle(Pixel16Palette.textMuted)
                            .lineLimit(aiLineLimit ?? 2)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .pixel16Bevel(raised: false, cornerRadius: 2.5, fillColor: Pixel16Palette.slot)
                }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .pixel16Bevel(raised: true, cornerRadius: 5, fillColor: isHovered ? Pixel16Palette.surfaceRaised : Pixel16Palette.surface)
        .padding(.horizontal, 4)
    }

    // MARK: - Mascot Cartridge Slot

    private var mascotCartridgeSlot: some View {
        VStack(spacing: 3) {
            ZStack {
                // Recessed dark slot
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(Pixel16Palette.slot)
                    .frame(width: 34, height: 34)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Pixel16Palette.bevelShadow, Color.clear, Pixel16Palette.bevelHighlight],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.0
                            )
                    )

                MascotView(source: session.mascotSource, status: session.status, size: 28)
            }

            // Subagents Indicator / Status LED
            if showAgentDetails && !session.subagents.isEmpty {
                let count = min(session.subagents.count, 6)
                HStack(spacing: 2) {
                    ForEach(0..<count, id: \.self) { _ in
                        Rectangle()
                            .fill(accentColor.opacity(0.85))
                            .frame(width: 3, height: 2.5)
                    }
                }
            } else {
                // Micro 16-Bit Status Beacon LED
                Circle()
                    .fill(statusColor)
                    .frame(width: 3.5, height: 3.5)
                    .shadow(color: statusColor.opacity(cardStatus == .working || cardStatus == .thinking ? 0.8 : 0.2), radius: 2)
            }
        }
        .frame(width: 36)
    }

    // MARK: - Header 16-Bit Row

    private var header16BitRow: some View {
        HStack(alignment: .center, spacing: 5) {
            // 1. Status Pill
            Pixel16Badge(cardStatus.label, color: statusColor, isFilled: cardStatus == .needsYou)

            // 2. Source Badge
            Pixel16Badge(session.source, color: Pixel16Palette.textMuted)

            // 3. Project Name & Branch
            let headline = session.headline(showProjectName: showProjectName)
            HStack(spacing: 3) {
                WorkspacePixelIcon(glyph: .folder, color: Pixel16Palette.textMuted, pixelSize: 0.85)
                Text(headline.text.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Pixel16Palette.textWhite)
                    .lineLimit(1)

                if let branch = session.gitBranch, !branch.isEmpty {
                    Text("//")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Pixel16Palette.textDim)
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
                    Pixel16Badge("+\(session.subagents.count) SUB", color: accentColor)
                }

                if session.isYoloMode == true {
                    Pixel16Badge("YOLO", color: Pixel16Palette.red)
                }

                if showModelLabel, let modelLabel = session.modelLabel {
                    Text(modelLabel.uppercased())
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(Pixel16Palette.textDim)
                        .padding(.horizontal, 3.5)
                        .padding(.vertical, 1.5)
                        .background(Pixel16Palette.slot)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }

                Text(timeAgo(session.startTime))
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Pixel16Palette.textDim)

                // 16-Bit Dismiss Button
                Button(action: {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    withAnimation(NotchAnimation.micro) {
                        appState.removeSession(sessionId)
                    }
                }) {
                    Text("✕")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(deleteHovered ? Pixel16Palette.red : Pixel16Palette.textDim)
                        .frame(width: 15, height: 15)
                        .background(
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(deleteHovered ? Pixel16Palette.red.opacity(0.2) : Pixel16Palette.slot)
                        )
                }
                .buttonStyle(.plain)
                .onHover { deleteHovered = $0 }
                .help("Dismiss / remove agent session")
            }
        }
    }

    // MARK: - 16-Bit Stepped Task Gauge

    private var taskProgress16BitGauge: some View {
        let items = session.agentTasks.items
        let doneCount = session.agentTasks.completedCount
        let totalCount = items.count

        return HStack(spacing: 6) {
            Text("[\(doneCount)/\(totalCount) TASKS]")
                .font(.system(size: 7.5, weight: .black, design: .monospaced))
                .foregroundStyle(doneCount == totalCount ? accentColor : Pixel16Palette.textWhite)

            // 16-Bit Stepped LED Gauge
            Pixel16Gauge(
                totalSegments: totalCount,
                filledSegments: doneCount,
                isCurrentFlashing: session.status != .idle,
                activeColor: accentColor,
                height: 2.5
            )
            .frame(maxWidth: 84)

            if let active = session.agentTasks.current {
                Text("▶ \(active.title.uppercased())")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Pixel16Palette.textMuted)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2.5)
        .pixel16Bevel(raised: false, cornerRadius: 2.5, fillColor: Pixel16Palette.slot)
    }

    // MARK: - 16-Bit Live Activity Row

    @ViewBuilder
    private var liveActivity16BitRow: some View {
        if let tool = session.currentTool {
            HStack(spacing: 5) {
                Pixel16Badge("▸ \(tool)", color: statusColor)

                if let detail = session.toolDescription, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(Pixel16Palette.textWhite)
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

    // MARK: - 16-Bit Approval Prompt Block

    @ViewBuilder
    private func approval16BitBlock(queueIndex idx: Int) -> some View {
        let event = appState.permissionQueue[idx].event
        let tool = event.toolName ?? session.currentTool ?? "COMMAND"

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("[!]")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .foregroundStyle(Pixel16Palette.amber)
                Text("APPROVAL REQUIRED:")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(Pixel16Palette.amber)
                Text(tool.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Pixel16Palette.textWhite)
            }

            HStack(spacing: 6) {
                Pixel16Button(
                    action: {
                        appState.approvePermission(always: false, expectedSessionId: sessionId)
                    },
                    isAccent: true,
                    accentColor: accentColor
                ) {
                    HStack(spacing: 3) {
                        Text("✓")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                        Text("APPROVE")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                    }
                    .foregroundStyle(Color.black)
                }

                Pixel16Button(
                    action: {
                        appState.denyPermission(expectedSessionId: sessionId)
                    },
                    isAccent: false
                ) {
                    HStack(spacing: 3) {
                        Text("✕")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                        Text("DENY")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                    }
                    .foregroundStyle(Pixel16Palette.red)
                }
            }
        }
        .padding(6)
        .pixel16Bevel(raised: false, cornerRadius: 3, fillColor: Pixel16Palette.amber.opacity(0.08))
    }

    private var cursorQuestion16BitBlock: some View {
        HStack(spacing: 4) {
            Text("[?]")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(Pixel16Palette.amber)
            Text("WAITING FOR ANSWER IN CURSOR")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Pixel16Palette.textWhite)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .pixel16Bevel(raised: false, cornerRadius: 2.5, fillColor: Pixel16Palette.amber.opacity(0.08))
    }

    private var questionWaiting16BitRow: some View {
        Button(action: {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            withAnimation(NotchAnimation.open) {
                appState.surface = .questionCard(sessionId: sessionId)
            }
        }) {
            HStack(spacing: 4) {
                Text("[?]")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(Pixel16Palette.amber)
                Text("QUESTION PENDING — CLICK TO ANSWER")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Pixel16Palette.amber)
                Spacer()
                Text("▸")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(Pixel16Palette.amber)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .pixel16Bevel(raised: true, cornerRadius: 2.5, fillColor: Pixel16Palette.amber.opacity(0.12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. 16-Bit Compact Single-Row Cartridge Strip
    // Completely solves the "2 warna berdekatan di samping icon agents":
    // NO double rails, NO colored tags flanking the mascot icon!
    // Clean layout: [ Recessed Slot + Mascot ] -> [ Project & Branch ] -> [ Live Activity ] -> [ Right Status Pill ]

    private var compact16BitView: some View {
        HStack(alignment: .center, spacing: 6) {
            // A. Clean Recessed Mascot Bay (No colored stripes hugging it)
            ZStack {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Pixel16Palette.slot)
                    .frame(width: 18, height: 18)

                MascotView(source: session.mascotSource, status: session.status, size: 15)
            }
            .frame(width: 18, height: 18)

            // B. Project Name & Branch (High-Contrast White Typography)
            let headline = session.headline(showProjectName: showProjectName)
            HStack(spacing: 3) {
                Text(headline.text.uppercased())
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Pixel16Palette.textWhite)
                    .lineLimit(1)

                if let branch = session.gitBranch, !branch.isEmpty {
                    Text("// \(branch)")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: compactProjectWidth, alignment: .leading)

            // C. Live Tool Execution / Activity in Center
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
                        .foregroundStyle(Pixel16Palette.textMuted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // D. Single 16-Bit Status Pill at Far Right (Far from the mascot icon!)
            Pixel16Badge(cardStatus.label, color: statusColor, isFilled: cardStatus == .needsYou)

            // E. Time Ago
            Text(timeAgo(session.startTime))
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Pixel16Palette.textDim)

            // F. 16-Bit Dismiss Button
            Button(action: {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                withAnimation(NotchAnimation.micro) {
                    appState.removeSession(sessionId)
                }
            }) {
                Text("✕")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(deleteHovered ? Pixel16Palette.red : Pixel16Palette.textDim)
                    .frame(width: 14, height: 14)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(deleteHovered ? Pixel16Palette.red.opacity(0.2) : Pixel16Palette.slot)
                    )
            }
            .buttonStyle(.plain)
            .onHover { deleteHovered = $0 }
            .help("Dismiss / remove agent session")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .pixel16Bevel(raised: true, cornerRadius: 4, fillColor: isHovered ? Pixel16Palette.surfaceRaised : Pixel16Palette.surface)
        .padding(.horizontal, 4)
    }
}
