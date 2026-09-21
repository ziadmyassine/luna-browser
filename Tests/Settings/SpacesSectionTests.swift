//
//  SpacesSectionTests.swift
//  LunaTests
//
//  Goals 12 and 13 of the Spaces wave: the four Settings rows that are no
//  longer dimmed for a missing method, the Space → Profile fan-out label, and
//  §6.4's deletion dialog.
//
//  The dialog strings are asserted as pure functions rather than by opening an
//  `NSAlert`: wording that can only be checked by clicking it is wording nobody
//  checks. These are the sentences that have to beat Firefox's (tabs, never the
//  data) and Chrome's (the data, never the windows). The key map lives in
//  `SpacesMenuTests.swift`.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class SpacesSectionTests: XCTestCase {

    // MARK: - Goal 12: nothing is dimmed for a missing method

    /// The rows whose `disabledReason` used to name the call they were waiting
    /// for — "BrowserSession can create and delete Spaces, but cannot yet
    /// rename or reorder one". The reason went; the row stayed (§30.4).
    func testRenameReorderAndPictureAreAllLive() {
        let rows = Self.rowsForOneSpace()
        for title in ["Name", "Position in the sidebar", "Picture"] {
            let row = rows.first { $0.accessibilityLabel() == title || Self.title(of: $0) == title }
            XCTAssertNotNil(row, "no row titled “\(title)”")
            // `SettingsRowView.acceptsFirstResponder` is `!isEnabled`: §4 puts a
            // disabled row into the key-view loop because the control AppKit
            // will not focus cannot carry its own reason.
            XCTAssertFalse(row?.acceptsFirstResponder ?? true, "“\(title)” is still dimmed")
            XCTAssertNil(row?.accessibilityHelp(), "“\(title)” still carries a disabled reason")
        }
    }

    /// Icon and gradient left the row list; they did not leave the app.
    /// They are grids on the card's corner button now (`SpaceAppearanceView`),
    /// and the thing worth asserting is that the move cost nothing: every one
    /// of §8.2's twelve pairs is still offered, §13.6's way back to neutral
    /// leads them, and all twelve icons are still there.
    func testEveryColourAndIconSurvivedTheMoveOffTheRowList() {
        let choices = SpacesSection.appearanceChoices
        XCTAssertEqual(choices.gradients.count, Tokens.Gradient.spacePalette.count + 1)
        XCTAssertEqual(choices.gradients.first, "No Colour", "§13.6's way out is not the first swatch")
        for name in Tokens.Gradient.spacePaletteNames {
            XCTAssertTrue(choices.gradients.contains(name), "“\(name)” is not offered any more")
        }
        XCTAssertEqual(choices.icons.count, SpacesSection.symbols.count)
        XCTAssertEqual(Set(choices.icons).count, choices.icons.count, "two icons share a label")
    }

    /// The grid is built against the Space it was opened for, so the swatch and
    /// the symbol it is already wearing are the ones marked — a picker that
    /// opens with nothing selected is a picker that cannot tell you what you
    /// have.
    func testTheAppearanceGridOpensOnTheSpacesOwnColourAndIcon() {
        let space = Space(name: "Work", symbolName: "flask", gradient: Tokens.Gradient.spacePalette[3])
        let view = SpaceAppearanceView(space: space, onGradient: { _ in }, onIcon: { _ in })
        let swatches = Self.descendants(of: view).compactMap { $0 as? SpaceSwatchChip }
        let symbols = Self.descendants(of: view).compactMap { $0 as? SpaceSymbolChip }
        XCTAssertEqual(swatches.filter(\.isChosen).map(\.gradient), [space.gradient])
        XCTAssertEqual(symbols.filter(\.isChosen).map(\.symbolName), [space.symbolName])
    }

    /// §9's fan-out moved off the profile row and onto the card's head, where
    /// it describes the Space rather than captioning a popup. It has to still
    /// be somewhere — this is the assertion that it is.
    func testTheFanOutIsOnTheCardsHead() {
        let space = Self.space("Work")
        let card = SpaceCardView(
            space: space,
            subtitle: SpacesSection.fanOut(space, session: nil),
            rows: [],
            onAppearance: { _ in }
        )
        let text = Self.descendants(of: card).compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(text.contains(space.name), "the card does not name its Space")
        XCTAssertTrue(text.contains { $0.contains("Favorite") }, "\(text)")
    }

    /// Whatever the rows say, none of them may still be advertising a method
    /// that now exists. §2's search indexes the reason, which is what makes
    /// this checkable without reaching into another agent's layout.
    func testNoRowStillNamesAMissingMethod() {
        let terms = SpacesSection().searchIndex.joined(separator: " ")
        for stale in [
            "cannot yet rename or reorder",
            "is fixed when the space is created",
            "browserstore has no delete(profileid:)"
        ] {
            XCTAssertFalse(terms.contains(stale), "a row still says “\(stale)”")
        }
    }

    /// The last Space is the one row that is still allowed to be dimmed, and
    /// its reason is a rule rather than a missing call.
    func testTheLastSpaceStillCannotBeDeleted() {
        let only = Self.space("Personal")
        let rows = SettingsRowView.rows(in: Self.host(SpacesSection().spaceRows(
            only, at: 0, of: [only], session: nil
        )))
        let delete = rows.first { Self.title(of: $0) == "Delete this Space" }
        XCTAssertEqual(delete?.acceptsFirstResponder, true)
        XCTAssertEqual(delete?.accessibilityHelp(), "A window must always have at least one Space.")
    }

    // MARK: - Goal 13: what the card's head says

    /// It was §9's fan-out — "Work profile · shared with 3 Spaces · 4
    /// Favorites" — the line no other browser shows, and the answer to the
    /// most-reported conceptual confusion in every review of Arc. `v7` answered
    /// that confusion by ending the sharing instead of explaining it, so what
    /// is left to say is whose tiles these are.
    func testTheCardsHeadNamesTheSpaceAndCountsItsFavorites() {
        let label = SpacesSection.fanOutLabel(spaceName: "Work", favorites: 4)
        XCTAssertTrue(label.contains("Work"), label)
        XCTAssertTrue(label.contains("4 Favorites"), label)
        XCTAssertFalse(label.contains("shared"), "there is nothing left to share")
    }

    /// One Favorite must not read "1 Favorites".
    func testOneFavoriteIsSingular() {
        let label = SpacesSection.fanOutLabel(spaceName: "Personal", favorites: 1)
        XCTAssertTrue(label.contains("1 Favorite"), label)
        XCTAssertFalse(label.contains("1 Favorites"), label)
    }

    /// The head names the Space once. It named it twice for as long as the
    /// second one was the Profile's name — the card read "Personal" over
    /// "Personal · 3 Favorites" once a Space owned its own jar, which is one
    /// word of information and two lines of it.
    func testTheCardsHeadDoesNotSayTheNameTwice() {
        let space = Self.space("Work")
        let subtitle = SpacesSection.fanOut(space, session: nil)
        XCTAssertFalse(subtitle.contains(space.name), subtitle)
        XCTAssertTrue(subtitle.contains("Favorite"), subtitle)
    }

    /// The picker in `Spaces+Dialogs` lists several Spaces at once, so that one
    /// still has to carry the name. Both labels come off the same count.
    func testThePickersLabelStillNamesItsSpace() {
        XCTAssertTrue(SpacesSection.fanOutLabel(spaceName: "Work", favorites: 2).contains("Work"))
        XCTAssertEqual(SpacesSection.favoritesLabel(2), "2 Favorites")
        XCTAssertEqual(SpacesSection.favoritesLabel(1), "1 Favorite")
    }

    /// Settings' own list called the section "Spaces & Profiles" for as long as
    /// there were two lists in it. There is one.
    func testTheSectionIsNamedForTheOneThingItHolds() {
        XCTAssertEqual(SpacesSection.title, "Spaces")
    }

    /// §2's search still finds a Space by the words a user would type for the
    /// thing that used to be a Profile — the concept went, the vocabulary
    /// people arrive with did not.
    func testSearchStillFindsASpaceByTheOldVocabulary() {
        let space = Self.space("Work")
        let terms = SpacesSection().spaceRows(space, at: 0, of: [space], session: nil)
            .flatMap(\.terms)
        for word in ["picture", "profile picture", "cookies"] {
            XCTAssertTrue(terms.contains(word), "“\(word)” finds nothing: \(terms)")
        }
    }

    // MARK: - §6.4's deletion dialog

    /// Firefox warns about the tab count and says nothing about the cookies and
    /// logins it destroys. Chrome itemises the data and never says it
    /// force-closes your windows. Luna says both.
    func testTheDeletionDialogNamesTabsAndData() {
        let detail = SpacesSection.deletionDetail(spaceName: "Work", tabs: 12, sites: 34)
        XCTAssertTrue(detail.contains("12 open tabs"), detail)
        XCTAssertTrue(detail.contains("cookies, logins and site data for 34 sites"), detail)
        XCTAssertTrue(detail.contains("Undo"), detail)
    }

    /// The clause that used to have two forms. A shared profile's jar was not
    /// deleted with the Space that named it, so the sentence had to say whether
    /// the cookies were going — and §6.4's example sentence promised the
    /// deletion and the sharing in one breath, which was false in exactly the
    /// case it existed for. There is one true thing to say now, and the part
    /// worth holding is that it never overpromises: no other Space is signed
    /// out, because no other Space could be.
    func testTheDialogPromisesNothingAboutOtherSpaces() {
        let detail = SpacesSection.deletionDetail(spaceName: "Work", tabs: 12, sites: nil)
        XCTAssertTrue(detail.contains("No other Space is signed out"), detail)
        XCTAssertTrue(detail.contains("Work's cookies"), detail)
    }

    func testTheDeletionDialogIsSingularForOneTab() {
        let detail = SpacesSection.deletionDetail(spaceName: "Work", tabs: 1, sites: 2)
        XCTAssertTrue(detail.contains("1 open tab is kept"), detail)
        XCTAssertFalse(detail.contains("1 open tabs"), detail)
    }

    func testTheDeletionTitleNamesTheSpace() {
        XCTAssertEqual(SpacesSection.deletionTitle(Self.space("Work")), "Delete “Work”?")
    }

    func testSpaceListsReadAsEnglish() {
        XCTAssertEqual(SpacesSection.list([]), "")
        XCTAssertEqual(SpacesSection.list(["Research"]), "Space Research")
        XCTAssertEqual(SpacesSection.list(["Research", "Side Project"]), "Spaces Research and Side Project")
        XCTAssertEqual(SpacesSection.list(["A", "B", "C"]), "Spaces A, B and C")
    }

    // MARK: - Bits

    private static func space(_ name: String) -> Space {
        Space(name: name, symbolName: "square.grid.2x2", gradient: .defaultSpace)
    }

    private static func rowsForOneSpace() -> [SettingsRowView] {
        let spaces = [space("Personal"), space("Work")]
        return SettingsRowView.rows(in: host(SpacesSection().spaceRows(
            spaces[1], at: 1, of: spaces, session: nil
        )))
    }

    /// `SettingsRowView.rows(in:)` walks a subtree, so the rows need one.
    private static func host(_ rows: [(view: NSView, terms: [String])]) -> NSView {
        let host = NSView()
        for row in rows { host.addSubview(row.view) }
        return host
    }

    /// An enabled row is a plain `.group` with no accessibility label of its
    /// own, so the title has to come off the label it draws.
    private static func title(of row: SettingsRowView) -> String? {
        row.accessibilityLabel() ?? Self.firstLabel(in: row)
    }

    /// Every view under `view`, itself excluded.
    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private static func firstLabel(in view: NSView) -> String? {
        for child in view.subviews {
            if let field = child as? NSTextField, !field.stringValue.isEmpty { return field.stringValue }
            if let found = firstLabel(in: child) { return found }
        }
        return nil
    }
}

