# shared/

Code and contracts used by more than one OS. `shared/contract/` holds the hook-edge protocol, the JSON schemas, the golden fixtures and their validators that the Swift (macOS), Rust and C# edges are all tested against; `shared/ci/` holds CI scripts that are not tied to one platform. The Rust crates (`shared/crates/`), the Tauri app for Windows and Linux (`shared/desktop/`), the hook plugins and the BLE protocol move in here in later PRs (see `docs/plan-windows-linux.md` §4).
