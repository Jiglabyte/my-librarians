# PerfectScreen (personal build)

A from-scratch After Effects CEP extension that composites footage onto a
screen surface and simulates the optics of a camera filming a real LCD
monitor — corner pin, exposure, tint, depth of field, chromatic aberration,
vignette, lens distortion, dust, grain, and a fully **toggleable** LCD pixel
simulation.

Built entirely on AE's public scripting API and built-in effects.
No license checks, no network access, personal use.

## Install

**Mac:** run `./install.sh`, restart After Effects.

**Windows:** double-click `install.bat`, restart After Effects.

Both scripts copy the extension into the user CEP extensions folder and set
`PlayerDebugMode = 1` (required because this extension is unsigned).

Open the panel via **Window → Extensions → PerfectScreen**.

> **Note:** the rig targets the *English* AE UI (expressions reference
> effect/property display names like "Slider" and property names inside
> effects). If you run AE in another language, switch to English or adapt
> the names in `jsx/core/rig.jsx`.

## Usage

1. Put your screen-content footage in the comp with your scene.
2. Select the footage layer, click **Apply to Layer** in the panel.
   The layer is precomposed into `PS Screen - <name>` containing the full
   effect rig; a Corner Pin effect is added to the precomp layer.
3. Position the screen: select the Corner Pin effect in the timeline and
   drag its four points directly in the comp viewer — or draw a 4-point
   mask on the rigged layer (clockwise from top-left) and click
   **Set From Mask**.
4. Adjust the sliders. Every parameter is also available in AE itself as an
   Expression Control on the `PS_Controls` null inside the precomp, so you
   can keyframe any of them like normal properties.
5. Flip the **LCD Pixels** toggle in the panel header of that section to
   kill or restore the entire pixel simulation (mosaic grid, pixel glow,
   grid lines, scanlines, RGB shift) in one click. All sub-settings are
   preserved while it's off.

## How the rig works

Inside the precomp, top to bottom:

| Layer | Role |
|---|---|
| `PS_Controls` | Hidden null carrying one Expression Control per parameter — the single source of truth |
| `PS_Grain` | Adjustment layer: Add Grain |
| `PS_Vignette` | Black solid in Multiply with a radial Gradient Ramp (white centre → black edges) |
| `PS_Dust` | Black solid in Screen with crushed Fractal Noise → sparse drifting specks |
| `PS_Optics` | Adjustment layer: Exposure, Tint, Optics Compensation, Camera Lens Blur |
| `PS_Grid` | Black solid with two Venetian Blinds effects → pixel grid + optional scanlines |
| `PS_PixelFX` | Adjustment layer: Mosaic + Glow — **the master pixel toggle gates this** |
| `PS_SRC_R` / `PS_SRC_B` | Red-only / blue-only duplicates in Add mode, position-shifted for chromatic aberration and RGB shift |
| `PS_SRC` | Your original layer, green channel only |

Every wired effect property carries an expression reading from
`PS_Controls`, so the panel is stateless: values live in your project file,
survive reload, and are keyframeable.

The pixel toggle is the `PS Pixels On` checkbox control. It drives the
opacity of `PS_PixelFX` and `PS_Grid` and zeroes the pixel-level RGB shift
via expressions — nothing is deleted when you switch it off.

## Panel ↔ AE protocol

The panel sends one JSON message per action to `PS.dispatch()` in
`jsx/host.jsx`: `apply`, `getState`, `setControl`, `applyPreset`, `setPin`,
`resetPin`, `pinFromMask`. Responses are `{ok, result|error}` JSON.

## Presets

Default, Cinematic Macro, Clean Flat (Pixels Off), CRT Vibe, Security Cam —
defined in `js/presets.js`. Add your own by copying an entry; keys are the
control names on `PS_Controls`.

## Known limitations (v1)

- **Auto Exposure** samples the green channel of the source layer at five
  points; it's a brightness proxy, not a true luma average.
- **DOF** is a uniform Camera Lens Blur; there is no focus-point falloff yet.
- Chromatic aberration offset is horizontal, not radial.
- Corner pin handles are AE's own viewer handles (no in-panel 2D preview).
- English AE UI assumed (see Install note).

## Compatibility

After Effects 2020 (17.0) and newer, Mac and Windows. All effects used are
AE built-ins: Corner Pin, Exposure, Tint, Optics Compensation, Camera Lens
Blur, Shift Channels, Gradient Ramp, Fractal Noise, Venetian Blinds, Mosaic,
Glow, Add Grain.
