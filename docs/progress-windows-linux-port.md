# Progress — Windows & Linux port

**Status:** #126 sudah merged (guard #124 beres); fase 1 selesai di PR (#120–#125, gate E2E-1 hijau di Xvfb, menunggu X11 nyata); fase 2 (#127, #128, #130, #131, #132, #133). Core = **Rust** (#117).
**Checkpoint terakhir:** 2026-11-20 — #126 merged (`f812e7b`), `main` ditarik ke `docs/#33` (konflik `AGENTS.md` selesai) dan #49 menunggu re-review.
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
| 0 | #78 | `fix(#78)`: endpoint plugin pasca-rebrand (plan §12) | `siap` — 3 keputusan kontrak sudah dijawab (@aazhrt, 2026-11-20) | test plugin memakai `fixtures/endpoint/cases.json` |
| 0.5 | #83 → PR #114 | skrip CI macOS `test`/`package`/`manifest` | `merged` (`c695753`, 2026-11-20) | pipeline hijau + satu run sengaja merah |
| 0.5 | #124 → PR #126 | guard `verify-local.sh` mengizinkan merge yang membawa CI upstream | `merged` (`f812e7b`, 2026-11-20) | merge `main` → branch fitur tidak diblokir lagi |
| 0.5 | #84 → PR #115 | kontrak endpoint + 38 kasus | `APPROVED` — keputusan tercatat di dokumen (`d947166`) | Swift `SocketPath.resolve` lulus kasus macOS |
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
| 2 | #135 → PR #137 | sisa #97: `SessionRecap` + `ModelObservation`/`ModelLabel` + `parseISO8601`, termasuk penyerapan delta ke snapshot | `PR dibuka` (stacked on #133) | 22 `ModelLabelTests` + 38/39 `SessionRecapTests`; delta & snapshot lengkap |
| 2 | #136 → PR #140 | sisa #97: parsing checklist (`AgentTaskTool`, event hook/transcript, `scan` backfill) | `PR dibuka` (stacked on #137) | 9 test parsing; `ScanDelta.task_events` terisi urut |
| 2 | #139 → PR #142 | `AgentTaskList` (dedupe, park, undo, pensiun plan per-turn, linger, rebuild attach, persistensi) + `Snapshot.agent_tasks` | `PR dibuka` (stacked on #140) | 38/39 test list-side; `scanFile` tetap di platform |
| 3 | #98 → PR #145/#146 | installer hook Claude Code: editor + rencana (#144), lalu crate `morrow-platform` + kartu Settings | `PR dibuka` (stacked #142 → #145 → #146) | 14 + 18 + 9 test; sisa hanya **E2E-2** di desktop Linux nyata |
| 3 | #99 → PR #147/#148 | **sembilan target** hook (Claude, 7 JSON, OpenCode) + flag TOML Codex, semua dari kartu Settings | `PR dibuka` (stacked #142→#148) | 19+15+2(40 fixture)+10+8 test; sisa hanya E2E di desktop Linux |
| 3 | #100 → PR #149 | source TOML (Kimi) + baris cakupan per agent di Settings | `PR dibuka` (stacked #142→#149) — `Fixes #100` | 8 + 5 test; L-002 lulus untuk JSON + TOML |
| 3 | #151 | source YAML (Hermes, TraeCli) — keputusan komentar-vs-macOS dulu | `belum` — opsi A/B/C diajukan, rekomendasi B | tiket terpisah supaya #100 bisa ditutup |
| 3 | #151 → PR #152 | source YAML (Hermes, TraeCli) sebagai blok terkelola — komentar utuh | `PR dibuka` (stacked #142→#152) | 14 + 6 test; keputusan **B** tercatat di tiket |
| 3 | #101 → PR #153 | Capability table 21 adapter + autostart + settings + **tray + global hotkey** | `PR dibuka` (stacked #142→#153) | 11 test + clippy bersih; **sisa hanya L-006…L-012 di desktop nyata** |
| 3 | #102 → PR #154 | kartu musik: MPRIS, ekstrapolasi posisi, lirik lrclib, volume | `PR dibuka` (stacked #142→#154) | 17 + 11 test; sisa: menggambar kartunya (pekerjaan panel) + L-003/L-004 |
| 3 | #103 → PR #155 | terminal jump (L-009), process watch, screen lock, notifikasi | `PR dibuka` (stacked #142→#155) | 14 test; sisa: perilaku panel yang memakainya |
| 3 | #104 → PR #156 | packaging deb/rpm/AppImage + feed per format + bridge di luar paket | `PR dibuka` (stacked #142→#156) | skrip + 5 test; sisa: L-011 smoke & `E2E-2` di host Debian |
| 3 | #98 (lanjutan) | E2E-2: `claude` asli → kartu → Approve/Deny, tanpa event dobel | `belum` — butuh desktop Linux nyata | satu-satunya sisa #98 |
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

