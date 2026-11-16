# Progress — Windows & Linux port

**Status:** fase 0 diimplementasikan secara lokal (PR 2 di `test/#33-export-golden-fixtures`, PR 3 di `fix/#33-windows-cursor-version`); menunggu push/PR dan verifikasi `dotnet test` di Windows CI.
**Checkpoint terakhir:** 2026-11-16 — ekspor 84×4 golden fixtures ke JSON + JSON Schemas + fix `cursor_version` C# selesai lokal.
**Fase kanonik:** [`plan-windows-linux.md`](plan-windows-linux.md) §7. Kalau dokumen ini berbeda dengan §7, §7 yang benar.

---

## Kalau kamu baru masuk, jawab tiga ini dulu

1. **Fase mana yang sedang berjalan?** → lihat kolom Status di papan di bawah.
2. **Apa gate-nya?** → §7 plan, atau tabel gate di bawah.
3. **Apa yang memblokir?** → entri teratas di Log Checkpoint.

Jangan mulai bekerja sebelum ketiganya jelas. Kalau tidak jelas, itu sendiri berarti checkpoint terakhir kurang lengkap — lengkapi dulu.

---

## Cara pakai dokumen ini

- **Update setelah setiap PR dibuka, di-merge, atau gagal** — bukan hanya saat selesai.
- **Update juga saat berhenti**, walaupun pekerjaannya setengah jadi. Justru itu gunanya.
- **Jangan hapus baris.** Ubah kolom Status, atau tambah baris baru kalau PR-nya dipecah.
- **Log Checkpoint bersifat append-only, terbaru di atas.** Formatnya tiga baris: *sudah apa*, *berikutnya apa*, *blocker apa*.
- Commit perubahan dokumen ini **di branch yang sedang dikerjakan**, bukan branch terpisah. Konflik di sini biasanya sepele.

---

## Papan status

Status: `belum` · `sedang` · `PR dibuka` · `merged` · `gagal` · `dilewati`

| Fase | PR | Isi | Status | Gate |
|---|---|---|---|---|
| — | 1 | `docs(#33)`: ADRs, glossary, plan, handoff | `PR dibuka` | — |
| 0 | 2 | `test(#33)`: ekspor golden fixtures ke JSON + schema | `sedang` | `BridgeGoldenTests` hijau; schema memvalidasi semua fixture |
| 0 | 3 | `fix(#33)`: hormati `cursor_version` di Windows | `sedang` | `windows/CodeIsland.Core.Tests` hijau; hook Cursor tidak muncul sebagai `claude` |
| 1 | 4 | `chore(#33)`: workspace Rust, protocol, ipc, CI purity check | `belum` | `cargo test`; `cargo tree -p codeisland-core` bersih |
| 1 | 5 | `feat(#33)`: bridge untuk `claude` | `belum` | `fixtures/macos/*` byte-identik dengan bridge Swift |
| 1 | 6 | `feat(#33)`: vertical slice island Linux X11 | `belum` | **`E2E-1`** — dua arah, <300 ms |
| 2 | 7–11 | `feat(core)`: reducer, attention, git, markdown, jsonl | `belum` | 100% fixture netral identik dengan Swift |
| 3 | 12+ | Linux lengkap: adapter, installer, packaging | `belum` | `L-001…L-011` + **`E2E-2`** |
| 4 | — | Windows | `belum` | `W-001…W-008` + **`E2E-2`** |
| 5 | — | Wayland | `belum` | Sway/Hyprland jalan; GNOME menyatakan tidak didukung |
| 6 | — | Hapus core C# | `belum` | Windows tests hijau; **butuh izin maintainer `windows/`** |

PR 4 → 5 → 6 di-stack. Lihat plan §8 untuk aturan slicing.

---

## Gate end-to-end

| Gate | Fase | Input | Membuktikan |
|---|---|---|---|
| `E2E-1` | 1 | hook JSON sintetis, tanpa installer, tanpa CLI asli | kabelnya tersambung **dua arah** di satu OS |
| `E2E-2` | 3, 4 | `claude` asli dengan hook terinstall | produknya bekerja terhadap CLI nyata |

`E2E-1` sengaja sintetis supaya round-trip terbukti di minggu 2, bukan minggu 9.

---

## Log Checkpoint

### 2026-11-16 — fase 0 (kontrak JSON, schema, dan `cursor_version` Windows)

- **Sudah:** ekspor 84×4 fixture (`fixtures/{neutral,macos,linux,windows}/*.json`) lewat `BridgeGoldenJSONExporter.swift` + verifikasi di `BridgeGoldenTests`, 3 JSON Schema Draft 2020-12 (`schemas/hook-payload.schema.json`, `schemas/hook-envelope.schema.json`, `schemas/golden-fixture.schema.json`) + `scripts/validate-fixtures.py` (336 file tervalidasi + self-test hijau) di branch `test/#33-export-golden-fixtures`; implementasi `cursor_version` + 3 unit test di `windows/CodeIsland.Protocol/RawAgentEventNormalizer.cs` & `windows/CodeIsland.Core.Tests/RawAgentEventNormalizerTests.cs` di branch `fix/#33-windows-cursor-version` (bercabang dari `origin/main`).
- **Berikutnya:** push branch `docs/#33-windows-linux-architecture`, `test/#33-export-golden-fixtures`, dan `fix/#33-windows-cursor-version`; buka PR 1, PR 2, dan PR 3; jalankan `dotnet test` lewat Windows CI (`.github/workflows/windows.yml`) sebelum merge PR 3; lalu lanjut fase 1 PR 4 (`rust/` workspace) setelah gate fase 0 hijau penuh.
- **Blocker:** `.NET 8 SDK` (`dotnet`) tidak terpasang di mesin dev macOS arm64, sehingga `windows/CodeIsland.Core.Tests` belum dapat dieksekusi secara lokal (perlu Windows CI atau mesin dengan `dotnet` 8.0).

### 2026-11-16 — dokumen arsitektur

- **Sudah:** riset mygo vs Tauri, verifikasi klaim issue #33 ke codebase, ADR-0001 (dua core), ADR-0002 (Tauri), `GLOSSARY.md`, plan + §7 fase kanonik + §8 slicing PR, handoff, sub-issue #47 dan #48 + komentar urutan, #33 body diperbarui dengan urutan + gate E2E.
- **Berikutnya:** push branch `docs/#33-windows-linux-architecture`, buka PR, lalu mulai fase 0 PR 2 (ekspor fixtures).
- **Blocker:** tidak ada. Catatan: `docs/research-mygo-vs-tauri.md` di-force-add melewati `.gitignore:83`; kalau aturan itu harus berlaku, `git rm --cached` sebelum merge.

---

## Fakta lingkungan yang memengaruhi progress

- Mesin dev macOS arm64. `go` 1.27.0, `rustc` 1.98.0 terpasang.
- **Tidak ada mesin Windows atau Linux.** Semua klaim perilaku Windows/Linux di dokumen adalah turunan dokumentasi, bukan pengukuran. Ini berarti fase 1 butuh mesin Linux (VM/container/hardware) sebelum gate `E2E-1` bisa dinilai.
- CI: `.github/workflows/` punya macOS XCTest + `windows.yml`. Belum ada job Linux — fase 1 perlu menambahkannya.
