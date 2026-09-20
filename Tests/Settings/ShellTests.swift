//
//  ShellTests.swift
//  LunaTests
//
//  The Settings shell: the §6 key table, §2's search rule and section list,
//  §4's disabled-row contract, §1's window floor, and §2's menu commands.
//
//  The point of every test here is that it fails on a *regression* rather than
//  restating a number: `testEverySectionSymbolResolves` asks the SDK whether the
//  nine SF Symbols exist, and `testRestoreAllReachesEveryKeyInTheTable` proves
//  the §3.9 button is a loop over `keys` rather than a list someone will forget.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class SettingsDefaultsTests: XCTestCase {

    private let domain = Bundle.main.bundleIdentifier ?? "dk.novapps.luna"

    /// §6's table is the one place a key is declared, so a key that is not in
    /// `keys` does not get restored — and the spelling of the three existing
    /// keys is load-bearing, because renaming one silently orphans the value
    /// the user already has.
    func testKeysCarryEverySettingSpecSixDeclares() {
        let keys = Set(SettingsDefaults.keys)
        for declared in [
            "general.onLaunch", "general.confirmClose",
            "appearance.theme", "appearance.glassOptimisation",
            "search.engine", "search.customEngineURL",
            "downloads.directory", "downloads.askEachTime", "downloads.autoOpen", "downloads.clearPolicy",
            "advanced.userAgent", "advanced.showDevelopMenu", "advanced.webInspector",
            "settings.lastSection"
        ] {
            XCTAssertTrue(keys.contains(declared), "§6 declares \(declared) and the table does not")
        }
    }

    /// §6: "existing keys are not renamed". Both are settings the window shows,
    /// so "restore all" has to reach them under the names they already have.
    func testExistingKeysKeepTheirOwnSpelling() {
        let keys = Set(SettingsDefaults.keys)
        XCTAssertTrue(keys.contains("blocking.httpsOnly"))
        XCTAssertTrue(keys.contains("luna.autoArchiveHours"))
    }

    /// `luna.activeSpaceID` is session state, not a setting. Restoring it would
    /// move the user's Space out from under them, which is not what a settings
    /// reset means.
    func testSessionStateIsNotInTheTable() {
        XCTAssertFalse(SettingsDefaults.keys.contains("luna.activeSpaceID"))
    }

    func testKeysHasNoDuplicates() {
        XCTAssertEqual(SettingsDefaults.keys.count, Set(SettingsDefaults.keys).count)
    }

    /// §3.9's "Restore all settings to defaults", as a loop over the table.
    ///
    /// The whole stored domain is snapshotted and put back, so running the
    /// tests does not reset the developer's own settings.
    func testRestoreAllReachesEveryKeyInTheTable() {
        let defaults = UserDefaults.standard
        let snapshot = defaults.persistentDomain(forName: domain)
        defer { defaults.setPersistentDomain(snapshot ?? [:], forName: domain) }

        SettingsDefaults.register()
        let sentinel = "luna.shelltests.sentinel"
        for key in SettingsDefaults.keys { defaults.set(sentinel, forKey: key) }
        SettingsDefaults.restoreAll()
        for key in SettingsDefaults.keys {
            XCTAssertNotEqual(defaults.string(forKey: key), sentinel, "\(key) survived restoreAll()")
        }
    }

    /// A registered default *satisfies* a reader's `?? fallback`, so a table row
    /// that disagrees with its reader silently overrides it. These four are the
    /// ones where the reader's fallback is not the obvious value.
    func testRegisteredDefaultsMatchTheirReaders() {
        let defaults = UserDefaults.standard
        let snapshot = defaults.persistentDomain(forName: domain)
        defer { defaults.setPersistentDomain(snapshot ?? [:], forName: domain) }

        SettingsDefaults.restoreAll()
        SettingsDefaults.register()
        XCTAssertTrue(defaults.bool(forKey: "general.confirmClose"), "GeneralSettings.confirmClose defaults on")
        XCTAssertTrue(defaults.bool(forKey: "advanced.webInspector"), "WebViewFactory.isWebInspectorEnabled defaults on")
        XCTAssertFalse(defaults.bool(forKey: "downloads.autoOpen"), "§3.5: auto-open defaults off on purpose")
        XCTAssertFalse(defaults.bool(forKey: "blocking.httpsOnly"))
    }
}

