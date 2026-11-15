import AppKit
import SwiftUI
import XCTest
@testable import CodeIsland

final class MailArrivalWingTests: XCTestCase {
    func testRollerCoasterGeometryStartsLeftOfMailboxAndMovesMonotonicallyRight() {
        let wingWidth: CGFloat = 104.0
        let mailboxLeftEdge = wingWidth - 25.0 // 19pt mailbox + 6pt trailing padding

        let start = RollerCoasterGeometry.sample(at: 0.0, for: wingWidth, isCompact: false)
        let end = RollerCoasterGeometry.sample(at: 1.0, for: wingWidth, isCompact: false)

        // Envelope starts well to the left outside the mailbox (envelope half-width is 6.25pt)
        XCTAssertEqual(start.point.x, 10.0, accuracy: 0.001)
        XCTAssertLessThan(start.point.x + 6.25, mailboxLeftEdge - 40.0)

        // Envelope ends inside the mailbox cavity mouth
        XCTAssertEqual(end.point.x, wingWidth - 22.5, accuracy: 0.001)
        XCTAssertEqual(end.point.y, 14.0, accuracy: 0.001)
        XCTAssertEqual(end.angle, 0.0, accuracy: 0.001)

        // Strictly monotonic forward movement (left -> right) and vertically inside 32pt wing
        var prevX = start.point.x
        for step in 1...100 {
            let u = CGFloat(step) / 100.0
            let sample = RollerCoasterGeometry.sample(at: u, for: wingWidth, isCompact: false)
            XCTAssertGreaterThan(sample.point.x, prevX)
            XCTAssertGreaterThan(sample.point.y, 4.0)
            XCTAssertLessThan(sample.point.y, 28.0)
            prevX = sample.point.x
        }

        // Even at narrow transient widths, curve never escapes past mailbox cavity
        let narrowEnd = RollerCoasterGeometry.sample(at: 1.0, for: 48.0, isCompact: false)
        XCTAssertLessThanOrEqual(narrowEnd.point.x, 48.0 - 22.5 + 0.001)
    }

    func testTimelineHoldsEnvelopeVisiblyOnLeftBeforeFlightAndTriggersMailboxOnlyAfterEntry() {
        // 1. Wing expansion cushion: envelope hidden while wing opens
        let early = MailArrivalTimelineState.evaluate(at: 0.05)
        XCTAssertEqual(early.letterOpacity, 0.0, accuracy: 0.001)
        XCTAssertEqual(early.flightProgress, 0.0, accuracy: 0.001)
        XCTAssertEqual(early.flagAngle, -85.0, accuracy: 0.001)

        // 2. Standby phase: envelope fully visible and stationary on the left before moving
        let standbyStart = MailArrivalTimelineState.evaluate(at: 0.28)
        let standbyEnd = MailArrivalTimelineState.evaluate(at: 0.45)
        XCTAssertEqual(standbyStart.letterOpacity, 1.0, accuracy: 0.001)
        XCTAssertEqual(standbyStart.letterScale, 1.0, accuracy: 0.001)
        XCTAssertEqual(standbyStart.flightProgress, 0.0, accuracy: 0.001)
        XCTAssertEqual(standbyEnd.flightProgress, 0.0, accuracy: 0.001)
        XCTAssertEqual(standbyEnd.trailOpacity, 0.0, accuracy: 0.001)

        // 3. Mid-flight: mailbox stays completely static (no recoil, flag folded down, no badge)
        let midFlight = MailArrivalTimelineState.evaluate(at: 0.95)
        XCTAssertGreaterThan(midFlight.flightProgress, 0.3)
        XCTAssertLessThan(midFlight.flightProgress, 0.7)
        XCTAssertEqual(midFlight.letterOpacity, 1.0, accuracy: 0.001)
        XCTAssertGreaterThan(midFlight.trailOpacity, 0.5)
        XCTAssertEqual(midFlight.recoilScale, 1.0, accuracy: 0.001)
        XCTAssertEqual(midFlight.flagAngle, -85.0, accuracy: 0.001)
        XCTAssertEqual(midFlight.badgeProgress, 0.0, accuracy: 0.001)

        // 4. Entry complete: envelope tucked completely inside before mailbox reacts
        let atEntry = MailArrivalTimelineState.evaluate(at: MailArrivalTimelineState.flightEnd)
        XCTAssertEqual(atEntry.flightProgress, 1.0, accuracy: 0.001)
        XCTAssertEqual(atEntry.letterScale, 0.0, accuracy: 0.001)
        XCTAssertEqual(atEntry.letterOpacity, 0.0, accuracy: 0.001)
        XCTAssertEqual(atEntry.flagAngle, -85.0, accuracy: 0.001)
        XCTAssertEqual(atEntry.badgeProgress, 0.0, accuracy: 0.001)

        // 5. Post-entry reaction: recoil -> flag raised upright (0 deg) -> +1 badge popped
        let duringRecoil = MailArrivalTimelineState.evaluate(at: 1.50)
        XCTAssertGreaterThan(duringRecoil.recoilScale, 1.0)

        let settled = MailArrivalTimelineState.evaluate(at: 2.00)
        XCTAssertEqual(settled.recoilScale, 1.0, accuracy: 0.001)
        XCTAssertEqual(settled.flagAngle, 0.0, accuracy: 0.001)
        XCTAssertEqual(settled.badgeProgress, 1.0, accuracy: 0.001)
    }

