# Option E experiment: `MorrowCore` on Linux (#85)

Date: 2026-11-19. Spec #82, decision rule in [ADR-0001](../adr/0001-two-cores-one-contract.md#decision-rule). Result: [ADR-0003](../adr/0003-swift-core-sidecar.md) (proposed).

## Verdict

`MorrowCore` builds on Linux (Swift 6.2.4, Ubuntu 22.04, aarch64) after shims in 16 of its 73 files. **973 of 1,005 pure-logic core tests pass (96.8%)**. None fail at runtime; the 30 that don't pass are in three suites that can't compile on Linux, and 2 more are skipped by the environment. The work took about 30 minutes of wall-clock time, well inside the 2-day timebox. Both ADR-0001 conditions are met, so ADR-0003 (Option E, Swift core as a sidecar) is written as **proposed**, pending maintainer acceptance.

Three stubs remain. They are blockers for a real port, but none comes from a gap in Foundation's core types or in Glibc:

| Blocker | File | Cause | What a real port needs |
|---|---|---|---|
| No vnode `DispatchSource` | `JSONLTailer.swift` | libdispatch on Linux has no `makeFileSystemObjectSource` | inotify watcher (stand-in polls every 250 ms; 44/46 tailer tests pass, the 2 file-replacement tests fail) |
| No `AttributedString(markdown:)` | `ChatMessageTextFormatter.swift` | swift-foundation on Linux has no markdown parser | render from `MarkdownBlockParser` blocks (which the Tauri frontend needs anyway), or a markdown dependency |
| No `inlinePresentationIntent` | `MarkdownPreviewText.swift` | Darwin-only Foundation attribute scope | same as above |

**Windows is unmeasured.** Nothing here says anything about Foundation on Windows, AF_UNIX/named pipes, or the Swift runtime on Windows. x86_64 Linux is also unmeasured; only aarch64 was built.

## Method

1. Image `swift:6.2-jammy` (digest `sha256:aa6e815df6d63c995a8e434fa81921295ec7b9dbdf2e5c8d4568935f312c2549`), `swift --version` = `Swift version 6.2.4 (swift-6.2.4-RELEASE)`, `Target: aarch64-unknown-linux-gnu`. A derived image adds `libsqlite3-dev` 3.37.2-2ubuntu0.8. `run.sh` installs it with apt-get instead.
2. Sources exported with `git archive` (no worktree) from `origin/main` @ `07db5f67d4c556c61e64975ad65a482c138c784d`: `Sources/MorrowCore` (73 files, 21,699 LOC), `Tests/MorrowCoreTests`, `Tests/TestDefaultsReset`.
3. A minimal [`Package.swift`](option-e/Package.swift) with `MorrowCore`, `TestDefaultsReset` and `MorrowCoreTests`, plus `CSQLite` (system library), `swift-crypto` 3.15.1 (Linux only), and a tiny `opte-probe` executable for the release measurement.
4. Baseline build of the unmodified sources, then shim layer by layer until green. All edits are in [`option-e/shims.patch`](option-e/shims.patch) (`diff -ruN` exported vs shimmed). No product source on any branch was changed.
5. Test build, then `swift test` serially with the macOS-bound suites skipped. A second, informational run covers the skipped suites.
6. A cold debug build in a fresh volume for timings, then a static release build of `opte-probe`.

Resource limits (dev laptop: 8 GB RAM, 6 cores): Colima VM with 2 CPU / 2 GiB; every container ran with `--cpus 2 --memory 1800m --memory-swap 3g`; every build used `swift build -j 1` and every test run was serial. One heavy command at a time. No step was OOM-killed, so the `-num-threads 1` fallback never ran. Colima only mounts `$HOME`, so sources are streamed into the container with `tar` rather than bind-mounted.

## Baseline errors

The unmodified build stops at `emit-module` on the first missing module, so each layer was fixed to reveal the next.

| Layer | Unique errors | Files | Cause |
|---|---|---|---|
| 0: unmodified | 1 reported (`no such module 'Darwin'`, `AgentTaskParsing.swift:2`) | 10 by static scan | 6 `import Darwin` (`AgentTaskParsing`, `BridgeLog`, `HookOrigin`, `JSONLTailer`, `PrivateFiles`, `SocketPath`), 2 `import SQLite3` (`HermesSessionStore`, `WarpPaneResolver`), 2 `import CryptoKit` (`CursorHookPayload`, `PushChannel`); 3 more need `FoundationNetworking` for `URLSession` (`ClaudeQuotaClient`, `PushChannel`, `PushTransport`) |
| 1: imports fixed | 28 | 9 | see breakdown below |
| 2: layer 1 fixed | 2 | 1 | `struct ucred` not exported by Glibc (`SocketPath.swift`) |
| 3 | **0, green** | | |

