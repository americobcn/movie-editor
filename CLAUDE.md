# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a macOS Xcode project. All building and testing is done via Xcode or `xcodebuild`.

```bash
# Build from command line
xcodebuild -project "Movie Editor.xcodeproj" -scheme "Movie Editor" build

# Build for release
xcodebuild -project "Movie Editor.xcodeproj" -scheme "Movie Editor" -configuration Release build

# Clean build
xcodebuild -project "Movie Editor.xcodeproj" -scheme "Movie Editor" clean build
```

There are no unit tests in this project.

## Architecture

**Movie Editor** is a macOS AppKit app (not SwiftUI) for non-destructive video editing with audio replacement and real-time spectrum visualization. It is a mixed Swift/Objective-C target with no external dependencies—only Apple frameworks.

### Layer Summary

| Layer | Files | Purpose |
|-------|-------|---------|
| Controllers | `MainViewController.swift`, `ExportSettingsPanelController.swift` | UI coordination, playback, export workflow |
| Views | `PlayerView.swift`, `MeterView.swift`, `SpectrumBarView.swift`, `ACTSliderCell.swift` | Custom NSView subclasses |
| Audio DSP | `Sources/FFTAnalyzer.swift`, `Sources/AudioTapProcessor.swift` | Real-time FFT spectrum analysis via `MTAudioProcessingTap` |
| Export | `Sources/MediaExporter.swift` | Non-destructive AVAssetReader/AVAssetWriter export |
| Utilities | `Sources/TagEditor.swift` | Binary hev1→hvc1 HEVC tag correction |
| ObjC Bridge | `Obective C/DictionaryKey.h/.m` | Notification name constants |

### Key Data Flow

**Spectrum Visualization:**
`MTAudioProcessingTap` (MediaToolbox) → `FFTAnalyzer` (Accelerate/vDSP, Hann windowing) → `AudioTapProcessor.makeLogSpectrum()` (log-spaced bands, throttled to 30 FPS) → `AudioSpectrumProviderDelegate` → `SpectrumBarView` height updates on main thread.

**Audio Replacement:**
User drags audio file → `NOTIF_REPLACE_AUDIO` (NotificationCenter) → `MainViewController` builds `AVMutableComposition` with original video + new audio → `MediaExporter` writes pass-through video + AAC-re-encoded audio.

**Export:**
`MediaExporter` uses separate `AVAssetReader`/`AVAssetWriter` instances on background dispatch queues. Video is always pass-through (no transcode). Audio is re-encoded to AAC.

### Notification Constants (ObjC)

Defined in `DictionaryKey.h/.m` and imported via the bridging header:
- `NOTIF_OPENFILE` — load a video file
- `NOTIF_REPLACE_AUDIO` — replace audio track
- `NOTIF_NEW_ASSET` — asset finished loading
- `NOTIF_TOGGLETIMECODEDISPLAY` — toggle timecode display

### Threading Model

- Audio tap callbacks run on a dedicated background queue
- `FFTAnalyzer` uses `NSLock` to protect buffer access
- All `SpectrumBarView`/`MeterView` updates must be dispatched to `DispatchQueue.main`
- Export uses two separate `DispatchQueue`s (video + audio) coordinated via `DispatchGroup`/semaphore

### FFT Details

`FFTAnalyzer` applies a Hann window before computing the FFT, then scales bins differently for DC, body, and Nyquist components. `AudioTapProcessor` maps the resulting linear bins to logarithmically-spaced display bands (20 Hz → Nyquist) using fractional-weight interpolation between adjacent bins for smooth visualization.

## Code Style

- 4-space indentation
- PascalCase for types, camelCase for properties/functions
- `MARK:` comments to separate logical sections within large files
- `async/await` preferred over completion handlers
- `@MainActor` for any UI updates triggered from async contexts
- Weak captures `[weak self]` in closures stored by objects
