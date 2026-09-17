// swift-tools-version: 6.3

import PackageDescription

// The §19.1 measurement harness. Deliberately a separate package: it links
// `BrowserKit` so the memory scenario drives the **real** `TabController` and
// `WebViewFactory` rather than a mock, but it is not part of the app and
// `project.yml` never sees it.
let package = Package(
    name: "luna-perf",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "../../BrowserKit")],
    targets: [
        .executableTarget(
            name: "LunaPerf",
            dependencies: [.product(name: "BrowserKit", package: "BrowserKit")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
