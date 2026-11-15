import XCTest
import SwiftUI
import AppKit
@testable import CodeIsland
import CodeIslandCore

/// Opt-in offscreen renderer for Notch Hoops prototype variants (screenshots + animation frames).
/// Skipped unless `NOTCH_HOOPS_GALLERY_DIR` is set in the environment.
@MainActor
final class NotchHoopsGalleryTests: XCTestCase {

    func testRenderVariantScreenshotsAndFrames() async throws {
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

        let variants: [(key: String, variant: NotchHoopsVariant)] = [
            ("variant-A-crt", .crtArcade),
            ("variant-B-arena", .arenaBroadcast),
            ("variant-C-telemetry", .tacticalTelemetry),
        ]

        let size = CGSize(width: 720, height: 245)

        // 1. Render static screenshot for each variant
        for item in variants {
            let view = variantContainer(state: state, variant: item.variant, engine: NotchHoopsEngine(highScore: 12), drag: nil)
                .frame(width: size.width, height: size.height)
            let cg = try OffscreenRender.hosted(view, size: size, appearance: .darkAqua)
            try OffscreenRender.writePNG(cg, to: "\(outDir)/\(item.key).png")
        }

        // 2. Find a clean scoring swipe vector
        let scoringSwipe = findScoringSwipe()

        // 3. Render 30fps video frames across all 3 variants (aim -> launch -> swish)
        var frameIndex = 0
        for item in variants {
            var engine = NotchHoopsEngine(highScore: 12)

            // 8 frames of aiming trajectory
            for step in 1...8 {
                let frac = Double(step) / 8.0
                let drag = CGSize(width: scoringSwipe.dx * frac, height: scoringSwipe.dy * frac)
                let view = variantContainer(state: state, variant: item.variant, engine: engine, drag: drag)
                    .frame(width: size.width, height: size.height)
                let cg = try OffscreenRender.hosted(view, size: size, appearance: .darkAqua)
                try OffscreenRender.writePNG(cg, to: String(format: "%@/frame-%04d.png", framesDir, frameIndex))
                frameIndex += 1
            }

            // Launch and step at 30fps (two 1/60s physics steps per video frame)
            _ = engine.launch(dragDeltaX: scoringSwipe.dx, dragDeltaY: scoringSwipe.dy)
            for _ in 0..<48 {
                engine.step(dt: 1.0 / 60.0)
                engine.step(dt: 1.0 / 60.0)
                let view = variantContainer(state: state, variant: item.variant, engine: engine, drag: nil)
                    .frame(width: size.width, height: size.height)
                let cg = try OffscreenRender.hosted(view, size: size, appearance: .darkAqua)
                try OffscreenRender.writePNG(cg, to: String(format: "%@/frame-%04d.png", framesDir, frameIndex))
                frameIndex += 1
                if !engine.needsTick { break }
            }

            // Hold 6 frames on result
            for _ in 0..<6 {
                let view = variantContainer(state: state, variant: item.variant, engine: engine, drag: nil)
                    .frame(width: size.width, height: size.height)
                let cg = try OffscreenRender.hosted(view, size: size, appearance: .darkAqua)
                try OffscreenRender.writePNG(cg, to: String(format: "%@/frame-%04d.png", framesDir, frameIndex))
                frameIndex += 1
            }
        }
    }

    private func variantContainer(
        state: AppState,
        variant: NotchHoopsVariant,
        engine: NotchHoopsEngine,
        drag: CGSize?
    ) -> some View {
        VStack(spacing: 0) {
            // Simulated top notch header bar matching CodeIsland's dark notch chrome
            HStack {
                HStack(spacing: 6) {
                    PixelIcon(glyph: .agents, color: .white.opacity(0.5), pixelSize: 1.3)
                    PixelIcon(glyph: .workspace, color: .white.opacity(0.5), pixelSize: 1.3)
                    PixelIcon(glyph: .music, color: .white.opacity(0.5), pixelSize: 1.3)
                    HStack(spacing: 4) {
                        PixelIcon(glyph: .game, color: Color(red: 0.22, green: 0.94, blue: 0.88), pixelSize: 1.35)
                        PixelText(text: "GAME", color: Color(red: 0.22, green: 0.94, blue: 0.88), pixelSize: 1.15)
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 18)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.22, green: 0.94, blue: 0.88).opacity(0.18)))
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
                initialVariant: variant,
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

    private func findScoringSwipe() -> (dx: Double, dy: Double) {
        for dragX in stride(from: 20.0, through: 120.0, by: 5.0) {
            for dragY in stride(from: -60.0, through: -150.0, by: -5.0) {
                var candidate = NotchHoopsEngine(highScore: 0)
                if candidate.launch(dragDeltaX: dragX, dragDeltaY: dragY) {
                    for _ in 0..<300 {
                        candidate.step(dt: 1.0 / 60.0)
                        if candidate.score > 0 { return (dragX, dragY) }
                        if candidate.phase != .flying { break }
                    }
                }
            }
        }
        return (65, -105)
    }
}
