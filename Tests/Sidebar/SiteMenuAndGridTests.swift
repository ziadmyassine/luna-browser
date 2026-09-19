//
//  SiteMenuAndGridTests.swift
//  LunaTests
//
//  Two surfaces that are arithmetic rather than appearance, so they are
//  asserted here instead of eyeballed: §3.3's grid shape, and the rule list
//  behind §3.2's Local Network permission.
//
//  The rule list is the one that would otherwise fail silently. WebKit refuses
//  a pattern its URL-filter engine cannot parse by *throwing*, and the compile
//  is a fire-and-forget `Task` — so a typo in a regex would leave
//  `localNetworkList` nil, nothing blocked, and a checkmark in the menu that
//  means nothing at all.
//

import BrowserKit
import WebKit
import XCTest
@testable import Luna

/// §3.3's grid as a set of views, which is where the *arrival* of a tile can go
/// wrong in a way arithmetic cannot see.
@MainActor
final class EssentialsGridArrivalTests: XCTestCase {

    private func grid() -> EssentialsGridView {
        let grid = EssentialsGridView()
        grid.frame = NSRect(x: 0, y: 0, width: 280, height: 120)
        return grid
    }

    private func tabs(_ count: Int) -> [Tab] {
        (0..<count).map { index in
            Tab(
                spaceID: UUID(),
                kind: .essential,
                url: URL(string: "https://example.com/\(index)")!,
                order: index
            )
        }
    }

    /// **A tile that has just been pinned lands in its slot.** It is a fresh
    /// view, so its frame is the grid's own origin until something places it,
    /// and the pass that places it is the animated one — so the tile flew up
    /// from the foot of the leading edge into the slot the lift had just come
    /// to rest in. The tiles that were already there still travel; only the
    /// one with nowhere to travel *from* is exempt.
    func testANewlyPinnedTileDoesNotFlyInFromTheCorner() {
        let grid = grid()
        let pinned = tabs(3)
        grid.show(Array(pinned.prefix(2)), activeTabID: nil)
        grid.layoutSubtreeIfNeeded()
        grid.show(pinned, activeTabID: nil)
        grid.layoutSubtreeIfNeeded()

        let tiles = grid.subviews.compactMap { $0 as? GlassButton }
        XCTAssertEqual(tiles.count, 3)
        XCTAssertEqual(tiles[2].frame, grid.slotRect(at: 2))
        XCTAssertNil(tiles[2].layer?.animation(forKey: "position"), "the new tile flew to its slot")
    }
}

@MainActor
final class EssentialsGridShapeTests: XCTestCase {

    /// The shapes Martin drew, one per reference: 1, 2, 3 and 4 across in a
    /// single row, then 3 + 2, 3 + 3, 4 + 3 and 4 + 4.
    func testShapeFollowsTheTileCount() {
        let expected: [Int: (rows: Int, columns: Int)] = [
            1: (1, 1), 2: (1, 2), 3: (1, 3), 4: (1, 4),
            5: (2, 3), 6: (2, 3), 7: (2, 4), 8: (2, 4)
        ]
        for (count, shape) in expected.sorted(by: { $0.key < $1.key }) {
            let actual = EssentialsGridView.shape(for: count)
            XCTAssertEqual(actual.rows, shape.rows, "\(count) tiles")
            XCTAssertEqual(actual.columns, shape.columns, "\(count) tiles")
        }
    }

    /// Past eight it keeps going by the same rule rather than falling over: as
    /// few rows as will hold them, then spread evenly across those rows.
    func testShapeKeepsGoingPastTheReference() {
        XCTAssertEqual(EssentialsGridView.shape(for: 9).columns, 3)
        XCTAssertEqual(EssentialsGridView.shape(for: 9).rows, 3)
        XCTAssertEqual(EssentialsGridView.shape(for: 12).columns, 4)
        XCTAssertEqual(EssentialsGridView.shape(for: 13).rows, 4)
    }

    /// An empty grid still has to answer, because `slotRect(at:)` divides by the
    /// column count on every layout pass — including the ones where nothing is
    /// pinned and §6.6 is only holding the grid open.
    func testEmptyGridDividesByOneRatherThanZero() {
        XCTAssertEqual(EssentialsGridView.shape(for: 0).rows, 0)
        XCTAssertEqual(EssentialsGridView.shape(for: 0).columns, 1)
    }