## Uji kering retarget (2026-11-20, belum di-push)

Diuji dengan `git merge-tree --write-tree` terhadap `main` = `f812e7b`; worktree tidak disentuh, tidak ada push. Polanya sama di semua branch, jadi retarget nanti hanya menyelesaikan 2–3 file yang sama:

| PR / branch | Bentrok | Penyelesaian |
|---|---|---|
| #49 `docs/#33` | — (sudah di-merge, `cad7ba7`) | — |
| #50 `test/#33`, #117 `research/#85` | `AGENTS.md`, `GEMINI.md` | ambil versi `main` (setelah #49: `AGENTS.md` lengkap dengan §7; `GEMINI.md` sudah jadi 1 baris penunjuk) |
| #120–#125, #128, #130–#133 | `AGENTS.md`, `GEMINI.md`, `.gitignore` | dua file pertama ambil `main`; `.gitignore` **pertahankan** versi branch (`target/`, `CLAUDE.md`) |
| #127 `test/#92` | `AGENTS.md`, `GEMINI.md` | ambil versi `main` |
| #118 `chore/#86` (draft) | `.woodpecker.yaml`, `GEMINI.md` | `.woodpecker.yaml` = zona @aazhrt, jangan disentuh agen |

Sebabnya: branch-branch ini dibuat sebelum `main` punya `AGENTS.md` (git melihatnya add/add), `GEMINI.md` sudah diringkas di #119, dan `.gitignore` versi Rust menambah `target/` + `CLAUDE.md`. `rerere.enabled` sudah aktif di clone ini dan resolusi `AGENTS.md` dari merge #49 sudah terekam, jadi konflik yang sama akan diputar ulang otomatis.

Urutan yang disarankan: merge #49 → retarget + merge `main` ke #50 dan #117 → sisanya tetap menumpang induknya, retarget hanya saat induknya masuk `main`. Biaya per push: build Swift ~1,5 menit, dan `swift test` branch ikut menjalankan suite Swift terbaru.

**Catatan: bagian ini sengaja belum di-push** (permintaan pemilik repo, 2026-11-20). Push menyusul bersama update berikutnya.

---

## Log Checkpoint

### 2026-11-20 (lanjutan 21) — #105 named pipe Windows (PR #157)

- **Sudah:** `morrow_ipc::windows` (pipe mode pesan; `FILE_FLAG_FIRST_PIPE_INSTANCE` + `PIPE_REJECT_REMOTE_CLIENTS`; descriptor `O:<sid>G:<sid>D:(A;;GA;;;<sid>)`; `ERROR_ACCESS_DENIED` → `AlreadyRunning`), cek identitas server lewat `GetNamedPipeServerProcessId` → token → SID, `pipe::` untuk nama+descriptor (murni, diuji di mesin mana pun, termasuk kecocokan nama dengan `endpoint::resolve`), `is_sid` menolak SID cacat sebelum masuk API. `morrow_ipc` me-re-export satu nama transport, jadi bridge dan shell berhenti menyebut `unix`. Skrip baru `scripts/ci/windows-check.sh`. Bukti: `cargo xwin clippy --target x86_64-pc-windows-msvc -- -D warnings` hijau untuk `morrow-ipc`, `morrow-bridge`, `morrow-core`; gate Unix hijau; 4 test string lulus. **PR #157** terhadap #156.
- **Berikutnya:** #106 (window plumbing, butuh #91 dan #105) dan #107 (WinRT + Capability) — keduanya berakhir di VM Windows; #108 (NSIS) di belakangnya.
- **Blocker:** **W-001** butuh host Windows dengan dua akun; lane Windows belum dipasang di `.woodpecker.yaml` (@aazhrt); review stack #145–#157. Lokal butuh `rustup target add x86_64-pc-windows-msvc` + `cargo install cargo-xwin --locked` (~1,5 GB).

