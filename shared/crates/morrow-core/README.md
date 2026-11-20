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

## `markdown`: MarkdownBlockParser

The block structure of an assistant reply (`Sources/MorrowCore/MarkdownBlockParser.swift`):
headings, paragraphs, lists and task items, fenced code, GFM tables, quotes
and thematic breaks, lenient enough for a reply that streams in. Inline spans
stay raw Markdown in the block; nothing here writes HTML — the frontend draws
the blocks. Names are the Swift ones (`MarkdownBlock`, `MarkdownList`,
`MarkdownListItem.Checkbox`, `MarkdownCodeBlock`, `MarkdownTable`,
`MarkdownTableAlignment`, `MAX_NESTING_DEPTH`, `MAX_TABLE_COLUMNS`).

Known difference: Swift counts and splits `Character`s (grapheme clusters),
the port counts and splits `char`s (scalar values).

## `git`: GitBranchReader

The checked-out branch of a session's `cwd`, read from `.git` rather than by
spawning `git` (`Sources/MorrowCore/GitBranchReader.swift`): `GitBranchInfo`,
`read`, `parse_head`, `parse_gitdir_pointer`, `standardize`. Core opens
nothing, so the disk arrives as a `git::Disk` the shell implements; paths go
through `Path`/`PathBuf`, joined and split by segment, so the same walk works
on Windows. Linked worktrees are told apart from submodules by segment
(`.git/worktrees/<name>`), never by a substring of the path.

## `transcript`: JSONLTailer

The live transcript (`Sources/MorrowCore/JSONLTailer.swift`): `scan_lines`
splits a chunk of JSONL on newlines and reports the newest `last_user_prompt`,
`last_assistant_message`, `turn_status`, whether the chunk was activity at all,
and the trailing `CursorQuestionSignal`; the bytes after the last newline come
back as a fragment for the next call. `TailState` is the reading position —
offset, fragment, and one replay of a replaced file — and `scan_tail_for_attach`
is the attach-time backfill. Nothing here opens a file or watches a path: the
platform watcher reads and hands the bytes in.

The delta also carries the agent's checklist (`task_events`): the events
TaskCreate/TaskUpdate, TodoWrite, `update_plan` and the prompt/turn boundaries
carry, in transcript order.

The delta also carries the idle recap and the model tag: `session_recap`
(`SessionRecap`), `model_observation` (`ModelObservation`), and
`configured_long_context` (a `/model` switch turning the 1M context variant on
or off). Their own modules are below.

## `session_recap`, `model_label`, `time`

The three pieces the transcript's readings are made of:

| Swift | Rust |
|---|---|
| `SessionRecap` (`from(transcriptLine:)`, `cleanedText`, `isSuperseded`) | `session_recap.rs` |
| `ModelObservation` (`from`, `fromCodexTurnContext`, `observedAt`, `latestInClaudeTranscript`, `latestCodexTurnContext`), `ModelLabel` (`label`, `displayName`, `mergedModelId`, `withLongContext`, `longContextSwitch`) | `model_label.rs` |
| `ClaudeUsageScanner.parseISO8601` | `time.rs` |

`latest_codex_turn_context` walks the blob backwards in chunks with the row
that straddles a boundary carried over, exactly as the Swift version does over
a file handle — the platform hands in the bytes.

A snapshot absorbs a delta here too: `apply_transcript_delta`,
`apply_transcript_backfill`, `apply_backfilled_model_observation`,
`clear_recap_if_superseded` (called by the reducer's `UserPromptSubmit`),
`visible_recap` and `model_label`, plus the subagent's
`claude_transcript_path` and label. `SessionSnapshot` gained `recap`,
`reasoning_effort` and `configured_long_context` for them — kept, not
projected, exactly as the reducer contract's `projection_omits` says.

## `agent_tasks`: the checklist

The vocabulary (`AgentTaskStatus`, `AgentTaskItem`, `AgentTaskDraft`,
`AgentTaskRowPatch`, `AgentTaskChange`, `AgentTaskEvent`) and — in `parsing` —
`AgentTaskTool`, the argument helpers (`string`, `id_string`, `json_object`,
`drafts`, `row_patches`, `created_task_id_from_result_text`), `hook_events`
and `events_from_line` for transcript rows, plus the backfill `scan` and its
byte prefilter `may_carry_task_event`.

In `list`, `AgentTaskList` is the list those events are applied to: dedupe by
op key, updates parked until their create names the row, undo when a call
fails, retiring a snapshot plan a whole turn went by without, the completion
linger, the attach-time rebuild, and persistence (`to_json` / `from_json`,
Swift's `Codable` keys and its 2001 epoch for `completedAt`). `SessionSnapshot`
carries it as `agent_tasks`: the reducer applies a hook's events, a subagent's
`TaskUpdate` lands on the parent card through `apply_shared_updates`, and
`SessionStart` restores the list unless the hook says `/clear`.

Not ported: reading a transcript file at attach time
(`AgentTaskTranscript.scanFile`) — opening a file belongs to the platform, as
it does for the tailer.

## `installer`: editing a CLI's config file

`installer::json_editor` is `JSONMinimalEditor` (429 lines of Swift): a
`set_top_level_value` / `delete_top_level_key` pair that replaces only the text
range of one top-level key, so comments, key order, escaping, indentation and
the trailing newline all survive, and a document that is not a JSON object at
the top level is refused rather than rewritten (#89). `strip_json_comments`
feeds parses, since Claude Code's `settings.json` is JSONC.

`installer::claude_hooks` is the Claude Code slice of `ConfigInstaller`: the
13-event table with its timeouts and version gates (`PostToolUseFailure` ≥
2.1.89, `StopFailure` ≥ 2.1.78), recognition of our own commands and the names
we used before, `install` (idempotent — a second run over its own output
changes nothing) and `uninstall` (an emptied `hooks` key is deleted, so a file
that held only our entries comes back byte for byte), plus the back-up naming
rule. All of it is a plan over text: the platform reads and writes the file.

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

`tests/markdown_parser.rs` is `MarkdownBlockParserTests` ported test for test
(53 of its 54; the cache test belongs to the macOS app), and
`tests/git_branch_reader.rs` is `GitBranchReaderTests` on an in-memory disk
(9 of 9, plus the depth cap and a standardized `cwd`).

`tests/model_label.rs` is `ModelLabelTests` (22 tests) and
`tests/session_recap.rs` is `SessionRecapTests` (38 of its 39; the one left
asserts the checklist, #136). `tests/agent_task_parsing.rs` is the parsing half of `AgentTaskListTests`
(9 tests) and `tests/agent_task_list.rs` the list half (38; the Swift test that
scans a file on disk has no counterpart here).
`tests/json_minimal_editor.rs` is `JSONMinimalEditorTests` (14 of 14), and
`tests/claude_hooks_installer.rs` is the Claude Code slice of
`ConfigInstallerTests` over text instead of a file system (18 tests: the table,
the version gates, the legacy-name cleanup, install/repair/uninstall and the
back-up rule).

`tests/transcript_tailer.rs` is `JSONLTailerTests` and
`JSONLTailerCursorQuestionTests` ported: 70 tests, all the parsing ones as
they are and the attach/replacement ones driven through `TailState` with the
bytes a watcher would have read. Two Swift tests are the watcher's own and
have no counterpart (a dispatch source that stops firing, a delayed reopen
after a rename).
