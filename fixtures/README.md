# Golden Fixtures (Frozen Contract)

Exported from [`Tests/MorrowCoreTests/BridgeGoldenFixtures.swift`](../Tests/MorrowCoreTests/BridgeGoldenFixtures.swift) and [`Tests/MorrowCoreTests/BridgeGoldenExpectations.swift`](../Tests/MorrowCoreTests/BridgeGoldenExpectations.swift) by [`BridgeGoldenJSONExporter.swift`](../Tests/MorrowCoreTests/BridgeGoldenJSONExporter.swift) as one `bridge-golden.json` bundle per scope.

These bundles cover the bridge (`morrow-bridge`) only; reducer and `AttentionPolicy` fixtures come in Phase 2.

## Layout

- `neutral/bridge-golden.json` holds every fixture's `input` (arguments, environment, stdin, process ancestry, reply, files) and its OS-independent `expectation`.
- `macos/`, `linux/`, `windows/bridge-golden.json` hold only `name` + `expectation` per fixture. The `name` refers to the fixture in `neutral/`, which supplies the input.
- Each bundle has top-level `omitted_keys` (forwarded keys the scope drops from the macOS recording) and `omitted_values` (keys kept only when the value is not listed). The rules live in `BridgeGoldenJSONExporter.swift` and nowhere else.

| Scope | Drops |
|---|---|
| `macos` | nothing: byte-identical to `BridgeGoldenExpectations.all` |
| `linux` | `_term_bundle`, `_iterm_session`, `_tty` (a macOS `/dev/ttysNNN` name), `_term_app` = `iTerm.app` / `Apple_Terminal` |
| `windows` | the linux keys plus tmux, kitty, zellij, cmux, herdr keys and `_env`; `_term_app` unless `WezTerm` |
| `neutral` | every key any OS drops, plus `_term_app` |

`_ppid` and `_hook_ppid` are neutral: their values are already tokens (`$PID0`), and every hook edge carries `_ppid`. Projecting any OS bundle through the neutral `omitted_keys` yields the neutral expectation exactly.

## Regenerating and Validating

```bash
CODEISLAND_GOLDEN_EXPORT_JSON="$(pwd)/fixtures" swift test --filter BridgeGoldenTests/testExportedJSONFixturesMatchSwiftGoldenSuite
swift test --filter BridgeGoldenTests
pip install -r scripts/requirements-fixtures.txt
python3 scripts/validate-fixtures.py
```

Schemas live in [`schemas/`](../schemas/).
