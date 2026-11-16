# Rencana Arsitektur Windows & Linux — Tauri v2 + Rust core

**Status:** rencana yang berlaku (2026-11-16). Menggantikan rencana Avalonia di [`linux/`](../linux/CodeIsland-Linux-Development-Plan.md) dan rencana WPF di [`windows/`](../windows/CodeIsland-Windows-Complete-Development-Plan.md).

**Keputusan yang mendasari:** Windows + Linux dibangun sebagai **satu shell Tauri v2** di atas **satu Rust core**, dihubungkan lewat **kontrak hook JSON yang dibekukan**. macOS **tidak disentuh**. Alasannya ada di [ADR-0001](adr/0001-two-cores-one-contract.md) dan [ADR-0002](adr/0002-tauri-v2-shell.md), bukan di sini.

---

## 0. Peta dokumen — baca ini dulu

Ada beberapa dokumen dan tiga di antaranya pernah memuat daftar fase sendiri. Yang berlaku **hanya satu**: **§7 di bawah, yang identik dengan "Urutan Implementasi" di [#33](https://github.com/fzrsahi/CodeIsland/issues/33).** Kalau ada dokumen lain yang daftar fasenya berbeda, dokumen itu sudah usang.

| Dokumen | Perannya | Cari di sini kalau… |
|---|---|---|
| [`GLOSSARY.md`](../GLOSSARY.md) | Kosakata kanonik | bingung Source vs Agent vs Hook target |
| [`adr/0001`](adr/0001-two-cores-one-contract.md) | Keputusan: dua core | "kenapa bukan satu core?" |
| [`adr/0002`](adr/0002-tauri-v2-shell.md) | Keputusan: Tauri | "kenapa bukan mygo / Avalonia?" |
| **dokumen ini** | Arsitektur + **fase kanonik (§7)** | modul, seam, adapter, urutan kerja |
| [#33](https://github.com/fzrsahi/CodeIsland/issues/33) | Urutan + alasan urutan | "kenapa Linux dulu?" |
| [#47](https://github.com/fzrsahi/CodeIsland/issues/47) | Scope Windows, item W0–W6, acceptance W-001…W-008 | detail kerja Windows |
| [#48](https://github.com/fzrsahi/CodeIsland/issues/48) | Scope Linux, item L0–L7, acceptance L-001…L-011 | detail kerja Linux |
| [`handoff-windows-linux-port.md`](handoff-windows-linux-port.md) | Indeks + daftar jebakan | mulai dari mana, apa yang menipu |
| [`research-mygo-vs-tauri.md`](research-mygo-vs-tauri.md) | Bukti primer + pengukuran | angka mentah di balik ADR |
| [`linux/…Development-Plan.md`](../linux/CodeIsland-Linux-Development-Plan.md) | **Usang** — tapi masih berguna | acceptance L-001…L-012, analisis risiko Wayland |
| [`windows/…Development-Plan.md`](../windows/CodeIsland-Windows-Complete-Development-Plan.md) | **Usang** | riwayat saja; pilihan WPF/.NET sudah mati |

**Aturan korelasi.** `W#` dan `L#` di #47/#48 adalah **item kerja lokal, bukan urutan**. Urutan yang mengikat adalah fase 0–6 di §7. Tabel di tiap fase memetakan item lokal mana yang masuk fase mana.

---

## 1. Keputusan

| Lapisan | Pilihan | Alasan |
|---|---|---|
| Shell Windows/Linux | **Tauri v2** (Rust + webview OS) | Paritas visual 43 view SwiftUI jauh lebih murah di CSS/Canvas; ekosistem tray/updater/hotkey matang |
| Core Windows/Linux | **Rust** (`codeisland-core`) | Satu toolchain dengan shell; `windows` crate = WinRT lengkap (SMTC, UIA, Geolocation); `btleplug` untuk ESP32 |
| Bridge | **Rust** (`codeisland-bridge`) | Satu toolchain; 4,49 ms median (terukur) — setara Swift 5,3 ms |
| Frontend | **Svelte 5 + CSS + Canvas** | Rune untuk state, runtime kecil, spring via `svelte/motion` |
| macOS | **Tidak berubah** — SwiftUI/AppKit + Swift core 21.278 LOC | 64.728 LOC test sudah hijau; rewrite = risiko tanpa hasil |
| Transport | UDS (Linux) / Named Pipe (Windows), **sama seperti macOS** | Seam proses sudah ada dan terbukti |

**Jumlah core: dua** (Swift + Rust), bukan satu dan bukan tiga. Lihat §2.

---

## 2. Mengapa dua core, dan mengapa itu bukan kegagalan

Issue #33 menargetkan "satu core untuk tiga OS" sambil mempertahankan macOS di Swift. Itu kontradiktif: kalau macOS tetap Swift, core-nya minimal dua.

Yang bisa dicapai, dan yang kita kejar:

```
        ┌──────────────────────────────────────────────┐
        │  KONTRAK (satu-satunya hal yang harus stabil)│
        │  docs/hook-edge-protocol.md                  │
        │  fixtures/*.json  (netral + per-OS)          │
        │  JSON Schema envelope                        │
        └───────┬──────────────────────┬───────────────┘
                │                      │
        ┌───────▼────────┐    ┌────────▼──────────────┐
        │ macOS          │    │ Windows + Linux       │
        │ Swift core     │    │ Rust core             │
        │ 21.278 LOC     │    │ (target ~18K LOC)     │
        │ 64.728 LOC test│    │                       │
        └───────┬────────┘    └────────┬──────────────┘
                │                      │
        ┌───────▼────────┐    ┌────────▼──────────────┐
        │ SwiftUI/AppKit │    │ Tauri v2 + Svelte     │
        │ NSPanel notch  │    │ pill overlay          │
        └────────────────┘    └───────────────────────┘
```

Yang **tidak** kita lakukan: FFI/UniFFI di macOS. Seam socket sudah ada, sudah dipakai bridge, dan tidak menambah pajak pada platform yang menghasilkan 100% pendapatan hari ini.

---

## 3. Topologi proses

```
  claude / codex / gemini / cursor / … (34 sumber)
        │  hook JSON di stdin
        ▼
  ┌─────────────────────────┐
  │ codeisland-bridge       │  bin kecil, statis, tanpa runtime
  │ ~1.5K LOC Rust          │  exit 0 dalam <10 ms bila tak ada listener
  └───────────┬─────────────┘
              │ UDS / Named Pipe  (envelope JSON, versioned)
              ▼
  ┌─────────────────────────────────────────────────┐
  │ codeisland-app  (Tauri, satu proses)            │
  │                                                 │
  │  ┌───────────────────────────────────────────┐  │
  │  │ codeisland-core  (lib, MURNI — tanpa OS)  │  │
  │  │ reducer · attention · facts · jsonl ·     │  │
  │  │ git · markdown · esp32 · quota · merge    │  │
  │  └───────────────────────────────────────────┘  │
  │  ┌───────────────────────────────────────────┐  │
  │  │ codeisland-platform (lib, per-OS)         │  │
  │  │ nowplaying · terminal · hotkey · display  │  │
  │  │ tray · autostart · secrets · ble · audio  │  │
  │  └───────────────────────────────────────────┘  │
  │  ┌───────────────────────────────────────────┐  │
  │  │ webview: Svelte 5 (render + input saja)   │  │
  │  └───────────────────────────────────────────┘  │
  └─────────────────────────────────────────────────┘
```

Dua binary, satu proses app. **Tidak ada IPC core↔UI** — core adalah library in-process. Ini lebih sederhana daripada macOS (yang punya socket karena bridge terpisah) dan lebih sederhana daripada mygo/Tauri-daemon.

---

## 4. Layout workspace

```
rust/
├── Cargo.toml                    # workspace
├── crates/
│   ├── codeisland-protocol/      # envelope, serde, versioning
│   ├── codeisland-core/          # MURNI. CI menolak dependensi OS di sini.
│   ├── codeisland-ipc/           # endpoint abstraction: UDS | named pipe
│   ├── codeisland-platform/      # trait + impl per-OS
│   ├── codeisland-hooks/         # deteksi + install/uninstall hook (6.163 LOC surface)
│   └── codeisland-bridge/        # bin
├── app/                          # Tauri
│   ├── src-tauri/
│   └── src/                      # Svelte 5
└── fixtures/                     # hasil ekspor golden fixtures
    ├── neutral/*.json
    ├── macos/*.json
    ├── windows/*.json
    └── linux/*.json
```

**Aturan CI yang mengikat:** `codeisland-core` tidak boleh punya dependensi `windows`, `libc`, `zbus`, `btleplug`, `tokio::process`, atau `std::process`. Diperiksa dengan `cargo tree -p codeisland-core` di CI. Tanpa aturan ini, "core murni" akan bocor dalam 2 minggu.

---

## 5. Pembagian tanggung jawab

### 5.1 `codeisland-core` — murni, portabel, tanpa OS

Di-port dari Swift, **bukan didesain ulang**. Ini yang membuat conformance test bermakna.

| Modul Swift | LOC | Catatan |
|---|---|---|
| `SessionSnapshot.swift` → `reduceHookEvent` / `applyHookEvent` / `SideEffect` | ~1.200 | Pure function. Sudah jadi target test. **Port pertama.** |
| `AttentionPolicy.swift` | ~700 | Pure. Menentukan sound/push/completion. |
| `HookEventFacts` (di `AttentionPolicy.swift:316`) | — | 6 caller di `SessionSnapshot`. Ikut reducer. |
| `GitBranchReader.swift` | — | Baca `.git` langsung, **tanpa spawn git**. Port dengan `std::fs` saja — jangan pakai `gix`. |
| `MarkdownBlockParser.swift` | ~800 | Emit blok terstruktur JSON, bukan HTML. Frontend yang menggambar. |
| `NotchHoopsEngine.swift` | — | Fisika murni, `Sendable`. |
| `ESP32Protocol.swift` | ~600 | Protokol saja; transport di `platform`. |
| `ClaudeQuota.swift`, `PushChannel` (parsing) | — | |

**Bukan** di core: `HookIntake` (memanggil `proc_pidpath`, `/dev/tty`, parse `_iterm_session` — lihat `HookIntake.swift:551`). Itu di `platform` + `bridge`.

### 5.2 `codeisland-platform` — trait + impl per-OS

| Trait | Windows | Linux |
|---|---|---|
| `NowPlaying` (baca) | `windows` crate: `Media::Control::GlobalSystemMediaTransportControlsSessionManager` | `zbus` → `org.mpris.MediaPlayer2.*` |
| `TerminalActivator` | `EnumWindows` + `SetForegroundWindow` + UIA | `/proc/<pid>/cwd` + `xdotool`/`wmctrl`; kitty/wezterm/tmux IPC |
| `GlobalHotkey` | `RegisterHotKey` | X11 `XGrabKey`; Wayland: XDG Portal `GlobalShortcuts` |
| `Display` | monitor enumeration + `SHAppBarMessage` | layer-shell exclusive zone |
| `Tray` | `Shell_NotifyIcon` (Tauri built-in) | StatusNotifierItem (Tauri built-in) |
| `Autostart` | `HKCU\…\Run` | `~/.config/autostart/*.desktop` |
| `Secrets` | Credential Manager (`keyring`) | libsecret (`keyring`) |
| `Ble` | `btleplug` (WinRT) | `btleplug` (BlueZ) |
| `Audio` | `rodio` (sound effect saja) | `rodio` (PipeWire/Pulse) |

**Setiap trait wajib punya `probe() -> Capability`.** Fitur yang tidak didukung harus **dinyatakan tidak didukung di UI**, bukan gagal diam-diam. Ini acceptance criterion L-009 di rencana Linux, dan alasannya masih berlaku.

### 5.3 Frontend — render + input saja

**Tidak ada domain logic di TypeScript.** Aturan: kalau sebuah aturan bisa diuji tanpa browser, ia milik Rust.

| Swift | Frontend |
|---|---|
| 43 `*View.swift` | ~12 komponen + tabel aset. **22 mascot = satu `<Mascot>` + `mascots.ts`** (issue §2.5 benar) |
| `CAMusicCurves` (sine, terverifikasi **sintetis** — tidak ada audio capture) | `<canvas>` + `requestAnimationFrame`, port rumus 1:1 |
| Pixel art / `PixelText` | `<canvas>` + sprite sheet, `image-rendering: pixelated` |
| Git spine graph | SVG (bukan canvas — perlu aksesibilitas + seleksi) |
| Markdown | Blok JSON dari Rust → komponen Svelte |
| Spring / `spring-based physics` | `svelte/motion` spring, konstanta disalin dari Swift |

**Streaming:** pakai Tauri `Channel`, **bukan** `emit`. Coalesce di Rust pada 60 Hz. Jangan pernah push per-event — 500 sesi × 10 event/detik akan membunuh IPC.

**Virtualisasi wajib.** Pelajaran dari benchmark mygo (§2.2 riset): `Scroll` yang membangun 3.000 baris = 11 ms/frame; `List` virtualized = 0,2 ms. Di web masalahnya identik — pakai `@tanstack/svelte-virtual` untuk session list, git log, dan diff.

---

## 6. Tiga lubang Tauri dan cara menutupnya

Ini pekerjaan nyata yang harus dianggarkan, bukan detail.

### 6.1 Click-through per-region

Tauri hanya punya `set_ignore_cursor_events(bool)` — **whole window**. `tauri#2090` terbuka sejak 2021.

**Solusi: plugin kecil `tauri-plugin-input-region` (~150 LOC).**

| OS | Teknik |
|---|---|
| Windows | `SetWindowSubclass` + `WM_NCHITTEST` → kembalikan `HTTRANSPARENT` di luar region |
| Linux X11 | `XShapeCombineRectangles(dpy, win, ShapeInput, …)` |
| Linux Wayland | `wl_surface.set_input_region`; GTK3 `gtk_widget_input_shape_combine_region` |

Frontend mengirim rect via command setiap layout berubah. **Fallback** bila gagal: window tight-fit ke konten (island memang resize saat collapsed→expanded), jadi click-through tidak dibutuhkan sama sekali. Fallback ini harus ada sejak hari pertama.

### 6.2 Nonactivating window

| OS | Teknik |
|---|---|
| Windows | `WS_EX_NOACTIVATE` via `SetWindowLongPtr` setelah window dibuat |
| Linux | layer-shell `keyboard-interactivity: none` |

### 6.3 Layer-shell di Wayland

`tauri#15913` ditutup Okt 2026 dengan workaround: `visible(false)` → init layer shell → `show()`. Menunggu migrasi GTK4.

**Rencana:** implementasikan workaround di `codeisland-platform`, dan **degradasi eksplisit** di GNOME (tidak ada layer-shell): panel jadi window biasa, UI menyatakan "anchoring tidak tersedia". Ini persis risiko #1 di rencana Linux §6 — tidak berubah oleh pilihan framework.

---

## 7. Fase dan gate — **daftar kanonik**

Sama persis dengan "Urutan Implementasi" di [#33](https://github.com/fzrsahi/CodeIsland/issues/33). Kalau keduanya berbeda, itu bug — perbaiki #33 dan dokumen ini bersamaan.

Tiap fase punya gate. **Jangan mulai fase berikutnya sebelum hijau.** Kolom "Item lokal" memetakan ke penomoran `W#`/`L#` di #47/#48, yang merupakan item kerja, bukan urutan.

| Fase | Fokus | OS | Item lokal |
|---|---|---|---|
| 0 | Bekukan kontrak | — | W0 = L0 |
| 1 | Vertical slice | Linux X11 | L1 + separuh L4 |
| 2 | Core conformance | — | L2 = W2 |
| 3 | Linux lengkap | Linux X11 | L3, L4, L6, L7 |
| 4 | Windows | Windows | W1, W3, W4, W5, W7 |
| 5 | Wayland | Linux | L5 |
| 6 | Hapus core C# | Windows | W6 |

### Fase 0 — Bekukan kontrak (3–4 hari, **tanpa Rust**)

| Tugas | Gate |
|---|---|
| Ekspor `BridgeGoldenFixtures`/`Expectations` → `fixtures/*.json` | `BridgeGoldenTests` tetap hijau |
| Pecah netral vs per-OS (`_ppid` 78×, `_term_bundle` 8×, `_term_app` 5×, `_tty` 3×, `_iterm_session` 2×) | 3 set expectation; netral identik lintas OS |
| **Fix `cursor_version` di `RawAgentEventNormalizer.cs`** (hari ini **0 match** di `windows/`) | Test baru: hook Cursor tidak muncul sebagai `claude`; `windows/CodeIsland.Core.Tests` hijau |
| JSON Schema untuk envelope + hook payload | Schema memvalidasi semua fixture |

Fase ini memberi hasil **walau Rust dibatalkan**. Kerjakan lebih dulu, tanpa kecuali. **Jangan menulis Rust di fase ini.**

### Fase 1 — Vertical slice Linux X11 (2–3 minggu)

Satu jalur tipis ujung ke ujung. **Bukan** port core.

| Dibangun | Tidak dibangun |
|---|---|
| Workspace `rust/` + `codeisland-protocol` + `codeisland-ipc` (UDS saja) | Port `reduceHookEvent` |
| `codeisland-bridge` untuk **satu** hook target (Claude Code) | Adapter platform, tray, hotkey, settings |
| Satu window Tauri: frameless, transparent, always-on-top, click-through | Packaging, 33 source lainnya |
| Reduksi trivial (session id + state) | Installer hook |

**Gate: `E2E-1`.**

```
hook JSON sintetis  →  bridge send --stdin  →  app  →  panel menampilkan sesi
                                                    →  klik Approve
                                                    →  bridge mencetak response JSON ke stdout
```

Lulus bila: response valid terhadap `fixtures/neutral/`, ujung ke ujung **<300 ms**, dan klik di area transparan menembus ke window di bawahnya.

`E2E-1` sengaja sintetis — tanpa installer, tanpa CLI asli — supaya loop-nya terbukti di minggu 2, bukan minggu 9.

Kalau gate ini gagal, **berhenti dan laporkan**. Jangan lanjut ke fase 2 sebelum tahu apakah Tauri bisa jadi island overlay sama sekali.

### Fase 2 — Core conformance (3–4 minggu)

Urutan ketat: `reduceHookEvent` → `AttentionPolicy` → `HookEventFacts` → `GitBranchReader` → `MarkdownBlockParser` → `JSONLTailer` → `ESP32Protocol`.

Gate: conformance terhadap `fixtures/neutral/*.json` = **100% identik** dengan output Swift. CI menolak dependensi OS di `codeisland-core` (`cargo tree -p codeisland-core`).

### Fase 3 — Linux lengkap (3–4 minggu)

9 hook target → 34 source, adapter platform + `probe()`, tray, hotkey, autostart, settings, installer hook, packaging.

Gate: `L-001…L-011` (minus yang khusus Wayland) **dan `E2E-2`.**

**`E2E-2` — loop terhadap CLI asli:**

```
install hook untuk `claude`  →  jalankan `claude`  →  ia memicu PreToolUse
   →  panel menampilkan permintaan izin  →  klik Approve
   →  `claude` benar-benar melanjutkan tool call
```

Lulus bila: `claude` lanjut tanpa timeout, **deny juga bekerja**, dan tidak ada event dobel. `E2E-1` membuktikan kabelnya; `E2E-2` membuktikan produknya.

### Fase 4 — Windows (3–4 minggu)

Port shell (Win32 plumbing: `WM_NCHITTEST` → `HTTRANSPARENT`, `WS_EX_NOACTIVATE`), adapter WinRT (SMTC, UIA, BLE), named pipe, NSIS.

Gate: `W-001…W-008` **dan `E2E-2`** di Windows.

Yang diwarisi gratis: shell yang sudah terbukti di X11, core yang sudah conformance, logika installer yang sudah teruji.

### Fase 5 — Wayland (2 minggu)

Layer-shell workaround (`tauri#15913`), `wl_surface.set_input_region`, XDG Portal `GlobalShortcuts`, degradasi eksplisit di GNOME.

Gate: jalan di Sway/Hyprland; di GNOME panel menjadi window biasa dan UI menyatakan **"anchoring tidak tersedia"**. Jangan disimulasikan.

### Fase 6 — Migrasi C#, lalu hapus (1 minggu, **butuh izin maintainer**)

`windows/` masuk sebagai commit squashed `31116ab` oleh kontributor luar yang menyebut dirinya *"not an official Windows release"*. Menghapus `RawAgentEventNormalizer.cs` + `SessionStateMachine.cs` adalah keputusan sosial sebelum keputusan teknis.

Gate: `windows/CodeIsland.Core.Tests` hijau; sesi Cursor tidak lagi dobel.

### Ringkasan gate end-to-end

| Gate | Fase | Input | Membuktikan |
|---|---|---|---|
| `E2E-1` | 1 | hook JSON sintetis | kabelnya tersambung, dua arah, di satu OS |
| `E2E-2` | 3, 4 | `claude` asli + hook terinstall | produknya bekerja terhadap CLI nyata |

---

## 8. Slicing PR

`.github/pull_request_template.md` memaksa tiga hal di setiap PR: **Summary + Evidence + Merge Danger (door type)**. Itu sendiri sudah menjadi aturan slicing.

**Satu PR per satu persilangan dari tiga sumbu:**

| Sumbu | Kalau dilanggar |
|---|---|
| **Bahasa** | Swift + C# dalam satu PR = reviewer Swift harus mereview C# |
| **Jenis bukti** | log `swift test` + log `dotnet test` = dua blok Evidence yang tidak berhubungan |
| **Door type** | refactor reversibel + direktori top-level baru dalam satu PR = reviewer tidak bisa menilai risiko |

**Aturan tambahan:** gate milik **PR terakhir** dalam satu stack. PR yang tidak bisa membuktikan gate-nya sendiri harus di-stack di belakang PR yang bisa.

### Urutan PR

| # | Judul | Bahasa | Door | Evidence |
|---|---|---|---|---|
| 1 | `docs(#33)`: ADRs, glossary, plan, handoff | md | two-way | — |
| 2 | `test(#33)`: ekspor golden fixtures ke JSON + schema | Swift + JSON | two-way | `BridgeGoldenTests` hijau, log `swift test` |
| 3 | `fix(#33)`: hormati `cursor_version` di Windows | **C# saja** | two-way | `windows/CodeIsland.Core.Tests` + payload sebelum/sesudah |
| 4 | `chore(#33)`: workspace Rust, protocol, ipc, CI purity check | Rust | **one-way** (direktori top-level baru) | `cargo test` + `cargo tree -p codeisland-core` bersih |
| 5 | `feat(#33)`: bridge untuk `claude` | Rust | two-way | conformance `fixtures/macos/*` byte-identik |
| 6 | `feat(#33)`: vertical slice island Linux X11 | Rust + TS | **one-way** (shell pertama) | GIF + log **`E2E-1`** |

PR 4 → 5 → 6 **di-stack**, karena `E2E-1` baru lulus di PR 6.

Setelah fase 1, fase 2 paling mudah di-slice — **satu PR per modul**, masing-masing satu file + satu conformance test, nol UI dan nol OS:

```
feat(core): port reduceHookEvent       → conformance fixtures/neutral
feat(core): port AttentionPolicy       → conformance
feat(core): port GitBranchReader       → conformance
feat(core): port MarkdownBlockParser   → conformance
feat(core): port JSONLTailer           → conformance
```

Fase 3 ke atas: **satu PR per adapter** (nowplaying, terminal, hotkey, tray), masing-masing dengan `probe()` yang bisa dinilai sendiri.

### Kenapa `cursor_version` harus PR sendiri

Ia **bug fix di kode orang lain**. Kalau digabung ke PR fixtures: maintainer `windows/` harus mereview PR yang 90%-nya file Swift, bug fix yang bisa ship hari ini tertahan berminggu-minggu, dan me-revert fixtures ikut menghapus fix-nya. Sebagai PR sendiri ia bisa di-merge independen **bahkan kalau seluruh port dibatalkan**.

### Ukuran

- PR non-UI: jaga **≤ ~400 baris diff**. Kalau lewat, biasanya ada dua concern yang tercampur.
- PR UI: ukuran tidak menentukan; **Evidence yang menentukan** — GIF dan log `E2E-1`.

---

## 9. Risiko

| Risiko | Dampak | Mitigasi |
|---|---|---|
| Layer-shell Wayland tidak stabil di GTK3 | Tinggi | Degradasi eksplisit; X11 jalur utama; jangan pura-pura |
| Click-through per-region butuh patch platform | Sedang | Fallback tight-fit window sejak hari pertama |
| Memori webview (WebView2/WebKitGTK) ~125–185 MB | Sedang | Diterima. Satu window, bukan dua. Ukur di Fase E |
| Dua core (Swift + Rust) menyimpang | **Tinggi** | Kontrak + fixtures adalah satu-satunya pertahanan. Setiap perbaikan provider wajib update fixture |
| `cursor_version`-class bug terulang | Tinggi | Schema + fixture per-OS di CI, bukan review manual |
| Governance `windows/` | Sedang | Selesaikan sebelum Fase G, bukan sesudah |
| 43 view SwiftUI → Svelte menyimpang visual | Sedang | Data-driven; screenshot diff di CI untuk 12 komponen inti |

---

## 10. Yang eksplisit **tidak** dikerjakan

- FFI/UniFFI di macOS. Seam socket sudah ada.
- Port `Sources/CodeIsland` (79.044 LOC Swift) ke Rust.
- Notch hardware detection (`NSScreen.auxiliaryTopLeftArea`), Live Activities, Apple Companion (`MultipeerConnectivity`), Sparkle — Apple-only.
- `L10n.swift` (4.217 LOC) — pindahkan ke file resource (JSON/FTL), jangan port sebagai kode.
- Capture audio untuk visualizer — **terverifikasi sintetis** (`CAMusicCurves` = kurva sinus, tanpa `AVAudioEngine`/tap). Tidak ada yang perlu di-port.
- `iced` / `gpui` / `slint` / Avalonia — ditolak di ADR ini, lihat riset §5.4.

---

## 11. Konsekuensi

**Positif**
- Satu shell untuk Windows + Linux, satu core Rust, satu bridge.
- WinRT lengkap → SMTC, UIA, BLE, Geolocation semuanya terjangkau.
- Paritas visual cepat: 43 view → ~12 komponen + tabel aset.
- macOS tidak berisiko.
- Kontrak beku berguna walau Rust dibatalkan.

**Negatif**
- Memori ~125–185 MB (webview), bukan ~34 MB (mygo native).
- Tiga bahasa di repo: Swift, Rust, TypeScript.
- Tiga lubang Tauri (§6) harus ditutup sendiri — ~1–2 minggu kerja yang tidak menghasilkan fitur.
- Dua core tetap dua core. Tidak ada jalan ke satu core tanpa menyentuh macOS.
