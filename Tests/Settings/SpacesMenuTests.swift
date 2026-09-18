//
//  SpacesMenuTests.swift
//  LunaTests
//
//  Goal 11: the key map after §13.2's rebinding — Spaces on ⌃1…⌃9, ⌘1…⌘9 given
//  to sidebar items, and ⌃⌥←/→ for previous/next Space.
//
//  **These assertions are not paperwork.** Two AppKit behaviours were measured
//  on macOS 26.5 while this was built, and both destroy shortcuts silently:
//  the key-equivalent search stops at the first match and consumes the event
//  there even when that item is disabled, and a ⌘-number that duplicates one
//  already in the menu bar is *erased* from the later item — mask intact, key
//  gone, no error at build time or run time. Nothing but a test sees either.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class SpacesMenuTests: XCTestCase {

    private var previous: NSMenu?

    override func setUp() {
        super.setUp()
        previous = NSApplication.shared.mainMenu
        MainMenu.install(into: NSApplication.shared)
    }

    override func tearDown() {
        NSApplication.shared.mainMenu = previous
        super.tearDown()
    }

    // MARK: - §13.2: Spaces leave ⌘-number

    /// D-S12. ⌘-number means "go to tab N" in Safari, Chrome, Firefox, Edge and
    /// Arc; Arc puts Spaces on ⌃-number, Dia on Ctrl-number, Vivaldi on
    /// ⌘⇧-number. If this fails, Luna has taken the namespace back.
    func testNoSpaceItemClaimsACommandNumber() throws {
        MainMenu.setSpaces(["Personal", "Work", "Research"], in: NSApplication.shared)
        let spaces = Self.items(withAction: #selector(AppDelegate.switchToSpace(_:)))
        XCTAssertEqual(spaces.count, 3)
        for (index, item) in spaces.enumerated() {
            XCTAssertEqual(item.keyEquivalent, String(index + 1))
            XCTAssertEqual(item.keyEquivalentModifierMask, .control, "Space \(index + 1) is still on ⌘-number")
            XCTAssertFalse(item.keyEquivalentModifierMask.contains(.command))
            XCTAssertEqual(item.tag, index)
        }
    }

    /// A tenth Space is listed and clickable, just without a shortcut — which
    /// is what every other browser does too.
    func testATenthSpaceIsListedWithoutAShortcut() {
        MainMenu.setSpaces((1...10).map { "Space \($0)" }, in: NSApplication.shared)
        let spaces = Self.items(withAction: #selector(AppDelegate.switchToSpace(_:)))
        XCTAssertEqual(spaces.count, 10)
        XCTAssertEqual(spaces[9].keyEquivalent, "")
    }

    /// The other half of D-S12: ⌘1…⌘9 now exists at all, which it never did.
    func testSidebarItemsClaimCommandNumber() {
        MainMenu.setSidebarItems(["Inbox", "Calendar", "Docs"], in: NSApplication.shared)
        let items = Self.items(withAction: #selector(AppDelegate.goToSidebarItem(_:)))
        XCTAssertEqual(items.count, 9, "the nine are built once and only renamed")
        XCTAssertEqual(items.prefix(3).map(\.title), ["Inbox", "Calendar", "Docs"])
        XCTAssertEqual(items.filter { !$0.isHidden }.count, 3)
        for (index, item) in items.enumerated() {
            XCTAssertEqual(item.keyEquivalent, String(index + 1))
            XCTAssertEqual(item.keyEquivalentModifierMask, .command)
            XCTAssertEqual(item.tag, index)
        }
    }

    func testOnlyNineSidebarItemsGetAShortcut() {
        MainMenu.setSidebarItems((1...20).map { "Tab \($0)" }, in: NSApplication.shared)
        let items = Self.items(withAction: #selector(AppDelegate.goToSidebarItem(_:)))
        XCTAssertEqual(items.count, 9)
        XCTAssertEqual(items.filter { !$0.isHidden }.count, 9)
        XCTAssertEqual(items.last?.title, "Tab 9")
    }

    /// **The regression that cost this wave an hour.** An item carrying a
    /// ⌘-number loses its key equivalent on the way into a menu bar that is
    /// already live — measured inside the running app: `"1"` on the line before
    /// `NSMenu.addItem`, `""` on the line after, mask intact, no error. So the
    /// nine are built during `install` and only ever renamed. If this fails,
    /// somebody has gone back to growing the menu to fit the tab count and
    /// every one of the nine shortcuts is silently gone.
    func testRefillingNeverRecreatesTheItems() {
        MainMenu.setSidebarItems(["Inbox"], in: NSApplication.shared)
        let first = Self.items(withAction: #selector(AppDelegate.goToSidebarItem(_:)))
        MainMenu.setSidebarItems(["A", "B", "C"], in: NSApplication.shared)
        let second = Self.items(withAction: #selector(AppDelegate.goToSidebarItem(_:)))
        XCTAssertEqual(first.count, second.count)
        for (lhs, rhs) in zip(first, second) {
            XCTAssertTrue(lhs === rhs, "the items were rebuilt; their ⌘-numbers are gone")
        }
        XCTAssertEqual(second.map(\.keyEquivalent), (1...9).map(String.init))
    }

    /// An untitled tab still has to be pickable — a blank menu item is not.
    func testAnUntitledTabIsStillNamed() {
        MainMenu.setSidebarItems([""], in: NSApplication.shared)
        let items = Self.items(withAction: #selector(AppDelegate.goToSidebarItem(_:)))
        XCTAssertEqual(items.first?.title, "Untitled")
        XCTAssertEqual(items.first?.isHidden, false)
        XCTAssertEqual(items.dropFirst().allSatisfy(\.isHidden), true)
    }

    // MARK: - The shadowing rule, asserted rather than trusted

    /// **Sidebar Items must come before Settings in menu-bar order.** Probed
    /// on macOS 26.5: the earlier match wins ⌘1 outright and the loser never
    /// runs. The Settings section items are nil-targeted, so if they came first
    /// ⌘1 would be dead in the browser window — no crash, no warning, just a
    /// key that does nothing.
    func testSidebarItemsOutranksSettings() throws {
        let titles = try XCTUnwrap(NSApplication.shared.mainMenu).items.map(\.title)
        XCTAssertLessThan(try XCTUnwrap(titles.firstIndex(of: "View")),
                          try XCTUnwrap(titles.firstIndex(of: "Window")))
    }

    /// **The regression this file exists for.** `install` hands the Window menu
    /// to AppKit as `NSApplication.windowsMenu`; AppKit then owns it, and an
    /// item added to it *after* that assignment comes back with its
    /// `keyEquivalent` silently cleared — modifier mask intact, key gone.
    /// Measured here: Sidebar Items lived under Window for one build and all
    /// nine shortcuts were erased at runtime while the code that set them read
    /// perfectly. Nothing but a test catches that.
    func testSidebarItemsIsNotInsideTheManagedWindowsMenu() throws {
        let window = try XCTUnwrap(NSApplication.shared.mainMenu?.items.first { $0.title == "Window" }?.submenu)
        XCTAssertTrue(NSApplication.shared.windowsMenu === window, "the Window menu is AppKit-managed")
        XCTAssertNil(window.items.first { $0.submenu?.title == "Sidebar Items" })
        let view = try XCTUnwrap(NSApplication.shared.mainMenu?.items.first { $0.title == "View" }?.submenu)
        XCTAssertNotNil(view.items.first { $0.submenu?.title == "Sidebar Items" })
    }

    /// The Spaces menu is built before the Window menu, so if a Space ever
    /// reclaimed ⌘-number it would shadow both Sidebar Items and Settings.
    func testTheSpacesMenuComesBeforeTheWindowMenu() throws {
        let titles = try XCTUnwrap(NSApplication.shared.mainMenu).items.map(\.title)
        let spaces = try XCTUnwrap(titles.firstIndex(of: "Spaces"))
        let window = try XCTUnwrap(titles.firstIndex(of: "Window"))
        XCTAssertLessThan(spaces, window)
    }

    /// **Exactly one family may claim ⌘-number, and AppKit enforces that more
    /// harshly than the first-match rule suggests.** Measured on macOS 26.5 in
    /// the running app: a ⌘-number duplicating one already in the bar is
    /// *erased* — the earlier item in menu-bar order keeps the key, the later
    /// one comes back with `keyEquivalent == ""`, mask intact, no error. So a
    /// second claimant does not shadow Sidebar Items, it silently loses its own
    /// shortcut, and the menu then prints a shortcut it does not have.
    ///
    /// This is also why Window ▸ Settings no longer declares ⌘1…⌘9: AppKit was
    /// already deleting them. The Settings window still gets all nine, through
    /// `goToSidebarItem(_:)`'s forwarding.
    func testOnlyOneFamilyClaimsCommandNumber() {
        MainMenu.setSpaces(["Personal", "Work"], in: NSApplication.shared)
        MainMenu.setSidebarItems(["Inbox", "Calendar"], in: NSApplication.shared)
        let claimants = Self.leaves().filter {
            $0.keyEquivalentModifierMask == .command && ("1"..."9").contains($0.keyEquivalent)
        }
        XCTAssertEqual(Set(claimants.compactMap(\.action)), [#selector(AppDelegate.goToSidebarItem(_:))])
        XCTAssertEqual(claimants.count, 9)
    }

    /// The Settings sections stay clickable and stay tagged — only the printed
    /// shortcut is gone, because it was never real.
    func testSettingsSectionsAreStillReachableWithoutAShortcut() {
        let sections = Self.items(withAction: #selector(SettingsWindowController.goToSettingsSection(_:)))
        XCTAssertEqual(sections.count, SettingsSectionRegistry.all.count)
        XCTAssertEqual(sections.map(\.tag), Array(sections.indices))
        XCTAssertTrue(sections.allSatisfy { $0.keyEquivalent.isEmpty })
        XCTAssertTrue(sections.allSatisfy { $0.target == nil }, "they must reach the window by the responder chain")
    }

    // MARK: - Previous / next

    /// §13.2 asks for `⌘⌥←/→` here. It is already Show Previous/Next Tab
    /// (§7.4, and `TODO.md` §20.1 lists it under tabs in the same line that
    /// gives Spaces ⌃-number), so the spec contradicts itself and the shipped
    /// binding wins. Spaces get the ⌘→⌃ translation, which keeps every Space
    /// command under one modifier. **If this test is changed, the tab bindings
    /// below must move in the same commit** — the two pairs cannot both be
    /// ⌘⌥-arrow, and the Spaces menu is searched first, so Spaces would win and
    /// tab switching would silently die.
    func testSpaceAndTabArrowsDoNotCollide() throws {
        MainMenu.setSpaces(["Personal", "Work"], in: NSApplication.shared)
        let left = String(UnicodeScalar(UInt32(NSLeftArrowFunctionKey))!)
        let right = String(UnicodeScalar(UInt32(NSRightArrowFunctionKey))!)

        let previousSpace = try XCTUnwrap(Self.items(withAction: #selector(AppDelegate.previousSpace(_:))).first)
        let nextSpace = try XCTUnwrap(Self.items(withAction: #selector(AppDelegate.nextSpace(_:))).first)
        XCTAssertEqual(previousSpace.keyEquivalent, left)
        XCTAssertEqual(nextSpace.keyEquivalent, right)
        XCTAssertEqual(previousSpace.keyEquivalentModifierMask, [.control, .option])
        XCTAssertEqual(nextSpace.keyEquivalentModifierMask, [.control, .option])

        let previousTab = try XCTUnwrap(Self.items(withAction: #selector(AppDelegate.previousTab(_:))).first)
        let nextTab = try XCTUnwrap(Self.items(withAction: #selector(AppDelegate.nextTab(_:))).first)
        XCTAssertEqual(previousTab.keyEquivalentModifierMask, [.command, .option])
        XCTAssertEqual(nextTab.keyEquivalentModifierMask, [.command, .option])
    }

    /// §20.1's `⌘D`. Favorites are capped at twelve per profile, so this is the
    /// one command that can be refused rather than merely dimmed.
    func testFavoritesHasAShortcut() throws {
        let item = try XCTUnwrap(Self.items(withAction: #selector(AppDelegate.toggleFavorite(_:))).first)
        XCTAssertEqual(item.keyEquivalent, "d")
        XCTAssertEqual(item.keyEquivalentModifierMask, .command)
    }

    /// §22.5: no `NSEvent` monitor anywhere, so a command that is not a menu
    /// item does not exist. Every new selector in this wave is in the bar.
    func testEveryNewCommandIsAMenuItem() {
        MainMenu.setSpaces(["Personal"], in: NSApplication.shared)
        MainMenu.setSidebarItems(["Inbox"], in: NSApplication.shared)
        let actions = Set(Self.leaves().compactMap(\.action))
        for selector: Selector in [
            #selector(AppDelegate.switchToSpace(_:)),
            #selector(AppDelegate.previousSpace(_:)),
            #selector(AppDelegate.nextSpace(_:)),
            #selector(AppDelegate.goToSidebarItem(_:)),
            #selector(AppDelegate.toggleFavorite(_:))
        ] {
            XCTAssertTrue(actions.contains(selector), "\(selector) is not reachable from the menu bar")
        }
    }

    /// The Shortcuts section reads the live bar rather than a second copy of
    /// the map, so the rebinding has to show up there with no edit at all.
    func testTheShortcutsSectionShowsTheNewBindings() throws {
        MainMenu.setSpaces(["Personal", "Work"], in: NSApplication.shared)
        let commands = ShortcutsSection.commands(in: try XCTUnwrap(NSApplication.shared.mainMenu))
        XCTAssertEqual(commands.first { $0.title == "Personal" }?.key, "⌃1")
        XCTAssertEqual(commands.first { $0.title == "Next Space" }?.key, "⌃⌥→")
        XCTAssertEqual(commands.first { $0.title == "Show Next Tab" }?.key, "⌥⌘→")
    }

    // MARK: - Reading the bar

    private static func leaves() -> [NSMenuItem] {
        guard let main = NSApplication.shared.mainMenu else { return [] }
        return main.items.compactMap(\.submenu).flatMap(leaves(of:))
    }

    private static func leaves(of menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item -> [NSMenuItem] in
            if let submenu = item.submenu { return leaves(of: submenu) }
            return item.isSeparatorItem ? [] : [item]
        }
    }

    private static func items(withAction action: Selector) -> [NSMenuItem] {
        leaves().filter { $0.action == action }
    }
}
