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
            .aheadAndModified(ahead: 2, modified: 4)
        )
        XCTAssertEqual(CompactGitStatusModel.state(isGitRepo: true, aheadCount: -1, changedCount: -2), .clean)
    }

    func testEstimatedBaselineWidthStaysCompact() {
        let clean = CompactGitStatusModel.estimatedBaselineWidth(isGitRepo: true, aheadCount: 0, changedCount: 0)
        let mod = CompactGitStatusModel.estimatedBaselineWidth(isGitRepo: true, aheadCount: 0, changedCount: 3)
        let ahead = CompactGitStatusModel.estimatedBaselineWidth(isGitRepo: true, aheadCount: 2, changedCount: 0)
        let both = CompactGitStatusModel.estimatedBaselineWidth(isGitRepo: true, aheadCount: 2, changedCount: 3)

        XCTAssertLessThanOrEqual(clean, 48)
        XCTAssertLessThan(mod, both)
        XCTAssertLessThan(ahead, both)
        XCTAssertLessThanOrEqual(both, 72)
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
}