### 2026-11-20 (lanjutan 20) — #104 packaging Linux (PR #156)

- **Sudah:** tiga skrip di kontrak §8.1 — `linux-package.sh` (semver tanpa `v`, signing key wajib di awal, tiap format butuh artefak + `.sig`, `SHA256SUMS` hanya kalau set lengkap), `linux-manifest.sh` (satu feed per format, **all-or-nothing**: validasi semua format dulu, tulis kedua, tiap dokumen di-parse ulang lalu di-rename), `linux-smoke.sh` (install → launch → tunggu copy-out bridge → satu hook sintetis berwaktu → uninstall; keluar **77** kalau host tidak punya display, karena lulus diam-diam lebih buruk daripada jujur tidak bisa). `morrow-platform::bridge` menyalin bridge ke `~/.local/bin/morrow-bridge` secara atomik; skrip hook memakai path stabil dulu, `~/.codeisland` cadangan, versi skrip v2. `tauri.conf.json` dapat `bundle.active`, tiga target, `externalBin`, updater artifacts, dependensi deb/rpm. Test `bridge_placement` 5; gate hijau. **PR #156** terhadap #155.
- **Berikutnya:** tidak ada tiket implementasi Linux yang bisa jalan tanpa desktop. Sisa Fase 3 = verifikasi: L-011 (smoke), E2E-2, L-003/L-004/L-006…L-012, plus perilaku panel yang memakai adapter #102/#103.
- **Blocker:** review stack #145–#156; host Debian/VM untuk semua gate di atas; gate **#91 masih OPEN**; `.woodpecker.yaml` (memasang tiga skrip) milik @aazhrt. Flake `bridge_process::gemini_permission_answer_is_put_as_gemini_reads_it` muncul lagi hari ini — perlu tiket sendiri.

### 2026-11-20 (lanjutan 19) — #103 empat adapter (PR #155)

- **Sudah:** `runner` dipindah jadi seam bersama, lalu empat adapter: `terminal` (sway `con_id` → Hyprland `address` → `wmctrl`/`xdotool` by class → **copy path/tty** sebagai lantai L-009 → penjelasan kalau dua-duanya tidak ada), `process` (satu angka dari `/proc/<pid>/stat` + start time agar pid daur ulang tidak menahan kartu mati; tanpa menelusuri tabel proses), `lock` (`loginctl … LockedHint`, tidak bisa menjawab = tidak terkunci), `notify` (`notify-send`, 8 dtk). Capability mengikuti: tanpa window API tapi ada clipboard = `Degraded` dengan jalur copy; tanpa `notify-send` = `Unsupported`. Shell mengekspos lima perintah. Test 14; gate hijau. **PR #155** terhadap #154.
- **Berikutnya:** #104 (packaging deb/AppImage/rpm + feed update + smoke install) — masih `blocked by #91`; sisanya adalah verifikasi desktop: L-003/L-004/L-006…L-012, E2E-2, dan perilaku panel yang memakai adapter #102/#103.
- **Blocker:** review stack #145–#155; verifikasi di desktop Linux nyata. Flake `bridge_process` (anggaran 5 dtk + sentinel gemini) masih perlu tiket sendiri.

### 2026-11-20 (lanjutan 18) — #102 kartu musik (PR #154)

