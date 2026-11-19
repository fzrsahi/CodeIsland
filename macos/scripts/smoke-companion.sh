#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

./scripts/check-companion-ui-regressions.sh

swift test --filter AppleCompanionPayloadTests
swift test --filter AppStateQuestionFlowTests
swift test --filter AppStatePrimarySourceTests
swift build

xcodebuild \
  -project ../ios/MorrowCompanion/MorrowCompanion.xcodeproj \
  -scheme MorrowCompanion \
  -destination 'generic/platform=iOS' \
  build
