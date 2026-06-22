# PerfectScreen AE Plugin — Personal Recreation Plan

A complete After Effects plugin that replicates ProductionCrate's PerfectScreen feature set,
with an added toggle to disable the LCD pixel simulation effect.

---

## 1. What We're Building

A dockable CEP (Common Extensibility Platform) panel for After Effects that:

- Composites any footage layer onto a screen surface using a 4-point corner pin
- Simulates the physical optics of a camera recording an LCD monitor
- Exposes all controls PerfectScreen provides (exposure, DOF, vignette, chromatic aberration, optic distortion, dust, color tint, grain)
- Adds a **Pixels On/Off master toggle** so the LCD pixel simulation can be killed with one click
- Works on AE 2020 (v17.x) and newer, on both Mac and Windows
- Requires no paid subscription, no cloud license check, and no internet connection after install

---

## 2. Architecture Decision

### Why CEP Extension (not native C++ / not plain JSX)

| Approach | UI quality | Install complexity | Maintenance |
|---|---|---|---|
| C++ AEX plugin | Native, GPU access | Very high (SDK, compiler, signing) | Hard |
| Plain JSX script | ScriptUI only (ugly) | Zero (drop in Scripts folder) | Easy |
| **CEP Extension** | **HTML/CSS panel, dockable** | **Low (one folder copy + debug flag)** | **Easy** |
| Expression presets (.ffx) | None (baked) | Low | Inflexible |

CEP is the right call for personal use: it gives a proper docked panel with sliders and toggles,
uses JSX under the hood to talk to AE, and requires no compiler toolchain.

The only "install" step is: copy the extension folder into AE's extensions directory and
set `PlayerDebugMode=1` in a plist/registry entry for unsigned extensions.

### Why not GPU-accelerated pixel simulation

ProductionCrate's pixel effect is native GPU code rendering sub-pixel LCD geometry.
We approximate it with AE's built-in Mosaic + Glow + Chromatic Aberration effects chained
on a dedicated adjustment layer. The result looks 90% as good at a fraction of the build cost.
The toggle the user wants maps exactly to enabling/disabling that adjustment layer.

---

## 3. Full Feature Specification

Each feature maps to one or more AE effects applied programmatically by the JSX backend.

### 3.1 Corner Pin / Perspective Transform

**Purpose:** Map the footage rectangle to an arbitrary quad on screen.

**Implementation:**
- Apply AE's built-in `ADBE Corner Pin` effect to the footage layer
- Expose 4 numbered point controls (Upper Left, Upper Right, Lower Right, Lower Left)
- Panel shows a 2D thumbnail with draggable corner handles (SVG overlay in HTML panel, coordinates
  synced to the AE comp via `evalScript`)
- "Auto Zoom" checkbox: adds an expression to Scale that computes the minimum scale needed to
  fill the pin region without black edges
- "Set from Mask" button: reads a 4-point mask path the user drew manually and fills the pin values

**AE Effects used:** `ADBE Corner Pin`

---

### 3.2 Exposure

**Purpose:** Control overall brightness of the composited screen, with optional auto-leveling.

**Controls:**
- Exposure slider: −3 EV to +3 EV (default 0)
- Auto Exposure toggle: when on, an expression reads the layer's average luminance and
  adjusts exposure to target 50% brightness

**Implementation:**
- Apply `ADBE Exposure` (Exposure effect) to the footage layer
- Expression on the Exposure property when Auto mode is on:
  ```
  var target = 0.5;
  var avg = thisComp.layer(index).sourceRectAtTime(time,false); // approximation
  // simplified: drive via sampleImage average
  linear(sampleImage([width/2,height/2])[0], 0, 1, 1.5, -1.5);
  ```
  (Full implementation uses `sampleImage` on a 3×3 grid for performance)

**AE Effects used:** `ADBE Exposure`

---

### 3.3 Color Tint

**Purpose:** Apply warm, cool, or green color cast to simulate real-world monitor temperature.

**Controls:**
- Tint Type dropdown: Neutral / Warm / Cool / Green / Custom
- Tint Amount slider: 0–100%
- Custom color swatch (shown only when Custom is selected)

**Implementation:**
- Apply `ADBE Color Balance (HLS)` + `ADBE Tint` effect
- Preset tint values:
  - Warm: +8 Hue, +5 Sat, slight Red boost in Curves
  - Cool: −8 Hue, +3 Sat, slight Blue boost
  - Green: Hue shift to ~130°, slight Green boost
