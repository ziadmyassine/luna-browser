//
//  FileStorageSeedTests.swift
//  LunaTests
//
//  A page opened from a file finds what another browser saved for it, once:
//  what the page changes in Luna afterwards stays changed.
//

import WebKit
import XCTest
@testable import BrowserKit
@testable import Luna

@MainActor
final class FileStorageSeedTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-seed-\(UUID().uuidString)")

    override func tearDown() async throws {
        FileStorageSeed.cached = nil
        FileStorageSeed.provider = nil
        try? FileManager.default.removeItem(at: directory)
    }

    private func open(_ file: URL, in store: WKWebsiteDataStore) async throws -> WKWebView {
        let tab = TabController(id: UUID(), dataStore: store)
        tab.load(file)
        let web = try XCTUnwrap(tab.webView)
        for _ in 0 ..< 100 {
            let loaded = try? await web.evaluateJavaScript("location.protocol == 'file:' && document.readyState == 'complete'")
            if loaded as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        return web
    }

    func testAFilePageIsSeededOnceAndKeepsWhatItChanges() async throws {
        FileStorageSeed.cached = nil
        FileStorageSeed.provider = { ["board": "from Dia", "note": "from Dia"] }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "board.html")
        // Reads its storage as it builds, the way a board restores its ticks.
        try Data("<!doctype html><script>window.seen = localStorage.getItem('board');</script>".utf8).write(to: file)
        let store = WKWebsiteDataStore.nonPersistent()

        let first = try await open(file, in: store)
        let seen = try await first.evaluateJavaScript("window.seen") as? String
        XCTAssertEqual(seen, "from Dia", "the page built itself before the seed landed")
        _ = try await first.evaluateJavaScript("localStorage.setItem('note', 'changed in Luna'); 1")

        let second = try await open(file, in: store)
        let note = try await second.evaluateJavaScript("localStorage.getItem('note')") as? String
        XCTAssertEqual(note, "changed in Luna", "the seed ran again over what the page changed")
    }

    func testNothingToCarryIsNoScript() {
        XCTAssertNil(FileStorageSeed.source(for: [:]))
        XCTAssertTrue(FileStorageSeed.source(for: ["a": "b"])?.contains(FileStorageSeed.marker) ?? false)
    }

    /// A text file WebKit has no viewer for is shown, not downloaded.
    func testAnUnviewableTextFileIsReadAsText() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let yaml = directory.appending(path: "config.yaml")
        try Data("key: value\n".utf8).write(to: yaml)
        XCTAssertEqual(TabController.localText(at: yaml), Data("key: value\n".utf8))
        XCTAssertNil(TabController.localText(at: directory.appending(path: "photo.png")))
        XCTAssertNil(TabController.localText(at: URL(string: "https://example.com/config.yaml")!))
    }
}