- **Sudah:** `morrow_core::music` (murni): parser metadata `playerctl`, `parse_lrc` untuk lrclib, parser volume `wpctl`/`pactl`, dan `Position` — ekstrapolasi posisi karena MPRIS `Position` tidak wajib di-refresh (paused diam, clamp di panjang track, tahan clock skew, dikoreksi bacaan berikutnya setelah loop). `morrow_platform::music` menjalankan `playerctl` (metadata, `Can*`, kontrol, seek `position 10+`/`10-`), `wpctl`/`pactl` (baca+tulis dengan tool yang sama, batas 150%), `curl` untuk lrclib; "no players" dan 404 jadi kartu kosong. Capability Now Playing kini menuntut `playerctl`, dan `CanSeek: false` menyembunyikan kontrol seek. Shell mengekspos sepuluh perintah kartu. Test 17 + 11; gate hijau. **PR #154** terhadap #153.
- **Berikutnya:** menggambar kartu musik ikut pekerjaan panel (polling, tombol), lalu #103 (adapter batch 3) dan #104 (packaging).
- **Blocker:** review stack #145–#154; verifikasi di desktop nyata (L-003/L-004, E2E-2, L-006…L-012). Flake `bridge_process` masih perlu tiket sendiri.

### 2026-11-20 (lanjutan 17) — #101 tray + hotkey (PR #153 lengkap)

- **Sudah:** dua bagian terakhir batch 1 masuk. `tray` = StatusNotifierItem lewat AppIndicator (menu Show/hide + Quit, klik kiri men-toggle island); tanpa lib hasilnya `Degraded("no tray icon: …")`, dicetak sekali, panel tetap jalan. `hotkey` = `Super+Space` lewat `tauri-plugin-global-shortcut` (satu-satunya plugin, karena Tauri core tidak mengekspos global shortcut); gagal grab (Wayland) jadi `Degraded` dengan saran `morrow toggle`. `capabilities` menimpa dugaan probe dengan hasil runtime untuk kedua adapter itu, jadi Settings melaporkan kenyataan. Gate hijau, `npm run build` hijau, clippy `-D warnings` bersih untuk `morrow-app`.
- **Berikutnya:** #101 berhenti di verifikasi (L-006…L-012 butuh desktop Linux hidup); berikutnya #102/#103 (adapter batch 2/3, blocked by #101) dan #104 (packaging, blocked by #91) — semuanya berakhir di verifikasi yang sama.
- **Blocker:** review stack #145–#153; verifikasi desktop Linux; flake `bridge_process` (anggaran 5 dtk + sentinel gemini) masih perlu tiket sendiri.

### 2026-11-20 (lanjutan 16) — #151 (PR #152) dan #101 batch 1 (PR #153)

- **#151 selesai:** diputuskan **opsi B** dan dicatat di tiket sebelum kode. `installer::yaml_hooks` hanya memiliki **satu region berpagar** (`# >>> morrow hooks` … `# <<< morrow hooks`) untuk Hermes (peta event → `{command, timeout}`) dan TraeCli (satu item, semua event sebagai matcher, `timeout: '86400s'`); tidak ada parser YAML, jadi tidak ada round-trip yang bisa menulis ulang dokumen. Tiga layout ditolak (`hooks:` inline, `hooks:` bersarang, indentasi tab) dan penolakan tampil di kartu sebagai *Needs a manual merge*. Test 14 + 6.
- **#101 batch 1:** `capability` (21 fitur, `Supported`/`Degraded`/`Unsupported` dengan alasan, `Environment` di-inject), `autostart` (satu entri FreeDesktop, idempoten), `settings` (`~/.codeisland/settings.json` lewat penulis minimal-diff), semuanya tampil di kartu Settings. Tanpa AppIndicator tray = `Unsupported` tapi adapter lain tetap menjawab. Test 11.
- **Berikutnya:** sisa #101 = ikon tray + global hotkey + L-006…L-012 (butuh panel dan desktop nyata); lalu #102/#103 (blocked by #101) dan #104 (packaging, blocked by #91).
- **Blocker:** review stack #145–#153; verifikasi di desktop Linux nyata (E2E-2, L-006…L-012). Flake `bridge_process` (anggaran 5 dtk) muncul lagi saat beban paralel — perlu tiket sendiri bersama flake gemini.