- Amount slider drives the blend opacity of a tint solid in Screen mode above the layer,
  or scales the effect intensity directly via expression

**AE Effects used:** `ADBE Tint`, `ADBE Color Balance (HLS)`, `ADBE Curves`

---

### 3.4 Depth of Field (DOF)

**Purpose:** Blur the screen content to simulate a camera with shallow focus.

**Controls:**
- DOF slider: 0 (sharp) to 100 (very blurry)
- Focus Point: X/Y position control — the point on the screen that stays sharpest
- (Advanced) Aperture shape: Circular / Hexagonal

**Implementation:**
- Apply `ADBE Camera Lens Blur` effect on the footage layer
- Blur Radius property driven by the DOF slider (0 = 0px, 100 = 40px)
- For focus-point-aware blur: apply `ADBE Compound Blur` using a radial gradient map
  generated by expressions (white at focus point, black at edges), which acts as a blur map
- Aperture: passed directly to Camera Lens Blur's Iris Shape property

**AE Effects used:** `ADBE Camera Lens Blur`, `ADBE Compound Blur`

---

### 3.5 Chromatic Aberration

**Purpose:** Split color channels slightly at edges, as a real lens does.

**Controls:**
- Aberration Amount: 0–20px
- Direction: Radial (outward from center) only

**Implementation:**
- Create an adjustment layer above the footage layer named `PS_ChromAb`
- Apply `ADBE Shift Channels` to separate R, G, B
- Apply `ADBE Transform` (position offset) per channel using channel extraction trick:
  1. Duplicate layer ×3 (R, G, B extractions)
  2. Use `ADBE Shift Channels` to isolate each channel
  3. Offset Red layer by +Amount/2 from center, Blue layer by −Amount/2
  4. Composite all three in Add/Screen mode with alpha
- The offset is expressed as: `offset = normalize(position - [width/2, height/2]) * amount`

**AE Effects used:** `ADBE Shift Channels`, `ADBE Transform`

---

### 3.6 Vignette

**Purpose:** Darken screen edges, mimicking lens vignetting.

**Controls:**
- Vignette Amount: 0–100%
- Feather: 0–200px
- Shape: Ellipse / Rectangle

**Implementation:**
- Create a black solid named `PS_Vignette` above the footage, set to Multiply blend mode
- Draw an elliptical mask with high feather (set by Feather slider) in Subtract mode
  (leaving edges dark, center transparent)
- Opacity of the solid driven by Amount slider

**AE Effects used:** None required — pure mask + blend mode

---

### 3.7 Optic Distortion (Lens Warp / Bulge)

**Purpose:** Add slight barrel/pincushion distortion as a real camera lens applies.

**Controls:**
- Barrel/Pincushion slider: −50 (pincushion) to +50 (barrel), default +5
- Edge Feather: 0–30

**Implementation:**
- Apply `ADBE Optics Compensation` effect to the footage layer
- Field of View property maps from the slider (positive = barrel = add FOV,
  negative = pincushion = subtract FOV)
- Alternatively use `ADBE Warp` (Bezier Warp) for finer control

**AE Effects used:** `ADBE Optics Compensation`

---

### 3.8 Dust / Particles

**Purpose:** Simulate tiny dust specks on the lens or screen surface.

**Controls:**
- Dust Amount: 0–100% (density)
- Dust Size: 0–10px
- Dust Opacity: 0–100%
- Dust Color: swatch (default near-white)

**Implementation:**
- Create a solid named `PS_Dust` above the footage layer in Screen blend mode
- Apply `ADBE Fractal Noise` with a very high Contrast and Scale, thresholded to create
  sparse white dots (simulates dust)
- Parameters:
  - Fractal Type: Rocky
  - Noise Type: Spline
  - Contrast: ~300 (amount controls this)
  - Scale: inversely mapped from Dust Size
- Animate the noise slightly (Noise Evolution driven by `time * 0.05`) for subtle organic movement
- Layer opacity = Dust Opacity slider

**AE Effects used:** `ADBE Fractal Noise`, `ADBE Levels` (to threshold)

---

### 3.9 LCD Pixel Effect — THE TOGGLEABLE MODULE

**Purpose:** Simulate the physical sub-pixel grid of an LCD screen, giving footage that
characteristic "you're looking at a real monitor" quality. **The user can turn this entire
module off with a single toggle.**

