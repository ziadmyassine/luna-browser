//
//  TabCommandTests.swift
//  LunaTests
//
//  §20.2: §3.4a's tab menu from the keyboard. Each command is in the table
//  (so Settings ▸ Shortcuts and the Command Bar list it), in the menu bar, and
//  runs the verb the tab menu runs on the front window's tab.
//
//  The app delegate here is a fresh one with a window of its own, never the
//  test host's, and nothing here is put on screen.
//

import AppKit
@testable import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class TabCommandTests: XCTestCase {

    private let domain = Bundle.main.bundleIdentifier ?? "dev.novapps.luna"
    private var snapshot: [String: Any]?
    private var directory: URL!
    private var session: BrowserSession!
    private var delegate: AppDelegate!
    private var window: BrowserWindow!
    private var offscreen: NSWindow?

    private let commands: [BrowserCommand] = [.renameTab, .muteSite, .moveToFolder, .newFolder, .siteSettings]

    override func setUp() async throws {
        snapshot = UserDefaults.standard.persistentDomain(forName: domain)
        directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
        session = try await BrowserSession.restored(store: BrowserStore(path: directory.appending(path: "luna.sqlite")))
        window = BrowserWindow(session: session, controller: BrowserWindowController(remembersFrame: false))
        session.setKeyWindow(window.id)
        delegate = AppDelegate()
        delegate.windows = [window]
        delegate.front = window
    }

    override func tearDown() async throws {
        offscreen?.close()
        window.controller.close()
        session.tearDown()
        UserDefaults.standard.setPersistentDomain(snapshot ?? [:], forName: domain)
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Listed

    func testEachCommandIsInTheTableAndTheCommandBar() {
        for command in commands {
            XCTAssertNotNil(BrowserCommand.command(id: command.id), command.id)
            XCTAssertTrue(command.isCustomisable, "\(command.id) cannot be given a key in Settings")
            XCTAssertNotNil(command.symbolName, "\(command.id) is left out of the Command Bar")
        }
    }

    /// The two that ship with a key are the only owners of it, and the three
    /// that do not are free for the user to give one.
    func testTheShippedKeysCollideWithNothing() throws {
        XCTAssertEqual(BrowserCommand.muteSite.defaults, [KeyBinding("m", .control)])
        XCTAssertEqual(BrowserCommand.newFolder.defaults, [KeyBinding("n", [.command, .option])])
        for command in [BrowserCommand.muteSite, .newFolder] {
            let binding = try XCTUnwrap(command.defaults.first)
            XCTAssertNil(KeyBindings.conflict(for: binding, ignoring: command), "\(command.id) takes a key in use")
        }
        for command in [BrowserCommand.renameTab, .moveToFolder, .siteSettings] {
            XCTAssertTrue(command.defaults.isEmpty, "\(command.id) ships a key with no convention behind it")
        }
    }

    func testTheMenuBarCarriesThem() throws {
        MainMenu.rebuild(in: NSApplication.shared)
        let bar = try XCTUnwrap(NSApp.mainMenu)
        let file = try XCTUnwrap(bar.items.first { $0.title == "File" }?.submenu)
        let view = try XCTUnwrap(bar.items.first { $0.title == "View" }?.submenu)
        for command in [BrowserCommand.renameTab, .muteSite, .moveToFolder, .newFolder] {
            XCTAssertNotNil(file.items.first { $0.action == command.action }, "File has no \(command.title)")
        }
        let site = try XCTUnwrap(view.items.first { $0.action == BrowserCommand.siteSettings.action })
        XCTAssertEqual(site.title, "Site Settings…")
        let mute = try XCTUnwrap(file.items.first { $0.action == BrowserCommand.muteSite.action })
        XCTAssertEqual(mute.keyEquivalent, "m")
        XCTAssertEqual(mute.keyEquivalentModifierMask, .control)
    }

    /// The menu's Pin is `⌘D`, and the Command Bar finds it by that word.
    func testPinIsAddToFavorites() {
        XCTAssertTrue(BrowserCommand.toggleFavorite.keywords.contains("pin tab"))
        XCTAssertTrue(BrowserCommand.toggleFavorite.keywords.contains("unpin tab"))
    }

    // MARK: - Each reaches its verb

    func testMuteSiteMutesTheFrontTabAndSaysWhichWayItGoes() throws {
        let tab = try frontTab()
        let item = NSMenuItem(title: "", action: BrowserCommand.muteSite.action, keyEquivalent: "")
        XCTAssertEqual(delegate.validateTabCommand(item, in: session), true)
        XCTAssertEqual(item.title, "Mute Site")

        delegate.toggleSiteMute(nil)
        XCTAssertTrue(session.isMuted(tab))
        _ = delegate.validateTabCommand(item, in: session)
        XCTAssertEqual(item.title, "Unmute Site")
        delegate.toggleSiteMute(nil)
        XCTAssertFalse(session.isMuted(tab))
    }

    func testNewFolderGathersTheFrontTab() throws {
        let tab = try frontTab()
        delegate.newTabFolder(nil)
        let group = try XCTUnwrap(session.list.tab(tab)?.groupID.flatMap { session.group($0) })
        XCTAssertEqual(group.name, BrowserSession.untitledGroupName)
    }

    /// Move to Folder… pops §3.4a's folder submenu up on its own; its items
    /// move the tab where the tab menu's would.
    func testMoveToFolderOffersEveryFolderAndMovesTheTab() throws {
        let tab = try frontTab()
        let work = try XCTUnwrap(session.createGroup(name: "Work"))
        _ = try XCTUnwrap(session.createGroup(name: "Reading"))
        let menu = try XCTUnwrap(session.folderMenu(forTab: tab))
        let titles = menu.items.filter { !$0.isSeparatorItem }.map(words)
        XCTAssertEqual(titles.first, "New Folder")
        XCTAssertTrue(Set(titles).isSuperset(of: ["Work", "Reading"]), "\(titles)")

        let index = try XCTUnwrap(menu.items.firstIndex { words($0) == "Work" })
        menu.performActionForItem(at: index)
        XCTAssertEqual(session.list.tab(tab)?.groupID, work)
        let again = try XCTUnwrap(session.folderMenu(forTab: tab))
        XCTAssertNotNil(again.items.first { words($0) == "Remove from Folder" })
    }

    /// A tile has no folder to go to, so the command dims.
    func testMoveToFolderDimsForATile() throws {
        let tab = try frontTab()
        XCTAssertTrue(session.pinTab(tab))
        let item = NSMenuItem(title: "", action: BrowserCommand.moveToFolder.action, keyEquivalent: "")
        XCTAssertEqual(delegate.validateTabCommand(item, in: session), false)
        XCTAssertNil(session.folderMenu(forTab: tab))
    }

    /// Rename opens the field on the tab's own row, where the menu's Rename does.
    func testRenameOpensTheRowsOwnField() async throws {
        let tab = try frontTab()
        let sidebar = SidebarViewController(session: session, windowID: window.id)
        let host = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 800), styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        host.contentViewController = sidebar
        sidebar.view.frame = NSRect(x: 0, y: 0, width: 300, height: 800)
        session.notifyChange()
        sidebar.view.layoutSubtreeIfNeeded()
        offscreen = host
        window.sidebar = sidebar

        delegate.renameActiveTab(nil)
        let row = try XCTUnwrap(sidebar.rowView(forTab: tab) as? SidebarRowView)
        XCTAssertFalse(row.editor.isHidden, "Rename Tab… did not open the row's name field")
    }

    /// Site Settings… needs an address bar on screen to stand on; a window
    /// showing none dims it rather than opening a pop-out off its edge.
    func testSiteSettingsDimsWithNoAddressBarOnScreen() throws {
        _ = try frontTab()
        XCTAssertNil(window.siteSettingsOpener())
        let item = NSMenuItem(title: "", action: BrowserCommand.siteSettings.action, keyEquivalent: "")
        XCTAssertEqual(delegate.validateTabCommand(item, in: session), false)
    }

    // MARK: - Fixtures

    /// An item's words without the glyph that rides in front of them
    /// (`SidebarMenu.glyphItem`).
    private func words(_ item: NSMenuItem) -> String {
        item.title.components(separatedBy: "\t").last ?? item.title
    }

    /// A loose tab selected in the window, without waking it.
    private func frontTab() throws -> UUID {
        let space = try XCTUnwrap(session.spaces.first).id
        let tab = Tab(spaceID: space, kind: .today, url: URL(string: "https://example.com/")!, title: "Example", order: 0)
        session.persistAll(session.list.insert(tab))
        session.windowFocus[window.id] = .init(spaceID: space, tabBySpace: [space: tab.id])
        return tab.id
    }
}
