import XCTest
import SwiftUI
import AppKit
@testable import CodeIsland
import CodeIslandCore

/// Opt-in offscreen renderer for Notch Hoops Arena screenshots & animation frames.
/// Skipped unless `NOTCH_HOOPS_GALLERY_DIR` is set in the environment.
@MainActor
final class NotchHoopsGalleryTests: XCTestCase {

    func testRenderArenaScreenshotsAndFrames() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let outDir = env["NOTCH_HOOPS_GALLERY_DIR"] else {
            throw XCTSkip("NOTCH_HOOPS_GALLERY_DIR not set — gallery render is opt-in")
        }

        _ = NSApplication.shared
        let fm = FileManager.default
        let framesDir = "\(outDir)/frames"
        try fm.createDirectory(atPath: framesDir, withIntermediateDirectories: true)

        let state = AppState()
        state.surface = .sessionList
        state.expandedTab = .game
        state.activeTabLabel = .game
        state.isTabTransitioning = false

        let size = CGSize(width: 720, height: 306)

        // 1. Render static screenshot of the Arena design
        let initialEngine = NotchHoopsEngine(highScore: 12, positionMode: .random, initialLaunchX: 85)
        let staticView = arenaContainer(state: state, engine: initialEngine, drag: nil)
            .frame(width: size.width, height: size.height)
        let staticCG = try OffscreenRender.hosted(staticView, size: size, appearance: .darkAqua)
        try OffscreenRender.writePNG(staticCG, to: "\(outDir)/arena-ready.png")

        let settingsView = SettingsView(appState: state, initialPage: .game)
        let settingsCG = try OffscreenRender.hosted(
            settingsView,
            size: CGSize(width: 660, height: 540),
            appearance: .darkAqua,
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            passes: 5
        )
        try OffscreenRender.writePNG(settingsCG, to: "\(outDir)/settings-game.png")

        // 2. Render 30fps video frames across 3PT -> 2PT -> 1PT random turns!
        let turns: [(mode: NotchHoopsEngine.PositionMode, launchX: Double)] = [
            (.threePoint, 85),
            (.twoPoint, 160),
            (.onePoint, 225),
        ]

