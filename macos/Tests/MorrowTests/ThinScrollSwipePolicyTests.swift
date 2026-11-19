import XCTest
@testable import Morrow

final class ThinScrollSwipePolicyTests: XCTestCase {
    func testHorizontalSwipeForwardsAndResetsOnEnd() {
        let start = ThinScrollSwipePolicy.decision(
            deltaX: -12,
            deltaY: 1,
            isForwardingHorizontal: false,
            isPhaseBegin: true,
            isPhaseEnd: false
        )
        XCTAssertTrue(start.forward)
        XCTAssertTrue(start.nextForwardingState)

        // Tail/end event often has zero deltas; it must still forward so NotchNavigationManager resets.
        let end = ThinScrollSwipePolicy.decision(
            deltaX: 0,
            deltaY: 0,
            isForwardingHorizontal: start.nextForwardingState,
            isPhaseBegin: false,
            isPhaseEnd: true
        )
        XCTAssertTrue(end.forward)
        XCTAssertFalse(end.nextForwardingState)
    }

    func testVerticalScrollStaysInScrollView() {
        let vertical = ThinScrollSwipePolicy.decision(
            deltaX: 1,
            deltaY: -18,
            isForwardingHorizontal: false,
            isPhaseBegin: false,
            isPhaseEnd: false
        )
        XCTAssertFalse(vertical.forward)
        XCTAssertFalse(vertical.nextForwardingState)
    }

    func testNewBeginResetsPriorForwardingState() {
        let verticalBegin = ThinScrollSwipePolicy.decision(
            deltaX: 0,
            deltaY: -8,
            isForwardingHorizontal: true,
            isPhaseBegin: true,
            isPhaseEnd: false
        )
        XCTAssertFalse(verticalBegin.forward)
        XCTAssertFalse(verticalBegin.nextForwardingState)
    }
}