**Controls:**
- **Pixels Enable toggle** (master on/off — this is the feature the user requested) ✓
- Pixel Scale: 0.5–5.0 (size of simulated pixels; 1.0 = default)
- Pixel Contrast: 0–100% (how pronounced the grid lines are)
- Sub-pixel Mode: RGB Stripe / OLED / None
- Scanlines toggle + Scanline Intensity: 0–100%
- RGB Shift Amount: 0–15px (chromatic offset between pixel triads)

**Implementation:**

The LCD pixel module is isolated entirely in its own precomp named `PS_PixelFX_PRECOMP`.
Disabling the toggle simply hides/collapses this layer — no effect baking, all values preserved.

Inside `PS_PixelFX_PRECOMP`:

**a) Pixel Grid (Mosaic)**
- Apply `ADBE Mosaic` to create the block-pixel look
- Horizontal/Vertical blocks driven by `Pixel Scale`: `Math.round(comp.width / (scale * 100))`
- Enable "Sharp Colors" mode

**b) Sub-pixel Grid Overlay**
- Create a 3×1 pixel-wide column solid tiled to comp size using `ADBE Tile`
- Colors: R|G|B stripes with slight transparency
- Blend mode: Multiply
- Driven by Sub-pixel Mode dropdown

**c) Scanlines**
- Create a horizontal stripe solid (1px black, 1px transparent, repeating)
- Applied via `ADBE Tile` + `ADBE Levels` on a new solid
- Scanline Intensity drives the opacity of this solid

**d) Intra-pixel RGB Shift**
- Same channel-split technique as Chromatic Aberration (§3.5) but at pixel scale
- Applied only within the precomp scope

**e) Glow / Light Bleed**
- Apply `ADBE Glow` effect on the precomp layer to simulate the slight bloom/bleed
  that LCD panels exhibit
- Glow Threshold: 60%, Glow Radius: 10px, Glow Intensity: 0.3 (all adjustable)

**AE Effects used:** `ADBE Mosaic`, `ADBE Tile`, `ADBE Glow`, `ADBE Shift Channels`

---

### 3.10 Grain

**Purpose:** Add photographic grain to blend the composited screen with the surrounding footage.

**Controls:**
- Grain Amount: 0–100%
- Grain Size: 0.5–3.0
- Color/Monochrome toggle

**Implementation:**
- Apply `ADBE Add Grain` effect to the footage layer (or an adjustment layer above it)
- Intensity and Size driven by sliders
- Monochrome toggle sets the Monochromatic checkbox in the effect

**AE Effects used:** `ADBE Add Grain`

---

## 4. File Structure

```
perfectscreen-ae/
├── CSXS/
│   └── manifest.xml              # CEP extension manifest (ID, AE target version, panel size)
├── css/
│   └── panel.css                 # Dark theme to match AE's dark UI
├── js/
│   ├── panel.js                  # Panel logic: slider events → evalScript calls
│   ├── cornerpin-ui.js           # SVG overlay for 4-point handle dragging
│   └── presets.js                # Built-in preset definitions (JSON)
├── jsx/
│   ├── host.jsx                  # Main JSX entry point, exposes all functions to CEP
│   ├── core/
│   │   ├── layer-manager.jsx     # Create/find/name PS_ layers and the precomp
│   │   ├── effect-utils.jsx      # Helpers: applyEffect(), setProperty(), addExpression()
│   │   └── state.jsx             # Serialize/deserialize plugin state to layer comments
│   └── modules/
│       ├── cornerpin.jsx
│       ├── exposure.jsx
│       ├── colortint.jsx
│       ├── dof.jsx
│       ├── chromab.jsx
│       ├── vignette.jsx
│       ├── opticdistort.jsx
│       ├── dust.jsx
│       ├── pixels.jsx            # LCD pixel module (the toggleable one)
│       └── grain.jsx
├── icons/
│   ├── icon_32.png
│   ├── icon_64.png
│   └── icon_128.png
└── index.html                    # Panel HTML: sliders, toggles, section headers
```

---

## 5. Panel UI Layout

