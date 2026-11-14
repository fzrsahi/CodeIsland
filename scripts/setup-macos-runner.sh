#!/usr/bin/env bash
set -euo pipefail

echo "==> Configuring macOS Runner for Swift & XCTest..."

CLT_DIR="/Library/Developer/CommandLineTools"
MANIFEST_API_DIR="$CLT_DIR/usr/lib/swift/pm/ManifestAPI/PackageDescription.swiftmodule"
SWIFT_INC_DIR="$CLT_DIR/usr/include/swift"
FRAMEWORKS_DIR="$CLT_DIR/Library/Developer/Frameworks"

# 1. Fix PackageDescription manifest linker issue (Apple Xcode 16 bug on x86_64)
if [ -f "$MANIFEST_API_DIR/x86_64-apple-macos.private.swiftinterface" ]; then
    echo "==> Fixing PackageDescription private.swiftinterface..."
    sudo mv "$MANIFEST_API_DIR/x86_64-apple-macos.private.swiftinterface" "$MANIFEST_API_DIR/x86_64-apple-macos.private.swiftinterface.bak" || true
fi
if [ -f "$MANIFEST_API_DIR/arm64-apple-macos.private.swiftinterface" ]; then
    sudo mv "$MANIFEST_API_DIR/arm64-apple-macos.private.swiftinterface" "$MANIFEST_API_DIR/arm64-apple-macos.private.swiftinterface.bak" || true
fi

# 2. Fix SwiftBridging module redefinition (Apple Xcode 16 duplicate modulemap bug)
if [ -f "$SWIFT_INC_DIR/module.modulemap" ]; then
    echo "==> Fixing SwiftBridging duplicate modulemap..."
    sudo mv "$SWIFT_INC_DIR/module.modulemap" "$SWIFT_INC_DIR/module.modulemap.bak" || true
fi

# 3. Build & Install XCTest.framework with Xcode-matching @MainActor isolation
echo "==> Compiling and installing swift-corelibs-xctest with @MainActor support..."
rm -rf /tmp/xctest_clone /tmp/XCTest.framework
git clone --branch swift-6.0.3-RELEASE --depth 1 https://github.com/swiftlang/swift-corelibs-xctest.git /tmp/xctest_clone

# Fix RunLoop default mode compatibility
sed -i '' 's/mode: \.default/mode: RunLoop.Mode.defaultRunLoopMode/g' /tmp/xctest_clone/Sources/XCTest/Public/Asynchronous/XCTWaiter.swift
sed -i '' 's/forMode: \.default/forMode: RunLoop.Mode.defaultRunLoopMode/g' /tmp/xctest_clone/Sources/XCTest/Public/Asynchronous/XCTNSPredicateExpectation.swift

# Align open-source XCTestCase with Apple SDK @MainActor isolation for Swift 6
python3 -c '
with open("/tmp/xctest_clone/Sources/XCTest/Public/XCAbstractTest.swift", "r") as f:
    c = f.read()
c = c.replace("open func setUp() {}", "@MainActor open func setUp() {}")
c = c.replace("open func tearDown() {}", "@MainActor open func tearDown() {}")
c = c.replace("open func setUpWithError() throws {}", "@MainActor open func setUpWithError() throws {}")
c = c.replace("open func tearDownWithError() throws {}", "@MainActor open func tearDownWithError() throws {}")
c = c.replace("open func setUp() async throws {}", "@MainActor open func setUp() async throws {}")
c = c.replace("open func tearDown() async throws {}", "@MainActor open func tearDown() async throws {}")
with open("/tmp/xctest_clone/Sources/XCTest/Public/XCAbstractTest.swift", "w") as f:
    f.write(c)

with open("/tmp/xctest_clone/Sources/XCTest/Public/XCTestSuite.swift", "r") as f:
    c = f.read()
