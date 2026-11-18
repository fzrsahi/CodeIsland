import AppKit
import SwiftUI
import XCTest
@testable import Morrow
import MorrowCore

@MainActor
final class DynamicIslandModeTests: XCTestCase {
    private let suiteName = "DynamicIslandModeTests"
    private var suite: UserDefaults!
    private var sandbox: DefaultsSandbox!
    private let notchW: CGFloat = 185
    private let notchHeight: CGFloat = 32
    private let screenWidth: CGFloat = 1512

    override func setUp() async throws {
        try await super.setUp()
        _ = NSApplication.shared
        sandbox = DefaultsSandbox(keys: DefaultsSandbox.panelKeys)
        suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        suite.removePersistentDomain(forName: suiteName)
        MascotAnimationGate.shared.setPanelVisible(false)
        IslandSignals.shared.setInQuietHours(false)
        IslandSignals.shared.setVolumeHUDVisible(false)
        IslandSignals.shared.setMiniPeekBanner(false)
        IslandSignals.shared.setChargingBanner(visible: false, batteryLevel: 100)
    }

    override func tearDown() async throws {
        suite.removePersistentDomain(forName: suiteName)
        sandbox?.restore()
        NowPlayingManager.shared.isPlaying = false
        NowPlayingManager.shared.title = ""
        NowPlayingManager.shared.artist = ""
        NowPlayingManager.shared.album = ""
        NowPlayingManager.shared.artworkImage = nil
        NowPlayingManager.shared.lyrics = []
        IslandSignals.shared.setMusic(isPlaying: false, showToast: false, hasTitle: false, hasLyrics: false, title: "", artist: "")
        IslandSignals.shared.setChargingBanner(visible: false, batteryLevel: 100)
        MascotAnimationGate.shared.setPanelVisible(true)
        try await super.tearDown()
    }