```
┌─────────────────────────────────┐
│  ⬛ PerfectScreen               │
├─────────────────────────────────┤
│ [Select Screen Layer ▼]  [Apply]│
├─────────────────────────────────┤
│ ▼ CORNER PIN                    │
│  [Corner Pin UI — 2D preview]   │
│  [ ] Auto Zoom    [Set from Mask]│
├─────────────────────────────────┤
│ ▼ OPTICS                        │
│  Exposure      ────●──── 0.0EV  │
│  [ ] Auto Exposure               │
│  Barrel/Pin    ──●────── +5     │
│  DOF           ─────●─── 20     │
│  Focus Point   X[   ] Y[   ]    │
├─────────────────────────────────┤
│ ▼ COLOR                         │
│  Tint Type     [Warm ▼]         │
│  Tint Amount   ────●──── 30%    │
│  Chrom. Ab.    ──●────── 3px    │
├─────────────────────────────────┤
│ ▼ SURFACE                       │
│  Vignette      ────●──── 40%    │
│  Vignette Fth  ──────●── 120px  │
│  Dust Amount   ─●─────── 15%    │
│  Grain Amount  ───●───── 25%    │
├─────────────────────────────────┤
│ ▼ LCD PIXELS  [ON ●───] OFF     │  ← master toggle
│  Pixel Scale   ────●──── 1.0    │
│  Pixel Contrast ───●──── 50%    │
│  Sub-pixel     [RGB Stripe ▼]   │
│  [ ] Scanlines                  │
│  Scanline Int. ───●──── 20%     │
│  RGB Shift     ──●────── 4px    │
├─────────────────────────────────┤
│ Presets: [Default▼] [Save][Load]│
└─────────────────────────────────┘
```

---

## 6. State Persistence

Plugin settings are saved as JSON in the **footage layer's Comment field** (accessible via
`layer.comment`). This means settings survive project saves/reloads without any external file.

```json
{
  "ps_version": "1.0",
  "cornerpin": { "ul": [0,0], "ur": [1920,0], "lr": [1920,1080], "ll": [0,1080] },
  "exposure": 0.5,
  "autoExposure": false,
  "colorTint": { "type": "warm", "amount": 30 },
  "dof": 20,
  "chromab": 3,
  "vignette": { "amount": 40, "feather": 120 },
  "opticDistort": 5,
  "dust": { "amount": 15, "size": 2, "opacity": 80 },
  "pixels": {
    "enabled": true,
    "scale": 1.0,
    "contrast": 50,
    "subpixelMode": "rgb",
    "scanlines": false,
    "scanlineIntensity": 20,
    "rgbShift": 4
  },
  "grain": { "amount": 25, "size": 1.0, "mono": false }
}
```

---

## 7. Implementation Phases

### Phase 1 — Project Scaffold (Est. 1 day)
- [ ] Create directory structure and `manifest.xml`
- [ ] Stub `index.html` panel with all sections (collapsed) and placeholder controls
- [ ] Stub all JSX module files with empty function signatures
- [ ] Implement `effect-utils.jsx`: `applyEffect()`, `setProperty()`, `getProperty()`
- [ ] Implement `layer-manager.jsx`: find selected layer, create/find named PS_ layers
- [ ] Wire `panel.js` to call `host.jsx` via `evalScript` (round-trip test)
- [ ] Write install script (`install.sh` / `install.bat`) that copies extension to correct OS path
- [ ] Verify panel loads in AE debug mode

### Phase 2 — Corner Pin (Est. 1 day)
- [ ] Implement `cornerpin.jsx`: apply `ADBE Corner Pin`, set 4 point values
- [ ] Build `cornerpin-ui.js`: SVG 2D preview with draggable handles
- [ ] Sync handle positions ↔ AE comp coordinates (accounting for comp pixel aspect)
- [ ] Implement Auto Zoom expression
- [ ] Implement "Set from Mask" — read 4-point mask from selected layer
- [ ] Test with a phone screen mockup footage

### Phase 3 — Optics Stack (Est. 1.5 days)
- [ ] Implement `exposure.jsx` with slider + Auto Exposure expression
- [ ] Implement `opticdistort.jsx` with `ADBE Optics Compensation`
- [ ] Implement `dof.jsx` with `ADBE Camera Lens Blur` + radial blur map approach
- [ ] Wire all three to panel sliders with live preview (triggered on `input` event)
- [ ] Test at extreme values to verify no render artifacts

### Phase 4 — Color & Aberration (Est. 1 day)
- [ ] Implement `colortint.jsx` — all four presets + custom swatch
- [ ] Implement `chromab.jsx` — channel-split technique
- [ ] Implement `grain.jsx` — `ADBE Add Grain`
- [ ] Connect panel dropdowns/sliders
- [ ] Test warm/cool/green tints for realism

### Phase 5 — Surface Effects (Est. 1 day)
- [ ] Implement `vignette.jsx` — mask + Multiply solid
- [ ] Implement `dust.jsx` — Fractal Noise + Levels threshold approach
- [ ] Connect panel controls
- [ ] Test dust visibility at various exposure levels

