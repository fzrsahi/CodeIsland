import XCTest
@testable import Morrow

final class CompactGitWingLayoutTests: XCTestCase {
    func testGitDisplayStateCoversAllCombinations() {
        XCTAssertEqual(CompactGitStatusModel.state(isGitRepo: false, aheadCount: 3, changedCount: 5), .nonRepo)
        XCTAssertEqual(CompactGitStatusModel.state(isGitRepo: true, aheadCount: 0, changedCount: 0), .clean)
        XCTAssertEqual(CompactGitStatusModel.state(isGitRepo: true, aheadCount: 0, changedCount: 3), .modified(3))
        XCTAssertEqual(CompactGitStatusModel.state(isGitRepo: true, aheadCount: 2, changedCount: 0), .ahead(2))
        XCTAssertEqual(
            CompactGitStatusModel.state(isGitRepo: true, aheadCount: 2, changedCount: 4),
            .modified(4)
        )
        XCTAssertEqual(CompactGitStatusModel.state(isGitRepo: true, aheadCount: -1, changedCount: -2), .clean)
    }

    func testEstimatedBaselineWidthStaysCompact() {
        let clean = CompactGitStatusModel.estimatedBaselineWidth(isGitRepo: true, aheadCount: 0, changedCount: 0)
        let mod = CompactGitStatusModel.estimatedBaselineWidth(isGitRepo: true, aheadCount: 0, changedCount: 3)
        let ahead = CompactGitStatusModel.estimatedBaselineWidth(isGitRepo: true, aheadCount: 2, changedCount: 0)
        let both = CompactGitStatusModel.estimatedBaselineWidth(isGitRepo: true, aheadCount: 2, changedCount: 3)

        XCTAssertLessThanOrEqual(clean, 48)
        XCTAssertEqual(both, mod)
        XCTAssertLessThanOrEqual(ahead, 48)
    }

    func testCenterShiftLocksHardwareNotchAtZero() {
        let left: CGFloat = 44
        let right: CGFloat = 68
        let shift = CompactNotchWingGeometry.centerShift(
            leftWidth: left,
            rightWidth: right,
            hasNotch: true,
            asymmetricEnabled: true
        )
        XCTAssertEqual(shift, 12, accuracy: 0.001)

        // Centered window has barLeft = -(left + notch + right)/2 + shift = -(left + notch/2)
        // and notch center = barLeft + left + notch/2 = 0.
        let notch: CGFloat = 185
        let totalWidth = left + notch + right
        let notchCenter = (-totalWidth / 2 + shift) + left + (notch / 2)
        XCTAssertEqual(notchCenter, 0, accuracy: 0.001)

        XCTAssertEqual(
            CompactNotchWingGeometry.centerShift(leftWidth: left, rightWidth: right, hasNotch: false, asymmetricEnabled: true),
            0
        )
        XCTAssertEqual(
            CompactNotchWingGeometry.centerShift(leftWidth: left, rightWidth: right, hasNotch: true, asymmetricEnabled: false),
            0
        )
    }

    func testStrictSymmetricWingWidthsAcrossIdleThinkingAndHUD() {
        let states: [(name: String, leftNatural: CGFloat, rightNatural: CGFloat)] = [
            ("idle", 42, 68),
            ("thinking", 132, 64),
            ("hud", 250, 250),
        ]

        for state in states {
            let symmetricWidth = CompactNotchWingGeometry.strictSymmetricWingWidth(
                leftWidth: state.leftNatural,
                rightWidth: state.rightNatural
            )
            XCTAssertEqual(
                symmetricWidth,
                max(state.leftNatural, state.rightNatural),
                "Expected strict symmetric wing width for \(state.name)"
            )
            XCTAssertEqual(
                CompactNotchWingGeometry.centerShift(
                    leftWidth: symmetricWidth,
                    rightWidth: symmetricWidth,
                    hasNotch: true,
                    asymmetricEnabled: false
                ),
                0,
                "Expected zero horizontal shift for symmetric \(state.name) state"
            )
        }
    }
}