/// `LunaTests` is hosted by `Luna.app`. Every `xcodebuild test` therefore
/// launches the real `AppDelegate`, and `applicationDidFinishLaunching` opens a
/// `BrowserStore` before the first test method runs. Until `databaseURL` grew
/// its XCTest branch that store was the user's own database: the test host
/// held it open for the whole run — locking the owner out of his browser with a
/// raw "database is locked" dialog — and applied this wave's migration to his
/// real tabs on the way in.
///
/// No test asked for that and no test could have prevented it by being careful
/// with its own fixture path, because the offending open is app launch, not a
/// test. This is the one assertion that keeps the branch alive.
@MainActor
final class AppDelegateDatabaseTests: XCTestCase {

    func testTheTestHostNeverOpensTheRealDatabase() throws {
        XCTAssertTrue(AppDelegate.isRunningTests, "XCTestConfigurationFilePath is not set in this host")
        let path = AppDelegate.databaseURL.path
        XCTAssertFalse(path.contains("Application Support"), path)
        XCTAssertTrue(path.hasSuffix("luna.sqlite"), path)
        // Per run, so two runs cannot share a lock either.
        XCTAssertNotEqual(AppDelegate.databaseURL, AppDelegate.databaseURL)
    }

    /// The shipping app is unchanged: without the environment key the path is
    /// Application Support, exactly as before.
    func testTheShippingPathIsStillApplicationSupport() throws {
        XCTAssertNil(ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"].flatMap { _ -> String? in
            nil
        })
        let support = try XCTUnwrap(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        )
        XCTAssertTrue(support.path.contains("Application Support"))
    }
}
