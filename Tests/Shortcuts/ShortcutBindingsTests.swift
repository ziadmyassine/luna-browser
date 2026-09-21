//
//  ShortcutBindingsTests.swift
//  LunaTests
//
//  §3.6's store and the menu it drives: overrides, conflicts, and the invariant
//  that Luna does not ship two commands on one keystroke.
//
//  Every test that writes a binding puts the whole stored domain back. The
//  test host is the real app (`AppDelegate`'s `databaseURL` comment has the
//  full story), so an override left behind here is an override on the
//  developer's own copy of Luna.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class ShortcutBindingsTests: XCTestCase {

    private let domain = Bundle.main.bundleIdentifier ?? "dk.novapps.luna"
    private var snapshot: [String: Any]?

    override func setUp() {
        super.setUp()
        snapshot = UserDefaults.standard.persistentDomain(forName: domain)
    }

    override func tearDown() {
        UserDefaults.standard.setPersistentDomain(snapshot ?? [:], forName: domain)
        super.tearDown()
    }

    // MARK: - What Luna ships

    /// The invariant a table makes checkable and a pile of literals did not:
    /// no keystroke appears twice. Two menu items on one key equivalent is
    /// not an error AppKit reports — it picks the earlier one in menu-bar order
    /// and the other command silently stops working.
    ///
    /// Alternates are in the sweep, because a hidden item's key equivalent is
    /// just as live as a visible one's.
    func testNoTwoShippedCommandsWantTheSameKeystroke() {
        var owner: [KeyBinding: String] = [:]
        for command in BrowserCommand.all {
            for binding in command.defaults {
                if let taken = owner[binding] {
                    XCTFail("\(command.id) and \(taken) both ship \(binding.display)")
                }
                owner[binding] = command.id
            }
        }
    }

    /// `⌘1…⌘9` belongs to the sidebar rows and `⌃1…⌃9` to the Spaces, both
    /// built from the live session rather than from the table — so a shipped
    /// command that landed on one would lose, and lose silently.
    func testNoShippedCommandLandsOnANumberedFamily() {
        for command in BrowserCommand.all {
            for binding in command.defaults where binding.key.count == 1 {
                guard let digit = Int(binding.key), (1...9).contains(digit) else { continue }
                XCTAssertFalse(
                    binding.modifiers == .command || binding.modifiers == .control,
                    "\(command.id) ships \(binding.display), which the numbered menus already own"
                )
            }
        }
    }

    /// The commands this wave added, each with the keystroke it was asked for.
    func testTheNewCommandsShipTheKeystrokesTheyWereGiven() {
        let expected: [(BrowserCommand, String)] = [
            (.forceReloadPage, "⇧⌘R"), (.closeAllTabs, "⇧⌘K"), (.cleanUpTabs, "⌥⌘K"),
            (.copyURL, "⇧⌘C"), (.copyMarkdown, "⌥⇧⌘C"), (.showHistory, "⌘Y"),
            (.zoomIn, "⌘+"), (.zoomOut, "⌘-"), (.actualSize, "⌘0"), (.closeWindow, "⇧⌘W")
        ]
        for (command, printed) in expected {
            XCTAssertEqual(KeyBindings.primary(for: command)?.display, printed, command.id)
        }
    }

    // MARK: - Overrides

    /// Three states, not two. An absent key means "whatever ships"; a user who
    /// deliberately took a shortcut away has to be told apart from one who never
    /// touched it, or the default comes back on the next launch.
    func testClearingAShortcutIsDifferentFromNeverChoosingOne() {
        XCTAssertFalse(KeyBindings.isCustomised(.newTab))
        XCTAssertEqual(KeyBindings.primary(for: .newTab)?.display, "⌘T")

        KeyBindings.set(nil, for: .newTab)
        XCTAssertTrue(KeyBindings.isCustomised(.newTab))
        XCTAssertNil(KeyBindings.primary(for: .newTab))

        KeyBindings.reset(.newTab)
        XCTAssertFalse(KeyBindings.isCustomised(.newTab))
        XCTAssertEqual(KeyBindings.primary(for: .newTab)?.display, "⌘T")
    }

    /// An override replaces the whole list. Show Next Tab ships answering
    /// to two keystrokes; a user who moves it is not left with our second one
    /// still live and nothing in the UI saying so.
    func testAnOverrideReplacesTheAlternatesToo() {
        XCTAssertEqual(KeyBindings.bindings(for: .nextTab).count, 2)
        KeyBindings.set(KeyBinding("n", [.control, .command]), for: .nextTab)
        XCTAssertEqual(KeyBindings.bindings(for: .nextTab), [KeyBinding("n", [.control, .command])])
    }

    /// ⌘Q, ⌘X and ⌘M are macOS's, not Luna's.
    func testACommandMacOSOwnsCannotBeMoved() {
        KeyBindings.set(KeyBinding("j", .command), for: .cut)
        XCTAssertEqual(KeyBindings.primary(for: .cut)?.display, "⌘X")
        XCTAssertFalse(KeyBindings.isCustomised(.cut))
    }

    func testResetAllPutsEveryOverrideBack() {
        KeyBindings.set(KeyBinding("j", .command), for: .newTab)
        KeyBindings.set(nil, for: .closeTab)
        XCTAssertTrue(KeyBindings.hasAnyCustomisation)

        KeyBindings.resetAll()
        XCTAssertFalse(KeyBindings.hasAnyCustomisation)
        XCTAssertEqual(KeyBindings.primary(for: .newTab)?.display, "⌘T")
        XCTAssertEqual(KeyBindings.primary(for: .closeTab)?.display, "⌘W")
    }

    // MARK: - Conflicts

    func testAKeystrokeAnotherCommandHasIsRefusedByName() throws {
        let clash = try XCTUnwrap(KeyBindings.conflict(for: KeyBinding("t"), ignoring: .closeTab))
        guard case let .command(owner) = clash else { return XCTFail("expected a command, got \(clash)") }
        XCTAssertEqual(owner.id, BrowserCommand.newTab.id)
    }

    /// The one a per-command check would miss: ⇧⌘] is printed nowhere, because
    /// it is Show Next Tab's second binding.
    func testAnAlternateBindingIsAConflictToo() {
        let alternate = KeyBinding("]", [.command, .shift])
        XCTAssertNotNil(KeyBindings.conflict(for: alternate, ignoring: .newTab))
    }

    func testACommandIsNeverInConflictWithItself() {
        XCTAssertNil(KeyBindings.conflict(for: KeyBinding("t"), ignoring: .newTab))
    }

    /// The numbered families have no row in the table to collide with and are
    /// taken all the same.
    func testTheNumberedFamiliesAreRefusedWithAReason() throws {
        let sidebar = try XCTUnwrap(KeyBindings.conflict(for: KeyBinding("3"), ignoring: .newTab))
        guard case .reserved = sidebar else { return XCTFail("⌘3 should be reserved") }
        let space = try XCTUnwrap(KeyBindings.conflict(for: KeyBinding("1", .control), ignoring: .newTab))
        guard case .reserved = space else { return XCTFail("⌃1 should be reserved") }
    }

    /// The sidebar rows start at one, so ⌘0 is not in the reserved range — it
    /// is merely taken, by the command that is asking.
    func testZeroIsNotReserved() {
        XCTAssertNil(KeyBindings.conflict(for: KeyBinding("0"), ignoring: .actualSize))
    }

    /// ⇧⌘3 and ⇧⌘4 are screenshots, not sidebar rows — the reserved range is
    /// the exact modifier, not "any number".
    func testANumberWithOtherModifiersIsNotReserved() {
        XCTAssertNil(KeyBindings.conflict(for: KeyBinding("5", [.command, .option]), ignoring: .newTab))
    }
}