Layer 1, grouped by cause:

| Cause | Errors | Files |
|---|---|---|
| libdispatch: no vnode `DispatchSource` | 8 | `JSONLTailer` |
| Foundation: `AttributedString(markdown:)` / `inlinePresentationIntent` missing | 7 | `ChatMessageTextFormatter` (3), `MarkdownPreviewText` (4) |
| Module-qualified calls (`Darwin.connect/send/recv/write/lstat`) | 5 | `AiWorkWatchClient` (3), `PrivateFiles`, `SocketPath` |
| Glibc: `memmem` not exported (`_GNU_SOURCE`), plus 1 cascade | 3 | `AgentTaskParsing` |
| Glibc types: `SOCK_STREAM` is an enum, no `SO_NOSIGPIPE` | 2 | `AiWorkWatchClient` |
| No `getpeereid` | 1 | `SocketPath` |
| CoreFoundation: `CFNumberIsFloatType` not exported | 1 | `CodexAppServerClient` |
| FoundationNetworking: `waitsForConnectivity` is get-only | 1 | `PushTransport` |

Test target: 1 error unmodified (`import Darwin` in `BridgeLogTests`), then 47 unique errors in 7 files: 26 missing `FoundationNetworking` import (`ClaudeQuotaTests`, `PushSigningAndResponseTests`), 9 Glibc socket differences (`SocketPathHolderTests`, `BridgeGoldenHarness`), 2 `CFGetTypeID`/`CFBooleanGetTypeID` (`BridgeGoldenHarness`), and 10 `inlinePresentationIntent` (`ChatMessageTextFormatterTests`, `MarkdownInlineLiteralsTests`, `MarkdownPreviewTextTests`). `TestDefaultsReset.c` (CFPreferences) is guarded with `#ifdef __APPLE__`.

## Shims

ADR-0001 estimated ~13 of 73 files. The real number is **16 of 73 core files** (+146/−7 LOC), plus a 2-file `CSQLite` module. Tests: 9 files changed (+63/−9), 3 excluded, and `TestDefaultsReset.c` guarded (+4).

| File | Kind | +LOC |
|---|---|---|
| `AgentTaskParsing.swift` | Darwin→Glibc import; `memmem` bound with `@_silgen_name` | 9 |
| `AiWorkWatchClient.swift` | `SOCK_STREAM` cast, `MSG_NOSIGNAL` instead of `SO_NOSIGPIPE`, `sysConnect/sysSend/sysRecv` wrappers | 22 (−4) |
| `BridgeLog.swift` | Darwin→Glibc import | 4 |
| `ChatMessageTextFormatter.swift` | **stub**: raw text, no inline markdown (TODO, blocker) | 6 |
| `ClaudeQuotaClient.swift` | `FoundationNetworking` import | 3 |
| `CodexAppServerClient.swift` | `CFNumberIsFloatType` → `NSNumber.objCType` `d`/`f` | 6 |
| `CursorHookPayload.swift` | CryptoKit → `Crypto` (swift-crypto) | 4 |
| `HermesSessionStore.swift` | SQLite3 → `CSQLite` | 4 |
| `HookOrigin.swift` | Darwin→Glibc import | 4 |
| `JSONLTailer.swift` | Darwin→Glibc import; **stub**: 250 ms timer source instead of vnode source, no delete/rename/revoke (TODO, blocker) | 35 (−3) |
| `MarkdownPreviewText.swift` | **stub**: no heading/code styling (TODO, blocker) | 6 |
| `PrivateFiles.swift` | Darwin→Glibc import; `Glibc.write` | 8 |
| `PushChannel.swift` | CryptoKit → `Crypto`; `FoundationNetworking` import | 7 |
| `PushTransport.swift` | `FoundationNetworking` import; skip `waitsForConnectivity` | 5 |
| `SocketPath.swift` | Darwin→Glibc import; `Glibc.lstat`; `getpeereid` → `SO_PEERCRED` with a local `ucred` | 19 |
| `WarpPaneResolver.swift` | SQLite3 → `CSQLite` | 4 |
| `Sources/CSQLite/` | `systemLibrary` module map + header | 6 |