    func testCompactTimelineClosesFlapBeforeSealAndPopsBadge() {
        // 1. Entry: envelope starts slightly lower, faded out, flap fully open, no seal/badge
        let start = MailCompactTimelineState.evaluate(at: 0.0)
        XCTAssertEqual(start.opacity, 0.0, accuracy: 0.001)
        XCTAssertEqual(start.flapOpen, 1.0, accuracy: 0.001)
        XCTAssertEqual(start.sealScale, 0.0, accuracy: 0.001)
        XCTAssertEqual(start.badgeProgress, 0.0, accuracy: 0.001)

        // 2. Visible with flap mid-fold before seal stamps
        let midFold = MailCompactTimelineState.evaluate(at: 0.25)
        XCTAssertEqual(midFold.opacity, 1.0, accuracy: 0.001)
        XCTAssertLessThan(midFold.flapOpen, 0.9)
        XCTAssertGreaterThan(midFold.flapOpen, 0.1)
        XCTAssertEqual(midFold.sealScale, 0.0, accuracy: 0.001)
        XCTAssertEqual(midFold.badgeProgress, 0.0, accuracy: 0.001)

        // 3. Flap closed (0.36s), seal actively stamping, badge still hidden before 0.46s
        let sealed = MailCompactTimelineState.evaluate(at: 0.46)
        XCTAssertEqual(sealed.flapOpen, 0.0, accuracy: 0.001)
        XCTAssertEqual(sealed.sealScale, 1.0, accuracy: 0.001)
        XCTAssertEqual(sealed.badgeProgress, 0.0, accuracy: 0.001)

        // 4. Settled (0.64s+): flap shut, wax seal stamped, +1 badge popped at top-right
        let settled = MailCompactTimelineState.evaluate(at: 0.70)
        XCTAssertEqual(settled.flapOpen, 0.0, accuracy: 0.001)
        XCTAssertEqual(settled.sealScale, 1.0, accuracy: 0.001)
        XCTAssertEqual(settled.badgeProgress, 1.0, accuracy: 0.001)
        XCTAssertEqual(settled.tiltDegrees, 0.0, accuracy: 0.001)
        XCTAssertEqual(settled.scale, 1.0, accuracy: 0.001)
    }

    @MainActor
    func testMailArrivalWingDoesNotCollapseUnderFixedSizeParent() {
        _ = NSApplication.shared
        let view = MailArrivalWingView(isRetro: false, isCompact: false)
            .fixedSize(horizontal: true, vertical: false)
        let hosting = NSHostingView(rootView: view)
        let fitting = hosting.fittingSize
        XCTAssertGreaterThanOrEqual(fitting.width, 96.0)
        XCTAssertEqual(fitting.height, 32.0, accuracy: 0.5)

        let compactView = MailArrivalWingView(isRetro: false, isCompact: true)
            .fixedSize(horizontal: true, vertical: false)
        let compactHosting = NSHostingView(rootView: compactView)
        let compactFitting = compactHosting.fittingSize
        XCTAssertGreaterThanOrEqual(compactFitting.width, 32.0)
        XCTAssertLessThanOrEqual(compactFitting.width, 44.0)
        XCTAssertEqual(compactFitting.height, 32.0, accuracy: 0.5)
    }

    @MainActor
    func testArrivalBaselineHandlesZeroUnreadInboxAndNewMessages() {
        let mail100 = MailItem(
            id: 100,
            senderRaw: "Alice <alice@example.com>",
            senderName: "Alice",
            senderEmail: "alice@example.com",
            subject: "First",
            dateReceived: "just now",
            isRead: false
        )
        let mail200 = MailItem(
            id: 200,
            senderRaw: "Bob <bob@example.com>",
            senderName: "Bob",
            senderEmail: "bob@example.com",
            subject: "Second",
            dateReceived: "just now",
            isRead: false
        )

        // Launch with 0 unread: establishes baseline without triggering
        let emptyInit = MailManager.evaluateArrival(topItem: nil, hasCompletedBaseline: false, knownLatestId: nil)
        XCTAssertFalse(emptyInit.shouldTrigger)
        XCTAssertNil(emptyInit.nextKnownLatestId)
        XCTAssertTrue(emptyInit.nextHasBaseline)

        // First email arrives after empty baseline: MUST trigger
        let firstArrival = MailManager.evaluateArrival(
            topItem: mail100,
            hasCompletedBaseline: emptyInit.nextHasBaseline,
            knownLatestId: emptyInit.nextKnownLatestId
        )
        XCTAssertTrue(firstArrival.shouldTrigger)
        XCTAssertEqual(firstArrival.nextKnownLatestId, 100)

        // Polling again with same top email: must not re-trigger
        let samePoll = MailManager.evaluateArrival(
            topItem: mail100,
            hasCompletedBaseline: firstArrival.nextHasBaseline,
            knownLatestId: firstArrival.nextKnownLatestId
        )
        XCTAssertFalse(samePoll.shouldTrigger)

        // Newer email arrives: MUST trigger
        let secondArrival = MailManager.evaluateArrival(
            topItem: mail200,
            hasCompletedBaseline: samePoll.nextHasBaseline,
            knownLatestId: samePoll.nextKnownLatestId
        )
        XCTAssertTrue(secondArrival.shouldTrigger)
        XCTAssertEqual(secondArrival.nextKnownLatestId, 200)

        // Reading mail 200 reveals older mail 100: must not re-trigger
        let olderRevealed = MailManager.evaluateArrival(
            topItem: mail100,
            hasCompletedBaseline: secondArrival.nextHasBaseline,
            knownLatestId: secondArrival.nextKnownLatestId
        )
        XCTAssertFalse(olderRevealed.shouldTrigger)
        XCTAssertEqual(olderRevealed.nextKnownLatestId, 200)
    }

