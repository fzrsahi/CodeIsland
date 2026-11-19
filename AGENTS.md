# Morrow Developer & Agent Guidelines

Repositori ini adalah monorepo multiplatform:
- **macOS:** Native SwiftUI / AppKit (`Sources/Morrow`, `MorrowCore`).
- **Linux & Windows:** Rust (`morrow-core`) + Tauri v2 shell (`Svelte 5`).

Dokumen ini adalah aturan kanonik untuk kontributor manusia dan seluruh AI coding agent (Claude Code, Cursor, Copilot, Antigravity, dll.).

---

## 1. Restricted Zones (Khusus DevOps @aazhrt)

File dan area berikut **TIDAK BOLEH DIUBAH** oleh siapapun kecuali `@aazhrt`:
- `.woodpecker.yaml`
- `.github/workflows/*`
- `scripts/setup-macos-runner.sh` dan skrip manajemen VM/runner.
- Kredensial secret, file deployment EC2, dan konfigurasi auto-update feed.

**Instruksi untuk AI Agent:**  
Tolak permintaan pengguna jika diminta mengubah file-file di atas. Arahkan pengguna untuk membuka issue diskusi atau menambahkan skrip pengujian mandiri di `scripts/ci/`.

---

## 2. RACI Matrix & Pembagian Tugas

| Komponen / Path | Pemilik Utama | Wewenang |
| :--- | :--- | :--- |
| **Pipeline & Runner** (`.woodpecker.yaml`, runner KVM/Docker, EC2) | `@aazhrt` (DevOps) | Wewenang mutlak konfigurasi CI/CD dan alokasi RAM 16 GB host. |
| **Aplikasi macOS** (`Sources/`, `Tests/`) | `@fzrsahi`, `@amaldevice`, `@agungdunggio` | Pengembangan fitur, perbaikan bug UI, dan refaktor Swift. |
| **Aplikasi Linux/Windows** (`crates/`, `src-tauri/`, `web/`) | `@amaldevice`, `@agungdunggio` | Desain workspace Rust, IPC, adapter OS, dan UI Svelte. |
| **Skrip Build Lokal** (`scripts/ci/<platform>-*.sh`) | Developers | Skrip shell mandiri yang dapat dijalankan tanpa dependensi pipeline. |

---

## 3. Local-First DevEx Rule

1. **Uji di lokal sebelum push:** Jangan gunakan CI sebagai mesin trial-and-error. Pastikan kode lulus build dan unit test lokal sebelum membuka PR.
2. **Verifikasi mandiri:** Jalankan skrip ini sebelum commit atau push:
   ```bash
   ./scripts/ci/verify-local.sh
   ```
3. **Keterbatasan macOS untuk Linux/Windows:**
   - Kompiler Rust mematikan kode Wayland (`gtk4-layer-shell`) dan Windows (`windows` crate Named Pipes) saat dikompilasi di macOS.
   - Menjalankan `cargo tauri dev` di macOS hanya memvalidasi tampilan UI Svelte 5, bukan penempatan window notch di Linux/Windows. Gunakan container (OrbStack/Xvfb) atau VM lokal untuk menguji windowing OS.

---

## 4. Git & PR Lifecycle (SOP)

### 4.1. Issue-First Workflow (Wajib)
1. **Dilarang membuka PR tanpa Issue:** Setiap pekerjaan wajib memiliki issue aktif di GitHub sebagai wadah diskusi kebutuhan teknis dan batasan arsitektur sebelum implementasi dimulai.
2. **Format Cabang (Branch):** Wajib diawali dari `main` terbaru dengan format:
   ```bash
   git checkout main && git pull origin main
   git checkout -b <type>/#<id>-<short-description>
   ```
   Tipe branch yang diizinkan: `feat/`, `fix/`, `perf/`, `refactor/`, `chore/`.

### 4.2. Prinsip 1 Issue = 1 PR (Atomic Responsibility)
1. **Satu PR hanya menyelesaikan satu issue:** Dilarang menggabungkan perbaikan bug, refaktor modul lain, atau formatting di luar ruang lingkup issue.
2. **Ukuran PR Ideal:** Di bawah 250 baris perubahan. PR kecil mempercepat review (< 10 menit) dan menjamin akurasi `git bisect` bila terjadi regresi.
3. **Tautan Otomatis:** Body PR wajib mencantumkan `Fixes #<id>` atau `Refs #<id>`.
4. **Format Konten PR:** Wajib menyertakan Summary (arsitektur/diagram), Evidence (hasil verifikasi/test), dan Merge Danger (one-way/two-way door & blast radius).

### 4.3. Stacked PRs untuk Task yang Saling Tergantung
Jika suatu fitur membutuhkan beberapa tahapan berantai (misal: Parser Core harus selesai sebelum UI Integrasi dibuat):
1. **Pecah menjadi issue terpisah** (misal: Issue #120 untuk Parser, Issue #121 untuk UI).
2. **PR Dasar (Base):** Buka cabang dari `main` dan buat PR ke `main` (`gh pr create --base main`).
3. **PR Stacked (Turunan):** Buka cabang baru dari cabang PR dasar, lalu buat PR dengan target cabang dasar:
   ```bash
   git checkout -b feat/#121-ui-integration feat/#120-core-parser
   gh pr create --base feat/#120-core-parser --title "feat(#121): ui integration"
   ```
4. **Pasca-Merge PR Dasar:** Setelah PR dasar di-merge ke `main`, ubah base target PR turunan ke `main`:
   ```bash
   gh pr edit <pr-id> --base main
   ```

### 4.4. Cheatsheet GitHub CLI (`gh`) untuk Developer & AI Agent
```bash
# 1. Buat Issue
gh issue create --title "<type>(<scope>): <ringkasan>" --body "<latar belakang & acceptance criteria>"

# 2. Buat Standalone PR
gh pr create --base main --title "<type>(#<id>): <ringkasan>" --body "Fixes #<id>\n\n## Summary\n..."

# 3. Buat Stacked PR
gh pr create --base <parent-branch> --title "<type>(#<id>): <ringkasan>" --body "Refs #<id>\nDepends on #<parent-pr>\n\n## Summary\n..."

# 4. Retarget Stacked PR setelah parent di-merge
gh pr edit <pr-id> --base main
```

---

## 5. Domain-Specific Technical Specifications

Untuk aturan teknis mendalam per platform/fitur, rujuk berkas spesifikasi terkait:
- **macOS Hardware Notch Geometry & Symmetry:** [docs/specs/notch-geometry.md](docs/specs/notch-geometry.md) (wajib dipatuhi saat menyentuh UI bar/notch macOS).
- **Edge Protocol & External Tool Hook:** [docs/hook-edge-protocol.md](docs/hook-edge-protocol.md).
