import XCTest
@testable import Morrow
@testable import MorrowCore

final class CodexTerminalRoutingTests: XCTestCase {
    func testGhosttyTmuxCodexDoesNotUseDesktopFallback() {
        var session = SessionSnapshot()
        session.source = "codex"
        session.termBundleId = "com.mitchellh.ghostty"
        session.termApp = "tmux"
        session.tmuxPane = "%14"
        session.tmuxEnv = "/tmp/tmux-test/default,123,0"
        session.tmuxClientTty = "/dev/ttys000"

        XCTAssertFalse(session.isNativeAppMode)
        XCTAssertFalse(session.isIDETerminal)
        // activate() consults this mapping before reaching activateTmux().
        // A desktop entry here steals the jump when Codex.app is running.
        XCTAssertNil(TerminalActivator.sourceToNativeAppBundleId[session.source])
        XCTAssertTrue(TerminalActivator.knownTerminals.contains {
            $0.bundleId == session.termBundleId
        })
    }

    func testCodexWithoutTerminalMetadataDoesNotGuessDesktopHost() {
        // Missing terminal metadata is not evidence that this is a desktop run.
        XCTAssertNil(TerminalActivator.sourceToNativeAppBundleId["codex"])
    }

    func testExplicitCodexDesktopSessionRemainsNativeAppMode() {
        var session = SessionSnapshot()
        session.source = "codex"
        session.termBundleId = "com.openai.codex"

        XCTAssertTrue(session.isNativeAppMode)
        XCTAssertFalse(session.isIDETerminal)
    }

    /// An ambiguous Codex tmux jump raises the session's terminal app only.
    func testAmbiguousJumpRaisesTheSessionsTerminalApp() {
        XCTAssertEqual(TerminalActivator.appLevelTerminalBundleId(
            termApp: "Ghostty", termBundleId: "com.googlecode.iterm2"), "com.googlecode.iterm2")
        XCTAssertEqual(TerminalActivator.appLevelTerminalBundleId(
            termApp: "ghostty", termBundleId: nil), "com.mitchellh.ghostty")
        XCTAssertEqual(TerminalActivator.appLevelTerminalBundleId(
            termApp: "iTerm2", termBundleId: ""), "com.googlecode.iterm2")
        XCTAssertNil(TerminalActivator.appLevelTerminalBundleId(termApp: "Hyper", termBundleId: nil))
    }

    /// Buddy's focus button with no Codex card still raises Codex.app; only a
    /// session's own jump stopped falling back to it.
    func testSessionlessCallersStillFindTheCodexDesktopApp() {
        XCTAssertEqual(TerminalActivator.desktopAppBundleId(forSource: "codex"), "com.openai.codex")
        XCTAssertEqual(TerminalActivator.desktopAppBundleId(forSource: "trae"), "com.trae.app")
        XCTAssertNil(TerminalActivator.desktopAppBundleId(forSource: "claude"))
    }
}
