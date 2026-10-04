//
//  OpenLinkInNewTabTests.swift
//  LunaTests
//
//  The page's right-click menu offers Open Link in New Tab, which sends
//  WebKit's own new-window item marked for the background; and a link opened
//  that way, or ⌘-clicked, is a new tab that leaves the one in front where it is.
//

import AppKit
import BrowserKit
import WebKit
import XCTest
@testable import Luna

@MainActor
final class OpenLinkInNewTabTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-newtab-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private final class Recorder: NSObject {
        var fired = 0
        @objc func openInNewWindow(_ sender: Any?) { fired += 1 }
    }

    func testTheMenuOffersANewTabBeforeWebKitsNewWindow() throws {
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.activate()
        let view = try XCTUnwrap(controller.webView as? LunaWebView, "pages are not LunaWebViews")
        let recorder = Recorder()
        let newWindow = NSMenuItem(title: "Open Link in New Window", action: #selector(Recorder.openInNewWindow(_:)), keyEquivalent: "")
        newWindow.identifier = NSUserInterfaceItemIdentifier(LunaWebView.newWindowItem)
        newWindow.target = recorder
        let menu = NSMenu()
        menu.addItem(newWindow)

        view.willOpenMenu(menu, with: NSEvent())
        let item = try XCTUnwrap(menu.items.first, "no item was added")
        XCTAssertEqual(item.title, "Open Link in New Tab")
        XCTAssertTrue(menu.items[1] === newWindow, "the new tab item is not before WebKit's new window")

        let action = try XCTUnwrap(item.action)
        NSApp.sendAction(action, to: item.target, from: item)
        XCTAssertEqual(recorder.fired, 1, "WebKit's own item was not sent")
        XCTAssertTrue(controller.nextNewTabIsBackground, "the tab it makes was not marked for the background")
    }

    /// Nothing on the page says a tab opened behind it, so a toast does, and
    /// its one word goes to the tab.
    func testATabOpenedBehindSaysSoAndOffersToShowIt() {
        var shown = 0
        let toast = PageToast.openedInBackground("example.com") { shown += 1 }
        XCTAssertEqual(toast.text, "Opened in a new tab")
        XCTAssertEqual(toast.detail, "example.com")
        XCTAssertEqual(toast.actions.map(\.title), ["Show"])
        toast.actions.first?.run()
        XCTAssertEqual(shown, 1)
    }

    func testALinkOpenedInTheBackgroundLeavesTheFrontTabInFront() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        try await store.seedIfEmpty()
        let session = try await BrowserSession.restored(store: store)
        let front = session.newTab(url: URL(string: "https://example.com/front"))
        session.activateTab(front)
        let controller = try XCTUnwrap(session.controller(for: front))
        let before = Set(session.allTabs(includeArchived: false).map(\.id))

        session.tabController(controller, wantsToOpenInNewTab: URL(string: "https://example.com/next")!, inBackground: true)
        let added = session.allTabs(includeArchived: false).filter { !before.contains($0.id) }
        XCTAssertEqual(added.map(\.url.absoluteString), ["https://example.com/next"])
        XCTAssertEqual(session.activeTabID, front, "a background tab took the front")

        session.tabController(controller, wantsToOpenInNewTab: URL(string: "https://example.com/forward")!, inBackground: false)
        XCTAssertEqual(session.tab(session.activeTabID ?? UUID())?.url.absoluteString, "https://example.com/forward")
    }
}
