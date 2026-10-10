//
//  FindCommandTests.swift
//  LunaTests
//
//  §18.1's Edit ▸ Find menu, and ⌘F's two meanings: find in a browser
//  window, the search field in the Settings window. One menu item owns the
//  key and the window that is key decides what it does.
//
//  Every test that rebuilds the menu bar puts the stored shortcuts back; the
//  test host is the real app.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class FindCommandTests: XCTestCase {

    private let domain = Bundle.main.bundleIdentifier ?? "dev.novapps.luna"
    private var snapshot: [String: Any]?

    override func setUp() {
        super.setUp()
        snapshot = UserDefaults.standard.persistentDomain(forName: domain)
    }

    override func tearDown() {
        UserDefaults.standard.setPersistentDomain(snapshot ?? [:], forName: domain)
        super.tearDown()
    }

    func testEditHasTheFindMenuWithTheMacsKeys() throws {
        MainMenu.rebuild(in: NSApplication.shared)
        let edit = try XCTUnwrap(NSApp.mainMenu?.items.first { $0.title == "Edit" }?.submenu)
        let find = try XCTUnwrap(edit.items.first { $0.title == "Find" }?.submenu, "Edit has no Find submenu")
        let items = find.items.filter { !$0.isSeparatorItem }
        XCTAssertEqual(items.map(\.title), ["Find…", "Find Next", "Find Previous", "Use Selection for Find"])
        // ⌘E is Show Agent's; Use Selection for Find keeps its item, with no key.
        XCTAssertEqual(items.map(\.keyEquivalent), ["f", "g", "g", ""])
        XCTAssertEqual(items.prefix(3).map(\.keyEquivalentModifierMask), [.command, .command, [.command, .shift]])
        XCTAssertEqual(items.map(\.action), [
            #selector(AppDelegate.findInPage(_:)), #selector(AppDelegate.findNextInPage(_:)),
            #selector(AppDelegate.findPreviousInPage(_:)), #selector(AppDelegate.useSelectionForFind(_:))
        ])
    }

    /// AppKit stops at the first item carrying a key equivalent, so two items
    /// on ⌘F would leave the later one dead without a word. Find… is the one.
    func testExactlyOneItemInTheBarCarriesCommandF() throws {
        MainMenu.rebuild(in: NSApplication.shared)
        let bar = try XCTUnwrap(NSApp.mainMenu)
        let owners = leaves(of: bar).filter { $0.keyEquivalent == "f" && $0.keyEquivalentModifierMask == .command }
        XCTAssertEqual(owners.map(\.title), ["Find…"])
        // Search Settings stays in the menu, with no key of its own.
        let search = leaves(of: bar).first { $0.action == #selector(SettingsWindowController.focusSettingsSearch(_:)) }
        XCTAssertEqual(search?.keyEquivalent, "")
    }

    func testCommandFBelongsToFindInTheShortcutsTable() throws {
        let owner = try XCTUnwrap(KeyBindings.conflict(for: KeyBinding("f"), ignoring: .newTab))
        guard case let .command(command) = owner else { return XCTFail("⌘F should be a command's, not reserved") }
        XCTAssertEqual(command.id, BrowserCommand.find.id)
        XCTAssertTrue(BrowserCommand.searchSettings.defaults.isEmpty)
    }

    /// The Mac's own find keys, so they are listed and fixed like Cut and Copy.
    func testTheFindKeysAreFixed() {
        for command in [BrowserCommand.find, .findNext, .findPrevious, .useSelectionForFind] {
            XCTAssertFalse(command.isCustomisable, command.id)
            KeyBindings.set(KeyBinding("j", [.command, .option]), for: command)
            XCTAssertFalse(KeyBindings.isCustomised(command), "\(command.id) took a new key")
        }
    }

    /// While Settings is key, ⌘F is answered by the window before it reaches
    /// the app delegate, and what it does there is focus the search.
    func testTheSettingsWindowAnswersFindWithItsSearch() throws {
        let controller = SettingsWindowController()
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        window.makeFirstResponder(nil)
        XCTAssertTrue(window.tryToPerform(#selector(AppDelegate.findInPage(_:)), with: nil), "the window let ⌘F through")
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView, "nothing took the keyboard")
        let field = editor.delegate as? NSTextField
        XCTAssertTrue(field?.superview is SettingsSearchField, "⌘F focused something other than the search field")
    }

    /// Find… is in the Command Bar as well; its three companions are keys for
    /// a field that is already open, and not rows to choose.
    func testOnlyFindIsOfferedInTheCommandBar() {
        XCTAssertNotNil(BrowserCommand.find.symbolName)
        XCTAssertNil(BrowserCommand.findNext.symbolName)
        XCTAssertNil(BrowserCommand.findPrevious.symbolName)
        XCTAssertNil(BrowserCommand.useSelectionForFind.symbolName)
    }

    private func leaves(of menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item in item.submenu.map(leaves(of:)) ?? [item] }
    }
}
