# Movie Editor

## Project presentation

Movie Editor is a lightweight macOS application for replacing audio in a movie file, fix files tagged with 'hev1' that are not properly played in macos and save/exporting movie files. It provides audio visualization (meters, spectrum, FFT), non-destructive tagging, and streamlined export workflows. The app combines native macOS UI components with high-performance audio processing.

## Description

The app provides an integrated environment for inspecting and preparing video content. Core features include:

- Replace movie audio just dragging a new audio at insertion point and save without transcoding video.
- Real-time audio metering and spectrum analysis (FFT).
- Replace H.265 files tagged with 'hev1' tag to 'hvc1' to properly play file on macos.
- Export video to h.264, h.265 or ProRes 422 without changing video resolution.
- Set prefered export codec on Export Codec Panel.

The codebase is a mix of Swift and Objective-C (bridging headers), with a modular structure for Views, Controllers, and audio processing logic. It is designed to be easy to extend and integrate into existing macOS media workflows.

## Quick start

1. Open the Xcode project (Movie Editor.xcodeproj) and build for macOS.
2. Run the app from Xcode or the built app bundle.
3. Use the player to open media files, inspect audio with the meters and spectrum view, change 'hev1' tag to properly play with macos, insert audio and save or export via the Export Settings panel.

## Where to look in the code

- Controllers: `Controllers/` contains window and panel controllers like `MainViewController.swift` and `ExportSettingsPanelController.swift`.
- Audio processing: `Sources/` contains `AudioTapProcessor.swift`, `FFTAnalyzer.swift`, and `MediaExporter.swift`.
- Views: `Views/` has custom UI elements such as `MeterView.swift` and `SpectrumBarView.swift`.

## Contributing

Contributions and improvements welcome. Open an issue or submit a pull request with a short description of the change.