@MainActor
final class SettingsSearchTests: XCTestCase {

    /// §2: an empty query restores the window rather than emptying it.
    func testEmptyQueryMatchesEverything() {
        XCTAssertTrue(SettingsSearch.matches("", in: ["block ads"]))
        XCTAssertTrue(SettingsSearch.matches("   ", in: []))
    }

    /// The rule agents B and C implement in their own `filter(_:)`. If these two
    /// ever disagree the list dims a section whose rows are still showing, or
    /// the reverse.
    func testMatchesIsACaseInsensitiveSubstring() {
        XCTAssertTrue(SettingsSearch.matches("COOKIE", in: ["clear cookies and cache"]))
        XCTAssertTrue(SettingsSearch.matches("  cookie ", in: ["cookies"]))
        XCTAssertFalse(SettingsSearch.matches("cookie", in: ["block ads", "trackers"]))
    }
}

@MainActor
final class SettingsSectionRegistryTests: XCTestCase {

    func testEverySectionIsRegisteredInSpecOrder() {
        XCTAssertEqual(SettingsSectionRegistry.ids, [
            "general", "appearance", "privacy", "passwords", "search", "downloads",
            "shortcuts", "spaces", "extensions", "advanced"
        ])
    }

    /// Measured against the SDK rather than eyeballed: an SF Symbol that does
    /// not exist renders as nothing at all, and a section with no icon in a
    /// ten-row list is the kind of thing nobody notices until it ships.
    func testEverySectionSymbolResolves() {
        for section in SettingsSectionRegistry.all {
            XCTAssertNotNil(
                NSImage(systemSymbolName: section.symbolName, accessibilityDescription: nil),
                "\(section.id) names a symbol the SDK does not have: \(section.symbolName)"
            )
        }
    }

    /// §2: exactly one section is selected, always — including when
    /// `settings.lastSection` holds an id from a build that had different
    /// sections.
    func testUnknownLastSectionFallsBackToTheFirst() {
        XCTAssertEqual(SettingsSectionRegistry.index(ofID: "no-such-section"), 0)
        XCTAssertEqual(SettingsSectionRegistry.index(ofID: nil), 0)
        XCTAssertEqual(SettingsSectionRegistry.index(ofID: "privacy"), 2)
    }
}

@MainActor
final class SettingsRowTests: XCTestCase {

    /// §4, and the reason the row is a custom view: a disabled `NSControl` is
    /// dropped from the key-view loop and skipped by VoiceOver, so the row takes
    /// over as the focusable, labelled, helped element.
    func testDisabledRowStaysFocusableAndExplainsItself() throws {
        let reason = "A right-hand sidebar is not built yet."
        let row = try XCTUnwrap(SettingsRow.toggle(
            "Sidebar position",
            value: false,
            isEnabled: false,
            disabledReason: reason
        ) { _ in } as? SettingsRowView)

        XCTAssertTrue(row.acceptsFirstResponder, "§4: a disabled row is still focusable")
        XCTAssertEqual(row.accessibilityHelp(), reason)
        XCTAssertEqual(row.accessibilityLabel(), "Sidebar position")
        let toggle = try XCTUnwrap(Self.control(in: row, of: SettingsSwitch.self))
        XCTAssertFalse(toggle.isEnabled, "a disabled row's control must not be operable")
        XCTAssertFalse(toggle.acceptsFirstResponder, "and the row, not the switch, holds the focus")
    }

