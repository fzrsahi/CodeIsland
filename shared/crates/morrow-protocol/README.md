# morrow-protocol

The wire shapes of the **contract** (`GLOSSARY.md`) in Rust: the forwarded
hook payload, an edge's `_edge` facts, and the versioned **envelope** that
reaches the **endpoint**. Part of the **core**: no OS crate, no unsafe code
(`scripts/ci/rust-purity.sh` enforces the first).

| Item | Schema |
|---|---|
| `HookPayload`, `decode_payload`, `encode_payload` | `schemas/hook-payload.schema.json` |
| `EdgeFacts`, `EdgeHost`, `EdgePayload` | `$defs/edgeFacts`, `$defs/edgePayload` in `schemas/hook-envelope.schema.json` |
| `Envelope`, `decode_envelope`, `encode_envelope` | `schemas/hook-envelope.schema.json` (`ipcEnvelopeV1` or `edgePayload`) |
| `ProtocolError` | why bytes are none of these |

## Owns

- Decoding bytes into these shapes, checking exactly what the schemas state:
  required keys, the types of documented keys, `_edge.ppid` forbidden, no key
  but `v` and `payload` in an IPC envelope.
- Versioning: an IPC envelope with `v` other than `1` is
  `ProtocolError::UnsupportedVersion`; `_edge` facts of any `v >= 1` are read
  for the fields this build knows (`docs/hook-edge-protocol.md`,
  *Compatibility*).
- Lossless encoding: every key, known or not, written back in the order it
  arrived (`serde_json` with `preserve_order`).

## Does not own

- What a **hook event** means (source, session, whether it waits): that is
  HookIntake, `morrow-core`'s `intake`.
- Endpoint resolution, sockets, pipes and peer verification: `morrow-ipc`.
- Reading stdin, process ancestry, tty: `morrow-bridge`.

## Tests

`tests/conformance.rs` runs every golden fixture (`fixtures/*/bridge-golden.json`,
exported from the Swift suite) through decode and encode and compares the
bytes. The fixture root is the `FIXTURE_ROOT` constant there, the one place
to change when #86 moves the fixtures to `shared/contract/fixtures`.
`tests/errors.rs` covers what the schemas refuse.