@MainActor
final class MainMenuBindingTests: XCTestCase {

    private let domain = Bundle.main.bundleIdentifier ?? "dk.novapps.luna"
    private var snapshot: [String: Any]?

    override func setUp() {
        super.setUp()
        snapshot = UserDefaults.standard.persistentDomain(forName: domain)
    }

    override func tearDown() {
        UserDefaults.standard.setPersistentDomain(snapshot ?? [:], forName: domain)
        super.tearDown()
    }

    /// ⌘= is the keystroke the hand performs for ⌘+, and it reaches the command
    /// as a hidden second item rather than as a second row in every menu.
    func testAnAlternateBindingBecomesAHiddenItem() throws {
        let items = MainMenu.items(.zoomIn)
        XCTAssertEqual(items.count, 2)
        XCTAssertFalse(items[0].isHidden)
        XCTAssertEqual(items[0].keyEquivalent, "+")
        XCTAssertTrue(items[1].isHidden, "the alternate must not print a second Zoom In")
        XCTAssertEqual(items[1].keyEquivalent, "=")
        XCTAssertEqual(items[1].action, items[0].action)
    }

    func testTheMenuItemWearsTheUsersKeystroke() {
        KeyBindings.set(KeyBinding("j", [.command, .option]), for: .newTab)
        let item = MainMenu.item(.newTab)
        XCTAssertEqual(item.keyEquivalent, "j")
        XCTAssertTrue(item.keyEquivalentModifierMask.contains(.option))
        XCTAssertEqual(MainMenu.items(.newTab).count, 1, "an override drops the alternates")
    }