### 2026-11-20 (lanjutan 15) — #100 ditutup dengan TOML, YAML jadi #151

- **Sudah:** diputuskan **opsi C**: #100 selesai lewat PR #149 (TOML Kimi append-only + baris cakupan per agent), dan source YAML dipisah ke tiket **#151** yang memuat tiga opsi (A ikut macOS/re-dump, B blok YAML terkelola, C belum didukung) beserta rekomendasi **B** dan syarat keputusan dicatat sebelum kode. Body #149 diubah jadi `Fixes #100`. Alasannya dicatat di #100: `Yams` di macOS menulis ulang seluruh dokumen dan menghilangkan komentar, jadi menirunya justru melanggar kriteria L-002 tiket itu sendiri.
- **Berikutnya:** #151 menunggu keputusan (A/B/C); jalur kode lanjut ke adapter #101–#103 (blocked by #91) atau packaging #104. Stack review: #145 → #149.
- **Blocker:** review stack #145–#149; #101/#104 masih menunggu #91; E2E-2 butuh desktop Linux nyata.

### 2026-11-20 (lanjutan 14) — #100 TOML (Kimi) + cakupan per agent (PR #149)

- **Sudah:** `installer::kimi` — source pertama yang bukan JSON: blok `[[hooks]]` **ditambahkan** dan saat uninstall tepat blok itu dipotong, jadi komentar/urutan key pengguna selamat (L-002) tanpa parser TOML yang menulis ulang file; scalar legacy `hooks = …` dikomentari (bisa dipulihkan), dan hanya event tool yang membawa `matcher = ".*"`. `morrow_platform::kimi` memilih `~/.kimi-code` atau legacy `~/.kimi`, backup sekali, tulis hanya kalau berubah. Kartu Settings dapat baris Kimi + baris cakupan per agent ("N of M agents found here are hooked"). Test 8 + 5; gate & `npm run build` hijau. **PR #149** terhadap #148.
- **Berikutnya:** keputusan untuk source YAML (Hermes, TraeCli) — di macOS lewat `Yams` yang justru menghilangkan komentar; saya ajukan tiga opsi di #100 dan condong ke "tunda YAML, buka tiket kecil". Setelah itu #101–#103 (adapter) dan #104 (packaging).
- **Blocker:** jawaban atas pertanyaan YAML di #100; review stack #145–#149; E2E-2 butuh desktop Linux nyata. Flake `morrow-ipc` (`set_read_timeout` EINVAL) muncul sekali dan lulus saat diulang — di luar diff ini.

### 2026-11-20 (lanjutan 13) — #99 lengkap di sisi kode (PR #148)