    /// Every count up to four rows is one row of tiles per row of tiles: no
    /// shape may leave a row empty, and none may need more columns than the
    /// ceiling allows.
    func testEveryShapeHoldsEveryTile() {
        for count in 1 ... 40 {
            let shape = EssentialsGridView.shape(for: count)
            XCTAssertLessThanOrEqual(shape.columns, 4, "\(count) tiles")
            XCTAssertGreaterThanOrEqual(shape.rows * shape.columns, count, "\(count) tiles")
            XCTAssertLessThan((shape.rows - 1) * shape.columns, count, "\(count) tiles leaves a row empty")
        }
    }
}

@MainActor
final class LocalNetworkRuleTests: XCTestCase {

    /// The whole point: WebKit accepts every pattern. A throw here is the
    /// difference between a permission and a decoration — and it has already
    /// caught one, `([:/]|$)`, which WebKit's URL-filter engine refuses with
    /// "Disjunctions are not supported yet".
    func testWebKitCompilesTheLocalNetworkList() async throws {
        let store = try XCTUnwrap(WKContentRuleListStore.default())
        let identifier = "luna-tests-localnetwork-\(UUID().uuidString)"
        let list = try await store.compileContentRuleList(
            forIdentifier: identifier,
            encodedContentRuleList: ContentBlocker.localNetworkRules
        )
        XCTAssertNotNil(list)
        try? await store.removeContentRuleList(forIdentifier: identifier)
    }

    /// The JSON has to survive the double escaping: the patterns are Swift
    /// literals, so `\\.` is already one backslash by the time it is written
    /// into a JSON string that wants two.
    func testRulesAreValidJSONWithOneRulePerPattern() throws {
        let data = try XCTUnwrap(ContentBlocker.localNetworkRules.data(using: .utf8))
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(rules.count, ContentBlocker.privateAddressPatterns.count)
        for rule in rules {
            let trigger = try XCTUnwrap(rule["trigger"] as? [String: Any])
            XCTAssertNotNil(trigger["url-filter"] as? String)
            // Without this a page served from localhost could not load its own
            // assets, and Luna would be unusable to develop in.
            let exempt = try XCTUnwrap(trigger["unless-top-url"] as? [String])
            XCTAssertEqual(exempt.count, ContentBlocker.privateAddressPatterns.count)
        }
    }

    /// The defaults the menu shows before anybody has answered: a video floats
    /// when you leave it, and a page does not reach the network in the room.
    func testPermissionDefaults() {
        XCTAssertTrue(BrowserStore.SitePermission.automaticPictureInPicture.defaultsToAllowed)
        XCTAssertFalse(BrowserStore.SitePermission.localNetwork.defaultsToAllowed)
    }
}

/// §3.2a's glyphs, which fail by *disappearing*.
///
/// Both halves of that are here. A misspelt SF Symbol makes no image and no
/// fallback box — the label is drawn without it and the item is one gap out of
/// line with its neighbours — and the tab stop is what keeps the words in a
/// column in the first place, so an item whose symbol did not resolve must
/// still start its word where the rest of them start theirs.
@MainActor
final class SiteMenuGlyphTests: XCTestCase {

    func testEveryGlyphTheSiteMenuDrawsExists() {
        for name in SiteMenu.Glyph.all {
            XCTAssertNotNil(
                NSImage(systemSymbolName: name, accessibilityDescription: nil),
                "the system has no symbol called \(name)"
            )
        }
    }

    func testALabelCarriesItsGlyphAndLinesTheWordUp() {
        let label = SidebarMenu.label(symbol: SiteMenu.Glyph.secure, title: "Connection is secure")
        XCTAssertNotNil(
            label.attribute(.attachment, at: 0, effectiveRange: nil),
            "the glyph is the one thing `NSMenuItem.image` cannot do"
        )
        XCTAssertEqual(label.string, "\u{FFFC}\tConnection is secure")

        let paragraph = label.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(
            paragraph?.tabStops.first?.location,
            Tokens.Metric.menuGlyph + Tokens.Metric.rowIconGap
        )
    }

    /// A name the system does not have costs the icon and nothing else: no
    /// crash, no empty attachment, and the word still starts in the column.
    func testALabelWithoutAGlyphKeepsItsWordInTheColumn() {
        let label = SidebarMenu.label(symbol: "luna.not.a.symbol", title: "Copy Link")
        XCTAssertEqual(label.string, "\tCopy Link")
        let paragraph = label.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(
            paragraph?.tabStops.first?.location,
            Tokens.Metric.menuGlyph + Tokens.Metric.rowIconGap
        )
    }
}