c = c.replace("        setUp()\n        for test in tests {", "        MainActor.assumeIsolated { setUp() }\n        for test in tests {")
c = c.replace("        tearDown()\n        run.stop()", "        MainActor.assumeIsolated { tearDown() }\n        run.stop()")
with open("/tmp/xctest_clone/Sources/XCTest/Public/XCTestSuite.swift", "w") as f:
    f.write(c)

with open("/tmp/xctest_clone/Sources/XCTest/Public/XCTestCase.swift", "r") as f:
    c = f.read()
c = c.replace("try setUpWithError()", "try MainActor.assumeIsolated { try setUpWithError() }")
c = c.replace("        setUp()", "        MainActor.assumeIsolated { setUp() }")
c = c.replace("        tearDown()", "        MainActor.assumeIsolated { tearDown() }")
c = c.replace("try tearDownWithError()", "try MainActor.assumeIsolated { try tearDownWithError() }")
c = c.replace("open func recordFailure(", "nonisolated open func recordFailure(")
c = c.replace("func recordFailure(description:", "nonisolated func recordFailure(description:")
c = c.replace("private func recordFailure(for error:", "nonisolated private func recordFailure(for error:")
with open("/tmp/xctest_clone/Sources/XCTest/Public/XCTestCase.swift", "w") as f:
    f.write(c)

with open("/tmp/xctest_clone/Sources/XCTest/Private/XCTestCaseSuite.swift", "r") as f:
    c = f.read()
c = c.replace("let testCase = testCaseClass.init(name: testName, testClosure: testClosure)", "let testCase = MainActor.assumeIsolated { testCaseClass.init(name: testName, testClosure: testClosure) }")
c = c.replace("testCaseClass.setUp()", "MainActor.assumeIsolated { testCaseClass.setUp() }")
c = c.replace("testCaseClass.tearDown()", "MainActor.assumeIsolated { testCaseClass.tearDown() }")
with open("/tmp/xctest_clone/Sources/XCTest/Private/XCTestCaseSuite.swift", "w") as f:
    f.write(c)
'

(cd /tmp/xctest_clone && swift build -Xswiftc -DUSE_FOUNDATION_FRAMEWORK)

# Assemble framework bundle
mkdir -p /tmp/XCTest.framework/Versions/A/Modules/XCTest.swiftmodule
cp /tmp/xctest_clone/.build/debug/libXCTest.dylib /tmp/XCTest.framework/Versions/A/XCTest
cp /tmp/xctest_clone/.build/debug/Modules/XCTest.swiftmodule /tmp/XCTest.framework/Versions/A/Modules/XCTest.swiftmodule/x86_64-apple-macos.swiftmodule
cp /tmp/xctest_clone/.build/debug/Modules/XCTest.swiftdoc /tmp/XCTest.framework/Versions/A/Modules/XCTest.swiftmodule/x86_64-apple-macos.swiftdoc

cat << 'EOF' > /tmp/XCTest.framework/Versions/A/Modules/module.modulemap
framework module XCTest {
    umbrella header "XCTest.h"
    export *
    module * { export * }
}
EOF
mkdir -p /tmp/XCTest.framework/Versions/A/Headers
touch /tmp/XCTest.framework/Versions/A/Headers/XCTest.h
(cd /tmp/XCTest.framework/Versions && ln -s A Current)
(cd /tmp/XCTest.framework && ln -s Versions/Current/XCTest XCTest)
(cd /tmp/XCTest.framework && ln -s Versions/Current/Modules Modules)
(cd /tmp/XCTest.framework && ln -s Versions/Current/Headers Headers)
install_name_tool -id @rpath/XCTest.framework/Versions/A/XCTest /tmp/XCTest.framework/Versions/A/XCTest

sudo mkdir -p "$FRAMEWORKS_DIR"
sudo cp -R /tmp/XCTest.framework "$FRAMEWORKS_DIR/"
rm -rf /tmp/xctest_clone /tmp/XCTest.framework
echo "==> XCTest.framework installed successfully to $FRAMEWORKS_DIR/XCTest.framework!"

echo "==> macOS Runner setup completed successfully!"
