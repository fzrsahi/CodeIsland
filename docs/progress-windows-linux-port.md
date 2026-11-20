# Progress — Windows & Linux port

**Status:** fase 1 selesai di PR (#120–#125, gate E2E-1 hijau di Xvfb, menunggu X11 nyata); fase 2 (#127, #128, #130, #131, #132, #133). Core = **Rust** (#117).
**Checkpoint terakhir:** 2026-11-20 — PR #133 dibuka untuk #97 (transcript tail di `morrow-core`: 70 test, `TailState` murni untuk offset/rotasi).
**Fase kanonik:** [`plan-windows-linux.md`](plan-windows-linux.md) §7. Kalau dokumen ini berbeda dengan §7, §7 yang benar.

---

## Kalau kamu baru masuk, jawab tiga ini dulu

1. **Fase mana yang sedang berjalan?** → kolom Status di papan di bawah.
2. **Apa gate-nya?** → §7 plan, atau kolom Gate.
3. **Apa yang memblokir?** → entri teratas di Log Checkpoint.

---

## Cara pakai dokumen ini

- Update setelah setiap PR dibuka, di-merge, atau gagal — dan saat berhenti.
- Jangan hapus baris. Ubah Status, atau tambah baris kalau PR dipecah.
- Log Checkpoint append-only, terbaru di atas, tiga baris: *sudah*, *berikutnya*, *blocker*.

---

## Papan status

Status: `belum` · `sedang` · `PR dibuka` · `revisi` · `merged` · `gagal` · `dilewati`

| Fase | PR / tiket | Isi | Status | Gate |
|---|---|---|---|---|
| — | PR #49 | `docs(#33)`: ADR, glossary, plan, handoff, setup agent skills | `PR dibuka` — konflik dengan `main` (#119), tertahan guard #124 (fix PR #126) | — |
| 0 | PR #50 | `test(#33)`: ekspor golden fixtures bridge + schema | `PR dibuka`, approved | `BridgeGoldenTests` hijau; schema memvalidasi semua fixture |
| 0 | PR #51 | `fix(#33)`: hook Claude Windows tanpa `--source`, precedence = Swift | `merged` (`b314f9c`, 2026-11-20) | `windows/Morrow.Core.Tests` hijau |
| 0 | PR #52 | `ci(#33)`: pipefail XCTest | `dilewati` — ditutup, digantikan #111 | — |
| 0 | #78 | `fix(#78)`: endpoint plugin pasca-rebrand (plan §12) | `belum` — menunggu 3 keputusan kontrak di PR #115 | test plugin memakai `fixtures/endpoint/cases.json` |
| 0.5 | #83 → PR #114 | skrip CI macOS `test`/`package`/`manifest` | `merged` (`c695753`, 2026-11-20) | pipeline hijau + satu run sengaja merah |
| 0.5 | #84 → PR #115 | kontrak endpoint + 38 kasus | `PR dibuka` — 3 open question ditanyakan ke kolaborator | Swift `SocketPath.resolve` lulus kasus macOS |
| 0.5 | #85 → PR #117 | eksperimen Opsi E | `PR dibuka` — hijau 96,8%, tapi **ditolak → Rust** | ADR-0003 `rejected`, keputusan di ADR-0001 |
| 0.5 | #86 → PR #118 | layout monorepo (skrip replay) | `PR dibuka` (draft) — dijalankan ulang setelah PR lain merge; bagian `.woodpecker.yaml` perlu @aazhrt | `swift test` + DMG hijau, nol perubahan perilaku |
| 1 | #87 → PR #120 | workspace Rust + `morrow-protocol` + purity check | `PR dibuka` | 300 payload round-trip identik; `cargo tree` bersih |
| 1 | #88 → PR #121 | `morrow-ipc` UDS | `PR dibuka` (membawa #115 via merge) | 38 kasus endpoint + 11 test integrasi |
| 1 | #89 → PR #122 | `morrow-bridge` Claude Code | `PR dibuka` | 23 fixture claude; exit tanpa listener <10 ms (0,2–1,3 ms) |
| 1 | #90 → PR #123 | shell Tauri X11 tight-fit, nonactivating | `PR dibuka` | smoke Xvfb 17/17 |
| 1 | #91 → PR #125 | kartu approval dua arah | `PR dibuka` — menunggu run di X11 nyata (@aazhrt) | **`E2E-1`**: 27/27 di Xvfb, approve 35 ms, deny 13 ms |
| 2 | #92 → PR #127 | ekspor fixture reducer + `AttentionPolicy` | `PR dibuka` | 80 kasus reducer (161 step), 56 attention; `Sources/` tidak berubah |
| 2 | #93 → PR #128 | `HookIntake` → `morrow-core`; bridge memakainya | `PR dibuka` | 84/84 neutral, 84/84 linux |
| 2 | #94 → PR #130 | port reducer + `HookEventFacts` + wire morrow-app | `PR dibuka` (stacked on #128) | 80/80 kasus (161 step) fixture reducer identik, gate E2E-1 27/27 |
| 2 | #95 → PR #131 | `AttentionPolicy.intents` + `EventSoundRouting` + `reduce_event` | `PR dibuka` (stacked on #130) | 56/56 kasus attention; 80/80 + 161 step reducer termasuk intents; `morrow-app` 12/12 |
| 2 | #96 → PR #132 | `GitBranchReader` + `MarkdownBlockParser` | `PR dibuka` (stacked on #131) | 53/53 test markdown + 9/9 test git diport 1:1; `linux-test.sh` hijau |
| 2 | #97 → PR #133 | transcript tail: parser JSONL + `TailState` di core | `PR dibuka` (stacked on #132) | 70 test port (2 test `DispatchSource` milik watcher); file diganti → replay sekali lalu live |
| 3 | #98–#104 | Linux lengkap: installer, adapter, packaging | `belum` | `L-001…L-012` + **`E2E-2`** |
| 4 | #105–#108 | Windows | `belum` | `W-001…W-009` + **`E2E-2`** |
| 5 | #109 | Wayland | `belum` | Sway/Hyprland/KDE jalan; GNOME menyatakan tidak didukung |
| 6 | #110 | Hapus core C# | `belum` | test Windows hijau; **izin maintainer `windows/`** |

Stack PR dan urutan merge: body #33, bagian **Stack PR**. Ringkas: **sudah merged di `main`**: #51, #114. Masih menunggu: docs #49 → #50 → #117 / #127; Rust #120 → #121 → #122 → #123 → #125, cabang #122 → #128; #115 (3 OQ); #118 terakhir. Top of `main` saat catatan ini: `c695753`. Merge pakai *merge commit*, hapus branch setelah merge.

---

## Gate end-to-end

| Gate | Fase | Input | Membuktikan | Dinilai di |
|---|---|---|---|---|
| `E2E-1` | 1 | hook JSON sintetis | kabel tersambung dua arah | Xvfb (smoke) → host Debian X11 (final) |
| `E2E-2` | 3, 4 | `claude` asli + hook terinstall | produk bekerja terhadap CLI nyata | host Debian; Windows QEMU/hardware |

---

## Log Checkpoint

### 2026-11-20 (lanjutan 4) — #49 disiapkan, jalur merge dipetakan

- **Sudah:** merge `origin/main` → `docs/#33` dicoba di worktree terpisah (`~/dev/Morrow-49`, siap, belum di-commit). Hasil: **satu** file bentrok, `AGENTS.md` (add/add); versi branch = versi `main` + §7 port + *Agent skills* + aturan resource budget, jadi resolusi = ambil versi branch (tidak ada isi `main` yang hilang). Permintaan aazhrt kedua sudah beres: `.github/workflows` tidak ada di branch maupun di `main`. **Temuan:** commit merge itu ditolak `.githooks/pre-commit` dari `main` (`BLOCKED: .woodpecker.yaml`, #124); dengan diff PR #126 diterapkan, guard lolos — jadi #49 hanya bisa di-push setelah **#126** merge. Komentar tag dipasang di #126, #115, #49, #114, #51, #120 (rantai #120–#125 dan #127–#133).
- **Koreksi 2026-11-20:** #51 (`b314f9c`) dan #114 (`c695753`) ternyata **sudah merged** ke `main`; snapshot PR yang dipakai saat menulis komentar tag masih basi, jadi komentar "mohon di-merge" di #51 dan #114 salah dan sudah dikoreksi di PR masing-masing. Merge #49 di `~/dev/Morrow-49` sudah diulang terhadap `main` baru (`c695753`): tetap **satu** konflik (`AGENTS.md`), 21 file, +998/−178, guard lolos dengan diff #126.
- **Berikutnya:** begitu #126 di-approve+merge → commit+push merge #49, minta re-review aazhrt (dismiss `CHANGES_REQUESTED` lama), lalu #114 + #51 di-merge, lalu rantai Rust di-retarget ke `main` dari bawah (#50 → #120 … → #133).
- **Blocker:** approval #126 (@aazhrt); 3 OQ #115 (@fzrsahi, @agungdunggio); run E2E-1 di X11 nyata. Catatan: worktree `~/dev/Morrow-134` (branch `chore/#134-integrate-stacks`, belum di-push) ada di mesin dev — bukan buatan sesi ini.

### 2026-11-20 (lanjutan 3) — #97 selesai, PR #133 dibuka (stacked on #132)

- **Sudah:** `JSONLTailer` diport ke `shared/crates/morrow-core/src/transcript.rs`: `scan_lines` murni untuk semua bentuk baris (Claude + command echo + wrapper `<system-reminder>`/`<USER_REQUEST>`, Antigravity `USER_INPUT`/`PLANNER_RESPONSE`, Codex `event_msg`/`response_item`, Grok, MiniMax thinking blob, Cursor `role`-keyed + sinyal `AskQuestion`), plus `TailState` (offset, fragment, replay file yang diganti, rewind saat truncate) dan `scan_tail_for_attach` (backfill yang tahu batas jendela). Test: **70** lulus (dua test `DispatchSource` milik watcher tidak diport). `linux-test.sh` hijau; `morrow-core` tetap 20 crate murni. PR #133 dibuka terhadap base `feat/#96-core-git-markdown` (#132).
- **Berikutnya:** fase 2 selesai di sisi core begitu #131–#133 di-review. Kandidat berikut: watcher transcript di platform (bagian yang sengaja ditinggal di #97), atau tiga payload app-side yang ditunda (checklist, recap, label model) sebagai tiket sendiri; lalu Lane E: #98 installer + E2E-2, #101 adapter batch 1.
- **Blocker:** run E2E-1 di X11 nyata (@aazhrt); 3 keputusan kontrak endpoint (#115); review stack #120–#125, #128, #130–#133. **Bug baru ditemukan:** `bridge_process::gemini_permission_answer_is_put_as_gemini_reads_it` flaky — fallback sentinel 200 ms di test harness balapan delay 250 ms hook Gemini; perlu tiket sendiri (di luar #96/#97).

### 2026-11-20 (lanjutan 2) — #96 selesai, PR #132 dibuka (stacked on #131)

- **Sudah:** `MarkdownBlockParser` diport ke `shared/crates/morrow-core/src/markdown.rs` (blok saja: heading, paragraf, list bersarang + task, fenced code, tabel GFM, quote, thematic break; inline tetap Markdown mentah, **nol HTML**) dan `GitBranchReader` ke `src/git.rs` (baca `.git` tanpa spawn `git`; disk masuk lewat trait `git::Disk`; path lewat `Path`/`PathBuf` per segmen; worktree dikenali dari pasangan segmen `.git/worktrees`, bukan substring). Test: **53/53** test `MarkdownBlockParserTests` (satu test cache milik app macOS tidak diport) dan **9/9** `GitBranchReaderTests` di disk in-memory, plus batas kedalaman 12 dan cwd yang perlu distandardisasi. `linux-test.sh` hijau (fmt, clippy, test, purity). PR #132 dibuka terhadap base `feat/#95-core-attention` (#131).
- **Berikutnya:** #97 `JSONLTailer` (parser JSONL transcript di core + watcher di platform), stacked di atas #132. Catatan terbuka: test `morrow-bridge` `gemini_permission_answer_is_put_as_gemini_reads_it` **flaky** di run suite penuh (lolos 3/3 saat sendiri) — perlu tiket sendiri, bukan bagian #96.
- **Blocker:** run E2E-1 di X11 nyata (@aazhrt); 3 keputusan kontrak endpoint (#115); review stack #120–#125, #128, #130, #131, #132.

### 2026-11-20 (lanjutan) — #95 selesai, PR #131 dibuka (stacked on #130)

- **Sudah:** `AttentionPolicy.intents` dan `EventSoundRouting.soundEvent` diport ke `shared/crates/morrow-core/src/attention.rs` bersama tipe yang dipakainya (moment, subject, intents, push kind, follow-up intent). Fixture `fixtures/core/attention.json` lulus **56/56** (hook 29, request 11, elsewhere 11, reminder 5). 161 step `fixtures/core/reducer.json` kini juga membandingkan intents, tetap **80/80**. `reduce_event` (= `reduceEvent` Swift) menaruh `PlaySound`/`EnqueueCompletion` di slot reducer dan `morrow-app` memakainya (12/12 test). `./scripts/ci/linux-test.sh` hijau (fmt, clippy, test, purity: morrow-core 20 crate, tidak ada yang terlarang). PR #131 dibuka terhadap base `feat/#94-core-reducer` (#130). Catatan: `settle(_:context:)` **belum** diport — butuh adapter setelan/scene `morrow-platform` (plan §5.2, #101) dan tidak ada fixture-nya.
- **Berikutnya:** #96 `GitBranchReader` + `MarkdownBlockParser`, lalu #97 `JSONLTailer`, keduanya di-stack di atas #131. Jalur kritis tetap di luar kode: approval + merge #126 (guard #124), resolve konflik #49, jawab 3 OQ #115.
- **Blocker:** run E2E-1 di X11 nyata (@aazhrt); 3 keputusan kontrak endpoint (#115); review stack #120–#125, #128, #130, #131.

### 2026-11-20 — #94 selesai, PR #130 dibuka (stacked on #128)

- **Sudah:** Port `reduceHookEvent` dan `HookEventFacts` ke `shared/crates/morrow-core` (pure Rust, clock diinjeksi, 20 crate murni). 80 kasus fixture (161 step) dari #127 lulus 100%. Integrasi `shared/desktop` (`morrow-app`) menggunakan reducer murni, `test-desktop.sh` lulus, dan gate `E2E-1` di Xvfb lulus 27/27 (approve 16 ms, deny 10 ms). PR #130 dibuka terhadap base `feat/#93-core-hookintake` (#128).
- **Berikutnya:** Lanjut Lane A (#95 `AttentionPolicy` di `morrow-core` setelah PR #127 fixture attention ada di stack); atau review stack PR #120–#125, #128, #130; run E2E-1 di X11 nyata (@aazhrt).
- **Blocker:** Run E2E-1 di X11 nyata (@aazhrt); 3 keputusan kontrak endpoint (#115).

### 2026-11-19 — fase 1 di PR, fase 2 mulai, kerja dijeda

- **Sudah:** #85 lulus tapi core diputuskan **Rust** (#117). Fase 1 lengkap sebagai stack PR #120 → #121 → #122 → #123 → #125; gate E2E-1 hijau di Xvfb. Fase 2: #127 (fixture core) dan #128 (`HookIntake` di `morrow-core`, 84/84). Draft #94 disimpan di `wip/#94-core-reducer` (belum diverifikasi). #52 ditutup (digantikan #111). `main` menerima aturan baru #119 (`AGENTS.md` kanonik, `.woodpecker.yaml` khusus @aazhrt, pre-commit `verify-local.sh`).
- **Berikutnya:** setelah PR #126 merge, merge `main` ke #49 lalu teruskan ke stack di atasnya; lanjut #94 dari branch wip, lalu #95; #78 setelah 3 keputusan #115 terjawab.
- **Blocker:** guard pre-commit memblokir merge `main` ke branch fitur (#124, fix PR #126 belum merge); 3 keputusan kontrak endpoint (#115); run E2E-1 di X11 nyata (@aazhrt).

### 2026-11-18 (lanjutan 3) — spec + tiket

- **Sudah:** setup agent skills (`AGENTS.md`, `docs/agents/`, label triage); spec #82; 28 tiket #83–#110 dengan relasi sub-issue (#47/#48/#70) dan *blocked by* native; revisi #50 dan #52 di-push.
- **Berikutnya:** frontier #84 dan #85; review + merge #49–#52 membuka #83 dan #86.
- **Blocker:** runner Woodpecker belum punya .NET 8 SDK (#52 akan merah sampai dipasang).

### 2026-11-18 (lanjutan 2) — #51 dirombak, masukan #70 diserap

- **Sudah:** #51 opsi 2 — hook Claude Windows tanpa `--source`, precedence C# = Swift, installer 0.2.2 memicu repair; 23/23 test + self-test Hooks.Cli hijau, 7 test baru merah di kode lama. Masukan #70: signing Windows dilewati untuk beta (jalur gratis Store MSIX / SignPath sebelum GA), VM Windows hanya untuk build rilis + gate, kontrak skrip CI (plan §8.1).
- **Berikutnya:** revisi #50 dan #52; PR fix #78; Fase 0.5.
- **Blocker:** belum ada mesin Windows untuk memverifikasi #51 dengan Cursor asli (masuk gate #47).

### 2026-11-18 (lanjutan) — issue dirapikan

- **Sudah:** bug #78 dibuat (socket plugin pasca-rebrand); body #33/#47/#48 ditulis ulang jadi versi yang berlaku (body lama diarsipkan sebagai komentar, komentar usang di-minimize); #70 dijadikan sub-issue #33; kriteria W-009 dan L-012 (tabel Capability) ditambahkan; keamanan pipe masuk W-001.
- **Berikutnya:** keputusan #51; revisi #50 dan #52; PR fix #78; Fase 0.5.
- **Blocker:** keputusan precedence `--source claude` di #51.

### 2026-11-18 — review arsitektur + revisi dokumen

- **Sudah:** merge `origin/main` (rebrand Morrow) ke branch docs; rename `codeisland-*` → `morrow-*` dan path `Sources/MorrowCore`, `windows/Morrow.*`; ADR-0001 diamandemen (premis "mustahil satu core" dikoreksi, Opsi E + kill criteria); ADR-0002 dikoreksi (HTTRANSPARENT salah, tauri#15913 tidak di-merge, Tauri tidak diasumsikan lebih hemat dari .NET); plan: kontrak endpoint §3.1, layout monorepo §4, scope app-held §5.1, tabel adapter lengkap §5.2, strategi tight-fit §6, Fase 0.5, packaging §9, regresi socket §12; handoff: trap `HookIntake` dibalik, tabel "siapa mengerjakan apa"; rencana Linux lama diarsipkan ke `docs/archive/`.
- **Berikutnya:** revisi #50 dan #52; PR fix endpoint plugin; PR monorepo; eksperimen Opsi E.
- **Blocker:** keputusan precedence `--source claude` di #51; runner Linux (agent docker) untuk Woodpecker (#70); belum ada mesin X11 nyata untuk gate `E2E-1`.

### 2026-11-16 — dokumen arsitektur

- **Sudah:** riset mygo vs Tauri, verifikasi klaim issue #33, ADR-0001, ADR-0002, `GLOSSARY.md`, plan §7/§8, handoff, sub-issue #47/#48.
- **Berikutnya:** push branch, buka PR, mulai fase 0.
- **Blocker:** tidak ada.

---

## Fakta lingkungan

- Mesin dev macOS arm64. Swift 6.4.2, `rustc` 1.98.0, Docker CLI + Colima.
- **Tidak ada desktop Windows/Linux** di mesin dev. Gate perilaku dinilai di host Debian (#70) dan Windows QEMU.
- CI: Woodpecker, runner macOS (`local`). GitHub Actions tidak tersedia (billing). Belum ada lane Linux; `.woodpecker.yaml` hanya diubah @aazhrt — repo menyediakan skrip `scripts/ci/*` (plan §8.1).
- Laptop dev 8 GB / 6 core: jalankan satu build berat dalam satu waktu. Colima `--cpu 2 --memory 2`, container `--memory 1800m`, `CARGO_BUILD_JOBS=1` di container dan `-j 2` untuk Swift di host.
- Worktree baru: `git worktree add ../Morrow-<n> <branch>` lalu `swift package resolve --disable-dependency-cache` (mencegah error SwiftPM "unable to read tree").
