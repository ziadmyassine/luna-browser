//
//  CommandBarSettingsRowTests.swift
//  LunaTests
//
//  §9.2's settings rows — the ten §3 sections offered from the bar by name —
//  and §3.4's switch that takes them away again.
//
//  The register itself is asserted here too. `commandBarEntries` is the one
//  place a section's title and symbol are copied out of the section, so a
//  section added to `SettingsSectionRegistry.all` and forgotten here would be
//  a section the bar cannot find.
//

import XCTest
@testable import Luna

@MainActor
final class CommandBarSettingsRowTests: XCTestCase {

    /// These write the very keys the running app reads, so every one of them
    /// is put back exactly as it was found — the absent ones included.
    /// `SearchSettings.apply` would write all four, which leaves a key behind
    /// on a machine that never had one.
    private var saved: [String: Any?] = [:]

    private static let keys = [
        SearchSettings.engineKey, SearchSettings.customEngineKey,
        SearchSettings.suggestionsKey, SearchSettings.settingsResultsKey
    ]

    override func setUp() {
        super.setUp()
        saved = Dictionary(uniqueKeysWithValues: Self.keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
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

    private func setSettingsResults(_ on: Bool) {
        var setting = SearchSettings.current
        setting.settingsResults = on
        SearchSettings.apply(setting)
    }

    private func sources() -> CommandBarSources {
        var sources = CommandBarSources()
        sources.settings = SettingsSectionRegistry.commandBarEntries
        return sources
    }

    /// Both tiers: a section whose own name answered, and one the query only
    /// reached through a keyword.
    private func rows(_ query: String) -> [CommandBarResult] {
        CommandBarRanking.merge(query: query, sources: sources(), limit: 8)
            .filter { $0.source == .settings || $0.source == .keywordSettings }
    }

    // MARK: - The row

    /// What the feature is: type a section's name and the section is offered,
    /// wearing its own symbol and saying what the row will do.
    func testASectionsNameOffersTheSectionWithItsOwnSymbol() throws {
        setSettingsResults(true)
        let row = try XCTUnwrap(rows("shortcuts").first)

        XCTAssertEqual(row.title, ShortcutsSection.title)
        XCTAssertEqual(row.subtitle, SettingsResults.opens)
        XCTAssertEqual(row.symbolName, ShortcutsSection.symbolName)
        XCTAssertEqual(row.action, .openSettings(ShortcutsSection.id))
    }

    /// A settings row is not a page, so it carries no URL — which keeps it out
    /// of §9.4's autofill and out of the dedupe's URL bucket.
    func testASettingsRowCarriesNoURL() throws {
        setSettingsResults(true)
        XCTAssertNil(try XCTUnwrap(rows("downloads").first).url)
    }

    /// Nobody types the section's name when they already know the name of the
    /// switch they are after.
    func testAKeywordFindsTheSectionItsTitleDoesNot() {
        setSettingsResults(true)
        XCTAssertEqual(rows("cookies").map(\.action), [.openSettings(PrivacySection.id)])
        XCTAssertEqual(rows("user agent").map(\.action), [.openSettings(GeneralSection.id)])
        // A group's own name finds the page the group is on.
        XCTAssertEqual(rows("downloads").map(\.action), [.openSettings(GeneralSection.id)])
    }

    /// The title outranks the keyword list, and a title the query starts
    /// outranks one that merely contains it. "ap" is the front of Appearance
    /// and is buried in Luna Control's "allow apps to control luna", and the
    /// section actually called Appearance is the one somebody typing two
    /// letters means.
    func testTheSectionWhoseNameTheQueryStartsComesFirst() throws {
        setSettingsResults(true)
        let found = rows("ap")
        XCTAssertEqual(try XCTUnwrap(found.first).action, .openSettings(AppearanceSection.id))
        XCTAssertGreaterThan(found.count, 1, "the keyword matches should still be offered, below it")
        // And the whole name still beats the front of it.
        XCTAssertGreaterThan(
            try XCTUnwrap(rows("appearance").first).score,
            try XCTUnwrap(found.first).score
        )
    }

    /// Settings rows sit below every destination and above the search row —
    /// somebody typing into an address bar is usually going somewhere, but
    /// what they typed still outranks an engine's guess at what they meant.
    func testSettingsRowsRankBelowCommandsAndAboveTheSearchRow() throws {
        let order = CommandBarSource.allCases
        let settings = try XCTUnwrap(order.firstIndex(of: .settings))
        let search = try XCTUnwrap(order.firstIndex(of: .search))
        XCTAssertLessThan(try XCTUnwrap(order.firstIndex(of: .command)), settings)
        XCTAssertLessThan(settings, search)
        XCTAssertLessThan(search, try XCTUnwrap(order.firstIndex(of: .keywordSettings)))
    }

    /// Reported from the running app: typing `google` put the Search section
    /// on the top row, because "google" is one of its keywords. A word the row
    /// does not show cannot outrank the word the user typed — the search is
    /// first and the section is still there, underneath it.
    func testAWebsiteNameSearchesTheWebBeforeItOffersTheSection() throws {
        setSettingsResults(true)
        let found = CommandBarRanking.merge(query: "google", sources: sources(), limit: 8)
        XCTAssertEqual(try XCTUnwrap(found.first).source, .search)
        XCTAssertEqual(found.map(\.source), [.search, .keywordSettings])
    }

    /// `⌘T`'s opening list is for getting somewhere, not for browsing an index
    /// of Settings — the same rule §9.2's app commands are held to.
    func testAnEmptyQueryOffersNoSettings() {
        setSettingsResults(true)
        XCTAssertTrue(rows("").isEmpty)
        XCTAssertTrue(rows("   ").isEmpty)
    }

    // MARK: - §3.4's switch

    func testTheSwitchIsOnByDefault() {
        XCTAssertTrue(SearchEngineSetting().settingsResults)
    }

    func testTurningItOffRemovesTheRowsAndNothingElse() {
        setSettingsResults(false)
        XCTAssertTrue(rows("shortcuts").isEmpty)
        // The floor is still there: a query always has something to do.
        let all = CommandBarRanking.merge(query: "shortcuts", sources: sources(), limit: 8)
        XCTAssertEqual(all.map(\.source), [.search])
    }

    /// §6: a key with no row in `SettingsDefaults` does not exist.
    func testTheSwitchHasADeclaredDefault() {
        XCTAssertTrue(SettingsDefaults.keys.contains(SearchSettings.settingsResultsKey))
    }

    // MARK: - The register

    func testEverySectionIsReachableAndCarriesItsOwnTitleAndSymbol() {
        let entries = SettingsSectionRegistry.commandBarEntries
        XCTAssertEqual(entries.map(\.id), SettingsSectionRegistry.ids)
        for (entry, section) in zip(entries, SettingsSectionRegistry.all) {
            XCTAssertEqual(entry.title, section.title)
            XCTAssertEqual(entry.symbolName, section.symbolName)
        }
    }

    /// Matching folds the query and compares against these as they stand, so a
    /// capital in one is a keyword nothing can reach.
    func testEveryKeywordIsLowercased() {
        for entry in SettingsSectionRegistry.commandBarEntries {
            for keyword in entry.keywords {
                XCTAssertEqual(keyword, keyword.lowercased(), "\(entry.id): \(keyword)")
            }
        }
    }
}