- **Sudah:** dua target terakhir masuk. **Codex** kini juga memasang `features.hooks = true` di `config.toml` lewat `installer::codex_config` (= `CodexHooksConfig`, #354): editor TOML sempit yang menolak layout tak dikenal daripada membuat duplicate key, dan menyembuhkan blok `[features]` yang dulu ditambahkan build lama; ke-40 `CodexTomlHooksFixtures` lulus identik dengan Swift plus idempotensi. **OpenCode** masuk sebagai plugin: `installer::opencode` mendaftarkan referensi di `plugin` (komentar & plugin pengguna tetap, referensi `vibe-island` diganti), `morrow_platform::opencode` menaruh file plugin dari resource macOS via `include_str!` (satu sumber, dua core), memilih `opencode.jsonc` kalau ada, membersihkan registrasi legacy `config.json`, dan mem-backup sekali per file. Kartu Settings kini menampilkan sembilan target. Test baru: 2 + 10 + 8, `hooks_installer` jadi 17. Gate + `npm run build` hijau.
- **Berikutnya:** #99 tinggal E2E di desktop Linux (milik #98); tiket berikutnya #100 (sumber YAML/TOML, sekarang bisa memakai pola editor `codex_config`), lalu adapter #101–#103 dan packaging #104.
- **Blocker:** review stack #145–#148; E2E-2 butuh desktop Linux nyata. Dua flake `bridge_process` (anggaran 5 dtk, sentinel gemini 200 ms) muncul sekali masing-masing dan lulus saat diulang — di luar diff ini.

### 2026-11-20 (lanjutan 12) — #99 target hook bisa dipasang dari Settings (PR #148)

- **Sudah:** `morrow_platform::hooks` dapat `targets_status` / `install_target` / `uninstall_target`: target hanya disentuh kalau CLI-nya ada di mesin ini (`~/.cursor` harus ada sebelum `hooks.json` dibuat di dalamnya), source tak dikenal = error, dan aturannya sama dengan Claude Code (rencana dulu → file rusak membatalkan semuanya; backup sekali; tulis hanya kalau berubah). Shell: `target_install`/`target_uninstall`; kartu Settings menampilkan ketujuh target dengan state dan tombol Install/Remove, atau "Not detected" tanpa tombol. Test `hooks_installer.rs` **15**; `linux-test.sh` + `npm run build` hijau. **PR #148** terhadap #147.
- **Berikutnya:** sisa #99 hanya OpenCode (plugin JS) dan flag `hooks = true` Codex di `config.toml`; keduanya berformat lain, dan yang TOML sebaiknya menyusul #100 (sumber YAML/TOML dengan komentar dipertahankan).
- **Blocker:** review stack #145–#148; E2E-2 milik #98 (butuh desktop Linux nyata).

### 2026-11-20 (lanjutan 11) — #99 rencana 7 target hook (PR #147)

- **Sudah:** `installer::targets` — tabel + `install`/`uninstall`/`is_installed` untuk tujuh target JSON hook (Codex nested, Gemini nested dengan timeout milidetik + `--event`, Cursor flat + `--event`, Qoder/Droid/CodeBuddy format Claude, Copilot `bash`+`timeoutSec` dengan `version: 1`). Entri kita diganti per event (bukan ditumpuk) sehingga entri usang diperbaiki; uninstall menghapus kunci `hooks` yang jadi kosong; semuanya lewat `json_editor` jadi komentar JSON5 pengguna utuh; file yang tidak bisa di-parse ditolak. Shared helper baru `installer::settings` dipakai juga oleh `claude_hooks`. Test **19**; gate hijau. **PR #147** terhadap #146.
- **Berikutnya:** sambungkan ketujuh target ke kartu Settings (sekarang baru Claude), lalu OpenCode (plugin), flag `hooks = true` Codex di `config.toml`, dan #100 (source YAML/TOML).
- **Blocker:** review stack #145/#146/#147; E2E-2 tetap milik #98 dan butuh desktop Linux nyata.

### 2026-11-20 (lanjutan 10) — #98 bagian install (PR #146)

- **Sudah:** crate baru **`morrow-platform`** (plan §5.2) berisi `hooks::install/uninstall/status`: `~/.codeisland` 0700, skrip `codeisland-hook.sh` (ditulis hanya kalau penanda versi hilang), binary `morrow-bridge` (hanya kalau byte beda, temp+rename), backup `settings.json.codeisland.bak.<stamp>` sekali saja, tulis lewat symlink, dan `$CLAUDE_CONFIG_DIR` dihormati. Rencana perubahan settings dibuat **dulu** — file yang tidak bisa di-parse membatalkan seluruh install tanpa meninggalkan skrip/binary (#89). Versi `claude` jadi input (`None` → event bergerbang dilewati); `morrow-core`'s `install()` kini menerima nama perintah dari platform. Shell: `hooks_status`/`hooks_install`/`hooks_uninstall` + kartu "Claude Code hooks" di tampilan island yang diperluas. Test **9** (home sementara); `linux-test.sh` + `npm run build` hijau. **PR #146** terhadap #145.
- **Berikutnya:** #98 tinggal **E2E-2** (`claude` asli → kartu → Approve/Deny, tanpa event dobel) di desktop Linux nyata; lalu #99–#104 (adapter, tray, hotkey, packaging).
- **Blocker:** desktop Linux nyata untuk E2E-2; review stack (#145, #146) dan `CHANGES_REQUESTED` lama di #49. Catatan: dua test anggaran waktu `bridge_process` sempat flaky saat seluruh workspace dites paralel (`took 5.05s` vs batas 4,5 dtk); lulus 3/3 sendiri dan gate hijau saat mesin idle — bukan dari diff ini, kandidat tiket sendiri bersama flake gemini.

### 2026-11-20 (lanjutan 9) — #144: editor config + rencana hook Claude (PR #145)

- **Sudah:** #98 ternyata masih `blocked by #91`/`#93` (PR #125, #128), jadi bagian kodenya dipecah ke tiket **#144** dan dikerjakan sekarang. Yang diport, murni tanpa I/O: `installer::json_editor` (`JSONMinimalEditor`, hanya mengganti rentang nilai satu kunci level atas — komentar/urutan/escape/indent/newline pengguna utuh, dokumen non-objek ditolak = guard #89; plus `strip_json_comments` karena `settings.json` itu JSONC) dan `installer::claude_hooks` (tabel 13 event + gerbang versi 2.1.89/2.1.78, nama legacy `vibenotch`/`vibe-island`/`vibeisland`, install idempoten, perbaikan `async` basi, uninstall yang menghapus kunci `hooks` kosong sehingga kembali byte-per-byte, aturan backup). Test: **14** + **18**; `linux-test.sh` hijau; 20 crate murni. **PR #145** dibuka terhadap #142.
- **Berikutnya:** sisi platform #98 (skrip hook + binary bridge, pemanggilan dari Settings shell) baru bisa setelah #91/#93; berikutnya #99–#104 (adapter, tray, hotkey, packaging). Jalur kritis tetap review #49 dan stack-nya.
- **Blocker:** `CHANGES_REQUESTED` lama di #49; E2E-1/X11 nyata; #91 & #93 belum merge (menahan E2E-2).

### 2026-11-20 (lanjutan 8) — #115 diputuskan, #139 selesai (PR #142)

- **Sudah:** @aazhrt **APPROVED** #115 dan menjawab ketiganya (kosong = unset di semua OS; path remote ikut kode `/tmp/codeisland-<uid>/island.sock`, rename ke tiket sendiri; `CODEISLAND_SOCKET_PATH` fallback legacy). Keputusan itu **masuk dokumen**, bukan cuma komentar: `§1.4`/`§2.1`/`§3.1`/`§4`, dua tempat di `hook-edge-protocol.md`, dan `§6` yang kini berjudul *Decisions and what is still open* (satu pertanyaan lama — seleksi path legacy tak memeriksa jenis file — tetap terbuka dan dipatok dua kasus `macos-legacy-*`). Lalu #139 diport: `AgentTaskList` utuh (dedupe per op, park sampai create tiba, undo saat panggilan gagal, pensiun plan snapshot per-turn, linger 8 dtk, `rebuilt` untuk attach, persistensi bergaya `Codable` dengan epoch 2001), `SessionSnapshot.agent_tasks`, wiring reducer (subagent lewat `apply_shared_updates`, `SessionStart` memulihkan kecuali `/clear`). Test **38** baru; `linux-test.sh` hijau; `morrow-core` tetap 20 crate murni. **PR #142** dibuka terhadap #140.
- **Berikutnya:** fase 2 tuntas di sisi core (#131–#133, #137, #140, #142). Fokus pindah ke jalur merge: cabut `CHANGES_REQUESTED` #49 → merge #49 → retarget #50/#117/#127 + stack Rust ke `main`. Setelah itu #78 (keputusan #115 sudah ada) dan #105.
- **Blocker:** `CHANGES_REQUESTED` lama di #49 (hanya @aazhrt/admin bisa cabut); run E2E-1 di X11 nyata; `scanFile` + watcher transcript kini satu-satunya sisa fase 2 yang tinggal di platform.

### 2026-11-20 (lanjutan 7) — #135 lengkap, #136 parsing, #139 dibuat

- **Sudah:** #135 dilengkapi: `SessionSnapshot` dapat `recap`/`reasoning_effort`/`configured_long_context` (disimpan, tidak diproyeksikan), penyerapan delta (`apply_transcript_delta`, `apply_transcript_backfill`, `apply_backfilled_model_observation`, `clear_recap_if_superseded` yang kini dipanggil reducer pada `UserPromptSubmit`, `visible_recap`, `model_label`), plus `SubagentState.reasoning_effort`/`model_label`/`claude_transcript_path`. Test `session_recap` 24 → **38/39**. Push ke #137. Lalu #136 dipecah (1.220 baris sumber + 812 test): parsing diport (**PR #140**, 9 test, `ScanDelta.task_events`), state machine daftar jadi tiket **#139**.
- **Berikutnya:** #139 (`AgentTaskList` + `agentTasks` di snapshot + wiring reducer/transcript). Setelah itu fase 2 tuntas di sisi core dan fokus pindah ke jalur review/merge.
- **Blocker:** review #49 (@aazhrt), 3 OQ #115, E2E-1 di X11. Catatan proses: komentar scope di #136 dan body #139 sempat rusak karena backtick dieksekusi shell; sudah dikoreksi, dan nomor tiket lanjutan yang benar adalah **#139** (bukan #138).

### 2026-11-20 (lanjutan 6) — #135 dikerjakan, PR #137 dibuka (stacked on #133)

- **Sudah:** dua tiket lanjutan #97 dibuat (#135 recap+label, #136 checklist). #135 diport: `session_recap.rs`, `model_label.rs`, `time.rs` (`parseISO8601`), dan `ScanDelta` kembali membawa `session_recap` / `model_observation` / `configured_long_context`; `quick_type_probe` mem-parse lagi baris `system`+`away_summary` dan `turn_context`. Test baru: **22** (`ModelLabelTests`) + **24** (scan-level `SessionRecapTests`); suite `morrow-core` dan `linux-test.sh` hijau. PR #137 dibuka terhadap base `feat/#97-core-transcript` (#133). 15 test `SessionRecapTests` yang menguji penyerapan delta ke snapshot **belum** diport (butuh state `recap`/`reasoningEffort`/`modelReportedAt` di snapshot Rust) — dicatat di PR + README.
- **Berikutnya:** #136 (`AgentTaskTranscript`), stacked di atas #137; lalu retarget rantai saat #49 masuk `main`.
- **Blocker:** review #49 (@aazhrt, dismiss `CHANGES_REQUESTED` lama); 3 OQ #115; run E2E-1 di X11 nyata.

### 2026-11-20 (lanjutan 5) — #126 merged, #49 lepas dari konflik

- **Sudah:** **#126 merged** (`f812e7b`, branch dihapus), jadi guard `.githooks/pre-commit` tidak lagi memblokir merge `main` ke branch fitur (#124 tutup). `main` (`f812e7b`) ditarik ke `docs/#33`; konflik **satu** file (`AGENTS.md`) diselesaikan dengan versi branch (isi `main` + §7 port + *Agent skills* + batas resource), guard jalur merge lolos (`✅ Local verification passed`), commit `c780771`. Papan diperbarui: #51, #114, #126 merged. Catatan proses: dua komentar tag saya di #51/#114 sempat salah karena memakai snapshot basi; sudah dikoreksi di PR-nya.
- **Berikutnya:** minta @aazhrt mencabut `CHANGES_REQUESTED` lama di #49 (hanya dia/admin yang bisa) → merge #49 → retarget #50/#117/#127 ke `main` → merge rantai Rust dari bawah (#120 → #125, #127 → #133). E2E-1 di X11 nyata tetap jadi syarat penutup fase 1.
- **Blocker:** re-review #49 (@aazhrt); 3 OQ #115 (@fzrsahi, @agungdunggio); run E2E-1 di X11 nyata.

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
