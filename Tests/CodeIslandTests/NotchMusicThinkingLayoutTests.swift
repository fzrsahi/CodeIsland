import AppKit
import SwiftUI
import XCTest
@testable import CodeIsland
import CodeIslandCore

/// Issue #40:
/// - When agent is thinking (`isThinking`), music wing layout must sync to `{ [album cover] [title music] [music play style] }`
///   and thinking indicator / right wing must not overlap into the notch.
/// - When agent is idle, music wing layout must sync to `{ [album cover] [music play style] }`.
@MainActor
final class NotchMusicThinkingLayoutTests: XCTestCase {
    private let suiteName = "NotchMusicThinkingLayoutTests"
    private var suite: UserDefaults!
    private let notch: CGFloat = 185
    private let windowWidth: CGFloat = 620
    private let screenWidth: CGFloat = 1512
    private var savedLanguage: String?
    private var savedRawAppLanguage: Any?

    override func setUp() async throws {
        try await super.setUp()
        _ = NSApplication.shared
        suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        suite.removePersistentDomain(forName: suiteName)
        savedRawAppLanguage = UserDefaults.standard.object(forKey: SettingsKey.appLanguage)
        savedLanguage = L10n.shared.language
        MascotAnimationGate.shared.setPanelVisible(false)
        IslandSignals.shared.setInQuietHours(false)
        IslandSignals.shared.setVolumeHUDVisible(false)
        IslandSignals.shared.setMiniPeekBanner(false)
        IslandSignals.shared.setChargingBanner(visible: false, batteryLevel: 100)
    }

    override func tearDown() async throws {
        suite.removePersistentDomain(forName: suiteName)
        if let savedLanguage {
            L10n.shared.language = savedLanguage
        }
        if let savedRawAppLanguage {
            UserDefaults.standard.set(savedRawAppLanguage, forKey: SettingsKey.appLanguage)
        } else {
            UserDefaults.standard.removeObject(forKey: SettingsKey.appLanguage)
        }
        NowPlayingManager.shared.isPlaying = false
        NowPlayingManager.shared.title = ""
        NowPlayingManager.shared.artist = ""
        NowPlayingManager.shared.album = ""
        NowPlayingManager.shared.artworkImage = nil
        NowPlayingManager.shared.lyrics = []
        IslandSignals.shared.setMusic(isPlaying: false, showToast: false, hasTitle: false, hasLyrics: false, title: "", artist: "")
        IslandSignals.shared.setInQuietHours(false)
        MascotAnimationGate.shared.setPanelVisible(true)
        try await super.tearDown()
    }

    func testThinkingWithMusicShowsCoverTitleVisualizerAndClearsNotch() throws {
        for theme in [IslandUITheme.modern, IslandUITheme.pixel] {
            configureMusic(title: "Midnight City", artworkColor: NSColor(srgbRed: 0.0, green: 0.25, blue: 1.0, alpha: 1.0))
            configureDefaults(theme: theme, widthScale: 100)
            let state = makeAgentState(status: .processing)

            let render = try renderCollapsedBar(state: state, hasNotch: true, saveName: "thinking-music-\(theme.rawValue)")
            let tag = "theme=\(theme.rawValue)"

            XCTAssertNil(render.intrusion, "\(tag): bar drew under physical notch at \(render.intrusion ?? 0)pt")
            XCTAssertGreaterThanOrEqual(render.barLeft, 0, "\(tag): bar clipped past window left edge")
            XCTAssertLessThanOrEqual(render.barRight, windowWidth, "\(tag): bar clipped past window right edge")

            let albumRange = try XCTUnwrap(render.rightAlbumRange, "\(tag): album cover missing when thinking+music")
            let titleRange = try XCTUnwrap(render.rightTitleRange, "\(tag): music title missing when thinking+music")
            let vizRange = try XCTUnwrap(render.rightVisualizerRange, "\(tag): music visualizer missing when thinking+music")

            XCTAssertLessThanOrEqual(albumRange.upperBound, titleRange.lowerBound, "\(tag): expected [album cover] before [title music]")
            XCTAssertLessThanOrEqual(titleRange.upperBound, vizRange.lowerBound, "\(tag): expected [title music] before [music play style]")
        }
    }

