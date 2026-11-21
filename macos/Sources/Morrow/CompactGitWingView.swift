import SwiftUI

/// Display state for the minimal Git-only collapsed right wing (single-priority indicator).
public enum CompactGitDisplayState: Equatable, Sendable {
    case nonRepo
    case clean
    case modified(Int)
    case ahead(Int)
}

public enum CompactGitStatusModel {
    /// Derives the compact right-wing Git state with strict single-state priority:
    /// modified (uncommitted) takes priority over ahead (unpushed), never shown simultaneously.
    public static func state(isGitRepo: Bool, aheadCount: Int, changedCount: Int) -> CompactGitDisplayState {
        guard isGitRepo else { return .nonRepo }
        let safeAhead = max(0, aheadCount)
        let safeChanged = max(0, changedCount)
        if safeChanged > 0 {
            return .modified(safeChanged)
        }
        if safeAhead > 0 {
            return .ahead(safeAhead)
        }
        return .clean
    }

    /// Estimates the right-wing width baseline before GeometryReader finishes its first measurement pass.
    public static func estimatedBaselineWidth(isGitRepo: Bool, aheadCount: Int, changedCount: Int) -> CGFloat {
        switch state(isGitRepo: isGitRepo, aheadCount: aheadCount, changedCount: changedCount) {
        case .nonRepo:
            return 42
        case .clean:
            return 44
        case .modified:
            return 46
        case .ahead:
            return 48
        }
    }
}

public enum CompactNotchWingGeometry {
    /// Enforces strict left/right wing symmetry for notched layouts across idle, thinking, and HUD states.
    public static func strictSymmetricWingWidth(leftWidth: CGFloat, rightWidth: CGFloat) -> CGFloat {
        max(0, max(leftWidth, rightWidth))
    }

    /// Horizontal offset needed so asymmetric left/right wings keep the physical camera notch centered.
    public static func centerShift(
        leftWidth: CGFloat,
        rightWidth: CGFloat,
        hasNotch: Bool,
        asymmetricEnabled: Bool
    ) -> CGFloat {
        guard hasNotch, asymmetricEnabled else { return 0 }
        return (rightWidth - leftWidth) / 2
    }
}

/// Minimal Git-only right wing view using Full Auto theme/album colors and zero dot separators.
struct CompactGitStandbyWingView: View {
    @ObservedObject var workspaceManager: WorkspaceMonitorManager
    var appState: AppState
    var isDynamicIslandCompact: Bool = false
    var isWideMode: Bool = false
    var maxContentWidth: CGFloat? = nil
    var onTap: (() -> Void)? = nil

    @AppStorage(SettingsKey.islandUITheme) private var islandUITheme = SettingsDefaults.islandUITheme
    @AppStorage(SettingsKey.musicHUDProgressColor) private var musicHUDProgressColor = SettingsDefaults.musicHUDProgressColor
    @AppStorage(SettingsKey.syncThemeWithAlbumArt) private var syncThemeWithAlbumArt = SettingsDefaults.syncThemeWithAlbumArt

    private var isPixel: Bool {
        islandUITheme == IslandUITheme.pixel.rawValue
    }

    private var primaryAutoColor: Color {
        let base = AppColorTheme.accent(for: musicHUDProgressColor, isModern: !isPixel)
        return AppColorTheme.readableOnDark(base)
    }

    private var secondaryAutoColor: Color {
        AppColorTheme.secondaryAccent(for: musicHUDProgressColor)
    }

    private var isAlbumColorActive: Bool {
        let pc = MusicProgressColor(rawValue: musicHUDProgressColor) ?? .theme
        return (syncThemeWithAlbumArt || pc == .album)
            && NowPlayingManager.shared.isPlaying
            && NowPlayingManager.shared.artworkImage != nil
    }

    private var cleanColor: Color {
        isAlbumColorActive
            ? primaryAutoColor.opacity(0.85)
            : Color(red: 0.20, green: 0.83, blue: 0.60)
    }

