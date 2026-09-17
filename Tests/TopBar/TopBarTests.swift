//
//  TopBarTests.swift
//  LunaTests
//
//  The two pieces of the §4 top bar that are logic rather than layout: what the
//  URL pill puts on screen, and the claim that the action capsule hosts a
//  variable number of items (§30.14) — which is the only future-proofing M1
//  budgeted for, so it is worth a test that fails if it quietly stops being
//  true.
//

import XCTest
@testable import Luna

final class TopBarDomainTests: XCTestCase {

    private func display(_ string: String) -> String {
        TopBarDomain.display(for: URL(string: string))
    }

    func testDropsWWWButKeepsEveryOtherSubdomain() {
        XCTAssertEqual(display("https://www.apple.com/mac"), "apple.com")
        // Not eTLD+1: collapsing to the last two labels would hand this page
        // github.com's identity, which §3.2 calls "meaningful".
        XCTAssertEqual(display("https://docs.github.com/en"), "docs.github.com")
    }

    func testIgnoresPathQueryAndCase() {
        XCTAssertEqual(display("https://GitHub.com/luna?tab=1#x"), "github.com")
    }

    func testFallsBackToTheWholeStringWhenThereIsNoHost() {
        XCTAssertEqual(display("about:blank"), "about:blank")
        XCTAssertEqual(TopBarDomain.display(for: nil), "")
    }

    func testResolveAddsTheMissingScheme() {
        XCTAssertEqual(TopBarDomain.resolve("apple.com")?.absoluteString, "https://apple.com")
        XCTAssertEqual(TopBarDomain.resolve("  apple.com  ")?.absoluteString, "https://apple.com")
    }

    func testResolveKeepsAnExplicitScheme() {
        XCTAssertEqual(TopBarDomain.resolve("http://apple.com")?.absoluteString, "http://apple.com")
    }

    /// Anything that is not an address is a search, and search belongs to the
    /// Command Bar — the pill must say "not mine" rather than guess a URL.
    func testResolveRejectsSearchText() {
        XCTAssertNil(TopBarDomain.resolve("swift concurrency"))
        XCTAssertNil(TopBarDomain.resolve("apple"))
        XCTAssertNil(TopBarDomain.resolve(""))
    }
}

@MainActor
final class TopBarActionCapsuleTests: XCTestCase {

    private func item(_ id: String) -> TopBarActionItem {
        TopBarActionItem(id: id, symbolName: "plus", label: id) {}
    }

    /// §30.14: extension buttons dock into this capsule in v2. If its width
    /// stopped tracking its item count, that would mean re-laying out the whole
    /// right side of the bar later — which is exactly what building it this way
    /// was meant to avoid.
    func testWidthGrowsWithItemCountAndHeightDoesNot() {
        let capsule = TopBarActionCapsule(frame: .zero)
        capsule.items = [item("a"), item("b"), item("c")]
        let three = capsule.intrinsicContentSize
        capsule.items = [item("a"), item("b"), item("c"), item("d"), item("e")]
        let five = capsule.intrinsicContentSize

        XCTAssertGreaterThan(five.width, three.width)
        XCTAssertEqual(five.height, three.height)
        XCTAssertEqual(
            five.width - three.width,
            2 * (TopBarMetrics.capsuleItem.width + TopBarMetrics.gap),
            accuracy: 0.001
        )
    }

    func testEveryItemIsReachableByIdSoAPopoverCanAnchorToIt() {
        let capsule = TopBarActionCapsule(frame: .zero)
        capsule.items = [item("a"), item("downloads"), item("c")]
        XCTAssertNotNil(capsule.view(for: "downloads"))
        XCTAssertNil(capsule.view(for: "nope"))
    }

    /// Icon-only controls need an explicit VoiceOver label (§8, §21.1).
    func testItemsCarryTheirAccessibilityLabel() throws {
        let capsule = TopBarActionCapsule(frame: .zero)
        capsule.items = [item("Downloads")]
        let button = try XCTUnwrap(capsule.view(for: "Downloads"))
        XCTAssertEqual(button.accessibilityLabel(), "Downloads")
    }
}

@MainActor
final class TopBarURLPillLayoutTests: XCTestCase {

    /// The one piece of §4 layout worth a test: `NSTextField.intrinsicContentSize`
    /// reports the glyph run *without* the cell's 2 pt title inset on each side,
    /// so a label framed to it tail-truncates a domain that fits the pill with
    /// 90 pt to spare. The pill measures with `fittingSize` for that reason.
    func testTheDomainLabelIsWideEnoughToDrawItsString() throws {
        let pill = TopBarURLPill(frame: NSRect(origin: .zero, size: Tokens.Metric.urlPill.size))
        pill.apply(url: URL(string: "https://example.com"), icon: nil, tint: nil)
        pill.layoutSubtreeIfNeeded()

        let label = try XCTUnwrap(pill.subviews.compactMap { $0 as? NSTextField }.first)
        let cell = try XCTUnwrap(label.cell)
        XCTAssertEqual(label.stringValue, "example.com")
        XCTAssertGreaterThanOrEqual(label.frame.width, cell.cellSize.width)
    }
}
