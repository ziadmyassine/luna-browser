// swift-tools-version: 6.2

import PackageDescription

// Swift 6 language mode is complete strict concurrency; it is stated explicitly
// so the setting survives a future tools-version bump (§ contract: Swift 6, strict).
let swiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "BrowserKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "BrowserKit", targets: ["BrowserKit"])
    ],
    dependencies: [
        // GRDB 7 is the Swift 6 line: Sendable-audited, strict-concurrency clean, and it
        // ships `SQLITE_ENABLE_FTS5` so §11.2's full-text index needs no custom SQLite.
        // Exact pin (§0.3): a storage engine is not a thing to let float. Bump deliberately.
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1")
    ],
    targets: [
        .target(
            name: "BrowserKit",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "BrowserKitTests",
            dependencies: ["BrowserKit"],
            // §16's fixtures: a real Web Store CRX3 and a two-file extension.
            resources: [.copy("Fixtures")],
            swiftSettings: swiftSettings
        )
    ]
)