    private var displayState: CompactGitDisplayState {
        if workspaceManager.testWingPreview == .nonGitIdle || workspaceManager.testWingPreview == .nonGitThinking {
            return .nonRepo
        }
        return CompactGitStatusModel.state(
            isGitRepo: workspaceManager.isGitRepo,
            aheadCount: workspaceManager.aheadCount,
            changedCount: workspaceManager.changedFiles.count
        )
    }

    var body: some View {
        let fontSize: CGFloat = isDynamicIslandCompact ? 11 : 10.5

        Group {
            if isWideMode {
                wideBody(fontSize: fontSize)
            } else {
                compactBody(fontSize: fontSize)
            }
        }
        .fixedSize(horizontal: !isWideMode && displayState != .nonRepo, vertical: false)
        .frame(maxWidth: displayState == .nonRepo ? (isWideMode ? maxContentWidth : .infinity) : (isWideMode ? maxContentWidth : nil), alignment: displayState == .nonRepo ? .center : .trailing)
        .contentShape(Rectangle())
        .onAppear {
            if workspaceManager.currentCwd.isEmpty || !workspaceManager.isGitRepo {
                workspaceManager.resolveAndRefreshWorkspace(appState: appState)
            }
        }
        .onTapGesture {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            onTap?()
        }
    }

