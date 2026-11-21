# Golden Fixtures (Frozen Contract)

Exported from [`macos/Tests/MorrowCoreTests/BridgeGoldenFixtures.swift`](../../../macos/Tests/MorrowCoreTests/BridgeGoldenFixtures.swift) and [`macos/Tests/MorrowCoreTests/BridgeGoldenExpectations.swift`](../../../macos/Tests/MorrowCoreTests/BridgeGoldenExpectations.swift) by [`BridgeGoldenJSONExporter.swift`](../../../macos/Tests/MorrowCoreTests/BridgeGoldenJSONExporter.swift) as one `bridge-golden.json` bundle per scope.

The bridge bundles cover `morrow-bridge`. The core contract (reducer and `AttentionPolicy`) is in [`core/`](#core-contract-core).

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

## Core Contract (`core/`)

Exported from [`CoreContractCases.swift`](../../../macos/Tests/MorrowCoreTests/CoreContractCases.swift) by [`CoreContractJSONExporter.swift`](../../../macos/Tests/MorrowCoreTests/CoreContractJSONExporter.swift), which runs every case through Swift. `CoreContractTests` runs them again and fails when Swift no longer produces the files.

- `core/reducer.json`: per case, the initial `sessions` and ordered `steps`. Each step is a raw hook `event` (as the bridge forwards it) and what `reduceHookEvent` left: every session, the lifecycle `effects`, the `facts`, and the `AttentionPolicy.intents` for those facts with the event's session as `subject`. Case inputs: `max_history`, `reply_complete_placeholder`, `custom_sources`.
- `core/attention.json`: `AttentionPolicyTests`' intent rows, each a `moment` and `subject` with the `intents` Swift returns.

A port reproduces both. The reducer's effects never include `playSound` or `enqueueCompletion`: those are the policy's intents.

| Rule | |
|---|---|
| Clock | `$T0` is the time the initial sessions were built, `$Tk` the time step k (1-based) was applied: every clock read during step k returns `$Tk`. A fixed seeded instant is ISO 8601. |
| Configuration | A case's `custom_sources` are the user's custom CLI sources (`custom_cli_configs_v1`) for that case; custom agent commands are none. |
| Sessions | `SessionSnapshot` in snake_case. `status`, `source`, `start_time` and `last_activity` are always present; any other field is absent while nil, false, zero or empty. `projection_omits` lists the state left out (set outside the reducer, or generated per value). |
| Tags | Enums (`status`, effect and moment `type`, push kinds) use the Swift case names. |

Bridge golden payloads are reused as events with `$PIDn` as pid 4242+n and `$ROOT` as `/tmp/golden`.

## Regenerating and Validating

```bash
CODEISLAND_GOLDEN_EXPORT_JSON="$(pwd)/shared/contract/fixtures" swift test --package-path macos --filter BridgeGoldenTests/testExportedJSONFixturesMatchSwiftGoldenSuite
swift test --package-path macos --filter BridgeGoldenTests
CODEISLAND_CORE_EXPORT_JSON="$(pwd)/fixtures" swift test --filter CoreContractTests/testExportedCoreFixturesMatchSwift
swift test --filter CoreContractTests
pip install -r shared/contract/requirements-fixtures.txt
python3 shared/contract/validate-fixtures.py
```

Schemas live in [`shared/contract/schemas/`](../schemas/).
