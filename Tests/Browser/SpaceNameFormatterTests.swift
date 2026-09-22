//
//  SpaceNameFormatterTests.swift
//  LunaTests
//
//  §6.2's cap as the user meets it: the field stops rather than the commit
//  quietly shortening what was typed.
//
//  `BrowserSessionSpacesTests` covers the other half, where the cap is
//  enforced on everything that reaches the store. Both are needed — the store
//  is what a long name must not get into, and the field is the only place a
//  person finds out there is a limit at all.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class SpaceNameFormatterTests: XCTestCase {

    private let cap = BrowserSession.spaceNameCap

    /// `kept(of:)` answers nil when nothing has to change, so nil is the
    /// field accepting what arrived unaltered.
    func testAnOrdinaryNameIsLeftAlone() {
        XCTAssertNil(SpaceNameFormatter.kept(of: "Reading and Research"))
    }

    /// The last character that fits is still accepted — an off-by-one here is
    /// a field that stops one short of the cap everything else enforces.
    func testTheNameIsAcceptedRightUpToTheCap() {
        XCTAssertNil(SpaceNameFormatter.kept(of: String(repeating: "a", count: cap)))
    }

    func testOneCharacterPastItIsTrimmedBackToIt() {
        let kept = SpaceNameFormatter.kept(of: String(repeating: "a", count: cap + 1))
        XCTAssertEqual(kept?.count, cap)
    }

    /// A paste keeps what fits rather than being dropped. Refusing forty
    /// pasted characters because eight of them were over the line is the
    /// behaviour the cap is there to prevent, not a smaller version of it.
    func testALongPasteKeepsWhatFitsInsteadOfNothing() {
        let kept = SpaceNameFormatter.kept(of: "Client Work — Acme Corporation Limited, Europe")
        XCTAssertEqual(kept, "Client Work — Acme Corporation L")
    }

    /// The formatter counts what the cap counts. Cut by code unit instead, a
    /// name ending in a flag ends in half of one.
    func testItCountsCharactersRatherThanCodeUnits() {
        let kept = SpaceNameFormatter.kept(of: String(repeating: "🇩🇰", count: cap + 2))
        XCTAssertEqual(kept?.count, cap)
        XCTAssertEqual(kept?.hasSuffix("🇩🇰"), true)
    }

    /// And the field the sidebar puts in front of the user carries it, which
    /// is the wiring nothing else would catch.
    func testTheSidebarsNameFieldCarriesTheCap() {
        let space = Space(
            name: "Work",
            symbolName: BrowserSession.defaultSpaceSymbol,
            gradient: .defaultSpace
        )
        let editor = SpaceEditorView(space: space)
        editor.frame = NSRect(x: 0, y: 0, width: Tokens.Metric.sidebarWidth.default, height: 760)
        editor.layoutSubtreeIfNeeded()
        let fields = editable(in: editor)
        XCTAssertEqual(fields.count, 1, "§6.2's form has one field to type a name into")
        XCTAssertTrue(fields.first?.formatter is SpaceNameFormatter)
    }

    private func editable(in root: NSView) -> [NSTextField] {
        var found: [NSTextField] = []
        for child in root.subviews {
            if let field = child as? NSTextField, field.isEditable { found.append(field) }
            found += editable(in: child)
        }
        return found
    }
}
