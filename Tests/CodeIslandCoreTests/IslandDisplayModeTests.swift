import XCTest
@testable import CodeIslandCore

final class IslandDisplayModeTests: XCTestCase {

    func testNotchWidthScaleBoundsAndClamping() {
        XCTAssertEqual(NotchWidthScale.min, 0)
        XCTAssertEqual(NotchWidthScale.max, 200)
        XCTAssertEqual(NotchWidthScale.step, 1)
        XCTAssertEqual(NotchWidthScale.clamp(-25), 0)
        XCTAssertEqual(NotchWidthScale.clamp(100), 100)
        XCTAssertEqual(NotchWidthScale.clamp(350), 200)
    }

    func testDisplayModeRawValuesAndSafeResolution() {
        XCTAssertEqual(IslandDisplayMode.allCases, [.notch, .dynamicIsland])
        XCTAssertEqual(IslandDisplayMode.notch.rawValue, "notch")
        XCTAssertEqual(IslandDisplayMode.dynamicIsland.rawValue, "dynamicIsland")
        XCTAssertEqual(IslandDisplayMode.resolved(from: "dynamicIsland"), .dynamicIsland)
        XCTAssertEqual(IslandDisplayMode.resolved(from: "notch"), .notch)
        XCTAssertEqual(IslandDisplayMode.resolved(from: "invalid"), .notch)
        XCTAssertEqual(IslandDisplayMode.resolved(from: nil), .notch)
    }

    func testFloatingYOffsetDetachesInDynamicIslandOrFullscreen() {
        XCTAssertEqual(IslandDisplayMetrics.floatingYOffset(displayMode: .notch, isFullscreenMode: false), 0)
        XCTAssertEqual(IslandDisplayMetrics.floatingYOffset(displayMode: .notch, isFullscreenMode: true), 10)
        XCTAssertEqual(IslandDisplayMetrics.floatingYOffset(displayMode: .dynamicIsland, isFullscreenMode: false), 10)
        XCTAssertEqual(IslandDisplayMetrics.floatingYOffset(displayMode: .dynamicIsland, isFullscreenMode: true), 10)
    }

    func testCenterGapCollapsesDeadSpaceInDynamicIslandOnNonNotchScreens() {
        // Notch mode preserves simulated notch scaling
        XCTAssertEqual(
            IslandDisplayMetrics.centerGapWidth(notchWidth: 185, scalePercent: 100, hasNotch: false, displayMode: .notch),
            185
        )
        XCTAssertEqual(
            IslandDisplayMetrics.centerGapWidth(notchWidth: 200, scalePercent: 50, hasNotch: false, displayMode: .notch),
            100
        )

        // Dynamic Island on non-notch display (MacBook Air / external monitor / Windows) removes 185pt void
        XCTAssertEqual(
            IslandDisplayMetrics.centerGapWidth(notchWidth: 185, scalePercent: 100, hasNotch: false, displayMode: .dynamicIsland),
            16
        )
        XCTAssertEqual(
            IslandDisplayMetrics.centerGapWidth(notchWidth: 185, scalePercent: -10, hasNotch: false, displayMode: .dynamicIsland),
            8
        )
        XCTAssertEqual(
            IslandDisplayMetrics.centerGapWidth(notchWidth: 185, scalePercent: 300, hasNotch: false, displayMode: .dynamicIsland),
            32
        )
    }

    func testCenterGapPreservesPhysicalNotchClearanceWhenHardwareNotchPresent() {
        XCTAssertEqual(
            IslandDisplayMetrics.centerGapWidth(notchWidth: 185, scalePercent: 80, hasNotch: true, displayMode: .dynamicIsland),
            185
        )
        XCTAssertEqual(
            IslandDisplayMetrics.centerGapWidth(notchWidth: 185, scalePercent: 150, hasNotch: true, displayMode: .dynamicIsland),
            277.5
        )
    }

    func testRestingWidthFormsBalancedPillWhenNonNotchDynamicIslandIdle() {
        XCTAssertEqual(
            IslandDisplayMetrics.restingWidth(notchWidth: 185, scalePercent: 100, hasNotch: false, displayMode: .dynamicIsland),
            110
        )
        XCTAssertEqual(
            IslandDisplayMetrics.restingWidth(notchWidth: 185, scalePercent: 0, hasNotch: false, displayMode: .dynamicIsland),
            92
        )
        XCTAssertEqual(
            IslandDisplayMetrics.restingWidth(notchWidth: 185, scalePercent: 200, hasNotch: false, displayMode: .dynamicIsland),
            136
        )
        // Notched display still spans physical notch; notch mode matches centerGapWidth
        XCTAssertEqual(
            IslandDisplayMetrics.restingWidth(notchWidth: 185, scalePercent: 100, hasNotch: true, displayMode: .dynamicIsland),
            185
        )
        XCTAssertEqual(
            IslandDisplayMetrics.restingWidth(notchWidth: 185, scalePercent: 100, hasNotch: false, displayMode: .notch),
            185
        )
    }

    func testDynamicIslandPillCornerRadiiMatchCollapsedExtendedAndExpandedStates() {
        XCTAssertEqual(IslandDisplayMetrics.pillCornerRadius(height: 32, isExpanded: false, isExtendedPill: false), 16)
        XCTAssertEqual(IslandDisplayMetrics.pillCornerRadius(height: 18, isExpanded: false, isExtendedPill: false), 12)
        XCTAssertEqual(IslandDisplayMetrics.pillCornerRadius(height: 44, isExpanded: false, isExtendedPill: false), 22)
        XCTAssertEqual(IslandDisplayMetrics.pillCornerRadius(height: 58, isExpanded: false, isExtendedPill: true), 18)
        XCTAssertEqual(IslandDisplayMetrics.pillCornerRadius(height: 320, isExpanded: true, isExtendedPill: false), 24)
        XCTAssertEqual(IslandDisplayMetrics.pillCornerRadius(height: 80, isExpanded: true, isExtendedPill: true), 18)
    }

    func testPillOuterPaddingProtectsRoundedCapsInDynamicIslandMode() {
        XCTAssertEqual(
            IslandDisplayMetrics.outerPadding(wingWidth: 40, expanded: false, bilateral: false, displayMode: .dynamicIsland),
            13
        )
        XCTAssertEqual(
            IslandDisplayMetrics.outerPadding(wingWidth: 40, expanded: false, bilateral: false, displayMode: .notch),
            6
        )
        XCTAssertEqual(
            IslandDisplayMetrics.outerPadding(wingWidth: 60, expanded: false, bilateral: false, displayMode: .notch),
            8
        )
        XCTAssertEqual(
            IslandDisplayMetrics.outerPadding(wingWidth: 80, expanded: true, bilateral: false, displayMode: .dynamicIsland),
            12
        )
    }

    func testBalancedTwinWidthRemovesHollowGapAndScalesCleanly() {
        let idleMusicW = IslandDisplayMetrics.balancedTwinWidth(
            leftWidth: 26,
            rightWidth: 38,
            outerPadding: 13,
            dividerGap: 11,
            hasDivider: true,
            scalePercent: 100,
            maxAllowedWidth: 400
        )
        XCTAssertEqual(idleMusicW, 113, accuracy: 0.5)

        let thinkingW = IslandDisplayMetrics.balancedTwinWidth(
            leftWidth: 86,
            rightWidth: 44,
            outerPadding: 13,
            dividerGap: 11,
            hasDivider: true,
            scalePercent: 100,
            maxAllowedWidth: 400
        )
        XCTAssertEqual(thinkingW, 179, accuracy: 0.5)
    }
}
