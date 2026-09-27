//
//  TabsOnOtherMacsMenuTests.swift
//  LunaTests
//
//  History ▸ Tabs on Other Macs (docs/SYNC-PLAN.md §5, S12): one section per
//  Mac, and a click opens the tab here. Which Macs are listed is decided in
//  BrowserKit (`DevicePresenceTests`); this is the menu half.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class TabsOnOtherMacsMenuTests: XCTestCase {

    private var previous: NSMenu?
    private var directory: URL!

    override func setUp() {
        super.setUp()
        previous = NSApplication.shared.mainMenu
        directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
        MainMenu.install(into: NSApplication.shared)
    }

    override func tearDown() {
        MainMenu.setOtherMacs([], in: NSApplication.shared)
        NSApplication.shared.mainMenu = previous
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func tab(_ url: String, _ title: String) -> SyncDevice.OpenTab {
        SyncDevice.OpenTab(spaceID: UUID(), url: URL(string: url)!, title: title)
    }

    private func submenu() throws -> NSMenu {
        let history = try XCTUnwrap(NSApplication.shared.mainMenu?.items.first { $0.title == "History" }?.submenu)
        return try XCTUnwrap(history.items.first { $0.title == "Tabs on Other Macs" }?.submenu)
    }

    func testListsEachMacWithItsTabs() throws {
        MainMenu.setOtherMacs([
            SyncDevice(id: UUID(), name: "Laptop", tabs: [tab("https://a.example/", "A"), tab("https://b.example/", "")]),
            SyncDevice(id: UUID(), name: "Studio", tabs: [tab("https://c.example/", "C")])
        ], in: NSApplication.shared)

        let items = try submenu().items
        XCTAssertEqual(items.filter(\.isSectionHeader).map(\.title), ["Laptop", "Studio"])
        let tabs = items.filter { $0.action == #selector(AppDelegate.openTabFromOtherMac(_:)) }
        XCTAssertEqual(tabs.map(\.title), ["A", "b.example", "C"], "an untitled tab shows its host")
        XCTAssertEqual(tabs.compactMap { $0.representedObject as? URL }.map(\.absoluteString),
                       ["https://a.example/", "https://b.example/", "https://c.example/"])
    }

    func testSaysSoWhenThereAreNoOtherMacs() throws {
        MainMenu.setOtherMacs([], in: NSApplication.shared)

        let items = try submenu().items
        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items.first?.action)
    }

    /// Rebinding rebuilds the bar; the Macs already listed come back with it.
    func testSurvivesARebuild() throws {
        MainMenu.setOtherMacs([SyncDevice(id: UUID(), name: "Laptop", tabs: [tab("https://a.example/", "A")])],
                              in: NSApplication.shared)
        MainMenu.rebuild(in: NSApplication.shared)

        XCTAssertEqual(try submenu().items.filter(\.isSectionHeader).map(\.title), ["Laptop"])
    }

    func testClickingATabOpensItHere() async throws {
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        try await store.seedIfEmpty()
        let session = try await BrowserSession.restored(store: store)
        MainMenu.setOtherMacs([SyncDevice(id: UUID(), name: "Laptop", tabs: [tab("https://a.example/", "A")])],
                              in: NSApplication.shared)
        let item = try XCTUnwrap(try submenu().items.first { $0.title == "A" })

        AppDelegate.openTab(fromOtherMac: item, in: session)

        let opened = try XCTUnwrap(session.tabs.first { $0.url.absoluteString == "https://a.example/" })
        XCTAssertEqual(session.activeTabID, opened.id)
        session.tearDown()
    }
}