    /// A cleared shortcut leaves the item clickable and unbound, rather than
    /// leaving it wearing the default it was moved off.
    func testAClearedShortcutLeavesTheItemInTheMenu() {
        KeyBindings.set(nil, for: .reloadPage)
        let item = MainMenu.item(.reloadPage)
        XCTAssertEqual(item.keyEquivalent, "")
        XCTAssertEqual(item.title, BrowserCommand.reloadPage.title)
        XCTAssertNotNil(item.action)
    }

    /// The rebuild path §3.6 uses. The numbered families come back empty by
    /// design — `AppDelegate.render()` refills them — but the nine `⌘1…⌘9`
    /// placeholders have to survive, because a live menu bar will not accept
    /// them afterwards (see `MainMenu.setSidebarItems`).
    func testRebuildingTheBarKeepsTheNumberedPlaceholders() throws {
        MainMenu.rebuild(in: NSApplication.shared)
        let view = try XCTUnwrap(NSApp.mainMenu?.items.first { $0.title == "View" }?.submenu)
        let rows = try XCTUnwrap(view.items.first { $0.submenu?.items.count == 9 }?.submenu)
        XCTAssertEqual(rows.items.map(\.keyEquivalent), (1...9).map(String.init))
        XCTAssertTrue(rows.items.allSatisfy { $0.keyEquivalentModifierMask == .command })
    }

    /// §3.6's table is built by walking the live bar, so a command that is in
    /// the table and not in a menu is a shortcut nobody can find or change.
    func testEveryCustomisableCommandIsInTheMenuBar() throws {
        MainMenu.rebuild(in: NSApplication.shared)
        // Previous/Next Space are built by `setSpaces`, not by `install` — the
        // Spaces menu is session data and a rebuilt bar starts it empty. This
        // is the pairing `AppDelegate.shortcutsDidChange` performs, and the
        // reason it calls `render()` straight after rebuilding.
        MainMenu.setSpaces(["Personal", "Work"], in: NSApplication.shared)
        let listed = Set(ShortcutsSection.commands(in: try XCTUnwrap(NSApp.mainMenu)).map(\.title))
        for command in BrowserCommand.all where command.isCustomisable {
            XCTAssertTrue(listed.contains(command.title), "\(command.id) is not in any menu")
        }
    }

