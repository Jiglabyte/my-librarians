# ScreenLapse

A free, open-source native macOS screen recorder with built-in **time-lapse mode**. Inspired by Tap Record, but with HEVC hardware encoding for **massively smaller files** at the same visual quality — and time-lapse built right in.

## Highlights

- **Two modes**: Normal (25 / 30 / 60 fps) and Time-lapse (5× / 10× / 15× / 30× / 60×)
- **HEVC (H.265) hardware encoding** by default — files are 5–10× smaller than QuickTime; time-lapse files are 50–100× smaller
- **Menu-bar app** — no Dock icon, no clutter
- **Tap-Record-style floating toolbar** while recording so you always know where to stop
- **System audio + microphone** (normal mode)
- **Webcam overlay** (picture-in-picture, any corner, size slider)
- **Click highlighting** (ripples on mouse clicks)
- **Region / window / display** capture sources
- **Built-in trim editor** (lossless, no re-encode)
- **Quick share** via AirDrop / Mail / Messages
- **Recent recordings panel**
- **3-2-1 countdown** before recording starts
- **Global hotkey**: ⌃⇧R toggles recording from anywhere
- **Resolution presets**: native, 4K, 1440p, 1080p, 720p

| Mode | 1 minute of capture | Output file size |
|------|---------------------|------------------|
| QuickTime | 1 min video | ~75 MB |
| ScreenLapse Normal 30fps HEVC | 1 min video | ~15 MB |
| ScreenLapse Time-lapse 15× | 4 sec video | ~1 MB |

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15+ (for building)
- `xcodegen` (for project generation): `brew install xcodegen`

## Build

```bash
cd ScreenLapse
./build.sh debug      # build for development
./build.sh run        # build and launch
./build.sh release    # optimized build into build/ScreenLapse.app
./build.sh dmg        # build Release and create ScreenLapse-1.0.0.dmg
./build.sh clean      # remove build artifacts
```

Or open in Xcode:

```bash
xcodegen generate
open ScreenLapse.xcodeproj
# ⌘R to run
```

## First-launch permissions

The first time you click **Start Recording**, macOS will ask for:

- **Screen Recording** (required) — System Settings → Privacy & Security → Screen Recording
- **Camera** (only if you enable the webcam overlay)
- **Microphone** (only if you enable mic recording)

If you previously denied a permission, the Settings pane will offer a button to open the right System Settings panel.

## How to use

1. Click the **record-circle icon** in the menu bar — the popover opens
2. Pick **Normal** or **Time-lapse** at the top
3. Choose fps or speed multiplier
4. Pick a source (display / window / region)
5. Click **Start Recording** — a 3-second countdown, then capture begins
6. The **floating toolbar** appears in the corner with elapsed time, file size, and a stop button
7. Stop with the toolbar button, the menu bar popover, or the ⌃⇧R global hotkey
8. Open the popover and click **Recent** to trim, share, or reveal recordings

Recordings save to `~/Movies/ScreenLapse/` by default. Change the folder in **Settings → Recording**.

## Architecture

```
ScreenLapse/
├── project.yml                  XcodeGen spec
├── build.sh                     debug/release/run/dmg/clean
└── ScreenLapse/
    ├── ScreenLapseApp.swift     @main
    ├── AppDelegate.swift        Status item + popover + hotkey
    ├── Core/                    Capture, encoding, orchestration
    │   ├── RecordingMode.swift
    │   ├── RecordingManager.swift     ObservableObject orchestrator
    │   ├── CaptureEngine.swift        ScreenCaptureKit SCStream
    │   ├── CameraCapture.swift        AVCaptureSession (webcam)
    │   ├── MicCapture.swift           AVCaptureSession (mic)
    │   ├── ClickTracker.swift         CGEventTap → click events
    │   ├── FrameCompositor.swift      CoreImage overlay compositor
    │   ├── VideoWriter.swift          AVAssetWriter + HEVC, timestamp remap
    │   └── RecentRecordings.swift
    ├── Views/                   SwiftUI UI
    │   ├── MenuBarPopover.swift
    │   ├── NormalModeView.swift
    │   ├── TimeLapseModeView.swift
    │   ├── SourceSelectorView.swift
    │   ├── RegionSelectorOverlay.swift  drag-to-select overlay
    │   ├── FloatingToolbar.swift        Tap-Record-style toolbar
    │   ├── CountdownOverlay.swift       3-2-1 countdown
    │   ├── TrimEditorView.swift         lossless trim
    │   ├── RecentRecordingsView.swift
    │   └── SettingsView.swift
    ├── Support/                 Permissions, hotkey, share helpers
    │   ├── PermissionChecker.swift
    │   ├── Hotkey.swift                Carbon EventHotKey
    │   └── ShareHelper.swift           NSSharingServicePicker
    ├── Info.plist
    └── ScreenLapse.entitlements
```

### How time-lapse works (the trick)

We tell ScreenCaptureKit to capture at a low frame rate (e.g. 2 fps for a 15× time-lapse), then rewrite each frame's presentation timestamp so the output plays back at 30 fps. The result is a real time-lapse — captured cheaply, encoded cheaply, played back fast — at a tiny fraction of the size you'd get by recording at full rate and dropping frames in post.

```swift
// SCStreamConfiguration
config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(captureFPS))

// In VideoWriter.appendVideo
let pts = CMTime(value: frameIndex, timescale: 30)  // 30 fps playback
frameIndex += 1
pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: pts)
```

## Distribution

`./build.sh dmg` produces `build/ScreenLapse-<version>.dmg` with the app and an `/Applications` symlink for drag-to-install.

For App Store distribution you'd need to:
- Turn on `com.apple.security.app-sandbox` in `ScreenLapse.entitlements`
- Add security-scoped bookmarks for the user's chosen output folder
- Set up signing & a provisioning profile in Xcode

For Gatekeeper-friendly distribution outside the App Store, sign with your own Developer ID certificate (`codesign --sign "Developer ID Application: …"`) and notarize via `xcrun notarytool`.

## License

MIT — see top of repo. Free forever.
