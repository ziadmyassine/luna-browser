//
//  PrivateDownloadsTests.swift
//  LunaTests
//
//  §5.6 against §15.3: one manager and one list serve every window, so what
//  keeps a private window's downloads its own is which window the list asks,
//  what the window's closing clears, and what the quarantine record says.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class PrivateDownloadsTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testEachWindowListsItsOwnSpacesDownloads() {
        let manager = DownloadManager()
        let ordinary = UUID(), secret = UUID()
        let kept = item(inSpace: ordinary)
        let hidden = item(inSpace: secret)
        manager.add(kept)
        manager.add(hidden)
        let (normalWindow, normalAnchor) = window()
        let (privateWindow, privateAnchor) = window()
        let panel = DownloadsPanelController(manager: manager)
        panel.activeSpace = { $0 === normalWindow ? ordinary : secret }

        panel.toggle(in: normalWindow, from: normalAnchor, edge: .above)
        XCTAssertEqual(panel.items.map(\.id), [kept.id])
        panel.dismiss()
        panel.toggle(in: privateWindow, from: privateAnchor, edge: .above)
        XCTAssertEqual(panel.items.map(\.id), [hidden.id])
        panel.dismiss()
    }

    func testForgettingAPrivateSessionTakesOnlyItsRows() async throws {
        let manager = DownloadManager()
        let ordinary = try await makeSession()
        let secret = try await makeSession(isPrivate: true)
        let kept = item(session: ordinary)
        manager.add(kept)
        manager.add(item(session: secret))

        manager.forget(secret)
        XCTAssertEqual(manager.items.map(\.id), [kept.id])
    }

    func testAPrivateQuarantineKeepsTheFlagAndDropsTheURLs() async throws {
        let secret = try await makeSession(isPrivate: true)
        let properties = DownloadManager.quarantineProperties(for: item(session: secret))
        XCTAssertEqual(properties[kLSQuarantineTypeKey as String] as? String, kLSQuarantineTypeWebDownload as String)
        XCTAssertNil(properties[kLSQuarantineOriginURLKey as String])
        XCTAssertNil(properties[kLSQuarantineDataURLKey as String])

        let ordinary = DownloadManager.quarantineProperties(for: item())
        XCTAssertNotNil(ordinary[kLSQuarantineOriginURLKey as String])
        XCTAssertNotNil(ordinary[kLSQuarantineDataURLKey as String])
    }

    // MARK: - Helpers

    private func item(inSpace spaceID: UUID? = nil, session: BrowserSession? = nil) -> DownloadItem {
        DownloadItem(
            request: URLRequest(url: URL(string: "https://example.com/file.zip")!),
            pageURL: URL(string: "https://example.com/page"),
            filename: "file.zip",
            spaceID: spaceID,
            session: session
        )
    }

    private func makeSession(isPrivate: Bool = false) async throws -> BrowserSession {
        let store = try BrowserStore(path: directory.appending(path: "\(UUID().uuidString).sqlite"))
        return try await BrowserSession.restored(store: store, isPrivate: isPrivate)
    }

    private func window() -> (NSWindow, NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1070, height: 801),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let anchor = NSView(frame: NSRect(x: 20, y: 20, width: 28, height: 28))
        window.contentView?.addSubview(anchor)
        return (window, anchor)
    }
}