    /// An enabled row is a group: the control inside it is what the key-view
    /// loop and VoiceOver reach, and it carries the row's own label (§8).
    func testEnabledRowDefersToItsControl() throws {
        let row = try XCTUnwrap(SettingsRow.toggle("Block ads", value: true) { _ in } as? SettingsRowView)
        XCTAssertFalse(row.acceptsFirstResponder)
        let toggle = try XCTUnwrap(Self.control(in: row, of: SettingsSwitch.self))
        XCTAssertTrue(toggle.isEnabled)
        XCTAssertEqual(toggle.accessibilityLabel(), "Block ads")
        XCTAssertTrue(toggle.isOn)
        // §8: hand-drawn, so the role VoiceOver reads is ours to get right.
        XCTAssertEqual(toggle.accessibilityRole(), .checkBox)
        XCTAssertEqual(toggle.accessibilityValue() as? Bool, true)
    }

    /// AppKit's own switch is a fixed 54 × 24 at every `controlSize` — measured,
    /// and the reason `SettingsSwitch` exists. If a later macOS starts honouring
    /// `controlSize`, this is the test that says the workaround can go.
    func testTheSwitchIsTheSizeThePaneWasBuiltFor() throws {
        let row = try XCTUnwrap(SettingsRow.toggle("Block ads", value: true) { _ in } as? SettingsRowView)
        let toggle = try XCTUnwrap(Self.control(in: row, of: SettingsSwitch.self))
        XCTAssertEqual(toggle.intrinsicContentSize, Tokens.Metric.settingsSwitch.size)
        XCTAssertLessThan(toggle.intrinsicContentSize.height, Tokens.Metric.settingsControl)

        let appKit = NSSwitch()
        appKit.controlSize = .mini
        appKit.sizeToFit()
        XCTAssertGreaterThan(
            appKit.fittingSize.width,
            toggle.intrinsicContentSize.width,
            "NSSwitch honours controlSize again — SettingsSwitch may be able to go"
        )
    }

    /// The closure bridge is retained by the row. `NSControl.target` is weak, so
    /// without that the control would silently do nothing on its first click.
    func testToggleActuallyCallsBack() throws {
        var seen: Bool?
        let row = try XCTUnwrap(SettingsRow.toggle("Block ads", value: false) { seen = $0 } as? SettingsRowView)
        let toggle = try XCTUnwrap(Self.control(in: row, of: SettingsSwitch.self))
        // Through the accessibility press, which is the same path a click and
        // the space bar take — and the one a VoiceOver user takes.
        XCTAssertTrue(toggle.accessibilityPerformPress())
        XCTAssertEqual(seen, true)
        XCTAssertTrue(toggle.isOn)
    }

    /// §2's search reads these; a row that indexes nothing can never be found.
    func testRowIndexesItsOwnLabels() throws {
        let row = try XCTUnwrap(SettingsRow.popup(
            "Search engine",
            subtitle: "Where the address bar sends a query",
            options: ["DuckDuckGo", "Kagi"],
            selected: 1
        ) { _ in } as? SettingsRowView)
        XCTAssertTrue(row.searchTerms.contains("search engine"))
        XCTAssertTrue(row.searchTerms.contains("kagi"))
    }

    /// A `selected:` a section computed against an options list that has since
    /// changed would otherwise raise from AppKit.
    func testOutOfRangeSelectionIsClamped() throws {
        let row = try XCTUnwrap(SettingsRow.segmented(
            "Theme",
            options: ["Auto", "Light", "Dark"],
            selected: 99
        ) { _ in } as? SettingsRowView)
        // `SettingsChoice`, not `NSSegmentedControl` — the latter paints its
        // selection as a solid accent block, which Luna's chrome never does.
        let control = try XCTUnwrap(Self.find(in: row, of: SettingsChoice.self))
        XCTAssertEqual(control.selectedIndex, 2)
    }

