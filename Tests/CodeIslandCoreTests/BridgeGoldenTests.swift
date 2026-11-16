import Foundation
import XCTest

/// The real codeisland-bridge on every fixture in ``BridgeGoldenFixtures``,
/// under the process tree each one describes, against a stand-in socket.
///
/// - `CODEISLAND_REFERENCE_BRIDGE=<path>` also runs that build on every
///   fixture and requires the same bytes: forwarded event, stdout, exit
///   status and debug log (pids and timestamps aside), with deterministic
///   hashing so dictionary order is comparable.
/// - `CODEISLAND_GOLDEN_RECORD=<file>` writes ``BridgeGoldenExpectations``
///   from the reference build (or the one under test) instead of checking.
/// - `CODEISLAND_BRIDGE_UNDER_TEST=<path>` tests that build instead of the
///   one next to the test bundle.
final class BridgeGoldenTests: XCTestCase {
    /// One process tree for the whole class: launching a freshly copied
    /// executable the first time costs a code-signing check.
    private static var sharedRunner: Result<BridgeGoldenRunner, Error>?

    private var runner: BridgeGoldenRunner!

    override func setUpWithError() throws {
        if Self.sharedRunner == nil {
            Self.sharedRunner = Result { try BridgeGoldenRunner(stub: BridgeGoldenRunner.builtStub(for: Self.self)) }
        }
        runner = try Self.sharedRunner?.get()
    }

    override class func tearDown() {
        if case .success(let runner) = sharedRunner {
            runner.cleanUp()
        }
        sharedRunner = nil
        super.tearDown()
    }

