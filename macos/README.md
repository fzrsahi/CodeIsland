# Morrow macOS Native Application

This directory contains the native macOS implementation of Morrow, built with Swift, SwiftUI, and AppKit.

## Architecture

- **`Sources/Morrow`**: Main application entry point, AppKit window controller, and SwiftUI interface views.
- **`Sources/MorrowCore`**: Core state management, notch geometry calculations, and event dispatchers.
- **`Sources/MorrowBridge`**: IPC and bridge connectors interfacing with background processes and shared protocol contracts.
- **`Tests/`**: Native XCTest test suite covering notch geometry, models, and bridge serialization.

## Build and Test

```bash
# Run local tests
swift test --package-path macos

# Build release bundle
./macos/build.sh
```