    /// The row's *control*, not the first `NSControl` in it: a title is an
    /// `NSTextField`, which is also an `NSControl`, and it is laid out first.
    private static func control<T: NSControl>(in view: NSView, of kind: T.Type = T.self) -> T? {
        find(in: view, of: kind)
    }

    /// The same search, for the controls that are plain `NSView`s.
    private static func find<T: NSView>(in view: NSView, of kind: T.Type = T.self) -> T? {
        for child in view.subviews {
            if let match = child as? T { return match }
            if let found = find(in: child, of: kind) { return found }
        }
        return nil
    }
}

@MainActor
final class SettingsSectionListTests: XCTestCase {

    private func list() -> SettingsSectionList {
        SettingsSectionList(titles: ["A", "B", "C"], symbols: ["gearshape", "gearshape", "gearshape"])
    }

    /// §2: exactly one selected, always.
    func testSelectionIsNeverEmptyAndNeverOutOfRange() {
        let list = self.list()
        XCTAssertEqual(list.selected, 0)
        list.select(2)
        XCTAssertEqual(list.selected, 2)
        list.select(99)
        XCTAssertEqual(list.selected, 0, "an out-of-range section falls back to the first, not to none")
        list.select(-1)
        XCTAssertEqual(list.selected, 0)
    }

    /// §2: arrows walk the list and stop at the ends rather than wrapping — a
    /// list that wraps loses the user's place in a nine-item column.
    func testArrowsClampAtBothEnds() {
        let list = self.list()
        var picked: [Int] = []
        list.onSelect = { picked.append($0) }
        list.moveUp(nil)
        XCTAssertEqual(list.selected, 0)
        list.moveDown(nil)
        list.moveDown(nil)
        list.moveDown(nil)
        XCTAssertEqual(list.selected, 2)
        XCTAssertEqual(picked, [0, 1, 2, 2])
    }
}

@MainActor
final class SettingsWindowTests: XCTestCase {

    /// §1's floor, and the reason it is a constraint: `NSWindow.minSize` is
    /// documented as ignored once the content view uses Auto Layout, so a test
    /// that asserted `window.minSize` would pass while the window shrank to
    /// nothing.
    func testWindowEnforcesItsFloorWithConstraintsNotMinSize() throws {
        let controller = SettingsWindowController()
        let window = try XCTUnwrap(controller.window)
        let root = try XCTUnwrap(window.contentView)
        let floors = root.constraints.filter { $0.relation == .greaterThanOrEqual && $0.secondItem == nil }
        XCTAssertEqual(
            Set(floors.map(\.constant)),
            [SettingsMetrics.minWidth, SettingsMetrics.minHeight],
            "§1's 640 × 480 floor is missing from the root view"
        )
        // **Not an equality against `contentSize`.** `windowFrameAutosaveName`
        // is set on this window on purpose (§1: it comes back the size you left
        // it), so the frame it opens at is whatever the user last dragged it to
        // — and the test host shares the user's real `dk.novapps.luna` defaults
        // domain, so it reads *his* saved frame. This failed at 887 × 552 for
        // exactly that reason: `"NSWindow Frame LunaSettingsWindow" =
        // "656 310 887 552"` is in his preferences, not a regression in any
        // section's layout. Only the first window in a process gets the restore
        // — a second one with the same autosave name is refused — which is what
        // made this order-dependent as well.
        //
        // What is actually spec'd is the *declared* size and the floor, so that
        // is what is asserted.
        XCTAssertEqual(SettingsMetrics.contentSize, CGSize(width: 720, height: 520))
        let size = try XCTUnwrap(window.contentView?.frame.size)
        XCTAssertGreaterThanOrEqual(size.width, SettingsMetrics.minWidth)
        XCTAssertGreaterThanOrEqual(size.height, SettingsMetrics.minHeight)
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.isRestorable, "§1: not restorable into a browser window")
        window.close()
    }

    /// §1: the list column is fixed at 196, and deliberately not `sidebarWidth`
    /// — that one is dragged by the user and this one is not.
    func testSectionListColumnIsFixedAtSpecWidth() throws {
        let controller = SettingsWindowController()
        let root = try XCTUnwrap(controller.window?.contentView)
        // A constant-width constraint is installed on the view it constrains,
        // not on its superview — so this reads the column, not the root.
        let column = try XCTUnwrap(root.subviews.first)
        let widths = column.constraints.filter {
            $0.firstAttribute == .width && $0.relation == .equal && $0.secondItem == nil
        }
        XCTAssertEqual(widths.map(\.constant), [SettingsMetrics.listWidth])
        XCTAssertNotEqual(SettingsMetrics.listWidth, Tokens.Metric.sidebarWidth.default)
        controller.window?.close()
    }
}

