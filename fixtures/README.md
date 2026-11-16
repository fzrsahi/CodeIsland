# Golden Fixtures (Frozen Contract)

Exported from [`Tests/CodeIslandCoreTests/BridgeGoldenFixtures.swift`](../Tests/CodeIslandCoreTests/BridgeGoldenFixtures.swift) and [`Tests/CodeIslandCoreTests/BridgeGoldenExpectations.swift`](../Tests/CodeIslandCoreTests/BridgeGoldenExpectations.swift) by [`BridgeGoldenJSONExporter.swift`](../Tests/CodeIslandCoreTests/BridgeGoldenJSONExporter.swift) as one `bridge-golden.json` bundle per scope.

## Scopes

- `neutral/bridge-golden.json` — OS-independent expectations. Omits OS-specific telemetry keys: `_ppid`, `_hook_ppid`, `_term_bundle`, `_term_app`, `_tty`, `_iterm_session`. Stripping those keys from `macos`, `linux`, or `windows` must yield the exact `neutral` payload.
- `macos/bridge-golden.json` — Full macOS bridge expectations, byte-identical to `BridgeGoldenExpectations.all`.
- `linux/bridge-golden.json` — Linux expectations. Keeps `_ppid`, `_hook_ppid`, `_tty`, and cross-platform `_term_app` (`tmux`, `ghostty`, `WezTerm`); omits macOS-only `_term_bundle`, `_iterm_session`, and macOS-only `_term_app` (`iTerm.app`, `Apple_Terminal`).
- `windows/bridge-golden.json` — Windows expectations. Keeps `_ppid`, `_hook_ppid`, and Windows-valid `_term_app` (`WezTerm`); omits `_term_bundle`, `_iterm_session`, POSIX `_tty`, and non-Windows `_term_app`.

## Regenerating and Validating

```bash
CODEISLAND_GOLDEN_EXPORT_JSON="$(pwd)/fixtures" swift test --filter BridgeGoldenTests/testExportedJSONFixturesMatchSwiftGoldenSuite
swift test --filter BridgeGoldenTests
python3 scripts/validate-fixtures.py
```

Schemas live in [`schemas/`](../schemas/).
