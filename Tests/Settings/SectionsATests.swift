//
//  SectionsATests.swift
//  LunaTests
//
//  §23.1 §3.1, §3.2, §3.4 and §3.6 — the half that can be asserted without a
//  window.
//
//  What is deliberately **not** tested here is the view tree. `SettingsRow`
//  returns opaque `NSView`s by design, so "is this row dimmed" is not a
//  question a test can ask without reaching into another agent's private
//  layout; the shell's own tests cover the rows. What *is* tested is every
//  piece of logic this milestone added: the engine templates, the URL a query
//  becomes, the custom-engine validator, and the menu-bar reader.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class SectionsATests: XCTestCase {

    private var savedEngine: SearchEngineSetting!

    override func setUp() {
        super.setUp()
        savedEngine = SearchSettings.current
    }

    override func tearDown() {
        SearchSettings.apply(savedEngine)
        super.tearDown()
    }

    // MARK: - §3.4 engines

    /// Every built-in is the same shape as a custom one. If this fails,
    /// `.custom` has become a second code path.
    func testEveryBuiltInEngineIsAUsableTemplate() {
        for engine in SearchEngine.allCases where engine != .custom {
            let template = try? XCTUnwrap(engine.template)
            XCTAssertNotNil(template, "\(engine) has no template")
            XCTAssertTrue(template?.contains(SearchEngineSetting.placeholder) == true, "\(engine) has no %s")
            XCTAssertTrue(SearchEngineSetting.isUsable(template ?? ""), "\(engine) does not resolve to a URL")
        }
        XCTAssertNil(SearchEngine.custom.template)
    }

    func testTheShippedDefaultIsStillDuckDuckGo() {
        XCTAssertEqual(SearchEngine.fallback, .duckDuckGo)
        SearchSettings.apply(SearchEngineSetting())
        XCTAssertEqual(CommandBarURL.search(for: "luna")?.host, "duckduckgo.com")
    }

    func testTheEngineSettingChangesWhereAQueryGoes() {
        SearchSettings.apply(SearchEngineSetting(engine: .kagi))
        XCTAssertEqual(CommandBarURL.search(for: "luna")?.absoluteString, "https://kagi.com/search?q=luna")
        SearchSettings.apply(SearchEngineSetting(engine: .google))
        XCTAssertEqual(CommandBarURL.search(for: "luna")?.host, "www.google.com")
    }

    func testACustomEngineIsUsedOnlyOnceItCarriesThePlaceholder() {
        let template = "https://searx.example.com/?q=%s"
        SearchSettings.apply(SearchEngineSetting(engine: .custom, customTemplate: template))
        XCTAssertEqual(CommandBarURL.search(for: "luna")?.absoluteString, "https://searx.example.com/?q=luna")

        // No placeholder: the search row is the floor under the Command Bar
        // (§9.2), so it falls back rather than disappearing.
        SearchSettings.apply(SearchEngineSetting(engine: .custom, customTemplate: "https://searx.example.com/"))
        XCTAssertEqual(CommandBarURL.search(for: "luna")?.host, "duckduckgo.com")

        // Not a URL at all, and a scheme Luna will not navigate to.
        for junk in ["%s", "ftp://example.com/?q=%s", "notaurl%s"] {
            XCTAssertFalse(SearchEngineSetting.isUsable(junk), junk)
        }
    }

    func testSwitchingEngineKeepsTheCustomTemplate() {
        SearchSettings.apply(SearchEngineSetting(engine: .custom, customTemplate: "https://e.example/?q=%s"))
        var setting = SearchSettings.current
        setting.engine = .bing
        SearchSettings.apply(setting)
        XCTAssertEqual(SearchSettings.current.customTemplate, "https://e.example/?q=%s")
    }

    /// The measured bug the lift fixed: `URLComponents.queryItems` leaves `+`,
    /// `/` and `?` unescaped in a query value, so `a+b` reached the engine as
    /// `q=a+b` — two words. A space is still `%20`, exactly as before.
    func testQueriesAreEscapedIncludingThePlusSign() {
        SearchSettings.apply(SearchEngineSetting())
        XCTAssertEqual(CommandBarURL.search(for: "a+b")?.absoluteString, "https://duckduckgo.com/?q=a%2Bb")
        XCTAssertEqual(CommandBarURL.search(for: "hello world")?.absoluteString, "https://duckduckgo.com/?q=hello%20world")
        XCTAssertEqual(CommandBarURL.search(for: "rock & roll")?.absoluteString, "https://duckduckgo.com/?q=rock%20%26%20roll")
    }

    /// `SettingsDefaults.restoreAll()` removes the keys without telling the
    /// in-memory copy, so the copy has to be able to re-read them.
    func testReloadPicksUpAStoredValueChangedBehindTheCache() {
        SearchSettings.apply(SearchEngineSetting(engine: .bing))
        UserDefaults.standard.removeObject(forKey: "search.engine")
        XCTAssertEqual(SearchSettings.current.engine, .bing, "current is a cache, not a read-through")
        SearchSettings.reload()
        XCTAssertEqual(SearchSettings.current.engine, SearchEngine.fallback)
    }

    func testAnEmptyQueryIsStillNotASearch() {
        SearchSettings.apply(SearchEngineSetting())
        XCTAssertNil(CommandBarURL.search(for: ""))
        XCTAssertNil(CommandBarURL.search(for: "   \n "))
    }

    func testTheValidatorSaysWhichEngineIsActuallyInUse() {
        let live = SearchSection.validationText(SearchEngineSetting(engine: .custom, customTemplate: "https://e.example/?q=%s"))
        XCTAssertTrue(live.contains("custom engine"), live)
        let broken = SearchSection.validationText(SearchEngineSetting(engine: .custom, customTemplate: "https://e.example/"))
        XCTAssertTrue(broken.contains("Not in use"), broken)
        XCTAssertTrue(broken.contains(SearchEngine.fallback.title), broken)
        let empty = SearchSection.validationText(SearchEngineSetting(engine: .custom))
        XCTAssertTrue(empty.contains(SearchEngineSetting.placeholder), empty)
        let google = SearchSection.validationText(SearchEngineSetting(engine: .google))
        XCTAssertTrue(google.contains("Google"), google)
    }

    // MARK: - §3.1 general

    /// §6.3 spells "never" as zero hours, and the popup has to say so in words.
    func testAutoArchiveTitlesCoverEveryChoiceIncludingNever() {
        XCTAssertEqual(AutoArchive.choices.map(GeneralSection.hoursTitle), ["6 hours", "12 hours", "24 hours", "Never"])
        XCTAssertTrue(AutoArchive.choices.contains(AutoArchive.defaultHours))
    }

    /// The key keeps its `luna.` prefix (§6): renaming it would silently reset
    /// every existing install to 12 hours.
    func testAutoArchiveWritesTheExistingKey() {
        XCTAssertEqual(TabLifecycle.autoArchiveHoursKey, "luna.autoArchiveHours")
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: TabLifecycle.autoArchiveHoursKey)
        defaults.set(24.0, forKey: TabLifecycle.autoArchiveHoursKey)
        XCTAssertEqual(TabLifecycle.autoArchiveHours, 24)
        defaults.set(saved, forKey: TabLifecycle.autoArchiveHoursKey)
    }

    // MARK: - §3.2 appearance

    /// Auto is `nil`, which is the whole of how Luna follows System Settings.
    func testAutoThemeHandsTheChoiceBackToTheSystem() {
        XCTAssertNil(AppearanceSection.Theme.auto.appearance)
        XCTAssertEqual(AppearanceSection.Theme.light.appearance?.name, .aqua)
        XCTAssertEqual(AppearanceSection.Theme.dark.appearance?.name, .darkAqua)
    }

    /// §3.2: 160 × 72. A tile that is not the sampled size is not a sample.
    func testThePreviewTileIsTheSizeTheSpecMeasures() {
        XCTAssertEqual(AppearanceSection.previewTileSize, NSSize(width: 160, height: 72))
    }

    // MARK: - §3.6 shortcuts

    private func menuBar() -> NSMenu {
        func item(_ title: String, _ key: String, _ flags: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let entry = NSMenuItem(title: title, action: #selector(NSApplication.hide(_:)), keyEquivalent: key)
            entry.keyEquivalentModifierMask = flags
            return entry
        }
        let file = NSMenu(title: "File")
        file.addItem(item("New Tab", "t"))
        file.addItem(.separator())
        file.addItem(item("Reopen Last Archived Tab", "T"))
        file.addItem(item("Nothing Bound", ""))
        let window = NSMenu(title: "Window")
        let arrow = String(UnicodeScalar(UInt32(NSLeftArrowFunctionKey))!)
        window.addItem(item("Show Previous Tab", arrow, [.command, .option]))

        let bar = NSMenu()
        for menu in [file, window] {
            let top = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            top.submenu = menu
            bar.addItem(top)
        }
        return bar
    }

    // MARK: - Smoke

    /// Builds all four for real — `SettingsRow`, `Glass.previewTile`, the
    /// constraints and the live menu bar — because everything above is logic
    /// and none of it would catch a section that cannot be constructed.
    func testEverySectionBuildsIndexesAndFilters() {
        let sections: [any SettingsSection] = [
            GeneralSection(), AppearanceSection(), SearchSection(), ShortcutsSection()
        ]
        for section in sections {
            let name = type(of: section).id
            XCTAssertFalse(section.searchIndex.isEmpty, name)
            XCTAssertFalse(section.view.subviews.isEmpty, name)
            XCTAssertEqual(section.searchIndex, section.searchIndex.map { $0.lowercased() }, "\(name) index is not folded")
            section.filter("zzz-matches-nothing")
            section.filter("")
        }
    }

    /// The Shortcuts table is only correct because it is not a second copy of
    /// the key map: `MainMenu` installed this menu bar at launch, and `⌘,`
    /// arrived in it after this section was written.
    func testShortcutsIndexesTheRealMenuBar() throws {
        try XCTSkipIf(NSApplication.shared.mainMenu == nil, "no menu bar in this host")
        let index = ShortcutsSection().searchIndex
        XCTAssertTrue(index.contains("new tab"), "\(index)")
        XCTAssertTrue(index.contains("⌘t"), "\(index)")
    }

    func testTheTableIsReadOffTheLiveMenuBarAndGroupedByMenu() {
        let commands = ShortcutsSection.commands(in: menuBar())
        XCTAssertEqual(commands.map(\.menu), ["File", "File", "File", "Window"])
        XCTAssertEqual(commands.map(\.title), ["New Tab", "Reopen Last Archived Tab", "Nothing Bound", "Show Previous Tab"])
    }

    /// The one that is easy to get wrong: `MainMenu` spells `⇧⌘T` as an
    /// uppercase key equivalent with only `.command` in the mask, so reading
    /// the mask alone prints a different, already-taken shortcut.
    func testAnUppercaseKeyEquivalentImpliesShift() {
        let keys = ShortcutsSection.commands(in: menuBar()).map(\.key)
        XCTAssertEqual(keys, ["⌘T", "⇧⌘T", "", "⌥⌘←"])
    }
}
