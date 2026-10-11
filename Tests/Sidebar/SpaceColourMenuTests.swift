//
//  SpaceColourMenuTests.swift
//  LunaTests
//
//  §8.2a's Custom in the dot's right-click colour menu: present, ticked for a
//  custom pair, and aimed at the Space the menu was built for. The colour
//  panel is stubbed, so nothing is shown.
//

import XCTest
import BrowserKit
@testable import Luna

@MainActor
final class SpaceColourMenuTests: XCTestCase {

    private let custom = Tokens.Gradient.custom(from: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))

    private func menu(
        for gradient: GradientPair,
        setGradient: @escaping (GradientPair) -> Void = { _ in },
        pickCustom: @escaping (GradientPair, @escaping (GradientPair) -> Void) -> Void = { _, _ in }
    ) -> NSMenu {
        SidebarMenu.colours(
            for: Space(name: "Work", symbolName: "square.grid.2x2", gradient: gradient),
            in: NSAppearance(named: .aqua)!,
            setGradient: setGradient,
            edit: {},
            pickCustom: pickCustom
        )
    }

    private func customItem(_ menu: NSMenu) -> NSMenuItem? {
        menu.items.first { $0.title == "Custom Colour…" }
    }

    func testTheMenuOffersCustomColour() {
        XCTAssertNotNil(customItem(menu(for: .defaultSpace)))
    }

    func testCustomIsTickedOnlyForACustomPair() {
        XCTAssertEqual(customItem(menu(for: custom))?.state, .on)
        XCTAssertEqual(customItem(menu(for: Tokens.Gradient.spacePalette[0]))?.state, .off)
        XCTAssertEqual(customItem(menu(for: Tokens.Gradient.neutral))?.state, .off)
        let ticked = menu(for: custom).items.filter { $0.state == .on }
        XCTAssertEqual(ticked.map(\.title), ["Custom Colour…"], "one colour is ticked at a time")
    }

    /// The panel opens on the Space's own colour, and what it hands back is
    /// written to that Space.
    func testChoosingCustomWritesThePickToThisSpace() throws {
        var opened: GradientPair?
        var written: GradientPair?
        let built = menu(
            for: Tokens.Gradient.spacePalette[2],
            setGradient: { written = $0 },
            pickCustom: { current, onPick in
                opened = current
                onPick(self.custom)
            }
        )
        let item = try XCTUnwrap(customItem(built))
        built.performActionForItem(at: built.index(of: item))
        XCTAssertEqual(opened, Tokens.Gradient.spacePalette[2])
        XCTAssertEqual(written, custom)
    }
}
