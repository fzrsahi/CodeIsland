# Progress — Windows & Linux port

**Status:** fase 1 selesai di PR (#120–#125, gate E2E-1 hijau di Xvfb, menunggu X11 nyata); fase 2 mulai (#127, #128; #94 draft di `wip/#94-core-reducer`). Core = **Rust** (#117).
**Checkpoint terakhir:** 2026-11-19 — kerja dihentikan setelah #93; worktree lokal dibersihkan.
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
| 0 | PR #51 | `fix(#33)`: hook Claude Windows tanpa `--source`, precedence = Swift | `PR dibuka`, approved, siap merge | `windows/Morrow.Core.Tests` hijau |
| 0 | PR #52 | `ci(#33)`: pipefail XCTest | `dilewati` — ditutup, digantikan #111 | — |
| 0 | #78 | `fix(#78)`: endpoint plugin pasca-rebrand (plan §12) | `belum` — menunggu 3 keputusan kontrak di PR #115 | test plugin memakai `fixtures/endpoint/cases.json` |
| 0.5 | #83 → PR #114 | skrip CI macOS `test`/`package`/`manifest` | `PR dibuka`, approved @aazhrt | pipeline hijau + satu run sengaja merah |
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
| 2 | #94 | port reducer + `HookEventFacts` | `sedang` — draft belum diverifikasi di `wip/#94-core-reducer` | 100% fixture reducer identik |
| 2 | #95–#97 | attention, git + markdown, transcript live | `belum` | fixture/test port lulus |
| 3 | #98–#104 | Linux lengkap: installer, adapter, packaging | `belum` | `L-001…L-012` + **`E2E-2`** |
| 4 | #105–#108 | Windows | `belum` | `W-001…W-009` + **`E2E-2`** |
| 5 | #109 | Wayland | `belum` | Sway/Hyprland/KDE jalan; GNOME menyatakan tidak didukung |
| 6 | #110 | Hapus core C# | `belum` | test Windows hijau; **izin maintainer `windows/`** |

Stack PR dan urutan merge: body #33, bagian **Stack PR**. Ringkas: mandiri #51, #114, #115; docs #49 → #50 → #117 / #127; Rust #120 → #121 → #122 → #123 → #125, cabang #122 → #128; #118 terakhir. Merge pakai *merge commit*, hapus branch setelah merge.

---

## Gate end-to-end

| Gate | Fase | Input | Membuktikan | Dinilai di |
|---|---|---|---|---|
| `E2E-1` | 1 | hook JSON sintetis | kabel tersambung dua arah | Xvfb (smoke) → host Debian X11 (final) |
| `E2E-2` | 3, 4 | `claude` asli + hook terinstall | produk bekerja terhadap CLI nyata | host Debian; Windows QEMU/hardware |

---

## Log Checkpoint

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
