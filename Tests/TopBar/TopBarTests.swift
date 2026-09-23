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

import BrowserKit
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

    /// Luna's own pages have a host and it is not a name. A tab on one of them
    /// carries no title until the page reports it, and the label it wore in the
    /// meantime was `archive`.
    func testNamesLunasOwnPagesRatherThanShowingTheirHost() {
        XCTAssertEqual(display("luna://history"), "History")
        // The name it shows before the load and the `<title>` the page sets
        // afterwards are the same string, so the label does not change under
        // the pointer.
        XCTAssertEqual(display("luna://history"), InternalPages.Page.history.name)
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

/// §4's alignment (`TopBarTabRun`): a centred run is centred in the bar,
/// not in the strip it happens to live in.
final class TopBarTabRunTests: XCTestCase {

    /// A strip inset 146 pt on the left and 193 on the right, inside a 1070 pt
    /// bar: the numbers the running app actually produces. The bar's centre is
    /// 389 pt along a 731 pt strip — nowhere near its middle, which is the
    /// whole bug.
    private let span: CGFloat = 731
    private let barCentre: CGFloat = 389

    private func pad(_ position: TabsPosition, run: CGFloat) -> CGFloat {
        TopBarTabRun.leadingPad(position: position, run: run, span: span, barCentre: barCentre)
    }

    func testACentredRunStraddlesTheBarsCentreNotTheStrips() {
        let run: CGFloat = 172
        XCTAssertEqual(pad(.centre, run: run) + run / 2, barCentre, accuracy: 0.5)
        // What it used to do, and what the eye caught: 23 pt off.
        XCTAssertEqual(pad(.centre, run: run) - (span - run) / 2, 23.5, accuracy: 0.5)
    }

    /// Centring is the only position that asks where the bar's middle is; left
    /// and right are about the strip's own edges and must not have moved.
    func testLeftAndRightStillMeasureFromTheStripsOwnEdges() {
        XCTAssertEqual(pad(.left, run: 172), 0)
        XCTAssertEqual(pad(.right, run: 172), span - 172)
    }

    /// A run too wide to reach the middle starts as close to it as it can
    /// rather than sliding out under the cluster beside it.
    func testAWideRunIsClampedIntoTheStrip() {
        XCTAssertEqual(pad(.centre, run: 700), 31, accuracy: 0.5)
        XCTAssertEqual(pad(.centre, run: span), 0)
        XCTAssertEqual(pad(.centre, run: span + 100), 0)
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
final class TopBarChipLayoutTests: XCTestCase {

    /// The one piece of §4 layout worth a test: `NSTextField.intrinsicContentSize`
    /// reports the glyph run without the cell's 2 pt title inset on each side,
    /// so a chip sized to it tail-truncates a title that fits it. The chip
    /// measures with `fittingSize` for that reason.
    func testAChipIsWideEnoughToDrawItsTitle() throws {
        let chip = TopBarButton(metric: TopBarMetrics.chip, glass: .none)
        chip.titleText = "example.com"
        chip.setFrameSize(chip.intrinsicContentSize)
        chip.layoutSubtreeIfNeeded()

        let label = try XCTUnwrap(chip.subviews.compactMap { $0 as? NSTextField }.first)
        let cell = try XCTUnwrap(label.cell)
        XCTAssertEqual(label.stringValue, "example.com")
        XCTAssertGreaterThanOrEqual(label.frame.width, cell.cellSize.width)
    }

    /// A tile is its metric and nothing more: §4 draws a kept tab as a bare
    /// icon, and a title left on one would widen the run it is standing in.
    func testATileWithNoTitleIsItsMetric() {
        let tile = TopBarButton(metric: TopBarMetrics.tile, glass: .none)
        XCTAssertEqual(tile.intrinsicContentSize, TopBarMetrics.tile.size)
    }

    /// One long page title must not spend the room every other tab needs.
    func testALongTitleStopsAtTheCeiling() {
        let chip = TopBarButton(metric: TopBarMetrics.chip, glass: .none)
        chip.titleText = String(repeating: "long title ", count: 20)
        XCTAssertEqual(chip.intrinsicContentSize.width, TopBarMetrics.chipCeiling)
    }
}
