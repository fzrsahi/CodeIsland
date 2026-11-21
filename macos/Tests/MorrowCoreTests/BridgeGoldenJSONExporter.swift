import Foundation

/// Exports ``BridgeGoldenFixtures`` + ``BridgeGoldenExpectations`` into
/// `fixtures/{neutral,macos,linux,windows}/bridge-golden.json` and provides
/// canonicalization helpers for verification.
///
/// `neutral/` holds each fixture's `input` plus the OS-independent
/// expectation; the per-OS bundles hold only `name` + `expectation` and refer
/// to the neutral fixture by name. Every bundle records which forwarded keys
/// (`omitted_keys`) and which key values (`omitted_values`) its projection
/// drops from the macOS recording. This enum is the only place those rules
/// live; `scripts/validate-fixtures.py` reads them back from the bundles.
enum BridgeGoldenJSONExporter {
    enum Scope: String, CaseIterable {
        case neutral
        case macos
        case linux
        case windows
    }

    static let bundleFilename = "bridge-golden.json"

    /// Telemetry a macOS recording cannot vouch for on another OS:
    /// app bundle ids, iTerm2 sessions and `/dev/ttysNNN` names.
    private static let macosTelemetryKeys: Set<String> = [
        "_term_bundle",
        "_iterm_session",
        "_tty",
    ]

    /// `TERM_PROGRAM` values that only exist on macOS.
    private static let macosOnlyTermApps: Set<String> = ["iTerm.app", "Apple_Terminal"]

    /// `TERM_PROGRAM` values that exist on Windows.
    private static let windowsTermApps: Set<String> = ["WezTerm"]

    /// Unix-only terminals and multiplexers, plus plugin-forwarded `_env`
    /// (recorded from macOS processes), that a Windows bridge never reports.
    private static let unixOnlyTerminalKeys: Set<String> = [
        "_tmux",
        "_tmux_pane",
        "_tmux_client_tty",
        "_kitty_window",
        "_zellij",
        "_zellij_pane_id",
        "_zellij_session_name",
        "_cmux_surface_id",
        "_cmux_workspace_id",
        "_herdr_pane_id",
        "_herdr_socket_path",
        "_herdr_bin_path",
        "_env",
    ]

    /// Every `_term_app` value the recorded expectations contain.
    private static var recordedTermApps: Set<String> {
        Set(BridgeGoldenExpectations.all.values.compactMap { expectation in
            expectation.forwarded
                .flatMap { try? parseJSONObject($0) }
                .flatMap { $0["_term_app"] as? String }
        })
    }

    /// Forwarded keys a scope drops entirely. `neutral` drops the union of
    /// every OS's omissions, so each OS bundle projected through it equals
    /// the neutral expectation.
    static func omittedKeys(for scope: Scope) -> Set<String> {
        switch scope {
        case .macos:
            return []
        case .linux:
            return macosTelemetryKeys
        case .windows:
            return macosTelemetryKeys.union(unixOnlyTerminalKeys)
        case .neutral:
            return macosTelemetryKeys.union(unixOnlyTerminalKeys).union(["_term_app"])
        }
    }

    /// Forwarded keys a scope keeps only when the value is not listed.
    static func omittedValues(for scope: Scope) -> [String: Set<String>] {
        switch scope {
        case .macos, .neutral:
            return [:]
        case .linux:
            return ["_term_app": macosOnlyTermApps]
        case .windows:
            return ["_term_app": recordedTermApps.subtracting(windowsTermApps)]
        }
    }

    static func projectedForwarded(_ forwarded: [String: Any], scope: Scope) -> [String: Any] {
        let keys = omittedKeys(for: scope)
        let values = omittedValues(for: scope)
        return forwarded.filter { key, value in
            if keys.contains(key) { return false }
            if let dropped = values[key], let string = value as? String, dropped.contains(string) { return false }
            return true
        }
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

    static func inputDocument(_ fixture: BridgeGoldenFixture) -> [String: Any] {
        [
            "arguments": fixture.arguments,
            "environment": fixture.environment,
            "stdin": fixture.stdin,
            "ancestors": fixture.ancestors.map { ["path": $0.path, "arguments": $0.arguments] },
            "bundle_identifiers": fixture.bundleIdentifiers,
            "reply": fixture.reply,
            "files": fixture.files,
            "has_socket": fixture.hasSocket,
        ]
    }

    static func expectationDocument(_ expectation: BridgeGoldenExpectation, scope: Scope) throws -> [String: Any] {
        var forwarded: Any = NSNull()
        if let raw = expectation.forwarded {
            forwarded = projectedForwarded(try parseJSONObject(raw), scope: scope)
        }
        return [
            "forwarded": forwarded,
            "stdout": expectation.stdout,
            "status": Int(expectation.status),
        ]
    }

    static func bundleDocument(scope: Scope) throws -> [String: Any] {
        let fixtures: [[String: Any]] = try BridgeGoldenFixtures.all.map { fixture in
            guard let expectation = BridgeGoldenExpectations.all[fixture.name] else {
                throw NSError(
                    domain: "BridgeGoldenJSONExporter",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Missing expectation for \(fixture.name)"]
                )
            }
            var doc: [String: Any] = [
                "name": fixture.name,
                "expectation": try expectationDocument(expectation, scope: scope),
            ]
            if scope == .neutral {
                doc["input"] = inputDocument(fixture)
            }
            return doc
        }
        return [
            "scope": scope.rawValue,
            "omitted_keys": omittedKeys(for: scope).sorted(),
            "omitted_values": omittedValues(for: scope).mapValues { $0.sorted() },
            "fixtures": fixtures,
        ]
    }

    static func exportAll(to fixturesRoot: URL) throws {
        let fm = FileManager.default
        for scope in Scope.allCases {
            let scopeDir = fixturesRoot.appendingPathComponent(scope.rawValue, isDirectory: true)
            try fm.createDirectory(at: scopeDir, withIntermediateDirectories: true)

            if let existing = try? fm.contentsOfDirectory(at: scopeDir, includingPropertiesForKeys: nil) {
                for url in existing where url.pathExtension == "json" && url.lastPathComponent != bundleFilename {
                    try fm.removeItem(at: url)
                }
            }

            let bundle = try bundleDocument(scope: scope)
            var out = try JSONSerialization.data(
                withJSONObject: bundle,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            out.append(0x0A) // trailing newline
            try out.write(to: scopeDir.appendingPathComponent(bundleFilename))
        }
    }
}
