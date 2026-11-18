# Progress — Windows & Linux port

**Status:** fase 0 — PR #49–#52 terbuka, dua perlu revisi. Belum ada kode Rust.
**Checkpoint terakhir:** 2026-11-18 — review arsitektur, revisi dokumen pasca-rebrand Morrow.
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

| Fase | PR | Isi | Status | Gate |
|---|---|---|---|---|
| — | #49 | `docs(#33)`: ADR, glossary, plan, handoff | `PR dibuka` | — |
| 0 | #50 | `test(#33)`: ekspor golden fixtures ke JSON + schema | `revisi` | `BridgeGoldenTests` hijau; schema memvalidasi semua fixture |
| 0 | #51 | `fix(#33)`: atribusi hook Claude yang dijalankan Cursor di Windows (opsi 2) | `PR dibuka` | `windows/Morrow.Core.Tests` hijau |
| 0 | #52 | `ci(#33)`: test .NET di Woodpecker | `revisi` | test gagal = pipeline merah |
| 0 | — | `fix(#78)`: endpoint plugin pasca-rebrand (plan §12) | `belum` | test plugin memakai default asli |
| 0.5 | — | `chore`: layout monorepo (plan §4) | `belum` | `swift test` + DMG hijau, nol perubahan perilaku |
| 0.5 | — | kontrak endpoint (plan §3.1) | `belum` | satu dokumen; semua edge mengikuti |
| 0.5 | — | eksperimen Opsi E (Swift core di Linux) | `belum` | kill criteria ADR-0001 → ADR-0003 atau bukti Rust |
| 1 | — | `chore(#33)`: workspace Rust, protocol, ipc, CI purity | `belum` | `cargo test`; `cargo tree -p morrow-core` bersih |
| 1 | — | `feat(#33)`: bridge untuk `claude` | `belum` | conformance fixtures |
| 1 | — | `feat(#33)`: vertical slice island Linux X11 | `belum` | **`E2E-1`** — dua arah, <300 ms, tight-fit, tidak mencuri fokus |
| 2 | — | ekspor fixture reducer + `AttentionPolicy` | `belum` | fixture terbaca lintas bahasa |
| 2 | — | `feat(core)`: intake, reducer, attention, git, markdown, jsonl | `belum` | 100% fixture netral identik |
| 3 | — | Linux lengkap: adapter, installer, packaging | `belum` | `L-001…L-012` + **`E2E-2`** |
| 4 | — | Windows | `belum` | `W-001…W-009` + **`E2E-2`** |
| 5 | — | Wayland | `belum` | Sway/Hyprland/KDE jalan; GNOME menyatakan tidak didukung |
| 6 | — | Hapus core C# | `belum` | test Windows hijau; **izin maintainer `windows/`** |

---

## Gate end-to-end

| Gate | Fase | Input | Membuktikan | Dinilai di |
|---|---|---|---|---|
| `E2E-1` | 1 | hook JSON sintetis | kabel tersambung dua arah | Xvfb (smoke) → host Debian X11 (final) |
| `E2E-2` | 3, 4 | `claude` asli + hook terinstall | produk bekerja terhadap CLI nyata | host Debian; Windows QEMU/hardware |

---

## Log Checkpoint

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
- CI: Woodpecker, runner macOS (`local`). GitHub Actions tidak tersedia (billing). Belum ada lane Linux.