    func testFixtureNamesAreUnique() {
        let names = BridgeGoldenFixtures.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testBridgeReproducesTheRecordedOutput() throws {
        let environment = ProcessInfo.processInfo.environment
        let bridge = try BridgeGoldenRunner.bridgeUnderTest(for: Self.self)
        if let recordPath = environment["CODEISLAND_GOLDEN_RECORD"] {
            let source = environment["CODEISLAND_REFERENCE_BRIDGE"].map { URL(fileURLWithPath: $0) } ?? bridge
            try record(from: source, to: recordPath)
            throw XCTSkip("recorded \(BridgeGoldenFixtures.all.count) expectations to \(recordPath)")
        }
        for fixture in BridgeGoldenFixtures.all {
            guard let expected = BridgeGoldenExpectations.all[fixture.name] else {
                XCTFail("\(fixture.name): no recorded expectation")
                continue
            }
            let run = try runner.run(fixture, bridge: bridge)
            XCTAssertEqual(run.expectation.forwarded, expected.forwarded, "\(fixture.name): forwarded event")
            XCTAssertEqual(run.expectation.stdout, expected.stdout, "\(fixture.name): stdout")
            XCTAssertEqual(run.expectation.status, expected.status, "\(fixture.name): exit status")
        }
    }

    func testBridgeMatchesTheReferenceBuildByteForByte() throws {
        guard let referencePath = ProcessInfo.processInfo.environment["CODEISLAND_REFERENCE_BRIDGE"] else {
            throw XCTSkip("set CODEISLAND_REFERENCE_BRIDGE to compare against another bridge build")
        }
        let bridge = try BridgeGoldenRunner.bridgeUnderTest(for: Self.self)
        let reference = URL(fileURLWithPath: referencePath)
        var identical = 0
        for fixture in BridgeGoldenFixtures.all {
            let expected = try runner.run(fixture, bridge: reference, deterministicHashing: true)
            let actual = try runner.run(fixture, bridge: bridge, deterministicHashing: true)
            XCTAssertEqual(actual.byteSignature, expected.byteSignature, "\(fixture.name)")
            if actual.byteSignature == expected.byteSignature { identical += 1 }
        }
        print("bridge golden: \(identical)/\(BridgeGoldenFixtures.all.count) fixtures byte-identical to \(referencePath)")
    }

    func testExportedJSONFixturesMatchSwiftGoldenSuite() throws {
        if let exportDir = ProcessInfo.processInfo.environment["CODEISLAND_GOLDEN_EXPORT_JSON"] {
            try BridgeGoldenJSONExporter.exportAll(to: URL(fileURLWithPath: exportDir, isDirectory: true))
            throw XCTSkip("exported \(BridgeGoldenFixtures.all.count) fixtures per scope to \(exportDir)")
        }

        let fixturesRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures", isDirectory: true)

        for scope in BridgeGoldenJSONExporter.Scope.allCases {
            let scopeDir = fixturesRoot.appendingPathComponent(scope.rawValue, isDirectory: true)
            let files = try FileManager.default.contentsOfDirectory(at: scopeDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .map { $0.deletingPathExtension().lastPathComponent }
            XCTAssertEqual(
                Set(files),
                Set(BridgeGoldenFixtures.all.map(\.name)),
                "\(scope.rawValue): exported fixture file set must match BridgeGoldenFixtures.all"
            )
        }

        for fixture in BridgeGoldenFixtures.all {
            let expected = try XCTUnwrap(
                BridgeGoldenExpectations.all[fixture.name],
                "\(fixture.name): missing recorded expectation"
            )

            var neutralPayloadsByScope: [BridgeGoldenJSONExporter.Scope: String?] = [:]
            for scope in BridgeGoldenJSONExporter.Scope.allCases {
                let fileURL = fixturesRoot
                    .appendingPathComponent(scope.rawValue, isDirectory: true)
                    .appendingPathComponent("\(fixture.name).json")
                let data = try Data(contentsOf: fileURL)
                let doc = try XCTUnwrap(
                    try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    "\(scope.rawValue)/\(fixture.name): root must be JSON object"
                )

                XCTAssertEqual(doc["name"] as? String, fixture.name)
                XCTAssertEqual(doc["scope"] as? String, scope.rawValue)

                let expectationObj = try XCTUnwrap(doc["expectation"] as? [String: Any])
                XCTAssertEqual(expectationObj["stdout"] as? String, expected.stdout, "\(scope.rawValue)/\(fixture.name): stdout")
                XCTAssertEqual((expectationObj["status"] as? NSNumber)?.int32Value, expected.status, "\(scope.rawValue)/\(fixture.name): status")

                let expectedDoc = try BridgeGoldenJSONExporter.fixtureDocument(
                    fixture: fixture,
                    expectation: expected,
                    scope: scope
                )
                let expectedCanonical = try BridgeGoldenJSONExporter.canonicalJSONString(expectedDoc)
                let actualCanonical = try BridgeGoldenJSONExporter.canonicalJSONString(doc)
                XCTAssertEqual(actualCanonical, expectedCanonical, "\(scope.rawValue)/\(fixture.name): exported JSON mismatch")

                if let fwdObj = expectationObj["forwarded"] as? [String: Any] {
                    if scope == .macos, let expectedRaw = expected.forwarded {
                        XCTAssertEqual(
                            try BridgeGoldenJSONExporter.canonicalJSONString(fwdObj),
                            expectedRaw,
                            "macos/\(fixture.name): byte-identical forwarded payload"
                        )
                    }
                    let stripped = fwdObj.filter { !BridgeGoldenJSONExporter.osTelemetryKeys.contains($0.key) }
                    neutralPayloadsByScope[scope] = try BridgeGoldenJSONExporter.canonicalJSONString(stripped)
                } else {
                    XCTAssertTrue(expectationObj["forwarded"] is NSNull, "\(scope.rawValue)/\(fixture.name): forwarded must be object or null")
                    neutralPayloadsByScope[scope] = nil
                }
            }

            let neutralProjection = neutralPayloadsByScope[.neutral] ?? nil
            for scope in [BridgeGoldenJSONExporter.Scope.macos, .linux, .windows] {
                XCTAssertEqual(
                    neutralPayloadsByScope[scope] ?? nil,
                    neutralProjection,
                    "\(fixture.name): \(scope.rawValue) neutral projection must match neutral/"
                )
            }
        }
    }

    private func record(from bridge: URL, to path: String) throws {
        var lines: [String] = []
        for fixture in BridgeGoldenFixtures.all {
            let expectation = try runner.run(fixture, bridge: bridge).expectation
            let forwarded = expectation.forwarded.map(Self.swiftLiteral) ?? "nil"
            lines.append(
                "        \(Self.swiftLiteral(fixture.name)): .init(\n"
                    + "            forwarded: \(forwarded),\n"
                    + "            stdout: \(Self.swiftLiteral(expectation.stdout)),\n"
                    + "            status: \(expectation.status)\n"
                    + "        ),"
            )
        }
        let source = """
        // Generated by BridgeGoldenTests (CODEISLAND_GOLDEN_RECORD) from the
        // bridge as it was before its interpretation moved into HookIntake.
        // Do not edit by hand: an intended change to the bridge's output is
        // re-recorded and reviewed as a diff.
        enum BridgeGoldenExpectations {
            static let all: [String: BridgeGoldenExpectation] = [
        \(lines.joined(separator: "\n"))
            ]
        }

        """
        try Data(source.utf8).write(to: URL(fileURLWithPath: path))
    }

    /// A raw string literal with enough `#`s for `text`.
    private static func swiftLiteral(_ text: String) -> String {
        var hashes = "#"
        while text.contains("\"" + hashes) || text.contains("\\" + hashes) {
            hashes += "#"
        }
        return hashes + "\"" + text + "\"" + hashes
    }
}
