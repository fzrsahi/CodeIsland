// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Morrow",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Sparkle — auto-update framework. Pinned to 2.6+ for stable
        // SPUStandardUpdaterController + ed25519 signature verification.
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "MorrowCore",
            path: "Sources/MorrowCore"
        ),
        .executableTarget(
            name: "Morrow",
            dependencies: [
                "MorrowCore",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/Morrow",
            resources: [
                .copy("Resources")
            ]
        ),
        .executableTarget(
            name: "morrow-bridge",
            dependencies: ["MorrowCore"],
            path: "Sources/MorrowBridge"
        ),
        // Resets the xctest runner's shared defaults domain when a test
        // bundle loads (see Tests/TestDefaultsReset/TestDefaultsReset.c).
        .target(
            name: "TestDefaultsReset",
            path: "Tests/TestDefaultsReset"
        ),
        // The stand-in ancestor processes BridgeGoldenTests runs the bridge
        // under, built next to the test bundles (never shipped).
        .executableTarget(
            name: "morrow-golden-stub",
            path: "Tests/GoldenAncestryStub"
        ),
        .testTarget(
            name: "MorrowCoreTests",
            dependencies: ["MorrowCore", "TestDefaultsReset"],
            path: "Tests/MorrowCoreTests"
        ),
        .testTarget(
            name: "MorrowTests",
            dependencies: [
                "Morrow",
                "TestDefaultsReset",
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Tests/MorrowTests"
        ),
    ]
)
