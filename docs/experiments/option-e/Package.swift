// swift-tools-version: 5.9
// Option E experiment (#85): MorrowCore + its pure test suite only, built on
// Linux. On macOS the system SQLite3/CryptoKit modules are used instead.
import PackageDescription

let package = Package(
    name: "MorrowCoreLinux",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "opte-probe", targets: ["opte-probe"]),
    ],
    dependencies: [
        // CryptoKit replacement on Linux (SHA256, HMAC, P256/ES256 for push).
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite",
            providers: [.apt(["libsqlite3-dev"])]
        ),
        .target(
            name: "MorrowCore",
            dependencies: [
                .target(name: "CSQLite", condition: .when(platforms: [.linux])),
                .product(name: "Crypto", package: "swift-crypto",
                         condition: .when(platforms: [.linux])),
            ],
            path: "Sources/MorrowCore"
        ),
        // Tiny executable that links MorrowCore, used to measure a static
        // release binary.
        .executableTarget(
            name: "opte-probe",
            dependencies: ["MorrowCore"],
            path: "Sources/opte-probe"
        ),
        .target(
            name: "TestDefaultsReset",
            path: "Tests/TestDefaultsReset"
        ),
        .testTarget(
            name: "MorrowCoreTests",
            dependencies: [
                "MorrowCore", "TestDefaultsReset",
                .target(name: "CSQLite", condition: .when(platforms: [.linux])),
            ],
            path: "Tests/MorrowCoreTests",
            // Option E: these use AttributedString markdown attributes
            // (inlinePresentationIntent) that swift-foundation on Linux lacks.
            // They cannot compile on Linux and are counted as failed.
            exclude: [
                "ChatMessageTextFormatterTests.swift",
                "MarkdownInlineLiteralsTests.swift",
                "MarkdownPreviewTextTests.swift",
            ]
        ),
    ]
)
