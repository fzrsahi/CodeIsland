import Foundation

/// Exports ``BridgeGoldenFixtures`` + ``BridgeGoldenExpectations`` into
/// language-neutral and per-OS JSON fixture directories (`fixtures/neutral`,
/// `fixtures/macos`, `fixtures/linux`, `fixtures/windows`) and verifies them.
enum BridgeGoldenJSONExporter {
    enum Scope: String, CaseIterable {
        case neutral
        case macos
        case linux
        case windows
    }

    /// Keys in forwarded payloads that depend on OS-specific process trees,
    /// macOS app bundles, iTerm2, or terminal/TTY metadata.
    static let osTelemetryKeys: Set<String> = [
        "_ppid",
        "_hook_ppid",
        "_term_bundle",
        "_term_app",
        "_tty",
        "_iterm_session",
    ]

    private static let macosOnlyTermApps: Set<String> = [
        "iTerm.app",
        "Apple_Terminal",
    ]

    private static let windowsTermApps: Set<String> = [
        "WezTerm",
    ]

    static func omittedKeys(for scope: Scope, forwarded: [String: Any]) -> Set<String> {
        switch scope {
        case .macos:
            return []
        case .neutral:
            return osTelemetryKeys
        case .linux:
            var keys: Set<String> = ["_term_bundle", "_iterm_session"]
            if let termApp = forwarded["_term_app"] as? String, macosOnlyTermApps.contains(termApp) {
                keys.insert("_term_app")
            }
            return keys
        case .windows:
            var keys: Set<String> = ["_term_bundle", "_iterm_session", "_tty"]
            if let termApp = forwarded["_term_app"] as? String, !windowsTermApps.contains(termApp) {
                keys.insert("_term_app")
            }
            return keys
        }
    }

    static func projectedForwarded(_ forwarded: [String: Any], scope: Scope) -> [String: Any] {
        let omitted = omittedKeys(for: scope, forwarded: forwarded)
        return forwarded.filter { !omitted.contains($0.key) }
    }

    static func parseJSONObject(_ json: String) throws -> [String: Any] {
        let data = Data(json.utf8)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "BridgeGoldenJSONExporter",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Forwarded expectation is not a JSON object"]
            )
        }
        return obj
    }

    static func canonicalJSONString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        return String(decoding: data, as: UTF8.self)
    }

    static func fixtureDocument(
        fixture: BridgeGoldenFixture,
        expectation: BridgeGoldenExpectation,
        scope: Scope
    ) throws -> [String: Any] {
        let ancestors: [[String: Any]] = fixture.ancestors.map { ancestor in
            [
                "path": ancestor.path,
                "arguments": ancestor.arguments,
            ]
        }
        let bundleIdentifiers: [String: String] = scope == .macos ? fixture.bundleIdentifiers : [:]
        let input: [String: Any] = [
            "arguments": fixture.arguments,
            "environment": fixture.environment,
            "stdin": fixture.stdin,
            "ancestors": ancestors,
            "bundle_identifiers": bundleIdentifiers,
            "reply": fixture.reply,
            "files": fixture.files,
            "has_socket": fixture.hasSocket,
        ]

        let forwardedValue: Any
        if let forwardedString = expectation.forwarded {
            let parsed = try parseJSONObject(forwardedString)
            forwardedValue = projectedForwarded(parsed, scope: scope)
        } else {
            forwardedValue = NSNull()
        }

        let expectationObj: [String: Any] = [
            "forwarded": forwardedValue,
            "stdout": expectation.stdout,
            "status": Int(expectation.status),
        ]

        return [
            "name": fixture.name,
            "scope": scope.rawValue,
            "input": input,
            "expectation": expectationObj,
        ]
    }

    static func exportAll(to fixturesRoot: URL) throws {
        let fm = FileManager.default
        for scope in Scope.allCases {
            let scopeDir = fixturesRoot.appendingPathComponent(scope.rawValue, isDirectory: true)
            try fm.createDirectory(at: scopeDir, withIntermediateDirectories: true)

            let expectedNames = Set(BridgeGoldenFixtures.all.map(\.name))
            if let existing = try? fm.contentsOfDirectory(at: scopeDir, includingPropertiesForKeys: nil) {
                for url in existing where url.pathExtension == "json" {
                    let stem = url.deletingPathExtension().lastPathComponent
                    if !expectedNames.contains(stem) {
                        try fm.removeItem(at: url)
                    }
                }
            }

            for fixture in BridgeGoldenFixtures.all {
                guard let expectation = BridgeGoldenExpectations.all[fixture.name] else {
                    throw NSError(
                        domain: "BridgeGoldenJSONExporter",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Missing expectation for \(fixture.name)"]
                    )
                }
                let doc = try fixtureDocument(fixture: fixture, expectation: expectation, scope: scope)
                let data = try JSONSerialization.data(
                    withJSONObject: doc,
                    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                )
                var out = data
                out.append(0x0A) // trailing newline
                let fileURL = scopeDir.appendingPathComponent("\(fixture.name).json")
                try out.write(to: fileURL)
            }
        }
    }
}
