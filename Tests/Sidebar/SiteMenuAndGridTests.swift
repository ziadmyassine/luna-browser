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