    func testIdleWithMusicShowsCoverAndVisualizerWithoutTitleAndClearsNotch() throws {
        for theme in [IslandUITheme.modern, IslandUITheme.pixel] {
            configureMusic(title: "Midnight City", artworkColor: NSColor(srgbRed: 0.0, green: 0.25, blue: 1.0, alpha: 1.0))
            configureDefaults(theme: theme, widthScale: 100)
            let state = makeAgentState(status: .idle)

            let render = try renderCollapsedBar(state: state, hasNotch: true, saveName: "idle-music-\(theme.rawValue)")
            let tag = "idle theme=\(theme.rawValue)"

            XCTAssertNil(render.intrusion, "\(tag): bar drew under physical notch at \(render.intrusion ?? 0)pt")
            let albumRange = try XCTUnwrap(render.rightAlbumRange, "\(tag): album cover missing when idle+music")
            let vizRange = try XCTUnwrap(render.rightVisualizerRange, "\(tag): music visualizer missing when idle+music")
            XCTAssertLessThanOrEqual(albumRange.upperBound, vizRange.lowerBound, "\(tag): expected [album cover] before [visualizer]")
            XCTAssertNil(render.rightTitleRange, "\(tag): idle music wing should not render title when not hovered")
            XCTAssertLessThanOrEqual(vizRange.lowerBound - albumRange.upperBound, 12, "\(tag): unexpected gap between album cover and visualizer when idle")
        }
    }

    func testThinkingAndGermanThinkingClearNotchAcrossScalesWithoutMusic() throws {
        let cases: [(theme: IslandUITheme, lang: String, scale: Int, quiet: Bool)] = [
            (.modern, "en", 100, false),
            (.pixel, "en", 100, false),
            (.modern, "de", 100, true),
            (.pixel, "de", 100, true),
            (.modern, "en", 60, false),
            (.pixel, "en", 140, false),
        ]
        for c in cases {
            NowPlayingManager.shared.isPlaying = false
            NowPlayingManager.shared.title = ""
            NowPlayingManager.shared.artworkImage = nil
            IslandSignals.shared.setMusic(isPlaying: false, showToast: false, hasTitle: false, hasLyrics: false, title: "", artist: "")
            IslandSignals.shared.setInQuietHours(c.quiet)
            L10n.shared.language = c.lang
            configureDefaults(theme: c.theme, widthScale: c.scale)
            let state = makeAgentState(status: .processing)

            let render = try renderCollapsedBar(
                state: state,
                hasNotch: true,
                saveName: "thinking-nomusic-\(c.theme.rawValue)-\(c.lang)-\(c.scale)"
            )
            let tag = "\(c.theme.rawValue) lang=\(c.lang) scale=\(c.scale) quiet=\(c.quiet)"
            XCTAssertNil(render.intrusion, "\(tag): thinking indicator or wing drew under physical notch at \(render.intrusion ?? 0)pt")
            XCTAssertGreaterThanOrEqual(render.barLeft, 0, "\(tag): bar clipped past window left edge")
            XCTAssertLessThanOrEqual(render.barRight, windowWidth, "\(tag): bar clipped past window right edge")
        }
    }

    func testStateTransitionThinkingToIdleReSyncsAndShrinksRightWing() throws {
        configureMusic(title: "Midnight City", artworkColor: NSColor(srgbRed: 0.0, green: 0.25, blue: 1.0, alpha: 1.0))
        configureDefaults(theme: .modern, widthScale: 100)
        let state = makeAgentState(status: .processing)

        try withOffscreenPanel(state: state, hasNotch: true) { capture in
            let thinkingRender = try capture(0.08, nil)
            XCTAssertNil(thinkingRender.intrusion)
            XCTAssertNotNil(thinkingRender.rightTitleRange, "thinking state must show music title")
            let thinkingWidth = thinkingRender.barRight - thinkingRender.barLeft

            // Transition agent back to idle on the same live panel instance
            if var session = state.sessions["s1"] {
                session.status = .idle
                state.sessions["s1"] = session
                state.refreshDerivedState()
            }

            let idleRender = try capture(0.08, nil)
            XCTAssertNil(idleRender.intrusion)
            XCTAssertNil(idleRender.rightTitleRange, "idle state must remove music title in sync")
            let idleWidth = idleRender.barRight - idleRender.barLeft
            XCTAssertLessThan(idleWidth, thinkingWidth - 30, "bar width must shrink back cleanly on thinking -> idle transition")
        }
    }

