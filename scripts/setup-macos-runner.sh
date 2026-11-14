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

# 3. Build & Install XCTest.framework if not present
if [ ! -d "$FRAMEWORKS_DIR/XCTest.framework" ]; then
    echo "==> Compiling and installing swift-corelibs-xctest..."
    rm -rf /tmp/xctest_clone /tmp/XCTest.framework
    git clone --branch swift-6.0.3-RELEASE --depth 1 https://github.com/swiftlang/swift-corelibs-xctest.git /tmp/xctest_clone
    
    # Fix RunLoop default mode compatibility
    sed -i '' 's/mode: \.default/mode: RunLoop.Mode.defaultRunLoopMode/g' /tmp/xctest_clone/Sources/XCTest/Public/Asynchronous/XCTWaiter.swift
    sed -i '' 's/forMode: \.default/forMode: RunLoop.Mode.defaultRunLoopMode/g' /tmp/xctest_clone/Sources/XCTest/Public/Asynchronous/XCTNSPredicateExpectation.swift
    
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
else
    echo "==> XCTest.framework already present in $FRAMEWORKS_DIR."
fi

echo "==> macOS Runner setup completed successfully!"
