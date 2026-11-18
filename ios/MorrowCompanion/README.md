# Code Island Buddy

This is the Xcode project for the Code Island iPhone, Live Activity, and Apple Watch Buddy.

For the product overview, setup guide, protocol notes, and screenshots, see:

- [`../../apple-companion/README.md`](../../apple-companion/README.md)

## Project Contents

- `MorrowCompanion/` - iPhone app
- `MorrowCompanionWidget/` - iPhone Live Activity, Dynamic Island, and StandBy UI
- `MorrowWatchApp/` - Apple Watch app
- `MorrowWatchWidget/` - watchOS widget
- `Shared/` - shared models, display helpers, and mascot views
- `project.yml` - XcodeGen project definition

## Open in Xcode

```bash
cd ios/MorrowCompanion
xcodegen generate
open MorrowCompanion.xcodeproj
```