`getpeereid` was not stubbed: `SO_PEERCRED` is the Linux equivalent the plan already names, and `SocketPathHolderTests` passes with it (6 pass, 2 skipped because they look for macOS system sockets). It is not counted as a blocker.

swift-crypto cost: 2 extra packages (`swift-crypto` 3.15.1, `swift-asn1` 1.7.4), 371 compile steps (BoringSSL), **62–78 s** fetch + compile cold at `-j 1`. That is longer than `MorrowCore` and its tests combined.

## Tests

Denominator ("pure-logic core tests"): every XCTest method in `Tests/MorrowCoreTests` at the measured commit (1,117), minus the suites the issue names as macOS-bound and the benchmarks:

| Excluded suite | Tests | Why |
|---|---|---|
| `BridgeGoldenTests` | 3 | runs the `morrow-bridge` binary and `morrow-golden-stub`, not built here |
| `BridgeLogTests` | 11 | Darwin file APIs |
| `PrivateFilesTests` | 15 | Darwin file APIs |
| `SocketPathHolderTests` | 8 | Darwin sockets |
| `JSONLTailerTests` | 46 | vnode `DispatchSource` |
| `JSONLTailerCursorQuestionTests` | 24 | vnode `DispatchSource` |
| `PerformanceBenchmarks` | 5 | benchmarks, not logic |

Denominator = 1,117 − 112 = **1,005 tests in 79 suites**. The SQLite suites (`HermesSessionStoreTests`, `WarpPaneResolverTests`) are in the denominator because SQLite was shimmed.

| | Tests |
|---|---|
| Executed | 975 |
| Passed | **973** |
| Failed at runtime | 0 |
| Skipped by environment | 2 (`ConfigPathIdentityTests`: container runs as root; case-sensitive volume) |
| Not compilable, counted as failed | 30 (`ChatMessageTextFormatterTests` 6, `MarkdownInlineLiteralsTests` 7, `MarkdownPreviewTextTests` 17) |
| **Pass rate** | **973 / 1,005 = 96.8%** |

Suites in the denominator: AgentTaskListTests, AiWorkWatchClientTests, AntigravityHookContractTests, AppDistributionTests, AppleCompanionPayloadCompatTests, AppleCompanionPayloadTests, AttentionPolicyTests, BridgeSourceTests, CLIProcessResolverTests, ChatMessageTextFormatterTests (failed), ClaudeConfigPathsTests, ClaudeQuotaSchedulerTests, ClaudeQuotaTests, ClaudeUsageMultiRootTests, ClaudeUsageScannerTests, ClosedSubagentIdsCapTests, CodexAppServerClientTests, CodexNativeSubagentRoutingTests, CodexRichStatusTests, CodexThreadSubsessionTests, ConfigPathIdentityTests, ConfigRootDiscoveryTests, CoworkAuditLogTests, CoworkSessionTests, CursorHookPayloadTests, CursorSessionFoldingTests, CursorSubagentTranscriptIndexTests, DeclaredSubsessionTests, DerivedSessionStateTests, DisplayOnlyWaitPushFormatTests, DisplayOnlyWaitSchedulerTests, DisplayOnlyWaitTests, ESP32ProtocolTests, ExtraConfigDirsTests, FollowUpReminderSchedulerTests, GitBranchReaderTests, GrokHookForwardingPolicyTests, HermesHookFlowTests, HermesSessionStoreTests, HijriCalendarTests, HookEdgeFactsTests, HookEventFactsTests, HookEventToolUseIdTests, HookIntakeGoldenTests, HookOriginTests, HostHarnessResolverTests, IslandDisplayModeTests, KimiHookPayloadTests, MarkdownBlockParserTests, MarkdownInlineLiteralsTests (failed), MarkdownPreviewTextTests (failed), MiMoSourceTests, ModelLabelTests, MultiplexerEnvCaptureTests, NotchHoopsEngineTests, OfflineCityDatabaseTests, OutOfOrderToolStepTests, PiAgentEventFlowTests, PrayerTimeCalculatorTests, PromptTextCleanerTests, PushChannelPayloadTests, PushMessageFormatterTests, PushPolicyTests, PushRedactionTests, PushSigningAndResponseTests, RemoteHookLocalFieldsTests, RemoteReconnectPolicyTests, ReplyCompletePlaceholderTests, SceneMuteStateTests, SessionHeadlineTests, SessionMultiplexerLabelTests, SessionRecapTests, SessionSnapshotTitleTests, SoundVolumeCurveTests, SubsessionReducerTests, SubsessionRouterTests, TraeHookPayloadTests, TurnFailureSoundTests, WarpPaneResolverTests.