        var frameIndex = 0
        for turn in turns {
            var engine = NotchHoopsEngine(highScore: 12, positionMode: turn.mode, initialLaunchX: turn.launchX)
            let swipe = findScoringSwipe(launchX: turn.launchX)

            // 8 frames of aiming trajectory
            for step in 1...8 {
                let frac = Double(step) / 8.0
                let drag = CGSize(width: swipe.dx * frac, height: swipe.dy * frac)
                let view = arenaContainer(state: state, engine: engine, drag: drag)
                    .frame(width: size.width, height: size.height)
                let cg = try OffscreenRender.hosted(view, size: size, appearance: .darkAqua)
                try OffscreenRender.writePNG(cg, to: String(format: "%@/frame-%04d.png", framesDir, frameIndex))
                frameIndex += 1
            }

            _ = engine.launch(dragDeltaX: swipe.dx, dragDeltaY: swipe.dy)
            for _ in 0..<65 {
                engine.step(dt: 1.0 / 60.0)
                engine.step(dt: 1.0 / 60.0)
                let view = arenaContainer(state: state, engine: engine, drag: nil)
                    .frame(width: size.width, height: size.height)
                let cg = try OffscreenRender.hosted(view, size: size, appearance: .darkAqua)
                try OffscreenRender.writePNG(cg, to: String(format: "%@/frame-%04d.png", framesDir, frameIndex))
                frameIndex += 1
                if !engine.needsTick { break }
            }

            for _ in 0..<5 {
                let view = arenaContainer(state: state, engine: engine, drag: nil)
                    .frame(width: size.width, height: size.height)
                let cg = try OffscreenRender.hosted(view, size: size, appearance: .darkAqua)
                try OffscreenRender.writePNG(cg, to: String(format: "%@/frame-%04d.png", framesDir, frameIndex))
                frameIndex += 1
            }
        }
    }

    private func arenaContainer(
        state: AppState,
        engine: NotchHoopsEngine,
        drag: CGSize?
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    PixelIcon(glyph: .agents, color: .white.opacity(0.5), pixelSize: 1.3)
                    PixelIcon(glyph: .workspace, color: .white.opacity(0.5), pixelSize: 1.3)
                    PixelIcon(glyph: .music, color: .white.opacity(0.5), pixelSize: 1.3)
                    HStack(spacing: 4) {
                        PixelIcon(glyph: .game, color: Color(red: 0.30, green: 0.94, blue: 0.90), pixelSize: 1.35)
                        PixelText(text: "GAME", color: Color(red: 0.30, green: 0.94, blue: 0.90), pixelSize: 1.15)
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 18)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.30, green: 0.94, blue: 0.90).opacity(0.18)))
                }
                Spacer()
                HStack(spacing: 8) {
                    PixelIcon(glyph: .volume, color: .white.opacity(0.6), pixelSize: 1.3)
                    PixelIcon(glyph: .settings, color: .white.opacity(0.6), pixelSize: 1.3)
                    PixelIcon(glyph: .power, color: Color(red: 1.0, green: 0.35, blue: 0.35), pixelSize: 1.3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)

            NotchHoopsView(
                appState: state,
                initialEngine: engine,
                initialDrag: drag
            )
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func findScoringSwipe(launchX: Double) -> (dx: Double, dy: Double) {
        for dragX in stride(from: 20.0, through: 200.0, by: 5.0) {
            for dragY in stride(from: -50.0, through: -170.0, by: -5.0) {
                var candidate = NotchHoopsEngine(highScore: 0, positionMode: .random, initialLaunchX: launchX)
                if candidate.launch(dragDeltaX: dragX, dragDeltaY: dragY) {
                    for _ in 0..<300 {
                        candidate.step(dt: 1.0 / 60.0)
                        if candidate.score > 0 { return (dragX, dragY) }
                        if candidate.phase != .flying { break }
                    }
                }
            }
        }
        return (90, -110)
    }

    func testCourtGestureOverlayDeliversUpwardSwipeDelta() throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 250),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let view = CourtGestureOverlay.DragTrackingNSView(frame: NSRect(x: 0, y: 0, width: 400, height: 250))
        view.isEnabled = true
        window.contentView = view

        var changedDeltas: [CGSize] = []
        var endedDelta: CGSize?
        view.onDragChanged = { changedDeltas.append($0) }
        view.onDragEnded = { endedDelta = $0 }

        XCTAssertTrue(view.isFlipped)
        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
        XCTAssertIdentical(view.hitTest(NSPoint(x: 100, y: 200)), view)

        // Start at bottom-left in view coords (y=200 in flipped), drag up-right (y=110 in flipped -> dy = -90)
        // In window coords (unflipped), flipped y=200 is window y=50, flipped y=110 is window y=140.
        let downEvent = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 100, y: 50),
            modifierFlags: [],
            timestamp: 1.0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1.0
        ))
        let dragEvent = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: NSPoint(x: 190, y: 140),
            modifierFlags: [],
            timestamp: 1.1,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 1.0
        ))
        let upEvent = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: NSPoint(x: 190, y: 140),
            modifierFlags: [],
            timestamp: 1.2,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 3,
            clickCount: 1,
            pressure: 0.0
        ))

        view.mouseDown(with: downEvent)
        view.mouseDragged(with: dragEvent)
        view.mouseUp(with: upEvent)

        XCTAssertEqual(changedDeltas.count, 1)
        XCTAssertEqual(Double(changedDeltas[0].width), 90, accuracy: 0.5)
        XCTAssertEqual(Double(changedDeltas[0].height), -90, accuracy: 0.5)
        XCTAssertEqual(Double(endedDelta?.width ?? 0), 90, accuracy: 0.5)
        XCTAssertEqual(Double(endedDelta?.height ?? 0), -90, accuracy: 0.5)

        // Disabled overlay should not intercept hit testing
        view.isEnabled = false
        XCTAssertNil(view.hitTest(NSPoint(x: 100, y: 200)))
    }
}