    @ViewBuilder
    private func compactBody(fontSize: CGFloat) -> some View {
        HStack(spacing: isPixel ? 5 : 7) {
            switch displayState {
            case .modified(let modified):
                modifiedToken(count: modified, fontSize: fontSize)
            case .ahead(let ahead):
                HStack(spacing: 4) {
                    unpushedToken(ahead: ahead, fontSize: fontSize)
                    branchGlyph(color: isPixel ? Pixel16Palette.cyan : primaryAutoColor)
                }
            case .clean:
                HStack(spacing: isPixel ? 4 : 3) {
                    let color = isPixel ? Pixel16Palette.cyan : cleanColor
                    branchGlyph(color: color)
                    if isPixel {
                        WorkspacePixelIcon(glyph: .check, color: color, pixelSize: 1.2)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(color)
                    }
                }
            case .nonRepo:
                if isPixel {
                    WorkspacePixelIcon(glyph: .folder, color: Pixel16Palette.textDim, pixelSize: 1.75)
                } else {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.68))
                }
            }
        }
    }

    /// Strips conventional type prefixes (feat/, fix/, etc.) on long branches so meaningful IDs/slugs stay visible.
    private static func compactBranchLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "main" }
        if trimmed.count > 10, let slash = trimmed.firstIndex(of: "/") {
            let afterSlash = trimmed[trimmed.index(after: slash)...]
            if !afterSlash.isEmpty {
                return String(afterSlash)
            }
        }
        return trimmed
    }

    private var pixelWideTelemetryEstimatedWidth: CGFloat {
        let px: CGFloat = 1.0
        let charStep = 6.0 * px
        switch displayState {
        case .modified(let modified):
            let ins = max(0, workspaceManager.insertions)
            let del = max(0, workspaceManager.deletions)
            if ins > 0 || del > 0 {
                let insWidth = ins > 0 ? CGFloat("+\(ins)".count) * charStep : 0
                let delWidth = del > 0 ? CGFloat("-\(del)".count) * charStep : 0
                let gap: CGFloat = (ins > 0 && del > 0) ? 4 : 0
                return insWidth + delWidth + gap
            }
            return CGFloat("\(modified)M".count) * charStep
        case .ahead(let ahead):
            return 10 + 2 + CGFloat("\(ahead)".count) * charStep
        case .clean:
            let behind = max(0, workspaceManager.behindCount)
            if behind > 0 {
                return 10 + 2 + CGFloat("\(behind)".count) * charStep
            }
            return CGFloat("SYNC".count) * charStep
        case .nonRepo:
            return 0
        }
    }

    private var pixelWideMaxBranchChars: Int {
        let px: CGFloat = 1.0
        let charStep = 6.0 * px
        guard let maxW = maxContentWidth, maxW > 0 else { return 8 }
        // Reserve: branch icon (~10pt) + inner spacing (4pt) + outer HStack spacing (5pt) + telemetry + 4pt safety margin
        let overhead = 10 + 4 + 5 + pixelWideTelemetryEstimatedWidth + 4
        let remaining = max(0, maxW - overhead)
        return max(3, Int(floor(remaining / charStep)))
    }

    @ViewBuilder
    private func wideBody(fontSize: CGFloat) -> some View {
        let branchColor: Color = isPixel ? Pixel16Palette.cyan : primaryAutoColor
        let labelFont: Font = .system(size: 10, weight: .bold, design: .monospaced)
        let statFont: Font = .system(size: 10, weight: .bold, design: .monospaced)
        let branchLabel = Self.compactBranchLabel(workspaceManager.branch)
        let rawProject = workspaceManager.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectLabel = rawProject.isEmpty ? "Workspace" : rawProject
        let maxPixelChars = pixelWideMaxBranchChars

        HStack(spacing: isPixel ? 6 : 6) {
            switch displayState {
            case .nonRepo:
                if isPixel {
                    WorkspacePixelIcon(glyph: .folder, color: Pixel16Palette.textMuted, pixelSize: 1.5)
                    PixelText(text: projectLabel, color: Pixel16Palette.textWhite, pixelSize: 1.0, maxChars: maxPixelChars)
                } else {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.78))
                    Text(projectLabel)
                        .font(labelFont)
                        .foregroundStyle(Color.white.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            default:
                HStack(spacing: 4) {
                    branchGlyph(color: branchColor)
                    if isPixel {
                        PixelText(text: branchLabel, color: Pixel16Palette.textWhite, pixelSize: 1.0, maxChars: maxPixelChars)
                    } else {
                        Text(branchLabel)
                            .font(labelFont)
                            .foregroundStyle(Color.white.opacity(0.92))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                wideTelemetryToken(statFont: statFont)
            }
        }
    }

    @ViewBuilder
    private func wideTelemetryToken(statFont: Font) -> some View {
        switch displayState {
        case .modified(let modified):
            let ins = max(0, workspaceManager.insertions)
            let del = max(0, workspaceManager.deletions)
            if ins > 0 || del > 0 {
                HStack(spacing: isPixel ? 4 : 3) {
                    if ins > 0 {
                        if isPixel {
                            PixelText(text: "+\(ins)", color: Pixel16Palette.cyan, pixelSize: 1.0)
                        } else {
                            Text("+\(ins)")
                                .font(statFont)
                                .monospacedDigit()
                                .foregroundStyle(Color(red: 0.20, green: 0.85, blue: 0.58))
                        }
                    }
                    if del > 0 {
                        if isPixel {
                            PixelText(text: "-\(del)", color: Pixel16Palette.red, pixelSize: 1.0)
                        } else {
                            Text("-\(del)")
                                .font(statFont)
                                .monospacedDigit()
                                .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42))
                        }
                    }
                }
                .fixedSize()
            } else {
                if isPixel {
                    PixelText(text: "\(modified)M", color: Pixel16Palette.amber, pixelSize: 1.0)
                        .fixedSize()
                } else {
                    Text("\(modified)M")
                        .font(statFont)
                        .monospacedDigit()
                        .foregroundStyle(secondaryAutoColor)
                        .fixedSize()
                }
            }
        case .ahead(let ahead):
            HStack(spacing: isPixel ? 2 : 1) {
                if isPixel {
                    WorkspacePixelIcon(glyph: .push, color: Pixel16Palette.cyan, pixelSize: 1.05)
                    PixelText(text: "\(ahead)", color: Pixel16Palette.cyan, pixelSize: 1.0)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(ahead)")
                        .font(statFont)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(isPixel ? Pixel16Palette.cyan : primaryAutoColor)
            .fixedSize()
        case .clean:
            let behind = max(0, workspaceManager.behindCount)
            if behind > 0 {
                HStack(spacing: isPixel ? 2 : 1) {
                    if isPixel {
                        WorkspacePixelIcon(glyph: .sync, color: Pixel16Palette.amber, pixelSize: 1.05)
                        PixelText(text: "\(behind)", color: Pixel16Palette.amber, pixelSize: 1.0)
                    } else {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 8, weight: .bold))
                        Text("\(behind)")
                            .font(statFont)
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(isPixel ? Pixel16Palette.amber : secondaryAutoColor)
                .fixedSize()
            } else {
                if isPixel {
                    PixelText(text: "SYNC", color: Pixel16Palette.cyan, pixelSize: 1.0)
                        .fixedSize()
                } else {
                    Text("SYNC")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(cleanColor)
                        .fixedSize()
                }
            }
        case .nonRepo:
            EmptyView()
        }
    }

    @ViewBuilder
    private func unpushedToken(ahead: Int, fontSize: CGFloat) -> some View {
        let color = isPixel ? Pixel16Palette.cyan : primaryAutoColor
        HStack(spacing: isPixel ? 2 : 1) {
            if isPixel {
                WorkspacePixelIcon(glyph: .push, color: color, pixelSize: 1.2)
                PixelText(text: "\(ahead)", color: color, pixelSize: 1.4)
            } else {
                Image(systemName: "arrow.up")
                    .font(.system(size: 8.5, weight: .bold))
                Text("\(ahead)")
                    .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(color)
    }

    @ViewBuilder
    private func modifiedToken(count: Int, fontSize: CGFloat) -> some View {
        let color = isPixel ? Pixel16Palette.amber : secondaryAutoColor
        HStack(spacing: isPixel ? 5 : 2.5) {
            branchGlyph(color: color)
            if isPixel {
                PixelText(text: "\(count)", color: color, pixelSize: 1.4)
            } else {
                Text("\(count)")
                    .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
        }
    }

    @ViewBuilder
    private func branchGlyph(color: Color) -> some View {
        if isPixel {
            WorkspacePixelIcon(glyph: .branch, color: color, pixelSize: isWideMode ? 1.1 : 1.3)
                .fixedSize()
        } else {
            GitBranchGlyph(color: color)
                .frame(width: 10, height: 11)
                .fixedSize()
        }
    }
}

/// Crisp vector Git branch icon (trunk + curved branch + 3 commit nodes).
private struct GitBranchGlyph: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let leftX = w * 0.26
            let rightX = w * 0.76
            let topY = h * 0.20
            let bottomY = h * 0.80
            let branchY = h * 0.31
            let nodeRadius = min(w, h) * 0.165

            var paths = Path()
            paths.move(to: CGPoint(x: leftX, y: topY))
            paths.addLine(to: CGPoint(x: leftX, y: bottomY))

            paths.move(to: CGPoint(x: leftX, y: h * 0.65))
            paths.addCurve(
                to: CGPoint(x: rightX, y: branchY),
                control1: CGPoint(x: leftX, y: h * 0.44),
                control2: CGPoint(x: rightX, y: h * 0.52)
            )

            context.stroke(
                paths,
                with: .color(color),
                style: StrokeStyle(lineWidth: 1.45, lineCap: .round, lineJoin: .round)
            )

            let nodes = [
                CGPoint(x: leftX, y: topY),
                CGPoint(x: leftX, y: bottomY),
                CGPoint(x: rightX, y: branchY),
            ]
            for node in nodes {
                let rect = CGRect(
                    x: node.x - nodeRadius,
                    y: node.y - nodeRadius,
                    width: nodeRadius * 2,
                    height: nodeRadius * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
    }
}