The contract-relevant suites named in spec #82 all pass: `AttentionPolicyTests` 9/9, `SubsessionReducerTests` 6/6, `CursorSessionFoldingTests` 34/34, `HookIntakeGoldenTests` 2/2.

Informational run of the excluded suites (107 tests, not in the percentage): `BridgeLogTests` 11/11, `PrivateFilesTests` 15/15, `SocketPathHolderTests` 6 pass + 2 skipped, `JSONLTailerCursorQuestionTests` 24/24, `JSONLTailerTests` 44/46 (the two failures, `testDetachCancelsDelayedReattachAfterFileReplacement` and `testFileReplacementReattachesWhenSessionRemainsDesired`, are exactly the delete/rename events the polling stand-in can't see), `BridgeGoldenTests` 0/3 (bridge binaries not built). Across all 1,117 tests: 1,073 pass (96.1%), 35 fail or can't compile, 4 skipped, 5 benchmarks not run.

## Sizes and timings

All at `--cpus 2 --memory 1800m`, `-j 1`, Colima on an Apple-silicon Mac (aarch64 Linux guest). Where two values are given, the first comes from the interactive measurement runs (output read from the terminal, not archived) and the second from the archived `run.sh` run. Only the `run.sh` output was saved as a log.

| Measurement | Result |
|---|---|
| Cold debug build: swift-crypto fetch + compile | 62 s (78 s in the second, `run.sh` measurement) |
| Cold debug build: `MorrowCore` | 10–11 s |
| Cold debug build: test target | 13 s |
| Incremental rebuild of `MorrowCore` after a shim | ~9 s |
| Pure-logic test run | 6.6 s |
| `.build` size after debug build + tests | 279 MB |
| cgroup `memory.peak`, debug build | 460 MiB |
| `swift build -c release --static-swift-stdlib -j 1 --product opte-probe`, cold | **84–86 s, works (not OOM-killed)** |
| cgroup `memory.peak`, release build | 731–771 MiB (page cache included) |
| cgroup `memory.peak`, whole `run.sh` container | 983 MiB |
| `opte-probe` size | 90,134,760 B (86 MB); **60,513,880 B (58 MB) stripped** |
| `opte-probe` dynamic libraries | 37 per `ldd` (no Swift libraries; `libsqlite3`, `libcurl` and its TLS/Kerberos chain via FoundationNetworking, `libstdc++`, glibc) |

`opte-probe` links all of `MorrowCore` and runs (`markdown blocks: 2; git branch: none`). `--static-swift-stdlib` removes the Swift runtime dependency but not `libsqlite3` or `libcurl`. A sidecar would ship those as distro package dependencies or link them statically, which this experiment did not try.

## What this does not answer

- **Windows.** Unmeasured. ADR-0001 lists Foundation-on-Windows maturity and the Swift runtime on Windows as Option E's main costs; neither was tested.
- **x86_64 Linux.** Only aarch64 was built.
- **App-held domain logic** (~15–18K LOC in `Sources/Morrow`: `ConfigInstaller`, `Discovery/`, `HookServer`, …; plan §5.1). It was not built. `ConfigInstaller.swift` imports AppKit and Yams, `HookServer.swift` imports `os.log`.
- **The bridge.** `Sources/MorrowBridge/main.swift` uses `proc_pidpath`/`sysctl` and was not built; `BridgeGoldenTests` needs it.
- **The sidecar boundary.** The JSON-lines protocol between a Swift core process and the Tauri shell does not exist yet, and its latency against the `E2E-1` <300 ms gate is unmeasured.
- **Static linking of SQLite/curl**, and the size of a sidecar that also carries the app-held logic.

## Reproduction

```bash
# from a checkout of this branch; needs git, patch, docker (Colima works)
docs/experiments/option-e/run.sh            # pinned to 07db5f6
REF=origin/main docs/experiments/option-e/run.sh
```

[`run.sh`](option-e/run.sh) exports the sources, copies [`Package.swift`](option-e/Package.swift), applies [`shims.patch`](option-e/shims.patch), streams the tree into one `swift:6.2-jammy` container (`--cpus 2 --memory 1800m --memory-swap 3g`), installs `libsqlite3-dev`, and runs the cold build, both test runs and the static release probe at `-j 1`. It exits non-zero when a pure-logic test fails. Measured run: 221 s wall-clock, exit 0.
