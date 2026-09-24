//
//  UpdaterTests.swift
//  LunaTests
//
//  SETTINGS-SPEC §3.10's updater, without the network: which GitHub releases
//  count and which do not, how versions compare, what a downloaded bundle has
//  to be before it is swapped in, and what the About row says.
//

import XCTest
@testable import Luna

final class UpdateVersionTests: XCTestCase {

    func testVersionsCompareAsNumbers() throws {
        let nine = try XCTUnwrap(UpdateVersion("0.9.0"))
        let ten = try XCTUnwrap(UpdateVersion("v0.10.0"))
        XCTAssertLessThan(nine, ten)
        XCTAssertEqual(UpdateVersion("1.2"), UpdateVersion("1.2.0"))
        XCTAssertEqual(ten.description, "0.10.0")
        XCTAssertNil(UpdateVersion("nightly"))
        XCTAssertNil(UpdateVersion("1..2"))
    }
}

@MainActor
final class UpdateReleaseTests: XCTestCase {

    private let sha = String(repeating: "ab", count: 32)

    private func json(
        tag: String = "v0.2.0",
        asset: String = "Luna.zip",
        url: String = "https://github.com/ziadmyassine/luna-browser/releases/download/v0.2.0/Luna.zip",
        digest: String? = nil,
        body: String? = nil,
        prerelease: Bool = false
    ) -> Data {
        var file: [String: Any] = ["name": asset, "browser_download_url": url]
        if let digest { file["digest"] = digest }
        var release: [String: Any] = [
            "tag_name": tag,
            "html_url": "https://github.com/ziadmyassine/luna-browser/releases/tag/\(tag)",
            "draft": false,
            "prerelease": prerelease,
            "assets": [file]
        ]
        if let body { release["body"] = body }
        return (try? JSONSerialization.data(withJSONObject: release)) ?? Data()
    }

    func testAReleaseWithItsZipAndDigestIsRead() throws {
        let release = try XCTUnwrap(UpdateRelease.parse(json(digest: "sha256:\(sha)", body: "Faster tabs.\n\nMore.")))
        XCTAssertEqual(release.version, UpdateVersion("0.2.0"))
        XCTAssertEqual(release.sha256, sha)
        XCTAssertEqual(release.notes, "Faster tabs.")
    }

    /// The workflow writes the checksum into the notes too, and the notes'
    /// checksum line is never shown as the release's words.
    func testTheChecksumCanComeFromTheNotes() throws {
        let release = try XCTUnwrap(UpdateRelease.parse(json(body: "sha256:\(sha)\n")))
        XCTAssertEqual(release.sha256, sha)
        XCTAssertNil(release.notes)
    }

    func testReleasesThatCannotBeInstalledAreNotOffered() {
        XCTAssertNil(UpdateRelease.parse(json()), "no checksum")
        XCTAssertNil(UpdateRelease.parse(json(asset: "Luna.dmg", digest: "sha256:\(sha)")), "no zip")
        XCTAssertNil(UpdateRelease.parse(json(tag: "nightly", digest: "sha256:\(sha)")), "no version")
        XCTAssertNil(UpdateRelease.parse(json(digest: "sha256:\(sha)", prerelease: true)), "a pre-release")
        XCTAssertNil(UpdateRelease.parse(json(digest: "sha256:12")), "a short checksum")
        XCTAssertNil(
            UpdateRelease.parse(json(url: "https://example.com/Luna.zip", digest: "sha256:\(sha)")),
            "a zip from somewhere else"
        )
        XCTAssertNil(
            UpdateRelease.parse(json(
                url: "https://github.com/someone/else/releases/download/v0.2.0/Luna.zip",
                digest: "sha256:\(sha)"
            )),
            "another repo's zip"
        )
        XCTAssertNil(
            UpdateRelease.parse(json(
                url: "http://github.com/ziadmyassine/luna-browser/releases/download/v0.2.0/Luna.zip",
                digest: "sha256:\(sha)"
            )),
            "plain http"
        )
    }
}

@MainActor
final class UpdateSwapTests: XCTestCase {

    private var directory: URL!

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appending(path: "luna-swap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func bundle(identifier: String?, version: String) throws -> URL {
        let app = directory.appending(path: "\(UUID().uuidString).app")
        let contents = app.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleShortVersionString": version]
        if let identifier { info["CFBundleIdentifier"] = identifier }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))
        return app
    }

    /// Luna, newer, by what the bundle says of itself.
    func testOnlyANewerLunaPasses() throws {
        let luna = Bundle.main.bundleIdentifier
        let current = try XCTUnwrap(UpdateVersion("0.2.0"))
        XCTAssertNoThrow(try UpdateSwap.verify(bundle(identifier: luna, version: "0.3.0"), newerThan: current))
        XCTAssertThrowsError(try UpdateSwap.verify(bundle(identifier: luna, version: "0.2.0"), newerThan: current)) {
            XCTAssertEqual($0 as? UpdateSwap.Refused, .notNewer)
        }
        XCTAssertThrowsError(try UpdateSwap.verify(bundle(identifier: "com.example.other", version: "9.0"), newerThan: current)) {
            XCTAssertEqual($0 as? UpdateSwap.Refused, .wrongApp)
        }
    }

    func testTheDigestIsTheFilesSHA256() throws {
        let file = directory.appending(path: "hello.txt")
        try Data("hello".utf8).write(to: file)
        XCTAssertEqual(
            try UpdateSwap.digest(of: file),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
    }
}

@MainActor
final class AboutSectionTests: XCTestCase {

    func testTheUpdatesLineSaysWhatIsHappening() {
        XCTAssertEqual(AboutSection.checkLine(stage: .checking, lastChecked: nil), "Checking…")
        XCTAssertEqual(AboutSection.checkLine(stage: .idle, lastChecked: nil), "Checked once a day on its own")
        XCTAssertTrue(AboutSection.checkLine(stage: .current, lastChecked: Date()).hasPrefix("Luna is up to date"))
        XCTAssertEqual(AboutSection.checkLine(stage: .failed(nil, "Offline."), lastChecked: nil), "Offline.")
        let now = Date()
        let line = AboutSection.checkLine(stage: .idle, lastChecked: now.addingTimeInterval(-3600), now: now)
        XCTAssertTrue(line.contains("Last checked"))
    }

    /// A build made on a developer's Mac carries no release stamp, so it can
    /// never replace itself with the last release.
    func testADevelopmentBuildNeverInstalls() {
        XCTAssertFalse(Updater.shared.canInstall)
    }

    func testTheSectionIsRegisteredLast() {
        XCTAssertEqual(SettingsSectionRegistry.ids.last, AboutSection.id)
        _ = AboutSection().view
    }

    /// The icon starts where the card below starts, as a group's name does,
    /// not a `cardInset` further in.
    func testTheIconIsNotIndented() {
        let header = AboutHeader()
        header.frame = NSRect(x: 0, y: 0, width: 420, height: 80)
        header.layoutSubtreeIfNeeded()
        let icon = try? XCTUnwrap(firstImageView(in: header))
        guard let icon else { return }
        XCTAssertEqual(icon.convert(icon.bounds, to: header).minX, 0, accuracy: 0.001)
    }

    private func firstImageView(in view: NSView) -> NSImageView? {
        for child in view.subviews {
            if let match = child as? NSImageView { return match }
            if let match = firstImageView(in: child) { return match }
        }
        return nil
    }
}
