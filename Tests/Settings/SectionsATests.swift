//
//  SectionsATests.swift
//  LunaTests
//
//  §23.1 §3.1, §3.2, §3.4 and §3.6 — the half that can be asserted without a
//  window.
//
//  The view tree is deliberately not tested here. `SettingsRow` returns opaque
//  `NSView`s by design, so "is this row dimmed" is not a question a test can
//  ask without reaching into a private layout; the shell's own tests cover the
//  rows. What is tested is the logic: the engine templates, the URL a query
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

    /// The sentence under the row is gone; what it was protecting is not. A
    /// custom template without `%s` is silently ignored — searches fall back to
    /// DuckDuckGo — so the field has to be able to say so, and `isUsable` is
    /// what it asks.
    func testAnUnusableCustomTemplateIsDetectableWithoutRunningTheField() {
        XCTAssertTrue(SearchEngineSetting.isUsable("https://e.example/?q=%s"))
        XCTAssertFalse(SearchEngineSetting.isUsable("https://e.example/"))
        XCTAssertFalse(SearchEngineSetting.isUsable(""))
        XCTAssertNil(SearchEngineSetting(engine: .custom, customTemplate: "https://e.example/").activeTemplate)
        // And the fallback still happens, so nothing breaks while it is wrong.
        XCTAssertEqual(
            SearchEngineSetting(engine: .custom, customTemplate: "nope").url(searching: "luna")?.host,
            SearchEngineSetting(engine: .duckDuckGo).url(searching: "luna")?.host
        )
    }

    // MARK: - §3.4 suggestions

    /// On by default, and the key is what a fresh install reads.
    func testSuggestionsAreOnUntilTheUserTurnsThemOff() {
        UserDefaults.standard.removeObject(forKey: SearchSettings.suggestionsKey)
        SearchSettings.reload()
        XCTAssertTrue(SearchSettings.current.suggestions)

        var setting = SearchSettings.current
        setting.suggestions = false
        SearchSettings.apply(setting)
        SearchSettings.reload()
        XCTAssertFalse(SearchSettings.current.suggestions, "the switch has to survive the window closing")
        UserDefaults.standard.removeObject(forKey: SearchSettings.suggestionsKey)
        SearchSettings.reload()
    }

    /// Nothing is asked of an engine that has no suggestion endpoint, and
    /// nothing at all is asked while the switch is off — §9.6 as an assertion
    /// rather than as a paragraph.
    func testOnlyAnEngineWithAnEndpointIsEverAsked() {
        XCTAssertNotNil(SearchEngineSetting(engine: .duckDuckGo).suggestURL(for: "luna"))
        XCTAssertNotNil(SearchEngineSetting(engine: .google).suggestURL(for: "luna"))
        XCTAssertNotNil(SearchEngineSetting(engine: .bing).suggestURL(for: "luna"))
        XCTAssertNil(SearchEngineSetting(engine: .kagi).suggestURL(for: "luna"))
        XCTAssertNil(
            SearchEngineSetting(engine: .custom, customTemplate: "https://e.example/?q=%s").suggestURL(for: "luna"),
            "a search template says nothing about where that engine's suggestions live"
        )
        XCTAssertNil(SearchEngineSetting(engine: .duckDuckGo, suggestions: false).suggestURL(for: "luna"))
        XCTAssertNil(SearchEngineSetting(engine: .duckDuckGo).suggestURL(for: ""))

        // Every endpoint is https, and the query is escaped the same way a
        // search URL's is.
        let url = SearchEngineSetting(engine: .duckDuckGo).suggestURL(for: "a b")
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(url?.absoluteString.contains("a%20b"), true)
    }

    /// One parser for all three engines, asserted against the shape each of
    /// them actually returns.
    func testTheOpenSearchPayloadIsParsedAndDeduplicated() {
        let payload = Data(#"["git", ["github", "git bash", "GitHub", "  ", "gitlab"]]"#.utf8)
        XCTAssertEqual(SearchSuggestions.parse(payload), ["github", "git bash", "gitlab"])
        XCTAssertEqual(SearchSuggestions.parse(Data("not json".utf8)), [])
        XCTAssertEqual(SearchSuggestions.parse(Data(#"["git"]"#.utf8)), [])
        XCTAssertEqual(SearchSuggestions.parse(Data(#"["git", "nope"]"#.utf8)), [])
    }

    /// The engine's echo of what you typed is dropped: `searchRow` is already
    /// that line, a tier above, and two identical rows read as a bug.
    func testSuggestionRowsSitBelowTheSearchRowAndNeverRepeatIt() {
        SearchSettings.apply(SearchEngineSetting(engine: .duckDuckGo))
        var sources = CommandBarSources()
        sources.suggestions = ["git", "github", "gitlab"]
        let rows = CommandBarRanking.merge(query: "git", sources: sources, limit: 10)

        XCTAssertEqual(rows.first?.source, .search)
        XCTAssertEqual(rows.first?.title, "git")
        XCTAssertEqual(rows.dropFirst().map(\.title), ["github", "gitlab"])
        XCTAssertTrue(rows.dropFirst().allSatisfy { $0.source == .suggestion })
        // The engine's order is its ranking, and Luna does not re-sort it.
        XCTAssertEqual(rows.dropFirst().map(\.title), ["github", "gitlab"])
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
            GeneralSection(), AppearanceSection(), PrivacySection(), ShortcutsSection()
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
