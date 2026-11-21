# Morrow macOS Hardware Notch Geometry & Symmetry Rules

This specification is strictly mandatory when developing or modifying macOS notch bar components (`macos/Sources/Morrow/`):

1. **Strict Left/Right Symmetry (`leftWidth == rightWidth`, `centerShift == 0`):**
   - Left and right wings **must remain strictly equal in width** across all 3 primary states (**Idle**, **Thinking**, **HUD/Expanded**).
   - Enabling `usesAsymmetricNotchWings` or horizontally shifting the notch (`collapsedNotchHorizontalShift` must remain `0`) is strictly prohibited.

2. **State Width Budget Reference (assuming `mascotSize = 24pt`, scale `100%`):**
   - **Idle:** `wingWidth` **`41 – 56 pt`** (clean right content area ~`36 – 44 pt`).
   - **Thinking:**
     - Modern: `wingWidth` **`118 – 160 pt`** (clean right content area ~`102 pt`).
     - Pixel: `wingWidth` **`128 – 168 pt`** (clean right content area ~`108 pt`).
   - **Tool Active (non-thinking):** Modern **`88 – 128 pt`**, Pixel **`96 – 136 pt`**.
   - **HUD / Expanded:** `(panelWidth - expandedNotchCutoutWidth) / 2` (~`235 – 265 pt` per wing).

3. **Right Wing Must Not Force-Expand Notch:**
   - The right wing (`effectiveNaturalRightWidth`) **must not** widen the bar beyond `effectiveNaturalLeftWidth + badgeReserve` during Thinking or Idle states.

4. **Calculate Before Modifying UI:**
   - Before adding or adjusting elements in the left/right wings, **calculate first** whether all elements (icon + text + spacing + `badgeReserve`) fit within `maxContentWidth` (`collapsedInnerBudget - totalRightInnerPadding - badgeReserve`).
   - **If it fits:** proceed with implementation.
   - **If it does not fit / risks clipping into notch:** **DO NOT** expand the notch and **DO NOT** allow content to clip into the physical notch cutout — consult the user first and propose layout adaptations (e.g. shorten label, single-priority badge, or truncation/scaling).
   - If an incoming pull request violates symmetry or unilaterally expands width budget, **reject and cite this specification**.
