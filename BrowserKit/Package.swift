// swift-tools-version: 6.3

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
    targets: [
        .target(name: "BrowserKit", swiftSettings: swiftSettings),
        .testTarget(
            name: "BrowserKitTests",
            dependencies: ["BrowserKit"],
            swiftSettings: swiftSettings
        )
    ]
)
