# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MeshRed is a SwiftUI application built for multiple Apple platforms (iOS, macOS, and visionOS). The project is configured as a modern Xcode project using Swift 5.0 with the latest iOS 26.0 SDK and supports cross-platform deployment.

## Development Commands

### Building the Project
```bash
# Build for macOS
xcodebuild -scheme MeshRed -destination "platform=macOS"

# Build for iOS Simulator
xcodebuild -scheme MeshRed -destination "platform=iOS Simulator,name=iPhone 17"

# Build for physical iOS device
xcodebuild -scheme MeshRed -destination "platform=iOS,name=Any iOS Device"
```

### Running Tests
```bash
# Run unit tests
xcodebuild test -scheme MeshRed -destination "platform=macOS"

# Run UI tests
xcodebuild test -scheme MeshRed -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:MeshRedUITests
```

### Available Targets
- `MeshRed` - Main application target
- `MeshRedTests` - Unit tests using Swift Testing framework
- `MeshRedUITests` - UI tests

## Project Structure

```
MeshRed/
├── MeshRed/                    # Main application code
│   ├── MeshRedApp.swift       # App entry point
│   ├── ContentView.swift     # Main view
│   └── Assets.xcassets/      # App assets
├── MeshRedTests/              # Unit tests
└── MeshRedUITests/           # UI tests
```

## Architecture

This is a standard SwiftUI application with:

- **App Entry Point**: `MeshRedApp.swift` using the `@main` attribute
- **UI Framework**: SwiftUI for cross-platform compatibility
- **Testing**: Uses the modern Swift Testing framework (not XCTest)
- **Deployment Targets**: iOS 26.0, macOS 26.0, visionOS 26.0
- **Development Team**: QF2R75VM2Y

## Key Configurations

- **Bundle Identifier**: `EmilioContreras.MeshRed`
- **Swift Version**: 5.0
- **Minimum Deployment Targets**: iOS 26.0, macOS 26.0, visionOS 26.0
- **Supported Platforms**: iPhone, iPad, Mac, Apple Vision Pro
- **App Sandbox**: Enabled for security
- **Code Signing**: Automatic

## Testing Framework

The project uses Swift Testing framework (import Testing) instead of traditional XCTest. Test functions are marked with `@Test` attribute.