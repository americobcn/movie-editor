# AGENTS.md

Guidelines for AI coding agents working on the Movie Editor macOS application.

## Build/Run/Test Commands

- **Build in Xcode:** ⌘+B or `xcodebuild -project "Movie Editor.xcodeproj"`
- **Run:** ⌘+R in Xcode or build and open built app
- **Clean:** ⌘+Shift+K or `xcodebuild clean`
- **No unit tests:** This project currently has no test targets

## Project Structure

```
Movie Editor/
├── Controllers/          # NSViewController classes
│   ├── MainViewController.swift
│   └── ExportSettingsPanelController.swift
├── Sources/              # Core logic and processing
│   ├── AudioTapProcessor.swift    # Audio processing tap
│   ├── FFTAnalyzer.swift          # FFT spectrum analysis
│   ├── MediaExporter.swift        # Export functionality
│   └── TagEditor.swift            # HEVC tag editor
├── Views/                # Custom NSView classes
│   ├── MeterView.swift
│   ├── SpectrumBarView.swift
│   ├── PlayerView.swift
│   ├── ACTSliderCell.swift
│   └── ACTVerticalSliderCell.swift
├── Obective C/           # Objective-C bridge
│   ├── DictionaryKey.h/m
│   └── Movie Editor-Bridging-Header.h
├── AppDelegate.swift
└── Info.plist
```

## Code Style Guidelines

### Imports
- Group imports: Foundation first, then Apple frameworks, then local
- Use `@import` in Objective-C bridging header
- Example:
  ```swift
  import Foundation
  import AVFoundation
  import AppKit
  ```

### Naming Conventions
- **Classes/Structs:** PascalCase (e.g., `AudioTapProcessor`, `MeterView`)
- **Variables/Properties:** camelCase (e.g., `mediaPlayer`, `spectrumBands`)
- **Constants:** Upper snake case for notification keys (e.g., `NOTIF_OPENFILE`)
- **Enums:** PascalCase with camelCase cases (e.g., `case .playing, .stopped`)
- **IBOutlets:** End with type (e.g., `playerView`, `playPauseBtn`)
- **IBActions:** Start with verb (e.g., `playPauseVideo`, `loadMovie`)

### Comments
- Use `// MARK: - Section Name` for organization
- Use `//MARK: Description` (no space after slashes) for properties/methods
- Standard header in each file:
  ```swift
  //
  //  Filename.swift
  //  Movie Editor
  //
  //  Created by Name on Date.
  //  Copyright © Year Américo Cot Toloza. All rights reserved.
  //
  ```

### Formatting
- 4 spaces indentation
- Opening brace on same line as declaration
- Spaces around operators and after commas
- One blank line between methods/functions

### Types and Error Handling
- Use `async/await` for asynchronous operations
- Prefer `do-catch` with `try await` over completion handlers
- Use enums for custom errors with errorDescription
- Use `guard let` and `if let` for optional binding
- Mark private/internal appropriately
- Use `final class` for classes not intended for subclassing

### Swift-Specific
- Prefer `struct` for simple data containers
- Use protocols for delegates (e.g., `AudioSpectrumProviderDelegate`)
- Use `weak` for delegate references to prevent retain cycles
- Use `[weak self]` in closures capturing self
- Use `MainActor` for UI updates from async contexts
- Use `#keyPath()` for KVO instead of string literals

### Audio/Video Processing
- Use `MTAudioProcessingTap` for real-time audio processing
- Use `Accelerate` framework (vDSP) for DSP operations
- Handle CMTime and audio formats with proper type checking
- Validate asset tracks before processing

### Objective-C Bridge
- Keep Objective-C code minimal (constants/keys only)
- Import bridging header in Objective-C `.m` files
- Expose Swift classes to Objective-C with `@objc` if needed

### UI Patterns
- Subclass `NSView` for custom visual components
- Use `@IBOutlet` and `@IBAction` for Interface Builder connections
- Configure layer-backed views: `wantsLayer = true`
- Support concurrent drawing where appropriate: `canDrawConcurrently = true`

### AVFoundation Guidelines
- Load asset properties with `try await asset.load(.property)`
- Check for valid durations: `duration.isNumeric && duration.value != 0`
- Use `AVMutableComposition` for non-destructive editing
- Clean up resources (invalidate timers, remove observers) in `deinit`