    func testEdgeCasesKoreanThreeBadgesQuotaPriorityAndWideScale() throws {
        // 1. Korean ("생각 중") without music in Modern & Pixel themes
        NowPlayingManager.shared.isPlaying = false
        NowPlayingManager.shared.title = ""
        NowPlayingManager.shared.artworkImage = nil
        IslandSignals.shared.setMusic(isPlaying: false, showToast: false, hasTitle: false, hasLyrics: false, title: "", artist: "")
        L10n.shared.language = "ko"
        for theme in [IslandUITheme.modern, IslandUITheme.pixel] {
            configureDefaults(theme: theme, widthScale: 100)
            let koRender = try renderCollapsedBar(
                state: makeAgentState(status: .processing),
                hasNotch: true,
                saveName: "thinking-nomusic-\(theme.rawValue)-ko-100"
            )
            XCTAssertNil(koRender.intrusion, "ko \(theme.rawValue): thinking indicator intruded into notch")
            XCTAssertGreaterThanOrEqual(koRender.barLeft, 0)
            XCTAssertLessThanOrEqual(koRender.barRight, windowWidth)
        }
        L10n.shared.language = "en"

        // 2. collapsedWidthScale = 160 with thinking + music
        configureMusic(title: "Midnight City", artworkColor: NSColor(srgbRed: 0.0, green: 0.25, blue: 1.0, alpha: 1.0))
        configureDefaults(theme: .modern, widthScale: 160)
        let wideScale = try renderCollapsedBar(
            state: makeAgentState(status: .processing),
            hasNotch: true,
            saveName: "thinking-music-scale160"
        )
        XCTAssertNil(wideScale.intrusion, "scale=160 drew under notch")
        let wideAlbum = try XCTUnwrap(wideScale.rightAlbumRange, "scale=160 album missing")
        let wideTitle = try XCTUnwrap(wideScale.rightTitleRange, "scale=160 title missing")
        let wideViz = try XCTUnwrap(wideScale.rightVisualizerRange, "scale=160 visualizer missing")
        XCTAssertLessThanOrEqual(wideAlbum.upperBound, wideTitle.lowerBound)
        XCTAssertLessThanOrEqual(wideTitle.upperBound, wideViz.lowerBound)

        // 3. All 3 right-wing status badges simultaneously + thinking + music
        IslandSignals.shared.setInQuietHours(true)
        configureDefaults(theme: .modern, widthScale: 100)
        let badgeState = makeAgentState(status: .processing)
        badgeState.glanceCompletionActive = true
        let qEvent = try XCTUnwrap(HookEvent(from: try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "Notification",
            "session_id": "s2",
        ])))
        let qPayload = QuestionPayload(question: "Pick", options: ["A"], header: "Plan")
        badgeState.questionQueue.append(QuestionRequest(
            event: qEvent,
            question: qPayload,
            resolution: .codexAppServer { _ in },
            askUserQuestionState: AskUserQuestionState(
                items: [AskUserQuestionItem(payload: qPayload, answerKey: "q1", multiSelect: false)],
                answers: [:]
            )
        ))
        XCTAssertNotNil(badgeState.hiddenPendingQuestionSessionId)
        let badgesRender = try renderCollapsedBar(
            state: badgeState,
            hasNotch: true,
            saveName: "thinking-music-3badges"
        )
        XCTAssertNil(badgesRender.intrusion, "3 badges + thinking + music drew under notch")
        XCTAssertNotNil(badgesRender.rightAlbumRange)
        XCTAssertNotNil(badgesRender.rightTitleRange)
        XCTAssertNotNil(badgesRender.rightVisualizerRange)
        IslandSignals.shared.setInQuietHours(false)

        // 4. Quota + thinking priority (no music): thinking takes precedence cleanly without notch intrusion
        NowPlayingManager.shared.isPlaying = false
        NowPlayingManager.shared.title = ""
        NowPlayingManager.shared.artworkImage = nil
        IslandSignals.shared.setMusic(isPlaying: false, showToast: false, hasTitle: false, hasLyrics: false, title: "", artist: "")
        configureDefaults(theme: .modern, widthScale: 100)
        suite.set(true, forKey: SettingsKey.showClaudeQuota)
        suite.set(ClaudeQuotaChipMode.auto.rawValue, forKey: SettingsKey.claudeQuotaChip)
        let quotaThinkingState = makeAgentState(status: .processing)
        let now = Date()
        quotaThinkingState.claudeQuota.applyPreview(ClaudeQuotaSnapshot(limits: [
            ClaudeQuotaLimit(kind: .session, percent: 8, resetsAt: now.addingTimeInterval(4 * 3600)),
            ClaudeQuotaLimit(kind: .weeklyAll, percent: 25, resetsAt: now.addingTimeInterval(86_400)),
            ClaudeQuotaLimit(kind: .weeklyScoped, percent: 100, severity: "critical", resetsAt: now.addingTimeInterval(86_400), scopeLabel: "CodeIsland"),
        ], fetchedAt: now))
        let quotaRender = try renderCollapsedBar(
            state: quotaThinkingState,
            hasNotch: true,
            saveName: "thinking-quota-priority"
        )
        XCTAssertNil(quotaRender.intrusion, "quota + thinking drew under notch")
        XCTAssertGreaterThanOrEqual(quotaRender.barLeft, 0)
        XCTAssertLessThanOrEqual(quotaRender.barRight, windowWidth)
    }

    func testAdditionalConditionsToolRunningConnectedChinNonNotchAndBadges() throws {
        // 1. Tool running + music playing (modern)
        configureMusic(title: "Midnight City", artworkColor: NSColor(srgbRed: 0.0, green: 0.25, blue: 1.0, alpha: 1.0))
        configureDefaults(theme: .modern, widthScale: 100)
        var toolState = makeAgentState(status: .running, currentTool: "Edit")
        var r = try renderCollapsedBar(state: toolState, hasNotch: true, saveName: "tool-music-modern")
        XCTAssertNil(r.intrusion, "tool+music drew under notch")
        XCTAssertNotNil(r.rightAlbumRange)
        XCTAssertNotNil(r.rightTitleRange, "tool running (isThinking) must show music title")
        XCTAssertNotNil(r.rightVisualizerRange)

        // 2. Quiet hours + completion dot + thinking + music
        IslandSignals.shared.setInQuietHours(true)
        toolState = makeAgentState(status: .processing)
        toolState.glanceCompletionActive = true
        r = try renderCollapsedBar(state: toolState, hasNotch: true, saveName: "thinking-music-badges")
        XCTAssertNil(r.intrusion, "badges+thinking+music drew under notch")
        XCTAssertNotNil(r.rightTitleRange)
        IslandSignals.shared.setInQuietHours(false)

        // 3. Connected chin lyrics + thinking + music
        configureMusic(title: "Midnight City", artworkColor: NSColor(srgbRed: 0.0, green: 0.25, blue: 1.0, alpha: 1.0), lrc: "[00:00.00]Waiting in a car")
        suite.set(true, forKey: SettingsKey.showCompactLyrics)
        suite.set(FloatingLyricPreset.connectedChin.rawValue, forKey: SettingsKey.floatingLyricPreset)
        let chinRender = try renderCollapsedBar(state: makeAgentState(status: .processing), hasNotch: true, saveName: "chin-thinking-music")
        XCTAssertNil(chinRender.intrusion, "connectedChin+thinking+music drew under notch")
        XCTAssertNotNil(chinRender.rightTitleRange)

        // 4. Non-notch display (hasNotch: false) at scale=100 and scale=0
        configureMusic(title: "Midnight City", artworkColor: NSColor(srgbRed: 0.0, green: 0.25, blue: 1.0, alpha: 1.0))
        configureDefaults(theme: .pixel, widthScale: 100)
        let nonNotch = try renderCollapsedBar(state: makeAgentState(status: .processing), hasNotch: false, saveName: "nonnotch-thinking-music")
        XCTAssertGreaterThanOrEqual(nonNotch.barLeft, 0)
        XCTAssertLessThanOrEqual(nonNotch.barRight, windowWidth)
        XCTAssertNotNil(nonNotch.rightAlbumRange)
        XCTAssertNotNil(nonNotch.rightTitleRange)
        XCTAssertNotNil(nonNotch.rightVisualizerRange)

        configureDefaults(theme: .modern, widthScale: 0)
        let zeroScale = try renderCollapsedBar(state: makeAgentState(status: .processing), hasNotch: true, saveName: "thinking-music-scale0")
        XCTAssertNil(zeroScale.intrusion, "scale=0 must still never leak pixels into hardware notch")
    }

    // MARK: - Helpers

    private func configureDefaults(theme: IslandUITheme, widthScale: Int) {
        suite.removePersistentDomain(forName: suiteName)
        suite.set(theme.rawValue, forKey: SettingsKey.islandUITheme)
        suite.set(MusicHUDTheme.modernClean.rawValue, forKey: SettingsKey.musicHUDTheme)
        suite.set(MusicProgressColor.amber.rawValue, forKey: SettingsKey.musicHUDProgressColor)
        suite.set(false, forKey: SettingsKey.syncThemeWithAlbumArt)
        suite.set(false, forKey: SettingsKey.showCompactLyrics)
        suite.set(true, forKey: SettingsKey.showAgentDetails)
        suite.set(true, forKey: SettingsKey.showToolStatus)
        suite.set(widthScale, forKey: SettingsKey.collapsedWidthScale)
    }

    private func configureMusic(title: String, artworkColor: NSColor, lrc: String = "") {
        let size = NSSize(width: 24, height: 24)
        let img = NSImage(size: size)
        img.lockFocus()
        artworkColor.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        img.unlockFocus()

        NowPlayingManager.shared.startSimulatedPlayback(
            title: title,
            artist: "M83",
            album: "Hurry Up",
            duration: 240,
            lrc: lrc,
            artwork: img
        )
        IslandSignals.shared.setMusic(
            isPlaying: true,
            showToast: false,
            hasTitle: true,
            hasLyrics: !lrc.isEmpty,
            title: title,
            artist: "M83"
        )
    }

    private func makeAgentState(status: AgentStatus, currentTool: String? = nil) -> AppState {
        let state = AppState()
        var session = SessionSnapshot()
        session.source = "claude"
        session.cwd = "/Users/dev/code/CodeIsland"
        session.gitBranch = "main"
        session.status = status
        session.currentTool = currentTool
        state.sessions = ["s1": session]
        state.activeSessionId = "s1"
        state.refreshDerivedState()
        return state
    }

    private struct RenderInspection {
        let barLeft: CGFloat
        let barRight: CGFloat
        let intrusion: CGFloat?
        let rightAlbumRange: Range<CGFloat>?
        let rightTitleRange: Range<CGFloat>?
        let rightVisualizerRange: Range<CGFloat>?
    }

    private func renderCollapsedBar(state: AppState, hasNotch: Bool, saveName: String) throws -> RenderInspection {
        var result: RenderInspection!
        try withOffscreenPanel(state: state, hasNotch: hasNotch) { capture in
            result = try capture(0.1, saveName)
        }
        return result
    }

    private func withOffscreenPanel(
        state: AppState,
        hasNotch: Bool,
        notchHeight: CGFloat = 32,
        body: (_ capture: (_ waitInterval: TimeInterval, _ saveName: String?) throws -> RenderInspection) throws -> Void
    ) throws {
        let height: CGFloat = 64
        let view = NotchPanelView(
            appState: state,
            hasNotch: hasNotch,
            notchHeight: notchHeight,
            notchW: notch,
            screenWidth: screenWidth
        )
        .environment(\.mascotStaticTime, 5.2)
        .defaultAppStorage(suite)
        .background(Color(red: 1, green: 0, blue: 0))

        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: windowWidth, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil }

        try body { waitInterval, saveName in
            for _ in 0..<5 {
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(waitInterval))
            }

            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)

            if let saveName,
               let screenshotDir = ProcessInfo.processInfo.environment["CODEISLAND_SCREENSHOT_DIR"],
               !screenshotDir.isEmpty {
                let dirURL = URL(fileURLWithPath: screenshotDir, isDirectory: true)
                try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: dirURL.appendingPathComponent("\(saveName).png"))
                }
            }

            return try inspectBitmap(rep: rep, hasNotch: hasNotch, notchHeight: notchHeight)
        }
    }

    private func inspectBitmap(rep: NSBitmapImageRep, hasNotch: Bool, notchHeight: CGFloat) throws -> RenderInspection {
        let image = try XCTUnwrap(rep.cgImage)
        let w = image.width, h = image.height
        let scale = CGFloat(w) / windowWidth
        let context = try XCTUnwrap(CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)

        func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let p = px + (y * w + x) * 4
            return (Int(p[0]), Int(p[1]), Int(p[2]))
        }
        func isBackdrop(_ c: (Int, Int, Int)) -> Bool { c.0 > 200 && c.1 < 60 && c.2 < 60 }
        func isBlack(_ c: (Int, Int, Int)) -> Bool { c.0 < 15 && c.1 < 15 && c.2 < 15 }
        func isBlueAlbum(_ c: (Int, Int, Int)) -> Bool { c.2 > 160 && c.0 < 90 && c.1 < 120 }
        func isWhiteText(_ c: (Int, Int, Int)) -> Bool { c.0 > 180 && c.1 > 180 && c.2 > 180 }
        func isAmberVisualizer(_ c: (Int, Int, Int)) -> Bool { c.0 > 170 && c.1 > 100 && c.2 < 110 && !isBackdrop(c) }

        let barRows = 0..<Int(notchHeight * scale)
        let mid = Int(notchHeight / 2 * scale)
        let leftPx = try XCTUnwrap((0..<w).first { !isBackdrop(rgb($0, mid)) }, "no bar rendered")
        let rightPx = try XCTUnwrap((0..<w).reversed().first { !isBackdrop(rgb($0, mid)) }, "no bar end rendered")

        let notchLeftPx = Int((windowWidth - notch) / 2 * scale)
        let notchRightPx = Int((windowWidth + notch) / 2 * scale)
        let intrusionPx: Int? = hasNotch ? (notchLeftPx..<notchRightPx).first { x in
            barRows.contains { y in
                let c = rgb(x, y)
                return !isBlack(c) && !isBackdrop(c)
            }
        } : nil

        func xRange(in scanRange: Range<Int>, matching predicate: ((Int, Int, Int)) -> Bool) -> Range<CGFloat>? {
            let matchingCols = scanRange.filter { x in
                barRows.contains { y in predicate(rgb(x, y)) }
            }
            guard let minX = matchingCols.first, let maxX = matchingCols.last else { return nil }
            return (CGFloat(minX) / scale)..<(CGFloat(maxX + 1) / scale)
        }

        let rightScan = hasNotch ? (notchRightPx..<(rightPx + 1)) : (w / 2)..<(rightPx + 1)
        let albumRange = xRange(in: rightScan, matching: isBlueAlbum)
        let vizRange = xRange(in: rightScan, matching: isAmberVisualizer)
        let titleRange = xRange(in: rightScan, matching: isWhiteText)

        return RenderInspection(
            barLeft: CGFloat(leftPx) / scale,
            barRight: CGFloat(rightPx + 1) / scale,
            intrusion: intrusionPx.map { CGFloat($0) / scale },
            rightAlbumRange: albumRange,
            rightTitleRange: titleRange,
            rightVisualizerRange: vizRange
        )
    }
}
