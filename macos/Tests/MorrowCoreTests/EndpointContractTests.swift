import XCTest
import Darwin
import MorrowCore

/// `SocketPath.resolve` against the shared case table
/// (`fixtures/endpoint/cases.json`, rules in `docs/endpoint-contract.md`).
/// Every `macos` case must pass; the Linux and Windows cases are only
/// decoded here, for the Rust port and the plugins to run.
final class EndpointContractTests: XCTestCase {
    private struct Table: Decodable {
        let version: Int
        let cases: [Case]
    }

    private struct Case: Decodable {
        let name: String
        let os: String
        let env: [String: String]
        let uid: UInt32?
        let sid: String?
        let existing: [Entry]
        let expected: String
    }

    private struct Entry: Decodable {
        let path: String
        let kind: String
        let target: String?
    }

    private static let casesURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("shared/contract/fixtures/endpoint/cases.json")

    private func loadTable() throws -> Table {
        let data = try Data(contentsOf: Self.casesURL)
        let table = try JSONDecoder().decode(Table.self, from: data)
        XCTAssertEqual(table.version, 1)
        return table
    }

    /// Whether `path` exists as `FileManager.fileExists` sees it: a symlink
    /// counts only when what it points to does.
    private func fileExists(_ path: String, in entries: [Entry], depth: Int = 0) -> Bool {
        guard depth < 8, let entry = entries.first(where: { $0.path == path }) else { return false }
        guard entry.kind == "symlink" else { return true }
        guard let target = entry.target else { return false }
        return fileExists(target, in: entries, depth: depth + 1)
    }

    func testEveryMacOSCaseResolvesToItsExpectedEndpoint() throws {
        let cases = try loadTable().cases.filter { $0.os == "macos" }
        XCTAssertFalse(cases.isEmpty, "no macos cases in \(Self.casesURL.path)")
        for c in cases {
            let uid = try XCTUnwrap(c.uid, "\(c.name): a macos case needs a uid")
            let resolved = SocketPath.resolve(
                environment: c.env,
                uid: uid_t(uid),
                fileExists: { self.fileExists($0, in: c.existing) }
            )
            XCTAssertEqual(resolved, c.expected, c.name)
        }
    }

    func testTheTableIsWellFormedForEveryOS() throws {
        let cases = try loadTable().cases
        XCTAssertEqual(Set(cases.map(\.name)).count, cases.count, "case names must be unique")
        for c in cases {
            XCTAssertTrue(["macos", "linux", "windows"].contains(c.os), c.name)
            XCTAssertTrue(c.name.hasPrefix(c.os + "-"), c.name)
            if c.os == "windows" {
                XCTAssertNotNil(c.sid, "\(c.name): a windows case needs a sid")
                XCTAssertNil(c.uid, c.name)
            } else {
                XCTAssertNotNil(c.uid, "\(c.name): a \(c.os) case needs a uid")
                XCTAssertNil(c.sid, c.name)
            }
        }
    }

    /// `path` is `resolve` over the real environment, uid and file system.
    func testPathIsResolveOverTheRealSystem() {
        XCTAssertEqual(
            SocketPath.path,
            SocketPath.resolve(
                environment: ProcessInfo.processInfo.environment,
                uid: getuid(),
                fileExists: { FileManager.default.fileExists(atPath: $0) }
            )
        )
    }
}