    /// Hidden alternates must not show up as a second row for the same command.
    func testTheTableListsEachCommandOnce() throws {
        MainMenu.rebuild(in: NSApplication.shared)
        let rows = ShortcutsSection.commands(in: try XCTUnwrap(NSApp.mainMenu))
        let zoomIn = rows.filter { $0.title == BrowserCommand.zoomIn.title }
        XCTAssertEqual(zoomIn.count, 1)
        XCTAssertEqual(zoomIn.first?.key, "⌘+")
    }

    // MARK: - Which rows can be changed

    /// The row carries its own answer, so the pane cannot draw a recorder on a
    /// shortcut nothing can rebind.
    func testARowSaysWhetherItIsTheUsersToChange() throws {
        MainMenu.rebuild(in: NSApplication.shared)
        let rows = ShortcutsSection.commands(in: try XCTUnwrap(NSApp.mainMenu))
        let newTab = try XCTUnwrap(rows.first { $0.title == BrowserCommand.newTab.title })
        XCTAssertEqual(newTab.editableID, BrowserCommand.newTab.id)
        XCTAssertNil(newTab.fixedReason, "an editable row explains nothing; the box says it")

        let quit = try XCTUnwrap(rows.first { $0.key == "⌘Q" })
        XCTAssertNil(quit.editableID)
    }

    /// A command in the table that macOS owns the keystroke for — `⌘Z` and its
    /// neighbours — is listed and fixed, not listed and quietly editable.
    func testACommandMacOSOwnsIsListedAsFixed() throws {
        MainMenu.rebuild(in: NSApplication.shared)
        let rows = ShortcutsSection.commands(in: try XCTUnwrap(NSApp.mainMenu))
        let undo = try XCTUnwrap(rows.first { $0.title == BrowserCommand.undo.title })
        XCTAssertNil(undo.editableID)
    }

    /// "macOS owns it" would be a lie about `⌘1…⌘9`: they are Luna's, they are
    /// just built per session rather than from the table. A user told the wrong
    /// reason goes looking for a setting that cannot exist.
    func testTheNumberedFamiliesSayWhyTheyCannotMove() throws {
        MainMenu.rebuild(in: NSApplication.shared)
        MainMenu.setSidebarItems(["Inbox"], in: NSApplication.shared)
        MainMenu.setSpaces(["Personal", "Work"], in: NSApplication.shared)
        let rows = ShortcutsSection.commands(in: try XCTUnwrap(NSApp.mainMenu))
        XCTAssertEqual(rows.first { $0.key == "⌘1" }?.fixedReason, "Numbered from your sidebar")
        XCTAssertEqual(rows.first { $0.key == "⌃1" }?.fixedReason, "Numbered from your Spaces")
        XCTAssertTrue(rows.filter { $0.key == "⌘1" || $0.key == "⌃1" }.allSatisfy { $0.editableID == nil })
    }

    /// Only the numbered families carry a caption. Every other fixed row
    /// says so by being printed flat; the same sentence repeated down the app,
    /// Edit and Window menus was noise nobody reads past the third time.
    func testNoOtherFixedRowCarriesACaption() throws {
        MainMenu.rebuild(in: NSApplication.shared)
        MainMenu.setSidebarItems(["Inbox"], in: NSApplication.shared)
        MainMenu.setSpaces(["Personal", "Work"], in: NSApplication.shared)
        let captioned = ShortcutsSection.commands(in: try XCTUnwrap(NSApp.mainMenu))
            .filter { $0.fixedReason != nil }
        XCTAssertFalse(captioned.isEmpty, "the premise: the numbered rows do carry one")
        let numbered = ["Numbered from your sidebar", "Numbered from your Spaces"]
        XCTAssertTrue(
            captioned.allSatisfy { numbered.contains($0.fixedReason ?? "") },
            "\(captioned.map { ($0.title, $0.fixedReason) })"
        )
    }
}