@MainActor
final class SettingsMenuTests: XCTestCase {

    /// §22.5: every command is a menu item. No `NSEvent` monitor exists in Luna
    /// and none may be added, so if these items are missing the shortcuts are
    /// simply gone.
    func testSettingsCommandsAreAllMenuItems() throws {
        let app = NSApplication.shared
        let previous = app.mainMenu
        defer { app.mainMenu = previous }
        MainMenu.install(into: app)

        let items = try XCTUnwrap(app.mainMenu).items.compactMap(\.submenu).flatMap(Self.leaves(of:))
        let settings = try XCTUnwrap(items.first { $0.title == "Settings…" })
        XCTAssertEqual(settings.keyEquivalent, ",")
        XCTAssertEqual(settings.keyEquivalentModifierMask, .command)

        let search = try XCTUnwrap(items.first { $0.title == "Search Settings" })
        XCTAssertEqual(search.keyEquivalent, "f")

        // One item per section, tagged with its index — and **no key equivalent
        // of its own**, because AppKit was already taking it away.
        //
        // These used to declare ⌘1…⌘9. Measured on macOS 26.5 inside the running
        // app: a ⌘-number that duplicates one already in the menu bar is
        // *erased* from the later item — `keyEquivalent` comes back "", the
        // modifier mask survives, and nothing is reported at build time or run
        // time. View ▸ Sidebar Items is earlier in the bar and owns ⌘1…⌘9 now
        // (SPACES-SPEC §13.2), so re-declaring them here only prints a shortcut
        // the menu does not have. **Do not "restore" them.**
        //
        // §2's ⌘1…⌘9 still reaches this window: `AppDelegate.goToSidebarItem(_:)`
        // forwards to it while it is key, and a hidden Sidebar Item still fires
        // its key equivalent, so all nine arrive whatever the tab count.
        let sections = SettingsSectionRegistry.all.enumerated().map { index, type -> NSMenuItem in
            let match = items.first { $0.title == type.title && $0.tag == index }
            return match ?? NSMenuItem()
        }
        for (index, item) in sections.enumerated() {
            XCTAssertEqual(item.tag, index, "no menu item for section \(index)")
            XCTAssertTrue(item.keyEquivalent.isEmpty, "section \(index) declares a shortcut AppKit will erase")
        }
    }

    /// The section items reach this window through the responder chain rather
    /// than through a target, which is what lets `⌘1` mean "sidebar item" in
    /// the browser and "section" here. A target would break that, and so would
    /// a key equivalent — see the comment in the test above.
    func testSectionItemsAreNilTargeted() throws {
        let app = NSApplication.shared
        let previous = app.mainMenu
        defer { app.mainMenu = previous }
        MainMenu.install(into: app)
        let items = try XCTUnwrap(app.mainMenu).items.compactMap(\.submenu).flatMap(Self.leaves(of:))
        for item in items where item.action == #selector(SettingsWindowController.goToSettingsSection(_:)) {
            XCTAssertNil(item.target)
        }
    }

    private static func leaves(of menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item -> [NSMenuItem] in
            if let submenu = item.submenu { return leaves(of: submenu) }
            return item.isSeparatorItem ? [] : [item]
        }
    }
}
