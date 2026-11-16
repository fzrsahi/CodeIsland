import XCTest
@testable import Morrow
import MorrowCore

/// Qoder 国行 ships as its own `qoderclicn` binary rooted at ~/.qoder-cn. The
/// resolver only knew the international `qodercli` under ~/.qoder, so CN sessions
/// were never attributed and CodeIsland's "supports Qoder" claim only held for
/// the international build (#289).
final class QoderCNSupportTests: XCTestCase {

    func testChinaBinaryResolvesToTheQoderCliSource() {
        for path in [
            "/Users/me/.qoder-cn/bin/qoderclicn/qoderclicn-1.1.5",
            "/opt/homebrew/bin/qoderclicn",
            "/Users/me/.local/bin/qoderclicn",
        ] {
            XCTAssertTrue(
                CLIProcessResolver.sourceMatchesExecutablePath(path, source: "qoder-cli"),
                "\(path) must be recognized as Qoder CLI"
            )
        }
    }

    func testInternationalBinaryStillResolves() {
        for path in [
            "/Users/me/.qoder/bin/qodercli/qodercli",
            "/opt/homebrew/lib/node_modules/@qoder-ai/qodercli/bin/cli.js",
        ] {
            XCTAssertTrue(CLIProcessResolver.sourceMatchesExecutablePath(path, source: "qoder-cli"))
        }
    }

    func testUnrelatedBinariesAreNotClaimed() {
        for path in ["/usr/bin/codex", "/Applications/Cursor.app/Contents/MacOS/Cursor"] {
            XCTAssertFalse(CLIProcessResolver.sourceMatchesExecutablePath(path, source: "qoder-cli"))
        }
    }

    func testChinaSourceSpellingsNormalizeOntoQoderCli() {
        for spelling in ["qoderclicn", "QoderCliCN", "qoder-cn", "qodercn", "qodercli-cn"] {
            XCTAssertEqual(
                SessionSnapshot.normalizedSupportedSource(spelling),
                "qoder-cli",
                "\(spelling) must fold onto the shared qoder-cli source"
            )
        }
    }

    func testInstallerShipsAChinaEntryPointingAtTheChinaConfigRoot() throws {
        let cli = try XCTUnwrap(ConfigInstaller.allCLIs.first { $0.source == "qoder-cn" })
        XCTAssertEqual(cli.configPath, ".qoder-cn/settings.json")
        XCTAssertEqual(cli.configKey, "hooks")
        // Hooks must report the shared source so both builds land on one card kind.
        XCTAssertEqual(cli.bridgeSourceOverride, "qoder-cli")
        XCTAssertTrue(cli.events.contains { $0.0 == "PermissionRequest" })
    }

    func testChinaConfigDirIsTreatedAsAgentMetadataNotAProjectName() {
        var session = SessionSnapshot()
        session.cwd = "/Users/me/work/bucket/.qoder-cn"
        XCTAssertEqual(session.displayName, "bucket")
    }
}
