import Foundation

/// Visual presentation mode for the top island surface.
public enum IslandDisplayMode: String, CaseIterable, Identifiable, Sendable {
    /// Docked top-edge notch shell with concave upper ears.
    case notch = "notch"
    /// Detached floating pill with continuous rounded corners.
    case dynamicIsland = "dynamicIsland"

    public var id: String { rawValue }

    /// Safely resolves a stored defaults value, falling back to `.notch` on unknown input.
    public static func resolved(from rawValue: String?) -> IslandDisplayMode {
        guard let rawValue, let mode = IslandDisplayMode(rawValue: rawValue) else {
            return .notch
        }
        return mode
    }
}

/// Shared bounds for the collapsed-width scale setting — keeps the settings
/// slider and width math in lockstep across app targets.
public enum NotchWidthScale {
    public static let min = 0
    public static let max = 200
    public static let step = 1

    public static func clamp(_ scalePercent: Int) -> Int {
        Swift.max(min, Swift.min(scalePercent, max))
    }
}

/// Platform-agnostic geometry calculations shared by display-mode rendering and window positioning.
public enum IslandDisplayMetrics {
    public static let floatingPillTopGap: Double = 10.0
    private static let dynamicIslandCenterBaseGap: Double = 16.0

    private static func scaleFactor(for scalePercent: Int) -> Double {
        Double(NotchWidthScale.clamp(scalePercent)) / 100.0
    }

    /// Vertical distance below the top screen edge where the panel sits.
    public static func floatingYOffset(displayMode: IslandDisplayMode, isFullscreenMode: Bool) -> Double {
        (displayMode == .dynamicIsland || isFullscreenMode) ? floatingPillTopGap : 0.0
    }

    /// Center cutout / gap width reserved between left and right collapsed wings.
    public static func centerGapWidth(
        notchWidth: Double,
        scalePercent: Int,
        hasNotch: Bool,
        displayMode: IslandDisplayMode = .notch
    ) -> Double {
        let factor = scaleFactor(for: scalePercent)
        if displayMode == .dynamicIsland && !hasNotch {
            // Non-notch displays (e.g. external screens, non-notch Macs, Windows) need no 185pt camera block.
            return min(40.0, max(8.0, dynamicIslandCenterBaseGap * factor))
        }
        let scaled = notchWidth * factor
        return hasNotch ? max(notchWidth, scaled) : scaled
    }

    /// Width of the empty resting island shell when no sessions or status wings are shown.
    public static func restingWidth(
        notchWidth: Double,
        scalePercent: Int,
        hasNotch: Bool,
        displayMode: IslandDisplayMode
    ) -> Double {
        if displayMode == .dynamicIsland && !hasNotch {
            let factor = scaleFactor(for: scalePercent)
            if factor <= 1.0 {
                return 92.0 + (110.0 - 92.0) * factor
            }
            return 110.0 + (136.0 - 110.0) * (factor - 1.0)
        }
        return centerGapWidth(
            notchWidth: notchWidth,
            scalePercent: scalePercent,
            hasNotch: hasNotch,
            displayMode: displayMode
        )
    }

    /// Continuous corner radius used in Dynamic Island mode for each visual state.
    public static func pillCornerRadius(height: Double, isExpanded: Bool, isExtendedPill: Bool) -> Double {
        if isExpanded {
            return isExtendedPill ? 18.0 : 24.0
        }
        if isExtendedPill {
            return 18.0
        }
        return max(12.0, height / 2.0)
    }

    /// Outer horizontal padding keeping wing icons clear of the panel silhouette edge.
    public static func outerPadding(
        wingWidth: Double,
        expanded: Bool,
        bilateral: Bool,
        displayMode: IslandDisplayMode
    ) -> Double {
        if expanded || bilateral { return 12.0 }
        if displayMode == .dynamicIsland { return 10.0 }
        if wingWidth < 48.0 { return 6.0 }
        if wingWidth < 70.0 { return 8.0 }
        return 10.0
    }
}
