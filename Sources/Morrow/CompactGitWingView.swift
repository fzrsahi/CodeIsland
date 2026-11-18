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
        CompactGitStatusModel.state(
            isGitRepo: workspaceManager.isGitRepo,
            aheadCount: workspaceManager.aheadCount,
            changedCount: workspaceManager.changedFiles.count
        )
    }

    var body: some View {
        let fontSize: CGFloat = isDynamicIslandCompact ? 11 : 10.5

        HStack(spacing: 7) {
            switch displayState {
            case .modified(let modified):
                modifiedToken(count: modified, fontSize: fontSize)
            case .ahead(let ahead):
                HStack(spacing: 4) {
                    unpushedToken(ahead: ahead, fontSize: fontSize)
                    branchGlyph(color: primaryAutoColor)
                }
            case .clean:
                HStack(spacing: 3) {
                    branchGlyph(color: cleanColor)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(cleanColor)
                }
            case .nonRepo:
                Image(systemName: "folder")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
        .fixedSize()
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
    private func unpushedToken(ahead: Int, fontSize: CGFloat) -> some View {
        HStack(spacing: 1) {
            Image(systemName: "arrow.up")
                .font(.system(size: 8.5, weight: .bold))
            Text("\(ahead)")
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .monospacedDigit()
        }
        .foregroundStyle(primaryAutoColor)
    }

    @ViewBuilder
    private func modifiedToken(count: Int, fontSize: CGFloat) -> some View {
        HStack(spacing: 2.5) {
            branchGlyph(color: secondaryAutoColor)
            Text("\(count)")
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(secondaryAutoColor)
        }
    }

    @ViewBuilder
    private func branchGlyph(color: Color) -> some View {
        GitBranchGlyph(color: color)
            .frame(width: 10, height: 11)
            .fixedSize()
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
