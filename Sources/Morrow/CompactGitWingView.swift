import SwiftUI

/// Display state for the minimal Git-only collapsed right wing (Variant A, no dot separator).
public enum CompactGitDisplayState: Equatable, Sendable {
    case nonRepo
    case clean
    case modified(Int)
    case ahead(Int)
    case aheadAndModified(ahead: Int, modified: Int)
}

public enum CompactGitStatusModel {
    /// Derives the compact right-wing Git state from repository status, unpushed commits, and modified files.
    public static func state(isGitRepo: Bool, aheadCount: Int, changedCount: Int) -> CompactGitDisplayState {
        guard isGitRepo else { return .nonRepo }
        let safeAhead = max(0, aheadCount)
        let safeChanged = max(0, changedCount)
        switch (safeAhead > 0, safeChanged > 0) {
        case (true, true):
            return .aheadAndModified(ahead: safeAhead, modified: safeChanged)
        case (false, true):
            return .modified(safeChanged)
        case (true, false):
            return .ahead(safeAhead)
        case (false, false):
            return .clean
        }
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
        case .aheadAndModified:
            return 66
        }
    }
}

public enum CompactNotchWingGeometry {
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

    @ObservedObject private var nowPlaying = NowPlayingManager.shared
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
            && nowPlaying.isPlaying
            && nowPlaying.artworkImage != nil
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
            case .aheadAndModified(let ahead, let modified):
                unpushedToken(ahead: ahead, fontSize: fontSize)
                modifiedToken(count: modified, fontSize: fontSize)
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
        Image(systemName: "arrow.triangle.branch")
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(color)
            .fixedSize()
    }
}
