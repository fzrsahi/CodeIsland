# ADR-001 — Arsitektur Windows & Linux: Tauri v2 + Rust core

- **Status:** Diterima (2026-11-16)
- **Konteks:** [issue #33](https://github.com/fzrsahi/CodeIsland/issues/33), [riset mygo vs Tauri](./research-mygo-vs-tauri.md), [rencana Linux](../linux/CodeIsland-Linux-Development-Plan.md), [rencana Windows](../windows/CodeIsland-Windows-Complete-Development-Plan.md)
- **Keputusan:** Windows + Linux dibangun sebagai **satu shell Tauri v2** di atas **satu Rust core**, dihubungkan lewat **kontrak hook JSON yang dibekukan**. macOS **tidak disentuh**.

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

## 7. Fase dan gate

Tiap fase punya gate. Jangan mulai fase berikutnya sebelum hijau.

### Fase A — Bekukan kontrak (3–4 hari, **tanpa Rust**)

| Tugas | Gate |
|---|---|
| Ekspor `BridgeGoldenFixtures`/`Expectations` → `fixtures/*.json` | `BridgeGoldenTests` tetap hijau |
| Pecah netral vs per-OS (`_ppid` 78×, `_term_bundle` 8×, `_term_app` 5×, `_tty` 3×, `_iterm_session` 2×) | 3 set expectation; netral identik lintas OS |
| **Fix `cursor_version` di `RawAgentEventNormalizer.cs`** (hari ini **0 match** di `windows/`) | Test baru: hook Cursor tidak muncul sebagai `claude`; `windows/CodeIsland.Core.Tests` hijau |
| JSON Schema untuk envelope + hook payload | Schema memvalidasi semua fixture |

Fase ini memberi hasil **walau Rust dibatalkan**. Kerjakan lebih dulu, tanpa kecuali.

### Fase B — Bridge Rust (1–2 minggu)

| Tugas | Gate |
|---|---|
| `codeisland-protocol` + `codeisland-ipc` (UDS/named pipe) | — |
| `codeisland-bridge` bin: stdin → envelope → socket, stdout contract | `fixtures/macos/*.json` **byte-identik** dengan bridge Swift |
| Deteksi proses/terminal per-OS (`_ppid`, `_term_app`, `_tty`) | `fixtures/windows/*` + `fixtures/linux/*` lulus di OS-nya |
| Perilaku tanpa listener | exit 0 dalam <10 ms, tidak pernah memblokir CLI |

**ROI tertinggi, risiko terendah.** 385 LOC → ~1.500 LOC. Langsung memberi 3-OS coverage.

### Fase C — Core Rust (3–4 minggu)

Urutan ketat: `reduceHookEvent` → `AttentionPolicy` → `GitBranchReader` → `MarkdownBlockParser` → `JSONLTailer` → `ESP32Protocol`.

Gate: conformance test terhadap `fixtures/neutral/*.json` = **100% identik** dengan output Swift. CI menolak dependensi OS di `codeisland-core`.

### Fase D — Platform adapters (2–3 minggu)

Gate: setiap trait punya `probe()`; tidak ada fitur yang gagal diam-diam; tabel capability tampil di Settings.

### Fase E — Shell Tauri, Windows dulu (3–4 minggu)

Gate G1–G5 (riset §5.2): click-through, panel di atas fullscreen tanpa mencuri fokus, Wayland layer-shell, p95 hook→render <300 ms, tidak ada frame >16 ms saat scroll.

### Fase F — Hook installer (2–3 minggu)

6.163 LOC (`ConfigInstaller` 4.315 + `RemoteInstaller` 1.848) — JSON, JSON5, YAML, TOML, merge yang mempertahankan komentar user, untuk 34 sumber. `serde_json` + `json5` + `saphyr` + `toml_edit`.

Gate: install/uninstall **byte-idempotent** untuk 34 sumber di 3 OS; uninstall mengembalikan backup byte-for-byte.

### Fase G — Migrasi C#, lalu hapus (1 minggu, **butuh izin maintainer**)

`windows/` masuk sebagai commit squashed `31116ab` oleh kontributor luar yang menyebut dirinya *"not an official Windows release"*. Menghapus `RawAgentEventNormalizer.cs` + `SessionStateMachine.cs` adalah keputusan sosial sebelum keputusan teknis.

Gate: `windows/CodeIsland.Core.Tests` hijau; sesi Cursor tidak lagi dobel.

---

## 8. Risiko

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

## 9. Yang eksplisit **tidak** dikerjakan

- FFI/UniFFI di macOS. Seam socket sudah ada.
- Port `Sources/CodeIsland` (79.044 LOC Swift) ke Rust.
- Notch hardware detection (`NSScreen.auxiliaryTopLeftArea`), Live Activities, Apple Companion (`MultipeerConnectivity`), Sparkle — Apple-only.
- `L10n.swift` (4.217 LOC) — pindahkan ke file resource (JSON/FTL), jangan port sebagai kode.
- Capture audio untuk visualizer — **terverifikasi sintetis** (`CAMusicCurves` = kurva sinus, tanpa `AVAudioEngine`/tap). Tidak ada yang perlu di-port.
- `iced` / `gpui` / `slint` / Avalonia — ditolak di ADR ini, lihat riset §5.4.

---

## 10. Konsekuensi

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