### Phase 6 — LCD Pixel Module (Est. 2 days)
- [ ] Create `pixels.jsx` — build `PS_PixelFX_PRECOMP` precomp with all layers inside
- [ ] Implement Mosaic pixel grid
- [ ] Implement RGB sub-pixel stripe overlay
- [ ] Implement scanline solid
- [ ] Implement intra-pixel RGB shift
- [ ] Implement Glow light bleed
- [ ] Wire master enable toggle → `PS_PixelFX_PRECOMP` layer `.enabled` property
- [ ] Wire all pixel sub-controls to precomp layer properties
- [ ] Verify toggle persists correctly on project reload

### Phase 7 — State Persistence & Presets (Est. 0.5 days)
- [ ] Implement `state.jsx`: serialize full settings to `layer.comment`
- [ ] Implement `state.jsx`: deserialize settings on panel open / layer selection
- [ ] Implement `presets.js`: 5 built-in presets (Default, Cinematic, Phone Close-Up, TV Wide, Minimal)
- [ ] Add Save/Load preset UI to panel

### Phase 8 — Polish & Packaging (Est. 0.5 days)
- [ ] Finalize CSS: dark theme matching AE, smooth slider styling
- [ ] Add icons (`icon_32.png`, `icon_64.png`, `icon_128.png`)
- [ ] Write `README.md` with install instructions for both Mac and Windows
- [ ] Test full workflow: select layer → Apply → adjust all controls → save → reload project
- [ ] Verify on AE 2020, 2022, and 2024

**Total estimated effort: ~8 working days of focused development**

---

## 8. Installation (Personal Use)

### Mac
```bash
cp -r perfectscreen-ae ~/Library/Application\ Support/Adobe/CEP/extensions/
defaults write com.adobe.CSXS.11 PlayerDebugMode 1  # adjust version number for your AE
```

### Windows
```powershell
Copy-Item -Recurse perfectscreen-ae "C:\Users\$env:USERNAME\AppData\Roaming\Adobe\CEP\extensions\"
# Set HKCU\Software\Adobe\CSXS.11\PlayerDebugMode = "1" in Registry
```

Then in AE: **Window → Extensions → PerfectScreen**

No license server, no internet required.

---

## 9. Technical Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| `ADBE Mosaic` looks blocky, not like true sub-pixel LCD rendering | Medium | Add RGB stripe overlay + Glow bleed to soften; adjust Pixel Scale for realism |
| DOF radial blur map is slow on large comps | Medium | Expose a "Fast Mode" checkbox that swaps `ADBE Compound Blur` for simpler `ADBE Fast Box Blur` |
| Channel-split chromatic aberration breaks alpha transparency | Medium | Apply effect only inside a precomp, composite result back |
| State saved to `layer.comment` gets overwritten by user | Low | Prefix comment JSON with `#PS:` marker and only write/read inside that block |
| CEP debug mode required (unsigned) | Low | Personal use only; no signing needed; document setup clearly |
| AE effect match names differ across versions | Low | Test match names on target AE versions; maintain a version-gated name map |

---

## 10. What This Covers vs. PerfectScreen Original

| Feature | PerfectScreen | This Plugin |
|---|---|---|
| Corner Pin | ✓ | ✓ |
| Auto Zoom | ✓ | ✓ |
| Exposure | ✓ | ✓ |
| Auto Exposure | ✓ | ✓ (expression-based) |
| Color Tint | ✓ | ✓ |
| Depth of Field | ✓ | ✓ (AE Camera Lens Blur) |
| Chromatic Aberration | ✓ | ✓ |
| Vignette | ✓ | ✓ |
| Optic Distortion | ✓ | ✓ |
| Dust elements | ✓ | ✓ (Fractal Noise approx.) |
| LCD Pixel Effect | ✓ (GPU) | ✓ (AE effects approx.) |
| **Pixel Off Toggle** | ✗ | **✓ (added feature)** |
| GPU acceleration | ✓ | Partial (AE handles internally) |
| 20 cinematic presets | ✓ | 5 presets (expandable) |
| Premiere Pro support | ✓ | AE only (scope limit) |

---

## 11. Out of Scope (for now)

- Premiere Pro panel — AE only is sufficient for personal use
- Motion tracking integration — user tracks and parents the screen layer themselves
- True GPU sub-pixel rendering — the approximation is indistinguishable at normal viewing distances
- Cloud sync / settings backup
