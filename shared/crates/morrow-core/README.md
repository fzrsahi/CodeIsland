# morrow-core

The **core** (`GLOSSARY.md`) in Rust: pure domain code the Linux and
Windows shells share. No OS crate, no unsafe code, no environment, file,
process or clock read (`scripts/ci/rust-purity.sh` checks the dependencies).
What the OS knows comes in as values and closures.

## `intake`: HookIntake

What one hook invocation means (`docs/hook-edge-protocol.md`, *What the
island derives*): source, session, event, whether it waits for the answer,
terminal context, the answer's stdout. A faithful port of
`Sources/MorrowCore/HookIntake.swift` and the Swift types it calls, one
file per type, the same names in snake_case:

| Swift (`Sources/MorrowCore/`) | Rust (`src/intake/`) |
|---|---|
| `HookIntake` (`Facts`, `Ancestor`, `EdgeHost`, `AnswerFormat`, `environmentKeys`, `admits`, `immediateStdout`, `stdinObject`, `init`, `addTerminalContext`, `stdout(forAnswer:)`) | `mod.rs` (`Facts`, `Ancestor`, `EdgeHost`, `AnswerFormat`, `ENVIRONMENT_KEYS`, `admits`, `immediate_stdout`, `stdin_object`, `HookIntake::new`, `add_terminal_context`, `stdout_for_answer`) |
| `HookEdgeFacts` (`delivery(in:)`, `facts(from:)`, `mayCarryFacts`) | `hook_edge_facts.rs` (`delivery`, `facts`, `may_carry_facts`) |
| `CLIProcessResolver` (`Models.swift`) | `cli_process_resolver.rs` |
| `SessionSnapshot.supportedSources`, `ideHostSources`, `normalizedSupportedSource` | `session_snapshot.rs` |
| `CustomAgentCommandStore` (the parts intake reads) | `custom_agent_command.rs` |
| `EventNormalizer` | `event_normalizer.rs` |
| `CursorHookPayload` | `cursor_hook_payload.rs` |
| `AntigravityHookContract` | `antigravity_hook_contract.rs` |
| `GrokHookForwardingPolicy`, `GrokSessionPaths` | `grok.rs` |
| `HermesHookPayload.trimmedForForwarding` | `hermes_hook_payload.rs` |
| `HostHarnessResolver.outermostAppBundlePath`, URL path standardizing | `host_harness.rs` |
| `CryptoKit.SHA256` | `src/digest.rs` |

Where Swift reads the OS, the port takes it in:

- `UserDefaults` (custom CLI sources, custom agent commands): a
  `SourceCatalog` in `Facts`, empty by default.
  `default_seeded_commands(home, file_exists)` is what Swift's store holds
  when nothing was saved, as for a bridge.
- `NSString.expandingTildeInPath`: `Facts::expanding_tilde_in_path`
  (unchanged path by default).
- `JSONSerialization`'s NSNumber bridging: `_untracked_process` and
  `_edge.waits` read `1` / `0` as `true` / `false`, as Swift does.

Known differences: Grok's cwd encoding keeps `char::is_alphanumeric`
characters where Swift keeps `CharacterSet.alphanumerics`, which differ on
some combining marks; paths are standardized lexically, never against a
working directory.

## `reduce`: the reducer

`reduceHookEvent`: one hook event applied to the sessions, the lifecycle
`SideEffect`s for the shell, and the `HookEventFacts` the attention policy
reads. The clock, the custom sources and the home directory come in through
`ReduceContext`. `reduceEvent` is the reducer plus the policy's intents put
back where the reducer used to return them (`PlaySound` at the sound slot,
`EnqueueCompletion` at the completion slot).

## `attention`: AttentionPolicy

What a moment calls for before the user's settings and the room have their
say — a sound, a completion card, a push, a follow-up reminder. A faithful
port of `Sources/MorrowCore/AttentionPolicy.swift` and
`EventSoundRouting.swift`:

| Swift | Rust (`src/attention.rs`) |
|---|---|
| `AttentionPolicy.intents(for:subject:)` | `intents` |
| `EventSoundRouting.soundEvent`, `turnFailed` | `sound_event`, `TURN_FAILED` |
| `SoundCue` | `sound_cue` |
| `AttentionMoment`, `TurnEnd`, `TurnHost` | same names |
| `AttentionSubject`, `AttentionIntents`, `AttentionDecision` | `AttentionSubject`, `AttentionIntents` (`AttentionDecision` is `settle`'s) |
| `AttentionPushKind`, `FollowUpIntent`, `FollowUpReminderKind` | same names |

`settle(_:context:)` is **not ported yet**: it reads the user's sound
switches, quiet hours, the lock state, the completion style and Smart
Suppress, which arrive with the `morrow-platform` adapters (plan §5.2), and
no fixture covers it. A shell settles what it has in its own outlets until
then.

## Tests

`tests/conformance.rs` (the port of `HookIntakeGoldenTests.swift`) runs every
fixture of `fixtures/neutral/bridge-golden.json` and of
`fixtures/linux/bridge-golden.json` through HookIntake on injected facts:
the forwarded payload (normalized and projected as the bundles define),
stdout and exit status must match, 84 of 84 in each. `tests/golden/mod.rs`
reads the bundles; morrow-bridge's conformance test shares it.

`tests/attention_conformance.rs` runs the 56 policy cases of
`fixtures/core/attention.json` (a moment and a subject, the intents Swift
returns), and `tests/reducer_conformance.rs` checks the intents of all 161
reducer steps against `fixtures/core/reducer.json` besides the sessions, the
effects and the facts. `tests/contracts/mod.rs` holds the projection both
read.