    func testSettingsDefaultsAndPersistenceForDisplayMode() {
        XCTAssertEqual(SettingsDefaults.islandDisplayMode, IslandDisplayMode.notch.rawValue)

        UserDefaults.standard.removeObject(forKey: SettingsKey.islandDisplayMode)
        UserDefaults.standard.removeObject(forKey: SettingsKey.dynamicIslandTopOffset)
        XCTAssertEqual(SettingsManager.shared.islandDisplayMode, .notch)
        XCTAssertEqual(SettingsManager.shared.dynamicIslandTopOffset, 10)

        SettingsManager.shared.islandDisplayMode = .dynamicIsland
        SettingsManager.shared.dynamicIslandTopOffset = 22
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: SettingsKey.islandDisplayMode),
            IslandDisplayMode.dynamicIsland.rawValue
        )
        XCTAssertEqual(SettingsManager.shared.islandDisplayMode, .dynamicIsland)
        XCTAssertEqual(SettingsManager.shared.dynamicIslandTopOffset, 22)

        SettingsManager.shared.dynamicIslandTopOffset = 99
        XCTAssertEqual(SettingsManager.shared.dynamicIslandTopOffset, 40)
    }

    func testPanelWindowLayoutOffsetAndWidthMetrics() {
        let screenMaxY: CGFloat = 1000
        let panelHeight: CGFloat = 32
        XCTAssertEqual(
            PanelWindowLayout.anchoredY(screenMaxY: screenMaxY, panelHeight: panelHeight, displayMode: .notch, isFullscreenMode: false),
            968
        )
        XCTAssertEqual(
            PanelWindowLayout.anchoredY(screenMaxY: screenMaxY, panelHeight: panelHeight, displayMode: .dynamicIsland, isFullscreenMode: false),
            958
        )
        XCTAssertEqual(
            PanelWindowLayout.anchoredY(screenMaxY: screenMaxY, panelHeight: panelHeight, displayMode: .dynamicIsland, isFullscreenMode: false, topOffset: 24),
            944
        )
        XCTAssertEqual(
            PanelWindowLayout.anchoredY(screenMaxY: screenMaxY, panelHeight: panelHeight, displayMode: .dynamicIsland, isFullscreenMode: true),
            958
        )

        XCTAssertEqual(
            NotchWidthMetrics.effectiveNotchWidth(
                notchW: notchW,
                collapsedWidthScale: 100,
                hasNotch: false,
                displayMode: .dynamicIsland
            ),
            16
        )
        XCTAssertEqual(
            NotchWidthMetrics.effectiveNotchWidth(
                notchW: notchW,
                collapsedWidthScale: 100,
                hasNotch: true,
                displayMode: .dynamicIsland
            ),
            185
        )
    }

    func testNonNotchDynamicIslandRendersDetachedRoundedPillWithoutCenterDeadSpace() throws {
        configureMusic(artworkColor: NSColor(srgbRed: 0.0, green: 0.35, blue: 1.0, alpha: 1.0))

        // Before: Notch mode on non-notch display (docked flush at top with concave ears & 185pt center gap)
        let notchRender = try renderScene(
            displayMode: .notch,
            hasNotch: false,
            state: makeAgentState(status: .idle),
            canvasWidth: 620,
            canvasHeight: 72,
            saveName: "before-nonnotch-notch-idle-music"
        )
        XCTAssertEqual(notchRender.topGapPt, 0, accuracy: 1.0, "notch mode must sit flush at top edge")
        XCTAssertGreaterThan(
            notchRender.topRowWidthPt,
            notchRender.midRowWidthPt,
            "notch mode top row must flare wider than mid-bar due to concave ears"
        )
        XCTAssertGreaterThan(notchRender.midRowWidthPt, 240, "notch mode includes simulated center cutout")

        // After: Dynamic Island mode on non-notch display (floating detached rounded capsule pill)
        let pillRender = try renderScene(
            displayMode: .dynamicIsland,
            hasNotch: false,
            state: makeAgentState(status: .idle),
            canvasWidth: 620,
            canvasHeight: 72,
            saveName: "after-nonnotch-dynamic-island-idle-music"
        )
        XCTAssertGreaterThanOrEqual(pillRender.topGapPt, 9.0, "Dynamic Island must float detached below top edge")
        XCTAssertLessThan(
            pillRender.topRowWidthPt,
            pillRender.midRowWidthPt - 6,
            "Dynamic Island top edge must curve inward into a rounded pill (no concave ears)"
        )
        XCTAssertLessThan(
            pillRender.bottomRowWidthPt,
            pillRender.midRowWidthPt - 6,
            "Dynamic Island bottom edge must curve inward symmetrically"
        )
        XCTAssertLessThan(
            pillRender.midRowWidthPt,
            180,
            "non-notch Dynamic Island must collapse simulated 185pt notch dead space"
        )
        XCTAssertTrue(pillRender.hasBlueArtworkPixel, "album cover missing inside Dynamic Island pill")
        XCTAssertTrue(pillRender.hasAmberVisualizerPixel, "visualizer missing inside Dynamic Island pill")
    }

    func testDynamicIslandWithActiveThinkingAndNotchedHardwareProtection() throws {
        NowPlayingManager.shared.isPlaying = false
        IslandSignals.shared.setMusic(isPlaying: false, showToast: false, hasTitle: false, hasLyrics: false, title: "", artist: "")

        // Before: Non-notch thinking in Notch mode
        let notchThinking = try renderScene(
            displayMode: .notch,
            hasNotch: false,
            state: makeAgentState(status: .processing),
            canvasWidth: 620,
            canvasHeight: 72,
            saveName: "before-nonnotch-notch-thinking"
        )
        XCTAssertEqual(notchThinking.topGapPt, 0, accuracy: 1.0)
        XCTAssertGreaterThan(notchThinking.midRowWidthPt, 260)

        // After: Non-notch thinking in Dynamic Island mode
        let nonNotchThinking = try renderScene(
            displayMode: .dynamicIsland,
            hasNotch: false,
            state: makeAgentState(status: .processing),
            canvasWidth: 620,
            canvasHeight: 72,
            saveName: "after-nonnotch-dynamic-island-thinking"
        )
        XCTAssertGreaterThanOrEqual(nonNotchThinking.topGapPt, 9.0)
        XCTAssertLessThan(nonNotchThinking.topRowWidthPt, nonNotchThinking.midRowWidthPt - 6)
        XCTAssertGreaterThanOrEqual(
            nonNotchThinking.midRowWidthPt,
            148,
            "Balanced Twin Thinking pill must keep '... thinking' visible alongside branch label"
        )
        XCTAssertLessThan(nonNotchThinking.midRowWidthPt, 240)

        // Notched display comparison: Notch mode vs Dynamic Island mode preserving physical center clearance
        configureMusic(artworkColor: NSColor(srgbRed: 0.0, green: 0.35, blue: 1.0, alpha: 1.0))
        let notchedBefore = try renderScene(
            displayMode: .notch,
            hasNotch: true,
            state: makeAgentState(status: .idle),
            canvasWidth: 620,
            canvasHeight: 72,
            saveName: "before-notched-notch-idle-music"
        )
        XCTAssertEqual(notchedBefore.topGapPt, 0, accuracy: 1.0)

        let notchedPill = try renderScene(
            displayMode: .dynamicIsland,
            hasNotch: true,
            state: makeAgentState(status: .idle),
            canvasWidth: 620,
            canvasHeight: 72,
            saveName: "after-notched-dynamic-island-idle-music"
        )
        XCTAssertGreaterThanOrEqual(notchedPill.topGapPt, 9.0)
        XCTAssertLessThan(notchedPill.topRowWidthPt, notchedPill.midRowWidthPt - 6)
        XCTAssertNil(notchedPill.notchCenterIntrusion, "notched hardware cutout area must stay clear of non-black content")
        XCTAssertTrue(notchedPill.hasBlueArtworkPixel)
        XCTAssertTrue(notchedPill.hasAmberVisualizerPixel)
    }

    func testDynamicIslandExpandedCardFloatsWithContinuousRoundedCorners() throws {
        NowPlayingManager.shared.isPlaying = false
        IslandSignals.shared.setMusic(isPlaying: false, showToast: false, hasTitle: false, hasLyrics: false, title: "", artist: "")

        let expandedNotch = try renderScene(
            displayMode: .notch,
            hasNotch: false,
            state: makeAgentState(status: .processing, surface: .sessionList),
            canvasWidth: 760,
            canvasHeight: 380,
            saveName: "before-nonnotch-notch-expanded"
        )
        XCTAssertEqual(expandedNotch.topGapPt, 0, accuracy: 1.0)
        XCTAssertGreaterThan(expandedNotch.topRowWidthPt, expandedNotch.midRowWidthPt)

        let expandedPill = try renderScene(
            displayMode: .dynamicIsland,
            hasNotch: false,
            state: makeAgentState(status: .processing, surface: .sessionList),
            canvasWidth: 760,
            canvasHeight: 380,
            saveName: "after-nonnotch-dynamic-island-expanded"
        )
        XCTAssertGreaterThanOrEqual(expandedPill.topGapPt, 9.0)
        XCTAssertLessThan(expandedPill.topRowWidthPt, expandedPill.midRowWidthPt - 10)
        XCTAssertLessThan(expandedPill.bottomRowWidthPt, expandedPill.midRowWidthPt - 10)
        XCTAssertGreaterThan(expandedPill.midRowWidthPt, 660)
    }

    func testNonNotchIdleToastBannerKeepsFullWidthInDynamicIslandMode() throws {
        NowPlayingManager.shared.isPlaying = false
        IslandSignals.shared.setMusic(isPlaying: false, showToast: false, hasTitle: false, hasLyrics: false, title: "", artist: "")
        IslandSignals.shared.setChargingBanner(visible: true, batteryLevel: 85)

        let emptyState = AppState()
        emptyState.refreshDerivedState()

        let toastPill = try renderScene(
            displayMode: .dynamicIsland,
            hasNotch: false,
            state: emptyState,
            canvasWidth: 620,
            canvasHeight: 112,
            saveName: "after-nonnotch-dynamic-island-toast"
        )
        XCTAssertGreaterThanOrEqual(toastPill.topGapPt, 9.0)
        XCTAssertGreaterThanOrEqual(
            toastPill.midRowWidthPt,
            275,
            "idle toast-only banner must not be crushed to idle wing/resting width"
        )
        XCTAssertLessThan(toastPill.topRowWidthPt, toastPill.midRowWidthPt - 8)
    }

    func testDynamicIslandIdleMusicAndNativeLyricsRenderUnifiedBalancedPillWithoutDetachedBar() throws {
        configureMusic(artworkColor: NSColor(srgbRed: 0.0, green: 0.35, blue: 1.0, alpha: 1.0))

        // Option 2 Balanced Twin (Idle + Music): tightly proportioned width, no hollow center gap
        let idleMusic = try renderScene(
            displayMode: .dynamicIsland,
            hasNotch: false,
            state: makeAgentState(status: .idle),
            canvasWidth: 620,
            canvasHeight: 72,
            saveName: "after-balanced-twin-idle-music"
        )
        XCTAssertGreaterThanOrEqual(idleMusic.midRowWidthPt, 96)
        XCTAssertLessThanOrEqual(
            idleMusic.midRowWidthPt,
            152,
            "Option 2 Balanced Twin must avoid wide hollow gap between Mascot and Album+EQ"
        )
        XCTAssertTrue(idleMusic.hasBlueArtworkPixel)
        XCTAssertTrue(idleMusic.hasAmberVisualizerPixel)

        // Native Lyrics inside Dynamic Island Mode: single unified capsule (no detached sub-notch pill below)
        NowPlayingManager.shared.lyrics = [LyricLine(id: 0, timestamp: 0, text: "Midnight neon rain on the glass")]
        NowPlayingManager.shared.currentLyricIndex = 0
        IslandSignals.shared.setMusic(
            isPlaying: true,
            showToast: false,
            hasTitle: true,
            hasLyrics: true,
            title: "Midnight City",
            artist: "M83"
        )

        let lyricPill = try renderScene(
            displayMode: .dynamicIsland,
            hasNotch: false,
            state: makeAgentState(status: .idle),
            canvasWidth: 620,
            canvasHeight: 112,
            showCompactLyrics: true,
            saveName: "after-balanced-twin-lyrics"
        )
        XCTAssertLessThanOrEqual(
            lyricPill.renderedHeightPt,
            40,
            "Dynamic Island lyrics must live inside the unified top pill without a detached sub-notch bar"
        )
        XCTAssertTrue(lyricPill.hasBlueArtworkPixel)
    }

    func testSettingsAppearanceRendersDisplayModePicker() throws {
        suite.removePersistentDomain(forName: suiteName)
        suite.set(IslandDisplayMode.dynamicIsland.rawValue, forKey: SettingsKey.islandDisplayMode)
        let size = CGSize(width: 660, height: 540)
        let view = SettingsView(appState: nil, initialPage: .appearance)
            .defaultAppStorage(suite)
        let image = try OffscreenRender.hosted(
            view,
            size: size,
            appearance: .darkAqua,
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            passes: 5
        )
        XCTAssertGreaterThan(image.width, 0)
        if let path = screenshotPath(for: "after-settings-display-mode") {
            let backed = try XCTUnwrap(OffscreenRender.rasterize(
                ZStack {
                    Rectangle().fill(Color(white: 0.16))
                    Image(decorative: image, scale: 2)
                }.frame(width: size.width, height: size.height)
            ))
            try OffscreenRender.writePNG(backed, to: path)
        }
    }

    // MARK: - Helpers

    private func configureMusic(artworkColor: NSColor) {
        let size = NSSize(width: 24, height: 24)
        let img = NSImage(size: size)
        img.lockFocus()
        artworkColor.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        img.unlockFocus()

        NowPlayingManager.shared.startSimulatedPlayback(
            title: "Midnight City",
            artist: "M83",
            album: "Hurry Up",
            duration: 240,
            lrc: "",
            artwork: img
        )
        IslandSignals.shared.setMusic(
            isPlaying: true,
            showToast: false,
            hasTitle: true,
            hasLyrics: false,
            title: "Midnight City",
            artist: "M83"
        )
    }

    private func makeAgentState(status: AgentStatus, surface: IslandSurface = .collapsed) -> AppState {
        let state = AppState()
        var session = SessionSnapshot()
        session.source = "claude"
        session.cwd = "/Users/dev/code/CodeIsland"
        session.gitBranch = "main"
        session.status = status
        state.sessions = ["s1": session]
        state.activeSessionId = "s1"
        state.surface = surface
        state.refreshDerivedState()
        return state
    }

    private func screenshotPath(for saveName: String) -> String? {
        guard let screenshotDir = ProcessInfo.processInfo.environment["CODEISLAND_SCREENSHOT_DIR"],
              !screenshotDir.isEmpty else { return nil }
        let dirURL = URL(fileURLWithPath: screenshotDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        return dirURL.appendingPathComponent("\(saveName).png").path
    }

    private struct SceneMetrics {
        let topGapPt: CGFloat
        let renderedHeightPt: CGFloat
        let topRowWidthPt: CGFloat
        let midRowWidthPt: CGFloat
        let bottomRowWidthPt: CGFloat
        let notchCenterIntrusion: CGFloat?
        let hasBlueArtworkPixel: Bool
        let hasAmberVisualizerPixel: Bool
    }

    private func renderScene(
        displayMode: IslandDisplayMode,
        hasNotch: Bool,
        state: AppState,
        canvasWidth: CGFloat,
        canvasHeight: CGFloat,
        showCompactLyrics: Bool = false,
        saveName: String
    ) throws -> SceneMetrics {
        suite.removePersistentDomain(forName: suiteName)
        suite.set(displayMode.rawValue, forKey: SettingsKey.islandDisplayMode)
        suite.set(IslandUITheme.modern.rawValue, forKey: SettingsKey.islandUITheme)
        suite.set(MusicHUDTheme.modernClean.rawValue, forKey: SettingsKey.musicHUDTheme)
        suite.set(MusicProgressColor.amber.rawValue, forKey: SettingsKey.musicHUDProgressColor)
        suite.set(showCompactLyrics, forKey: SettingsKey.showCompactLyrics)
        suite.set(true, forKey: SettingsKey.showAgentDetails)
        suite.set(true, forKey: SettingsKey.showToolStatus)
        suite.set(100, forKey: SettingsKey.collapsedWidthScale)

        let topOffset = CGFloat(IslandDisplayMetrics.floatingYOffset(
            displayMode: displayMode,
            isFullscreenMode: state.isFullscreenMode
        ))

        let view = ZStack(alignment: .top) {
            Color(red: 0.72, green: 0.10, blue: 0.14)
            NotchPanelView(
                appState: state,
                hasNotch: hasNotch,
                notchHeight: notchHeight,
                notchW: notchW,
                screenWidth: screenWidth
            )
            .environment(\.mascotStaticTime, 5.2)
            .defaultAppStorage(suite)
            .padding(.top, topOffset)
        }
        .frame(width: canvasWidth, height: canvasHeight)

        let image = try OffscreenRender.hosted(
            view,
            size: CGSize(width: canvasWidth, height: canvasHeight),
            scale: 2,
            passes: 5
        )
        if let path = screenshotPath(for: saveName) {
            try OffscreenRender.writePNG(image, to: path)
        }
        return try inspectSceneBitmap(image: image, scale: 2, canvasWidth: canvasWidth, hasNotch: hasNotch)
    }

    private func inspectSceneBitmap(
        image: CGImage,
        scale: CGFloat,
        canvasWidth: CGFloat,
        hasNotch: Bool
    ) throws -> SceneMetrics {
        let w = image.width, h = image.height
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)

        func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let p = px + (y * w + x) * 4
            return (Int(p[0]), Int(p[1]), Int(p[2]))
        }
        func isPanelSurface(_ c: (Int, Int, Int)) -> Bool {
            c.0 < 85 && c.1 < 85 && c.2 < 85
        }
        func isBlack(_ c: (Int, Int, Int)) -> Bool { c.0 < 15 && c.1 < 15 && c.2 < 15 }
        func isBackdrop(_ c: (Int, Int, Int)) -> Bool { c.0 > 130 && c.1 < 75 && c.2 < 80 }
        func isBlueArtwork(_ c: (Int, Int, Int)) -> Bool { c.2 > 160 && c.0 < 90 && c.1 < 120 }
        func isAmberViz(_ c: (Int, Int, Int)) -> Bool { c.0 > 170 && c.1 > 100 && c.2 < 110 && !isBackdrop(c) }

        func rowSpanWidth(y: Int) -> CGFloat? {
            guard y >= 0, y < h else { return nil }
            guard let first = (0..<w).first(where: { isPanelSurface(rgb($0, y)) }),
                  let last = (0..<w).reversed().first(where: { isPanelSurface(rgb($0, y)) }) else {
                return nil
            }
            return CGFloat(last - first + 1) / scale
        }

        let panelRows = (0..<h).filter { rowSpanWidth(y: $0) != nil }
        let firstY = try XCTUnwrap(panelRows.first, "no panel rendered in bitmap")
        let lastY = try XCTUnwrap(panelRows.last, "no panel bottom rendered")
        let midY = (firstY + lastY) / 2

        let topWidth = try XCTUnwrap(rowSpanWidth(y: firstY + 1))
        let midWidth = try XCTUnwrap(rowSpanWidth(y: midY))
        let bottomWidth = try XCTUnwrap(rowSpanWidth(y: max(firstY, lastY - 1)))

        // Give a 0.5pt (1 pixel at scale 2) subpixel cushion on both outer boundaries
        // so subpixel edge anti-aliasing of the wing shapes is not mistaken for intrusion.
        let notchLeftPx = Int(((canvasWidth - notchW) / 2 + 0.5) * scale)
        let notchRightPx = Int(((canvasWidth + notchW) / 2 - 0.5) * scale)
        let intrusionPx: Int? = hasNotch ? (notchLeftPx..<notchRightPx).first { x in
            panelRows.contains { y in
                let c = rgb(x, y)
                return !isBlack(c) && !isBackdrop(c) && !isPanelSurface(c)
            }
        } : nil

        var hasBlue = false
        var hasAmber = false
        for y in panelRows {
            for x in 0..<w {
                let c = rgb(x, y)
                if isBlueArtwork(c) { hasBlue = true }
                if isAmberViz(c) { hasAmber = true }
            }
        }

        return SceneMetrics(
            topGapPt: CGFloat(firstY) / scale,
            renderedHeightPt: CGFloat(lastY - firstY + 1) / scale,
            topRowWidthPt: topWidth,
            midRowWidthPt: midWidth,
            bottomRowWidthPt: bottomWidth,
            notchCenterIntrusion: intrusionPx.map { CGFloat($0) / scale },
            hasBlueArtworkPixel: hasBlue,
            hasAmberVisualizerPixel: hasAmber
        )
    }
}
