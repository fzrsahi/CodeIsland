import Foundation
import XCTest

/// `fixtures/core/` is what the Swift reducer and `AttentionPolicy` do on
/// every case in ``CoreContractCases``: each case runs again here and must
/// produce the file on disk exactly.
///
/// `CODEISLAND_CORE_EXPORT_JSON=<fixtures dir>` rewrites the files instead
/// of checking them.
final class CoreContractTests: XCTestCase {
    func testCaseNamesAreUnique() {
        let reducer = CoreContractCases.reducer.map(\.name)
        let attention = CoreContractCases.attention.map(\.name)
        XCTAssertEqual(Set(reducer).count, reducer.count)
        XCTAssertEqual(Set(attention).count, attention.count)
    }

    func testExportedCoreFixturesMatchSwift() throws {
        if let exportDir = ProcessInfo.processInfo.environment["CODEISLAND_CORE_EXPORT_JSON"] {
            try CoreContractJSONExporter.exportAll(to: URL(fileURLWithPath: exportDir, isDirectory: true))
            throw XCTSkip("exported \(CoreContractCases.reducer.count) reducer and \(CoreContractCases.attention.count) attention cases to \(exportDir)/core")
        }

        let coreDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/core", isDirectory: true)
        let documents = try CoreContractJSONExporter.documents()
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: coreDir.path).filter { $0.hasSuffix(".json") }.sorted(),
            documents.map(\.0).sorted()
        )

        for (filename, document) in documents {
            let onDisk = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: Data(contentsOf: coreDir.appendingPathComponent(filename))) as? [String: Any]
            )
            let diskCases = try XCTUnwrap(onDisk["cases"] as? [[String: Any]])
            let swiftCases = try XCTUnwrap(document["cases"] as? [[String: Any]])
            XCTAssertEqual(diskCases.count, swiftCases.count, "\(filename): case count")
            // Case by case, so a failure names the case that changed.
            for (disk, swift) in zip(diskCases, swiftCases) {
                XCTAssertEqual(
                    try BridgeGoldenJSONExporter.canonicalJSONString(disk),
                    try BridgeGoldenJSONExporter.canonicalJSONString(swift),
                    "\(filename) \(swift["name"] ?? ""): Swift no longer does what the fixture says; rerun with CODEISLAND_CORE_EXPORT_JSON"
                )
            }
            XCTAssertEqual(
                try BridgeGoldenJSONExporter.canonicalJSONString(onDisk),
                try BridgeGoldenJSONExporter.canonicalJSONString(document),
                "\(filename): stale export, rerun with CODEISLAND_CORE_EXPORT_JSON"
            )
        }
    }
}
