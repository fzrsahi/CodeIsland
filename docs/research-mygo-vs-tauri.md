# mygo vs Tauri — Riset Performa untuk Porting CodeIsland ke Windows & Linux

> Tanggal riset: 2026-11-16
> Konteks: [issue #33](https://github.com/fzrsahi/CodeIsland/issues/33) — "[ARCH] Riset & Peluang Rewrite ke Rust untuk Native Support Windows & Linux"
> Repo yang diriset: [`egoist/mygo`](https://github.com/egoist/mygo) @ `v0.9.1` (2026-11-15), [`tauri-apps/tauri`](https://github.com/tauri-apps/tauri) v2
> **Batasan:** tidak ada mesin Windows/Linux di lingkungan riset ini. Semua klaim perilaku Windows/Linux di bawah berasal dari dokumentasi primer + issue tracker, **bukan** pengukuran sendiri. Yang benar-benar diukur di sini hanya satu: biaya spawn binary bridge (macOS).

---

## TL;DR — 5 poin

1. **Pertanyaannya salah kaprah.** mygo bukan alternatif Tauri. mygo punya **dua mode**: mode *webview* (WKWebView / WebKitGTK / WebView2) yang **secara arsitektur identik dengan Tauri**, dan mode *native UI* yang digambar sendiri di GPU tanpa webview. Jadi perbandingan yang bermakna bukan "mygo vs Tauri", tapi **"CodeIsland butuh WebView atau tidak?"**
2. **Kalau tidak butuh WebView, selisihnya besar dan terukur.** mygo native: **34,1 MB** RAM diam, **9,7 MB** binary, **173 ms** startup, **0,01%** CPU idle. Tauri: memori didominasi WebView2/WebKitGTK (~125 MB USS / 185 MB PSS untuk app default di Ubuntu, pengukuran komunitas). Untuk satu panel kecil di atas notch, 34 MB vs ~150 MB adalah argumen produk, bukan argumen mikro-optimasi.
3. **Yang benar-benar menentukan untuk CodeIsland bukan framework UI, tapi window plumbing** — transparent + click-through + always-on-top + nonactivating + layer-shell + tray + global hotkey. Di sini mygo menang telak: `Panel`, `SetInputRegion` (click-through **per-region**), dan `gtk-layer-shell` sudah jadi API kelas satu. Tauri **tidak** punya click-through per-region (issue `tauri#2090` terbuka sejak 2021, masih terbuka) dan layer-shell harus diakali per-window (`tauri#15913`, ditutup Okt 2026 dengan workaround, menunggu migrasi GTK4).
4. **Argumen "bridge harus Rust karena cold start" gugur.** Diukur: Go `5,31 ms` vs Rust `4,49 ms` median (25 run, macOS arm64). Keduanya sudah di lantai biaya `fork/exec` OS — dan angka Swift di Addendum v3 issue #33 adalah `5,3 ms`. Bahasa tidak menentukan; yang menentukan adalah zero-runtime-dependency, dan Go juga static single binary.
5. **Tapi mygo baru berumur 7 minggu** (repo dibuat 2026-09-26, `v0.9.1`, 136 open issues, 920/1100 commit dari satu orang). Tauri v2 sudah production sejak 2024. Jadi rekomendasinya bukan "pilih mygo", tapi **"jalankan spike 2 hari dengan 5 gate yang sudah terdefinisi"** — karena semua pertanyaan lain sudah terjawab dokumentasi.

---

## 1. Apa itu mygo (fakta primer)

Sumber: [mygo.run/docs](https://mygo.run/docs), [README](https://github.com/egoist/mygo).

| Aspek | Fakta |
|---|---|
| Bahasa | Go murni, **tanpa cgo** (`CGO_ENABLED=0` default di CLI) |
| Cross-compile | Dari mesin apa pun ke `darwin/universal`, `windows/amd64+arm64`, `linux/amd64+arm64` |
| Mode UI | (a) **web page** di webview OS — WKWebView / WebKitGTK / WebView2; (b) **native UI** digambar mygo sendiri |
| Renderer native | Metal (macOS), Direct3D 11 + WARP fallback (Windows), OpenGL via `GtkGLArea` (Linux); CPU renderer tersedia (`MYGO_GPU=0`) |
| Toolkit native | flexbox/grid, widget, text editing + IME, virtualized list, SVG, animasi, screen reader, shader (syntax Go), spring motion, Markdown |
| Desktop API | window, menu, tray, dialog, notification, **global shortcut**, deep link, file association, recent docs, **Now Playing + media keys**, accent color, aksesibilitas, file watch |
| Packaging | `.app`+`.dmg` (macOS, sign+notarize), `.exe`+installer NSIS (Windows), `.tar.gz`+`.deb`+`.rpm`+PKGBUILD (Linux) |
| Auto-update | Signed, delta update, "update window in the manner of Sparkle" |
| Lisensi | MIT |

**Yang penting dipahami:** mygo menempati ceruk yang sama dengan Tauri *plus* satu mode tambahan yang tidak dimiliki Tauri sama sekali. Kalau kamu memakai mygo mode webview, kamu mendapat arsitektur Tauri dengan backend Go, bukan Rust.

---

## 2. Performa terukur

### 2.1 mygo native UI vs framework native lain

Sumber: [mygo.run/benchmarks](https://mygo.run/benchmarks) — Apple M5, 32 GB, 5 run, diukur 2026-11-05. **Angka vendor**, satu mesin, satu OS.

| Metrik | mygo | GPUI | GPUI Fast | egui |
|---|---|---|---|---|
| Ukuran app (release, stripped) | 9,7 MB | 3,7 MB | 6,3 MB | 8,7 MB |
| Startup → frame pertama | 173 ms | 157 ms | 163 ms | 163 ms |
| **Memori diam** | **34,1 MB** | 33,7 MB | 34,6 MB | 58,4 MB |
| CPU diam | 0,01% | 0,42% | 0,01% | 0,01% |
| CPU/frame — list 100k baris | 2,71 ms | 2,54 ms | 1,46 ms | 2,13 ms |
| CPU/frame — dashboard 600 sel | 5,71 ms | 13,9 ms | 5,76 ms | 5,43 ms |
| CPU/frame — resize dokumen 20k char | 4,92 ms | 3,03 ms | 3,04 ms | 6,04 ms |
| Peak memori — list 100k baris | 111 MB | 93,8 MB | 117 MB | 168 MB |
| Peak memori — dashboard | 138 MB | 106 MB | 122 MB | 145 MB |

Bacaan: mygo **tidak** lebih cepat dari framework native lain. Ia setara. Keunggulannya relatif terhadap Tauri bukan "lebih cepat dari Rust", tapi **"tidak memuat WebView"**.

### 2.2 Biaya per frame mygo native (headless, CPU)

Sumber: [mygo.run/docs/ui/performance](https://mygo.run/docs/ui/performance) — Apple M5, `GOMAXPROCS=1`.

| Fixture | Waktu/frame | Alokasi/frame |
|---|---|---|
| 1.000 label statis | 397 µs | 0 |
| Baris terlihat dari list 1 juta baris | 14,5 µs | 20 (176 B) |
| Markdown 50 KB, utuh | 1,3 ms | 353 |
| Markdown 50 KB, streaming 16 B/frame | 0,8 ms | 350 |
| 1 label berubah dari 3.000 baris di `Scroll` | 11 ms | — |
| 1 label berubah dari 3.000 baris di `List` | 0,2 ms | — |
| Mengetik 1 huruf di field atas 3.000 baris | 17 ms | — |

Memori retensi: view 1.000 label ≈ **2,50 MB** Go heap.

**Ini relevan langsung ke CodeIsland.** Dua angka terakhir adalah jebakan arsitektural: mygo membangun ulang seluruh view tiap frame dan biayanya tumbuh dengan *jumlah elemen yang dibangun*, bukan dengan *apa yang berubah*. `Scroll` yang membangun 3.000 baris = 11 ms/frame. `List`/`Table` yang virtualized = 0,2 ms. Artinya port CodeIsland **wajib** memakai `List`/`Table` untuk session list, git graph, dan diff — persis seperti macOS yang sudah punya `Zero-Lag Async Engine` untuk alasan yang sama.

### 2.3 Tauri (webview)

Sumber: [tauri.app/start](https://tauri.app/start/) (binary minimal <600 KB), [tauri-apps/benchmark_results](https://tauri-apps.github.io/benchmark_results/) (metodologi: `mprof` peak RSS, `hyperfine`, hanya Linux yang diukur memorinya), dan [diskusi benchmark Tauri](https://github.com/tauri-apps/benchmark_results/issues) (USS/PSS).

| Metrik | Tauri |
|---|---|
| Binary minimal | <600 KB (tanpa asset) |
| Memori | **didominasi WebView2 / WebKitGTK**, bukan binary Tauri |
| App default, Ubuntu | 125 MB USS / 185 MB PSS (pengukuran komunitas, bukan resmi) |
| Catatan penting | WebKitGTK bisa memakai memori **lebih banyak** dari Electron untuk app web kompleks (temuan yang sama, >90 MB selisih konsisten lintas platform) |

Tauri sendiri menyatakan benchmark-nya "should be considered a smoke test / regression test", bukan perbandingan ilmiah. Jadi jangan pakai angka Tauri sebagai kebenaran mutlak — tapi arahnya tidak terbantahkan: **webview adalah lantai memori, dan lantainya tinggi.**

### 2.4 Bridge binary — diukur sendiri

Ini satu-satunya angka yang saya ukur langsung, karena ini komponen yang di issue #33 disebut "cold-start sub-milidetik sangat krusial" (sudah dikoreksi di Addendum v3 menjadi 5,3 ms untuk Swift).

Setup: Go 1.27.0 / rustc 1.98.0, macOS arm64 (Apple Silicon), `json.Marshal`+`Unmarshal` payload kecil lalu exit, 25 run, diukur `subprocess.run` wall-clock.

| Binary | Ukuran | Median | min | p95 |
|---|---|---|---|---|
| Go (`CGO_ENABLED=0 -trimpath -ldflags="-s -w"`) | 2,46 MB | **5,31 ms** | 2,50 ms | 13,43 ms |
| Rust (`opt-level=z`, LTO, `panic=abort`, strip) | 0,30 MB | **4,49 ms** | 2,43 ms | 10,63 ms |
| Swift (dari Addendum v3 issue #33) | 3,4 MB | 5,3 ms | 4,4 ms | — |

**Kesimpulan:** selisih ~0,8 ms, dan keduanya berada di lantai biaya spawn proses OS. Untuk hook yang dipanggil per `PreToolUse`/`PostToolUse`/`Stop`, ini **tidak terasa** dibanding latensi CLI itu sendiri. Argumen memilih Rust untuk bridge atas dasar performa **tidak didukung data**. Argumen yang valid untuk Rust adalah ukuran distribusi (0,3 MB vs 2,5 MB) dan akses ke crate `windows`/`btleplug` — bukan kecepatan.

---

## 3. Capability matrix — ini bagian yang menentukan

Bukan performa yang akan menentukan berhasil/tidaknya port CodeIsland. Ini yang akan menentukan:

| Kebutuhan CodeIsland | mygo | Tauri v2 | Sumber |
|---|---|---|---|
| Window transparan | `Transparent` + `Vibrancy` (Acrylic Win11 22H2, Liquid Glass macOS 26) | `transparent: true` | docs kedua pihak |
| **Click-through per-region** | **`SetInputRegion(rects)`** — klik di luar region menembus ke window bawah | **tidak ada.** Hanya whole-window `set_ignore_cursor_events`. `tauri#2090` terbuka sejak 2021, masih terbuka 2025 | [mygo docs](https://mygo.run/docs/windows), [tauri#2090](https://github.com/tauri-apps/tauri/issues/2090) |
| Always-on-top | `AlwaysOnTop`; di Wayland otomatis jadi layer surface | `always_on_top` — **silently no-op di Wayland** | [tauri#15913](https://github.com/tauri-apps/tauri/issues/15913) |
| **Layer-shell Wayland** | built-in: `libgtk-layer-shell.so.0`, layer `overlay`, anchor, margin, keyboard mode. `Panel` sudah memakainya | tidak ada di API. Harus `visible(false)` → init layer shell manual → `show()`. Menunggu migrasi GTK4 | [mygo#1864](https://github.com/egoist/mygo/issues/1864), tauri#15913 |
| Nonactivating panel (tidak mencuri fokus) | `Panel: true` → macOS nonactivating `NSPanel`; Windows topmost tool window; Linux utility window / layer surface | butuh `WS_EX_NOACTIVATE` manual di Windows; macOS butuh `NSPanel` dari objc2 | mygo docs (Launchers §Platforms) |
| Skip taskbar / no taskbar button | `SkipTaskbar` (Linux, Windows); panel tidak punya taskbar button di semua OS | `skip_taskbar` | docs |
| Tray | ✓ (Linux: StatusNotifierItem; bug #704 & #1835 sudah ditutup) | ✓ plugin resmi | issue tracker |
| Global shortcut | ✓ Carbon / `RegisterHotKey` / X11 grab / **XDG Portal `GlobalShortcuts` di Wayland** | ✓ plugin resmi, Wayland via portal | docs |
| **Baca Now Playing app lain** (Spotify/Apple Music) | ✗ — `mygo.NowPlaying` adalah **publisher** (app → sistem), bukan reader | ✗ — harus tulis sendiri | docs mygo §Now Playing |
| Tulis Now Playing / media keys | ✓ | plugin/komunitas | — |
| Auto-update signed + delta | ✓ | ✓ `tauri-plugin-updater` | docs |
| Packaging Win/Linux | ✓ NSIS, `.deb`/`.rpm`/PKGBUILD | ✓ | docs |
| Ekosistem / kematangan | v0.9.1, 7 minggu, 136 open issues | v2 production sejak 2024, audit keamanan | GitHub API |

### 3.1 Arti baris "click-through per-region"

CodeIsland adalah **satu panel** yang sebagian areanya transparan (di macOS: `PanelWindowController` — background clear, `hasShadow = false`, satu `NSPanel`). Kalau di Windows/Linux panel itu selebar 400×200 px tapi hanya pill 200×32 px yang terlihat, maka **seluruh 400×200 px akan mencuri klik** kecuali kamu bisa mendefinisikan region input.

- **Tauri:** tidak bisa. Workaround yang dipakai orang: perkecil window ke bounds pill lalu pindahkan window mengikuti animasi — dan itu **rusak begitu ada elemen yang keluar bounds** (persis kata issue `mygo#1463`). Workaround lain: polling posisi kursor + toggle `set_ignore_cursor_events` — rapuh dan flicker.
- **mygo:** `SetInputRegion(rects)` — API kelas satu, sudah dipakai untuk desktop pet dan subtitle overlay.

Ini bukan detail. Ini blocker UX yang menentukan apakah port terasa "native" atau "murah".

### 3.2 Batas jujur mygo di Linux (dari issue #1864, diukur vendor)

| | GNOME 51 (Wayland) | Plasma 6.8.2 (Wayland) |
|---|---|---|
| native Wayland, di atas window maximized | tidak | tidak |
| native Wayland, di atas full-screen | tidak | tidak |
| posisi | ditempatkan mutter di tepi bawah | di atas panel Plasma |

Issue ini **ditutup** (layer-shell untuk `AlwaysOnTop` ditambahkan), tapi tabel di atas menunjukkan bahwa **Wayland tetap bukan jalan yang mulus** — sama seperti kesimpulan `linux/CodeIsland-Linux-Development-Plan.md` §6. mygo tidak menghapus masalah Wayland; ia hanya menyediakan API yang benar untuk mengerjakannya, alih-alih memaksa kamu menambal GTK sendiri.

---

## 4. Di mana Tauri/Rust tetap menang

Jangan hanya membaca tabel di atas. Ini yang **tidak** diselesaikan mygo:

1. **WinRT.** CodeIsland butuh SMTC (`GlobalSystemMediaTransportControlsSessionManager`) untuk membaca Now Playing di Windows, UI Automation untuk terminal jump, `Windows.Devices.Geolocation` untuk jadwal sholat. Crate `windows` Rust punya proyeksi WinRT **lengkap dan resmi**. Go punya binding komunitas (`go-winrt`/`winrt-go`) yang jauh lebih tipis dan tidak lengkap. **Ini keunggulan Rust yang nyata dan spesifik untuk CodeIsland.**
2. **BLE.** ESP32 Buddy butuh BLE. Rust: `btleplug` (WinRT + BlueZ), matang. Go tanpa cgo: `tinygo.org/x/bluetooth` (BSD-3, peripheral di Windows/Linux ✓) atau SimpleBLE (BUSL 1.1 — **lisensi komersial per perusahaan**, tidak cocok untuk MIT project). Bisa, tapi lebih sempit.
3. **Paritas visual cepat.** 43 file `*View.swift`, 22 di antaranya mascot per-agent. Mereplikasi Cyber Music HUD, Pixel16 HUD, floating lyrics dengan spring, git spine graph — di CSS/Canvas itu **berhari-hari**; di `ui` toolkit Go itu **berminggu-minggu** karena setiap efek harus ditulis dengan `Painter`/shader. mygo punya shader, motion/spring, transitions, dan Markdown — tapi tidak ada `backdrop-filter`, tidak ada CSS grid yang sudah teruji, tidak ada ekosistem komponen.
4. **Kematangan.** Tauri v2: stabil, diaudit, dipakai produksi. mygo: `v0.9.1`, rilis pertama 2026-09-26, 136 open issues. Distribusi commit: `egoist` 920, kontributor manusia terbesar berikutnya 33 (`pseudoyu`), lalu 31, 24, 23, 23 — dan `claude` 91. Artinya proyek ini praktis satu orang. Untuk proyek yang harus hidup 3 tahun, ini risiko governance yang harus ditulis eksplisit, bukan diabaikan.
5. **GTK3.** mygo Linux berdiri di GTK3 + `gtk4-layer-shell`-nya belum ada (lib yang dipakai adalah `libgtk-layer-shell.so.0` untuk GTK3, yang oleh Tauri disebut "deprecated and unmaintained"). Tauri punya masalah yang sama. Keduanya punya utang GTK4.

---

## 5. Rekomendasi

### 5.1 Jangan mulai dari "framework mana"

Issue #33 sudah benar di Fase 0: **bekukan kontrak dulu.** Itu tetap benar dan tidak berubah oleh riset ini. Yang berubah adalah keyakinan bahwa pilihan UI adalah keputusan besar — ternyata **bukan**, karena:

- mygo dan Tauri sama-sama bisa memakai `codeisland-core` yang sama lewat FFI (mygo: `//go:linkname`? tidak — pakai **daemon lokal / IPC**, yang sudah jadi arsitektur CodeIsland sejak awal: bridge → socket → UI). CodeIsland **sudah** punya seam IPC. Jadi core dan UI memang sudah terpisah, dan pilihan UI tidak mengunci core.
- Artinya: **pilihan UI bisa dibuat reversibel**, dan itu yang harus dikejar.

### 5.2 Rekomendasi konkret: spike 2 hari, 5 gate

Jangan commit ke salah satu. Ukur 5 hal ini di Windows 11 + Linux (X11 **dan** Wayland), karena inilah satu-satunya yang tidak bisa dijawab dokumentasi:

| # | Gate | Lulus jika | Kenapa ini yang diukur |
|---|---|---|---|
| G1 | Transparent + `SetInputRegion` pill di Windows 11 | Klik di area transparan menembus ke Notepad di bawah; klik di pill masuk ke app | Satu-satunya keunggulan teknis mygo yang tidak dimiliki Tauri. Kalau gagal, seluruh argumenmya runtuh |
| G2 | Panel di atas full-screen app + tidak mencuri fokus | Video full-screen tetap fokus; panel muncul tanpa flicker taskbar | Ini yang bikin "island" terasa island |
| G3 | Wayland: layer surface di Sway/Hyprland **dan** GNOME | Di wlroots: pill nempel atas, di atas full-screen. Di GNOME: **dinyatakan tidak didukung di UI**, bukan diam-diam rusak | Sesuai risiko #1 di `linux/CodeIsland-Linux-Development-Plan.md` §6 |
| G4 | Replay 200 event hook nyata ke panel | p95 hook→render < 300 ms (budget L-003), idle CPU < 1%, RSS < 150 MB | Angka ini sudah jadi acceptance criteria di rencana Linux; pakai yang sama |
| G5 | `List` virtualized untuk 500 sesi + git graph 1.000 commit | Tidak ada frame > 16 ms saat scroll | Angka §2.2 menunjukkan `Scroll` = 11 ms/frame di 3.000 baris. Ini jebakan yang akan kena kalau tidak diuji |

Kalau **G1–G3 lulus**, mygo native UI adalah pilihan yang lebih baik daripada Tauri untuk CodeIsland, dengan alasan yang bukan performa: **ia menyediakan window plumbing yang Tauri tidak punya, dan menghapus ~120 MB memori per instance.** Kalau G1 atau G3 gagal, jatuh ke Tauri v2 (paritas visual cepat, ekosistem matang) dan terima biaya menambal click-through/layer-shell sendiri.

### 5.3 Yang saya **tidak** sarankan

- **Jangan** port ke mygo mode webview. Itu Tauri dengan backend Go — kamu kehilangan satu-satunya keunggulan mygo (native UI) dan tetap membayar WebView.
- **Jangan** pilih Rust untuk bridge atas dasar performa. §2.4 mengukur selisihnya ~0,8 ms. Pilih Rust untuk bridge kalau kamu memang memilih Rust untuk core (agar satu toolchain), bukan karena kecepatan.
- **Jangan** memindahkan `windows/CodeIsland.*` (C#) ke Go/Rust sebelum masalah governance di Addendum v3 §4 selesai. `windows/` adalah commit squashed dari kontributor luar yang menyebut dirinya "not an official Windows release". Menghapus `RawAgentEventNormalizer.cs` + `SessionStateMachine.cs` tanpa persetujuan maintainer-nya akan menimbulkan konflik, bukan menyelesaikan divergensi.

### 5.4 Kalau harus memilih hari ini

| Skenario | Pilihan |
|---|---|
| Prioritas: rilis Windows/Linux **cepat**, terima footprint besar | **Tauri v2** di atas core bersama |
| Prioritas: produk terasa native, footprint kecil, siap menulis UI dari nol | **mygo native UI** — dengan syarat G1–G3 lulus |
| Prioritas: Linux jalan secepatnya, tim sudah C# | Lanjutkan **Avalonia** (`linux/CodeIsland-Linux-Development-Plan.md`) — masih paling rasional jangka pendek |
| Prioritas: satu core tiga OS, jangka panjang | Rust core + **UI dipilih terpisah per OS**. mygo jadi kandidat kuat untuk shell Windows/Linux; macOS tetap SwiftUI |

---

## 6. Ringkasan koreksi terhadap asumsi di issue #33

| Asumsi di issue #33 | Status setelah riset ini |
|---|---|
| "Cold-start sub-milidetik sangat krusial" | Sudah dikoreksi di Addendum v3 (5,3 ms Swift). Ditambah: Go 5,31 ms, Rust 4,49 ms — **bahasa tidak relevan** |
| "Overhead RAM WebView2/WebKitGTK ~80–150 MB per window" | Arahnya benar, angkanya konservatif. mygo native = 34,1 MB diam |
| "Click-through pada area transparan bukan fitur bawaan Tauri" | **Terkonfirmasi**, dan lebih buruk dari yang ditulis: `tauri#2090` terbuka 4 tahun |
| "`winit` belum punya `wlr-layer-shell`" | Masih benar, dan berlaku juga untuk Tauri (`tauri#15913`). **mygo sudah punya** |
| "App hanya punya satu `NSPanel`, jadi satu WebView cukup" | Benar, dan itu justru memperkuat argumen native UI: satu panel kecil tidak butuh engine browser |
| "Opsi B (`iced`/`gpui`) ditolak karena transparansi Windows rusak & gpui tanpa Windows" | Alasan penolakan itu **tidak berlaku** untuk mygo: transparansi Windows 11 jalan (`mygo#821` ditutup), dan Windows adalah target kelas satu |
| "Tauri v2 untuk paritas visual cepat" | Tetap valid sebagai argumen **kecepatan pengembangan**, tapi bertabrakan dengan click-through/layer-shell yang harus ditambal sendiri |

---

## 7. Sumber

**mygo (primer)**
- https://mygo.run/docs — indeks dokumentasi
- https://mygo.run/docs/windows — `WindowOptions`, `Transparent`, `IgnoreMouseEvents`, `SetInputRegion`, `AlwaysOnTop`, `SkipTaskbar`, `Panel`
- https://mygo.run/docs/launchers — `Panel` + global shortcut + platform matrix (macOS `NSPanel` nonactivating, Windows topmost tool window, Linux layer surface)
- https://mygo.run/docs/native — Now Playing (publisher), global shortcuts, notifications, displays
- https://mygo.run/docs/ui — native UI, toolkit, shader, motion
- https://mygo.run/docs/ui/performance — biaya per frame, memori retensi
- https://mygo.run/docs/ui/rendering — backend GPU per OS, frame pacing, `MYGO_FRAME_STATS`
- https://mygo.run/docs/distribution — packaging Windows/Linux, cross-compile tanpa cgo
- https://mygo.run/benchmarks — mygo vs GPUI/GPUI Fast/egui (Apple M5, 2026-11-05)
- https://github.com/egoist/mygo — repo, `v0.9.1` (2026-11-15), dibuat 2026-09-26
- https://github.com/egoist/mygo/issues/1463 — click-through per-region (ditutup, `SetInputRegion`)
- https://github.com/egoist/mygo/issues/1864 — layer-shell untuk `AlwaysOnTop` di Wayland (ditutup, dengan tabel terukur GNOME/Plasma)
- https://github.com/egoist/mygo/issues/821 — transparent window native UI hitam di Windows (ditutup)
- https://github.com/egoist/mygo/issues/704, /1835 — tray Linux (ditutup)

**Tauri (primer)**
- https://tauri.app/start/ — arsitektur, webview OS, binary <600 KB
- https://tauri.app/develop/window-customization/ — `decorations`, kapabilitas window
- https://tauri-apps.github.io/benchmark_results/ — metodologi benchmark resmi (hyperfine, mprof, Linux-only memory)
- https://github.com/tauri-apps/tauri/issues/2090 — click-through pada area transparan (terbuka sejak 2021)
- https://github.com/tauri-apps/tauri/issues/15913 — layer-shell Wayland (ditutup Okt 2026, workaround, menunggu GTK4)

**Ekosistem Go (sekunder, untuk kelayakan non-UI)**
- `modernc.org/sqlite` — SQLite pure Go, ~17–31% lebih lambat dari `mattn/go-sqlite3` untuk write, tanpa cgo
- `tinygo.org/x/bluetooth` — BLE tanpa cgo, peripheral di Windows/Linux (BSD-3)
- SimpleBLE `simplegoble` — BLE tanpa cgo, **BUSL 1.1** (butuh lisensi komersial)

**Internal**
- `linux/CodeIsland-Linux-Development-Plan.md` — acceptance criteria L-001…L-012, risiko Wayland
- `windows/CodeIsland-Windows-Complete-Development-Plan.md` — rencana WPF/.NET 8
- `docs/hook-edge-protocol.md` — kontrak event yang harus dibekukan lebih dulu
- Issue #33 + Addendum v2/v3 — audit LOC, koreksi cold start, risiko governance `windows/`

---

# Bagian 8 — Verifikasi klaim issue #33 terhadap codebase

> Diverifikasi 2026-11-16 di HEAD `cb3adb8` dengan `codegraph_explore` + hitungan langsung. Semua angka di bawah **diukur ulang**, bukan diwariskan dari issue.

## 8.1 Yang terkonfirmasi

| Klaim issue #33 | Hasil ukur di `cb3adb8` | Status |
|---|---|---|
| Core ~21.3K LOC Swift, 0 AppKit/SwiftUI | 72 file / **21.278 LOC**; import: `Foundation` 72, `Darwin` 6, `SQLite3` 2, `CryptoKit` 2. `import AppKit\|SwiftUI` = **0 match** | ✅ |
| App ~71.8K LOC | **79.044 LOC** / 162 file (naik ~7K sejak audit v3) | ✅ + drift |
| Bridge 385 LOC | **385** | ✅ |
| Windows ~4.5K LOC C# / 10 proyek | **4.561 LOC** / 55 file / **10** `.csproj` | ✅ |
| 9 tools di `KnownTools.All` | **9** entri, path ber-backslash literal (`@".claude\settings.json"`) | ✅ |
| 34 sumber di `supportedSources` | **34** entri | ✅ |
| `ConfigInstaller` 4.315 + `RemoteInstaller` 1.848 | **4.315 + 1.848 = 6.163** | ✅ |
| Golden fixtures 33 KB + 31 KB | `BridgeGoldenFixtures.swift` 34.244 B, `BridgeGoldenExpectations.swift` 31.622 B | ✅ |
| Satu `NSPanel` | `NSPanel` hanya muncul di `PanelWindowController.swift` (2×) | ✅ |
| **`cursor_version` normatif tapi tidak dijalankan di C#** | `docs/hook-edge-protocol.md:210` normatif; Swift `CursorHookPayload.swift` 3×; **`windows/` = 0 match** | ✅ **terkonfirmasi** |
| Test 62K LOC | **64.728 LOC** / 263 file | ✅ |

**Divergensi §2.1 issue itu nyata, bukan teoretis.** `RawAgentEventNormalizer.Normalize()` (C#) memetakan event dari `hook_event_name` mentah dan tidak pernah membaca `cursor_version`; Swift membacanya di `CursorHookPayload`. Akibatnya aturan normatif "hook yang dijalankan Cursor tidak boleh tampil sebagai claude" hanya berlaku di macOS.

## 8.2 Yang perlu dikoreksi

### (a) Golden fixtures bukan conformance suite lintas-bahasa — ia suite **macOS**

Isi `BridgeGoldenExpectations.swift` mengandung kunci platform-spesifik:

```
_ppid 78×   _term_bundle 8×   _term_app 5×   _tty 3×   _iterm_session 2×
```

`_iterm_session` dan `_term_bundle` adalah hasil AppleScript/iTerm di macOS. **Gate Fase 1 issue ("stdout byte-per-byte identik") tidak bisa dicapai di Windows/Linux** — bukan karena bridge-nya salah, tapi karena expectation-nya memang macOS.

**Perbaikan:** pecah fixtures jadi `platform-neutral` (envelope, decision, `_edge` facts) + `expectations/macos.json`, `expectations/windows.json`, `expectations/linux.json`. Gate Fase 1 jadi: *netral identik, platform-spesifik di-assert per OS*.

### (b) Fixtures masih Swift literal, belum bisa dikonsumsi bahasa lain

`BridgeGoldenFixtures`/`Expectations` adalah `enum` Swift dengan raw string literal. Bahasa lain tidak bisa membacanya. **Fase 0 butuh 1 tugas eksplisit: ekspor ke JSON/JSONL** (`CODEISLAND_GOLDEN_RECORD` sudah ada di harness). Tanpa ini, "conformance suite" hanya nama.

### (c) `HookIntake` tidak murni — seam-nya lebih kecil dari yang issue gambarkan

Issue §2.2 menyebut `HookIntake` sebagai seam. Kenyataannya:

- **Murni, portabel:** `reduceHookEvent` / `applyHookEvent` / `SideEffect` / `HookEventFacts` (`SessionSnapshot.swift:1143`), `AttentionPolicy`, `NotchHoopsEngine`, `GitBranchReader`, `MarkdownBlockParser`.
- **Tidak murni:** `HookIntake` memanggil `proc_pidpath`, membuka `/dev/tty`, dan mem-parse `_iterm_session` (`HookIntake.swift:551`). Ini platform-bound, bukan pure.

**Konsekuensi:** urutan porting harus `reducer → policy → git/markdown → HookIntake (per-OS) → bridge`. Issue menaruh bridge di Fase 1, padahal bridge justru yang paling banyak mengandung platform code.

### (d) Tujuan "satu core untuk tiga OS" tidak bisa dicapai

Issue menetapkan dua hal sekaligus: (1) macOS tetap SwiftUI + Swift core, (2) satu core bersama untuk tiga OS. **Keduanya kontradiktif.** Kalau macOS tetap Swift, maka jumlah core minimal **dua**, apa pun bahasanya. Yang bisa dicapai adalah **dua core, satu kontrak** — dan itu target yang benar.

## 8.3 Angka yang mengubah prioritas

| Fakta | Implikasi |
|---|---|
| C# = 4.561 LOC vs Swift app 79.044 LOC (5,8%) | "Windows adalah core kedua" benar **secara semantik**, tapi kecil secara volume. Menghapusnya murah secara teknis; mahal secara sosial. |
| `KnownTools` 9 vs `supportedSources` 34 | Cakupan Windows 26%. Bukan "ketinggalan fitur" — ini gap 3,8×. |
| Bridge Go 5,31 ms vs Rust 4,49 ms (§2.4) | Bridge **bukan** tempat ROI tertinggi. Issue menaruhnya di Fase 1; itu salah prioritas. |
| `cursor_version` 0 match di `windows/` | Bug ini bisa diperbaiki **hari ini** di C#, ~50 LOC, tanpa rewrite apa pun. |

---

# Bagian 9 — Arsitektur yang dieksekusi

## 9.1 Prinsip

1. **Kontrak dulu, bahasa kemudian.** Kontrak = `docs/hook-edge-protocol.md` + golden fixtures JSON. Ini satu-satunya hal yang harus stabil 3 tahun.
2. **Dua core, satu kontrak, dua shell.** Bukan satu core. macOS tetap Swift; Windows+Linux berbagi satu.
3. **Shell dan core harus satu bahasa per platform.** Kalau shell Go dan core Rust, kamu menciptakan proses ketiga + FFI. Itu pajak permanen tanpa manfaat.
4. **Jangan tambah FFI di macOS.** Seam yang sudah ada (Unix socket daemon) sudah cukup dan sudah terbukti.

## 9.2 Target arsitektur

```
                  docs/hook-edge-protocol.md  +  fixtures/*.json
                  ─────────────────────────────────────────────
                              (kontrak beku)

   macOS                          Windows                    Linux
   ┌──────────────────┐      ┌──────────────────┐      ┌──────────────────┐
   │ SwiftUI / AppKit │      │ mygo native UI   │      │ mygo native UI   │
   │ (notch, NSPanel) │      │ (Go, D3D11)      │      │ (Go, OpenGL)     │
   └────────┬─────────┘      └────────┬─────────┘      └────────┬─────────┘
            │ in-process              │ in-process              │ in-process
   ┌────────▼─────────┐      ┌────────▼─────────────────────────▼────────┐
   │ CodeIslandCore   │      │ codeisland-core (Go)                      │
   │ (Swift, 21K LOC) │      │ reducer · attention · jsonl · git ·       │
   │                  │      │ markdown · ESP32 · quota · installer      │
   └────────┬─────────┘      └────────┬──────────────────────────────────┘
            │ UDS                     │ UDS (Linux) / named pipe (Win)
   ┌────────▼─────────┐      ┌────────▼─────────┐
   │ codeisland-bridge│      │ codeisland-bridge│
   │ (Swift, 385 LOC) │      │ (Go, ~1.5K LOC)  │
   └──────────────────┘      └──────────────────┘
```

Yang berubah dari rencana issue:

- **Windows/Linux: 1 proses app + 1 binary bridge.** Core adalah *library* di dalam proses UI, bukan daemon terpisah. Tidak ada IPC core↔UI.
- **macOS: tidak disentuh sama sekali.** Tidak ada Rust, tidak ada FFI, tidak ada daemon baru.
- **Rust keluar dari gambar** kecuali shell yang dipilih adalah Tauri. Kalau shell = mygo, Rust hanya menambah toolchain ketiga tanpa membeli apa pun.

## 9.3 Urutan fase (menggantikan Fase 0–3 issue)

### Fase A — Bekukan kontrak (3–4 hari, tanpa bahasa baru)

| Tugas | Gate |
|---|---|
| Ekspor `BridgeGoldenFixtures`/`Expectations` ke `fixtures/*.json` | File JSON ada, `BridgeGoldenTests` tetap hijau |
| Pisahkan expectation netral vs per-OS | 3 set expectation; netral identik lintas OS |
| Perbaiki `cursor_version` di `RawAgentEventNormalizer` (C#) | Test baru: hook Cursor tidak muncul sebagai `claude`; `windows/CodeIsland.Core.Tests` hijau |
| Bekukan skema envelope + `_edge` facts sebagai JSON Schema | Schema + validator, dipakai kedua sisi |

**Ini satu-satunya fase yang memberi hasil walau tidak ada rewrite sama sekali.** Kerjakan lebih dulu, tanpa kecuali.

### Fase B — Spike shell (2 hari, 5 gate)

Gate G1–G5 di §5.2. **Shell diputuskan sebelum core dipilih**, karena shell-lah yang berisiko (click-through, layer-shell, focus), sementara core bisa ikut bahasa shell secara gratis.

### Fase C — Core Go, Windows dipindah lebih dulu

Port berurutan, tiap langkah punya gate:

1. `reduceHookEvent` + `AttentionPolicy` + `HookEventFacts` → gate: replay fixtures netral, output identik
2. `GitBranchReader` + `MarkdownBlockParser` + `NotchHoopsEngine` → gate: unit test port 1:1
3. `JSONLTailer` + `WorkspaceMonitor` → gate: 500 sesi, tidak ada frame > 16 ms (pakai `List`, lihat §2.2)
4. `HookIntake` per-OS + `codeisland-bridge` Go → gate: `fixtures/linux.json` + `fixtures/windows.json` lulus
5. **Hapus** `RawAgentEventNormalizer.cs` + `SessionStateMachine.cs` → gate: `windows/CodeIsland.Core.Tests` hijau, sesi Cursor tidak dobel

Langkah 5 **hanya** setelah persetujuan maintainer `windows/` (risiko governance Addendum v3 §4).

### Fase D — Shell Windows, lalu Linux

Windows dulu (satu display server, tidak ada Wayland). Linux X11, lalu Wayland dengan capability detection eksplisit.

## 9.4 Yang eksplisit **tidak** dikerjakan

- Rust core. Tidak ada gate yang membutuhkannya.
- FFI/UniFFI di macOS. Seam socket sudah ada.
- Port `Sources/CodeIsland` (79K LOC Swift) ke bahasa lain.
- Notch hardware detection, Live Activities, Apple Companion, Sparkle — Apple-only.
- `L10n.swift` (4.217 LOC) — pindahkan ke file resource, jangan port sebagai kode.

## 9.5 Satu kalimat

**Issue #33 benar soal diagnosis dan salah soal obat.** Divergensi core itu nyata dan terukur (`cursor_version` 0 match). Tapi obatnya bukan "rewrite ke Rust" — obatnya **bekukan kontrak, lalu pilih shell berdasarkan gate yang bisa diukur**, dan biarkan bahasa core mengikuti shell. Hasilnya dua core, satu kontrak, dua shell — bukan tiga core seperti yang akan terjadi kalau rencana issue dijalankan apa adanya.
