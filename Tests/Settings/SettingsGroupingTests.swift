//
//  SettingsGroupingTests.swift
//  LunaTests
//
//  The three distances the pane uses to say what belongs to what, and the one
//  width its dialogs have to state for themselves.
//
//  Both were found by looking at the window rather than at the code: six Space
//  cards a full group apart read as six sections, and every field in every
//  dialog the pane raises came out a few points wide.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class SettingsGroupingTests: XCTestCase {

    private func body(cards: Int, inList: Bool) -> SettingsBody {
        let body = SettingsBody()
        body.heading(SettingsRow.heading("Spaces", accessory: NSView()), terms: [])
        for index in 0..<cards {
            body.card("Card \(index)", [(SettingsRow.note("row"), ["row"])], inList: inList)
        }
        return body
    }

    private func gap(after index: Int, in body: SettingsBody) -> CGFloat {
        let child = body.view.arrangedSubviews[index]
        let custom = body.view.customSpacing(after: child)
        // `NSStackView` returns its own `spacing` as a sentinel for "none set".
        return custom == NSStackView.useDefaultSpacing ? body.view.spacing : custom
    }

    // MARK: - What sits how far from what

    /// A run of cards that are the same kind of thing is a list, and a list is
    /// tighter than one group and the next.
    func testCardsInARunSitAListGapApart() {
        let body = body(cards: 3, inList: true)
        XCTAssertEqual(gap(after: 1, in: body), Tokens.Metric.settingsListGap)
        XCTAssertEqual(gap(after: 2, in: body), Tokens.Metric.settingsListGap)
    }

    /// And a card that is not in one keeps the full distance, so the pane does
    /// not quietly become a single list of everything.
    func testALoneCardKeepsTheGroupGap() {
        let body = body(cards: 3, inList: false)
        XCTAssertEqual(gap(after: 1, in: body), Tokens.Metric.settingsGroupGap)
    }

    /// The run's first card is still a group's distance from whatever came
    /// before it — here, its own heading, which sets the tighter gap itself.
    func testTheGapBelongsToThePairAndNotToTheCard() {
        let body = body(cards: 3, inList: true)
        XCTAssertEqual(gap(after: 0, in: body), Tokens.Metric.chromeGap, "the heading lost its card")
    }

    /// A note after a run is a footnote on the card above it, not the opening
    /// line of the next group — and the run must not have swallowed that.
    func testANoteAfterARunStillBelongsToIt() {
        let body = body(cards: 2, inList: true)
        body.loose(SettingsRow.note("A profile is a set of cookies and logins."), terms: ["profile"])
        XCTAssertEqual(gap(after: 2, in: body), Tokens.Metric.chromeGap)
    }

    // MARK: - The dialogs' one width

    /// Adding a view to an `NSStackView` turns its autoresizing mask off and
    /// drops the frame it was built with, so an empty field was sized to its
    /// own content — which is nothing. Every dialog in the pane showed it.
    func testEveryFieldInADialogIsTheFullWidthOfThePill() {
        let field = NSTextField(frame: NSRect(origin: .zero, size: Tokens.Metric.urlPill.size))
        field.placeholderString = "New Profile"
        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        picker.addItem(withTitle: "Its own profile — separate cookies and logins")

        let stack = SpacesSection.stack([field, picker])
        stack.layoutSubtreeIfNeeded()
        XCTAssertEqual(field.frame.width, Tokens.Metric.urlPill.width)
        XCTAssertEqual(picker.frame.width, Tokens.Metric.urlPill.width)
    }

    /// And the stack is as tall as what is in it. The old arithmetic multiplied
    /// one control's height by the number of them, which a popup and a field
    /// do not share.
    func testTheStackIsAsTallAsWhatItHolds() {
        let field = NSTextField(frame: NSRect(origin: .zero, size: Tokens.Metric.urlPill.size))
        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        picker.addItem(withTitle: "Its own profile")
        let stack = SpacesSection.stack([field, picker])
        stack.layoutSubtreeIfNeeded()
        XCTAssertEqual(
            stack.frame.height,
            field.frame.height + Tokens.Metric.rowGap + picker.frame.height,
            accuracy: 0.5
        )
    }

    // MARK: - §6.2's card

    /// §9's picture is a row on the Space's own card. It was a row on a
    /// Profile's card until `v7` deleted the Profile and moved the column.
    func testASpaceCardCarriesThePictureRow() {
        let space = Space(name: "Personal", symbolName: "moon", gradient: .defaultSpace)
        let rows = SpacesSection().spaceRows(space, at: 0, of: [space], session: nil)
        XCTAssertTrue(rows.contains { $0.terms.contains("picture") }, "§9's picture row is missing")
    }

    /// The count it was carrying is not lost — it is the reason Delete is
    /// dimmed, which is where it changes what the user can do.
    func testTheReasonDeleteIsDimmedCountsTheSpaces() {
        XCTAssertTrue(SpacesSection.inUseReason(3).contains("3 Spaces are using"), SpacesSection.inUseReason(3))
        XCTAssertTrue(SpacesSection.inUseReason(1).contains("1 Space is using"), SpacesSection.inUseReason(1))
    }
}
