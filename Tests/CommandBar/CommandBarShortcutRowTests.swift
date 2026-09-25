//
//  CommandBarShortcutRowTests.swift
//  LunaTests
//
//  §9.2's shortcut rows: §20.1's menu commands offered by name, with the
//  keystroke that fires them.
//
//  The rows are asserted against hand-built entries rather than against
//  `BrowserCommand.commandBarEntries`, which asks the responder chain and so
//  answers differently depending on what the host app has open. What is
//  asserted about the table itself is the half that cannot move: which
//  commands carry a symbol, that every symbol is a real one, and that every id
//  the bar can emit is one `AppDelegate` can look back up.
//

import XCTest
@testable import Luna

@MainActor
final class CommandBarShortcutRowTests: XCTestCase {

    /// These write the very keys the running app reads, so every one of them
    /// is put back exactly as it was found — the absent ones included.
    private var saved: [String: Any?] = [:]

    override func setUp() {
        super.setUp()
        let keys = [SearchSettings.shortcutResultsKey, SearchSettings.settingsResultsKey]
        saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
        setShortcutResults(true)
    }

    override func tearDown() {
        for (key, value) in saved {
            if let value { UserDefaults.standard.set(value, forKey: key) } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        SearchSettings.reload()
        super.tearDown()
    }

    private func setShortcutResults(_ on: Bool) {
        var setting = SearchSettings.current
        setting.shortcutResults = on
        SearchSettings.apply(setting)
    }

    private func entry(
        _ id: String,
        _ title: String,
        shortcut: String = "",
        keywords: [String] = []
    ) -> ShortcutEntry {
        ShortcutEntry(id: id, title: title, symbolName: "star", shortcut: shortcut, keywords: keywords)
    }

    private func sources() -> CommandBarSources {
        var sources = CommandBarSources()
        sources.shortcuts = [
            entry("newWindow", "New Window", shortcut: "⌘N"),
            entry("newPrivateWindow", "New Private Window", shortcut: "⇧⌘N", keywords: ["incognito"]),
            entry("copyURL", "Copy URL", shortcut: "⇧⌘C", keywords: ["copy link", "address"]),
            entry("copyMarkdown", "Copy URL as Markdown", shortcut: "⌥⇧⌘C", keywords: ["copy link", "markdown"]),
            entry("duplicateTab", "Duplicate Tab")
        ]
        return sources
    }

    /// Both tiers: a command whose own name answered, and one the query only
    /// reached through a keyword.
    private func rows(_ query: String) -> [CommandBarResult] {
        CommandBarRanking.merge(query: query, sources: sources(), limit: 8)
            .filter { $0.source == .shortcut || $0.source == .keywordShortcut }
    }

    // MARK: - The row

    /// What the feature is: name a command and pressing Return runs it.
    func testACommandsNameOffersItWithTheKeystrokeThatFiresIt() throws {
        let row = try XCTUnwrap(rows("new window").first)

        XCTAssertEqual(row.title, "New Window")
        XCTAssertEqual(row.subtitle, "⌘N")
        XCTAssertEqual(row.action, .runCommand("newWindow"))
        XCTAssertEqual(row.symbolName, "star")
    }

    /// Nobody calls it Copy URL. The keyword list is what makes the row
    /// findable under the name the command actually has in people's heads.
    func testAKeywordFindsACommandItsTitleDoesNot() {
        XCTAssertEqual(rows("incognito").map(\.action), [.runCommand("newPrivateWindow")])
        XCTAssertEqual(rows("address").map(\.action), [.runCommand("copyURL")])
    }

    /// A command nothing but a keyword found sits below the search row: the
    /// word that reached it is not on the row, so it is a weaker claim on the
    /// top of the list than the word the user typed.
    func testACommandFoundOnlyByAKeywordSitsBelowTheSearchRow() {
        let found = CommandBarRanking.merge(query: "incognito", sources: sources(), limit: 8)
        XCTAssertEqual(found.map(\.source), [.search, .keywordShortcut])
    }

    /// "copy link" is half a title match for both Copy URL and Copy URL as
    /// Markdown, and the plain one is what was asked for. Reported from the
    /// running app, where Markdown was sitting on top.
    func testOfTwoKeywordMatchesTheShorterTitleComesFirst() {
        XCTAssertEqual(
            rows("copy link").map(\.action),
            [.runCommand("copyURL"), .runCommand("copyMarkdown")]
        )
    }

    /// A command with no keystroke is still worth a row — Duplicate Tab is
    /// three levels into a menu and has no key at all — and its subtitle is
    /// simply empty rather than a made-up one.
    func testACommandWithNoShortcutIsStillOfferedAndSaysNothing() throws {
        let row = try XCTUnwrap(rows("duplicate").first)
        XCTAssertEqual(row.action, .runCommand("duplicateTab"))
        XCTAssertEqual(row.subtitle, "")
    }

    /// Both New Window and New Private Window start with "new", so the tie is
    /// broken by how much of the title the query covers — three letters is the
    /// whole front of one and a third of the other.
    func testOfTwoNamesTheQueryStartsTheShorterComesFirst() throws {
        let found = rows("new")
        XCTAssertEqual(found.map(\.action), [.runCommand("newWindow"), .runCommand("newPrivateWindow")])
        XCTAssertEqual(try XCTUnwrap(rows("new private").first).action, .runCommand("newPrivateWindow"))
    }

    /// A shortcut row carries no URL, so it stays out of §9.4's autofill.
    func testAShortcutRowCarriesNoURL() throws {
        XCTAssertNil(try XCTUnwrap(rows("new window").first).url)
    }

    func testAnEmptyQueryOffersNoCommands() {
        XCTAssertTrue(rows("").isEmpty)
        XCTAssertTrue(rows("   ").isEmpty)
    }

    /// Below the two app commands, above the Settings sections and the search
    /// row — see `CommandBarSource`'s declaration order.
    func testShortcutRowsRankBelowAppCommandsAndAboveTheSearchRow() throws {
        let order = CommandBarSource.allCases
        let shortcut = try XCTUnwrap(order.firstIndex(of: .shortcut))
        let search = try XCTUnwrap(order.firstIndex(of: .search))
        XCTAssertLessThan(try XCTUnwrap(order.firstIndex(of: .command)), shortcut)
        XCTAssertLessThan(shortcut, search)
        XCTAssertLessThan(search, try XCTUnwrap(order.firstIndex(of: .keywordShortcut)))
    }

    // MARK: - §3.4's switch

    func testTheSwitchIsOnByDefault() {
        XCTAssertTrue(SearchEngineSetting().shortcutResults)
    }

    /// Its own switch, not the settings one: turning the commands off leaves
    /// the Settings sections where they were.
    func testTurningItOffRemovesTheRowsAndLeavesTheSettingsRowsAlone() {
        setShortcutResults(false)
        XCTAssertTrue(rows("new window").isEmpty)

        var both = sources()
        both.settings = SettingsSectionRegistry.commandBarEntries
        let found = CommandBarRanking.merge(query: "extensions", sources: both, limit: 8)
        XCTAssertTrue(found.contains { $0.source == .settings })
        XCTAssertFalse(found.contains { $0.source == .shortcut })
    }

    /// §6: a key with no row in `SettingsDefaults` does not exist.
    func testTheSwitchHasADeclaredDefault() {
        XCTAssertTrue(SettingsDefaults.keys.contains(SearchSettings.shortcutResultsKey))
    }

    // MARK: - The table

    /// Every id the bar can emit has to reach a selector, or Return on the row
    /// would do nothing at all.
    func testEveryOfferedCommandCanBeLookedBackUpByID() {
        for command in BrowserCommand.all where command.symbolName != nil {
            XCTAssertNotNil(BrowserCommand.command(id: command.id), command.id)
        }
    }

    func testEverySymbolResolves() {
        for command in BrowserCommand.all {
            guard let symbol = command.symbolName else { continue }
            XCTAssertNotNil(
                NSImage(systemSymbolName: symbol, accessibilityDescription: nil),
                "\(command.id): \(symbol)"
            )
        }
    }

    /// Matching folds the query and compares against these as they stand.
    func testEveryKeywordIsLowercased() {
        for command in BrowserCommand.all {
            for keyword in command.keywords {
                XCTAssertEqual(keyword, keyword.lowercased(), "\(command.id): \(keyword)")
            }
        }
    }

    /// The commands deliberately left out, and why each one is: text editing
    /// belongs to whatever holds the keyboard, Settings is already answered by
    /// §9.2's settings rows, Search Settings means nothing outside that window,
    /// and Hide Sidebar is `AppCommand.toggleSidebar` already.
    func testTheCommandsThatShouldNotBeOfferedAreNot() {
        let excluded = ["undo", "redo", "cut", "copy", "paste", "selectAll",
                        "minimize", "settings", "searchSettings", "toggleSidebar", "openLocation"]
        for id in excluded {
            let command = BrowserCommand.command(id: id)
            XCTAssertNotNil(command, id)
            XCTAssertNil(command?.symbolName, "\(id) should not be offered in the Command Bar")
        }
    }

    /// A keyword list with no symbol beside it is a command that was written
    /// for the bar and then left out of it.
    func testNoCommandCarriesKeywordsItCannotBeFoundBy() {
        for command in BrowserCommand.all where !command.keywords.isEmpty {
            XCTAssertNotNil(command.symbolName, command.id)
        }
    }
}