    func testUnreadCountJumpAndDockBadgeParsing() {
        // Initial unread baseline does not trigger animation on startup
        let initial = MailManager.evaluateUnreadCountJump(newCount: 14471, baselineUnreadCount: nil)
        XCTAssertFalse(initial.shouldTrigger)
        XCTAssertEqual(initial.nextBaseline, 14471)

        // Same unread count does not trigger
        let unchanged = MailManager.evaluateUnreadCountJump(newCount: 14471, baselineUnreadCount: initial.nextBaseline)
        XCTAssertFalse(unchanged.shouldTrigger)
        XCTAssertEqual(unchanged.nextBaseline, 14471)

        // Upward jump immediately triggers arrival animation
        let arrived = MailManager.evaluateUnreadCountJump(newCount: 14472, baselineUnreadCount: unchanged.nextBaseline)
        XCTAssertTrue(arrived.shouldTrigger)
        XCTAssertEqual(arrived.nextBaseline, 14472)

        // Decreasing unread count updates baseline without triggering arrival
        let cleared = MailManager.evaluateUnreadCountJump(newCount: 14470, baselineUnreadCount: arrived.nextBaseline)
        XCTAssertFalse(cleared.shouldTrigger)
        XCTAssertEqual(cleared.nextBaseline, 14470)

        // Localized Dock AXStatusLabel badge strings parse cleanly
        XCTAssertEqual(MailManager.parseDockBadgeCount("14,472"), 14472)
        XCTAssertEqual(MailManager.parseDockBadgeCount("14.472"), 14472)
        XCTAssertEqual(MailManager.parseDockBadgeCount("3"), 3)
        XCTAssertNil(MailManager.parseDockBadgeCount(""))
        XCTAssertNil(MailManager.parseDockBadgeCount(nil))
    }

    func testThemeContrastingForegroundAndEnvelopeStroke() {
        // Light backgrounds (white, light gray, silver, cyan, amber) require dark foreground ink
        let lightGray = Color(red: 0.75, green: 0.75, blue: 0.75)
        let silverAlbum = Color(red: 0.90, green: 0.92, blue: 0.95)
        let cyan = Color(red: 0.0, green: 0.96, blue: 0.83)
        let amber = Color(red: 1.0, green: 0.72, blue: 0.20)

        for bg in [Color.white, lightGray, silverAlbum, cyan, amber] {
            XCTAssertTrue(AppColorTheme.isLightColor(bg))
            let fg = AppColorTheme.contrastingForeground(on: bg)
            XCTAssertLessThan(AppColorTheme.relativeLuminance(of: fg), 0.05)
        }

        // Darker/saturated backgrounds (pink, royal blue, dark slate) keep crisp white foreground
        let pink = Color(red: 1.0, green: 0.16, blue: 0.53)
        let royalBlue = Color(red: 0.15, green: 0.35, blue: 0.90)
        let darkGray = Color(red: 0.22, green: 0.22, blue: 0.26)

        for bg in [pink, royalBlue, darkGray] {
            XCTAssertFalse(AppColorTheme.isLightColor(bg))
            let fg = AppColorTheme.contrastingForeground(on: bg)
            XCTAssertGreaterThan(AppColorTheme.relativeLuminance(of: fg), 0.95)
        }

        // Envelope strokes/seals on white paper darken sufficiently for white and light-gray themes
        XCTAssertLessThan(AppColorTheme.relativeLuminance(of: AppColorTheme.envelopeAccentStroke(for: .white)), 0.15)
        XCTAssertLessThan(AppColorTheme.relativeLuminance(of: AppColorTheme.envelopeAccentStroke(for: silverAlbum)), 0.15)
        XCTAssertLessThan(AppColorTheme.relativeLuminance(of: AppColorTheme.envelopeAccentStroke(for: lightGray)), 0.40)
    }
}
