# Morrow macOS Hardware Notch Geometry & Symmetry Rules

Spesifikasi ini wajib dipatuhi saat mengembangkan atau menyunting komponen bilah/notch macOS (`Sources/Morrow/`):

1. **Strict Left/Right Symmetry (`leftWidth == rightWidth`, `centerShift == 0`):**
   - Sayap kiri dan kanan **wajib sama lebar** di 3 state utama (**Idle**, **Thinking**, **HUD/Expanded**).
   - Dilarang mengaktifkan `usesAsymmetricNotchWings` atau menggeser notch secara horizontal (`collapsedNotchHorizontalShift` harus tetap `0`).

2. **Patokan Width Budget per State (asumsi `mascotSize = 24pt`, scale `100%`):**
   - **Idle:** `wingWidth` **`41 – 56 pt`** (ruang konten bersih kanan ~`36 – 44 pt`).
   - **Thinking:**
     - Modern: `wingWidth` **`118 – 160 pt`** (ruang konten bersih kanan ~`102 pt`).
     - Pixel: `wingWidth` **`128 – 168 pt`** (ruang konten bersih kanan ~`108 pt`).
   - **Tool Active (non-thinking):** Modern **`88 – 128 pt`**, Pixel **`96 – 136 pt`**.
   - **HUD / Expanded:** `(panelWidth - expandedNotchCutoutWidth) / 2` (~`235 – 265 pt` per sayap).

3. **Sayap Kanan Dilarang Melebar-paksa Notch:**
   - Sayap kanan (`effectiveNaturalRightWidth`) **tidak boleh** memperlebar bar melebihi `effectiveNaturalLeftWidth + badgeReserve` saat Thinking maupun Idle.

4. **Wajib Hitung Sebelum Ubah UI:**
   - Sebelum menambah atau mengubah elemen di sayap kiri/kanan, **hitung dulu** apakah seluruh elemen (ikon + teks + spacing + `badgeReserve`) muat di dalam `maxContentWidth` (`collapsedInnerBudget - totalRightInnerPadding - badgeReserve`).
   - **Jika muat:** langsung kerjakan.
   - **Jika tidak muat / berisiko menyentuh notch:** **JANGAN** perlebar notch dan **JANGAN** biarkan terpotong masuk ke area notch — **tanya user terlebih dahulu** dan berikan rekomendasi (mis. ringkas label, *single-priority*, atau atur truncation/skala).
   - Jika ada perubahan dari dev/branch lain yang melanggar aturan simetri atau melebarkan width secara sepihak, **tolak dan jelaskan alasannya**.
