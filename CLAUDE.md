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

**Movie Editor** is a macOS SwiftUI app (SwiftUI `App` lifecycle, no XIB/storyboard, no Objective-C) for non-destructive video editing with audio replacement and real-time spectrum visualization. It uses only Apple frameworks. Swift 5 language mode, macOS 15.6 deployment target.

### Layer Summary

| Layer | Files | Purpose |
|-------|-------|---------|
| App | `App/MovieEditorApp.swift` | `@main`, single `Window`, menu `.commands`, `Settings` scene |
| Models | `Models/PlayerModel.swift`, `MeterModel.swift`, `MediaInfo.swift`, `ExportCodec.swift` | `@MainActor @Observable` state and logic: AVPlayer, loading, transport, seeking, audio replace, save/export, meter levels, info text, export codec |
| Views | `Views/ContentView.swift`, `TransportBar.swift`, `VideoSurface.swift`, `SpectrumView.swift`, `LevelMetersView.swift`, `ExportSettingsView.swift` | SwiftUI UI. `VideoSurface` wraps a bare `AVPlayerLayer` in an `NSViewRepresentable`; meters are `Canvas` views |
| Audio DSP | `Sources/FFTAnalyzer.swift`, `Sources/AudioTapProcessor.swift` | Real-time FFT spectrum analysis via `MTAudioProcessingTap` |
| Export | `Sources/MediaExporter.swift` | Non-destructive AVAssetReader/AVAssetWriter export |
| Utilities | `Sources/TagEditor.swift` | Binary hev1→hvc1 HEVC tag correction |

### Key Data Flow

**Spectrum Visualization:**
`MTAudioProcessingTap` (MediaToolbox) → `FFTAnalyzer` (Accelerate/vDSP, Hann windowing) → `AudioTapProcessor.makeLogSpectrum()` (log-spaced bands, throttled to 30 FPS) → `AudioSpectrumProviderDelegate` (implemented by `MeterModel`) → main-thread smoothing → `spectrumLevels` / `channelLevels` (0...1) → `SpectrumView` / `LevelMetersView`. When playback pauses, `MeterModel` fades the bars out with a timer.

**Audio Replacement:**
Audio file dropped on the video (`.dropDestination` in `ContentView`) → `PlayerModel.handleDrop` → `checkFileType` → `insertOrRemoveAudio(url:)` builds an `AVMutableComposition` with original video + new audio and attaches a new tap. Video files dropped or opened load via `loadMovie(url:)`.

**Export:**
Save (`PlayerModel.save`) uses `MediaExporter` with separate `AVAssetReader`/`AVAssetWriter` on background queues: video pass-through, audio re-encoded to AAC. Export (`exportMovie`) uses `AVAssetExportSession` with the preset of the codec chosen in Settings (`ExportCodec`, stored with `@AppStorage`).

### Threading Model

- Audio tap callbacks run on a dedicated background queue; `AudioTapProcessor` hops to the main queue via `MeterModel.spectrumDidChange`
- `FFTAnalyzer` uses `NSLock` to protect buffer access
- `PlayerModel` and `MeterModel` are `@MainActor`; AVPlayer observers (`rate`, periodic time) hop to the main actor
- Export uses two separate `DispatchQueue`s (video + audio) coordinated via `DispatchGroup`/semaphore

### FFT Details

`FFTAnalyzer` applies a Hann window before computing the FFT, then scales bins differently for DC, body, and Nyquist components. `AudioTapProcessor` maps the resulting linear bins to logarithmically-spaced display bands (20 Hz → Nyquist) using fractional-weight interpolation between adjacent bins for smooth visualization.

## Code Style

- 4-space indentation
- PascalCase for types, camelCase for properties/functions
- `MARK:` comments to separate logical sections within large files
- `async/await` preferred over completion handlers
- `@MainActor` for any UI updates triggered from async contexts
- `@Observable` models (not `ObservableObject`); mark non-UI state `@ObservationIgnored`
- Weak captures `[weak self]` in closures stored by objects

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
