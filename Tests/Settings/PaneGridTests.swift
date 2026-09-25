//
//  PaneGridTests.swift
//  LunaTests
//
//  §1's text grid, and the one piece of type that is deliberately not on it.
//

import XCTest
@testable import Luna

/// A group's name is the label of the card under it, so it starts where that
/// card starts. It used to start where the card's rows start, a `cardInset`
/// further in — which is the thing this asserts can never come back.
@MainActor
final class SettingsGroupHeaderTests: XCTestCase {

    private func laidOutGroup(title: String) -> NSView {
        let group = SettingsRow.group(title, [SettingsRow.status("On launch")])
        group.frame = NSRect(x: 0, y: 0, width: 420, height: 200)
        group.layoutSubtreeIfNeeded()
        return group
    }

    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        for child in view.subviews {
            if let match = child as? T { return match }
            if let match = find(type, in: child) { return match }
        }
        return nil
    }

    /// The alignment rect, not the frame. A bezel-less `NSTextField` is
    /// laid out by its alignment rect and its frame hangs 2 pt outside it on
    /// each side, so two labels that line up on screen have frames that do not
    /// — and a test written against frames would be asserting AppKit's text
    /// bearing rather than this window's grid.
    private func aligned(_ view: NSView, in root: NSView) -> NSRect {
        guard let parent = view.superview else { return view.frame }
        return root.convert(view.alignmentRect(forFrame: view.frame), from: parent)
    }

    private func label(_ title: String, in view: NSView) -> NSTextField? {
        for child in view.subviews {
            if let field = child as? NSTextField, field.stringValue == title { return field }
            if let match = label(title, in: child) { return match }
        }
        return nil
    }

    func testAGroupsNameStartsWhereItsCardStarts() {
        let group = laidOutGroup(title: "Startup and tabs")
        let card = try? XCTUnwrap(find(SettingsCardView.self, in: group))
        let name = try? XCTUnwrap(label("Startup and tabs", in: group))
        guard let card, let name else { return }
        XCTAssertEqual(
            aligned(name, in: group).minX,
            aligned(card, in: group).minX,
            accuracy: 0.001,
            "the name labels the card, so it stands on the card's edge and not on the rows' inset"
        )
    }

    /// The other half of the same rule: the rows keep their own inset. A name
    /// moved off the grid is a change to one label, not to the grid.
    func testTheRowsKeepTheCardsTextInset() {
        let group = laidOutGroup(title: "Startup and tabs")
        let card = try? XCTUnwrap(find(SettingsCardView.self, in: group))
        let row = try? XCTUnwrap(label("On launch", in: group))
        guard let card, let row else { return }
        XCTAssertEqual(
            aligned(row, in: group).minX - aligned(card, in: group).minX,
            SettingsMetrics.cardInset,
            accuracy: 0.001
        )
    }

    /// §3.7's `Spaces … [New Space]` is the same label with a control beside
    /// it, and the pair frames the cards below rather than sitting inside them.
    func testAHeadingAndItsControlFrameTheCardsBelowThem() {
        let button = SettingsPushButton(title: "New Space", isDestructive: false)
        let heading = SettingsRow.heading("Spaces", accessory: button)
        heading.frame = NSRect(x: 0, y: 0, width: 420, height: 32)
        heading.layoutSubtreeIfNeeded()
        let name = try? XCTUnwrap(label("Spaces", in: heading))
        guard let name else { return }
        XCTAssertEqual(aligned(name, in: heading).minX, 0, accuracy: 0.001)
        XCTAssertEqual(aligned(button, in: heading).maxX, heading.bounds.maxX, accuracy: 0.001)
    }
}

/// A press swells a control 5 %, and the pane's scroll view cuts at its own
/// edges. The page's margins are inside it, so a control on the page's edge —
/// a mode card, New Space — has room to swell into on every side.
@MainActor
final class SettingsPaneSwellRoomTests: XCTestCase {

    func testThePageHasRoomToSwellIntoOnEverySide() throws {
        let pane = SettingsDetailPane(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        let page = NSView()
        page.heightAnchor.constraint(equalToConstant: 200).isActive = true
        pane.show(page, title: "Page", animated: false)
        pane.layoutSubtreeIfNeeded()
        let clip = try XCTUnwrap(page.enclosingScrollView?.contentView)
        let inClip = clip.convert(page.bounds, from: page)
        let room = { (side: CGFloat) in side * (Tokens.Motion.pressSwell - 1) / 2 }
        XCTAssertGreaterThanOrEqual(inClip.minX - clip.bounds.minX, room(inClip.width), "cut on the leading edge")
        XCTAssertGreaterThanOrEqual(clip.bounds.maxX - inClip.maxX, room(inClip.width), "cut on the trailing edge")
        XCTAssertGreaterThanOrEqual(inClip.minY - clip.bounds.minY, room(inClip.height), "cut at the top")
        // Where the page starts on screen has not moved.
        XCTAssertEqual(pane.convert(page.bounds, from: page).minX, SettingsMetrics.paneInset, accuracy: 0.5)
    }
}
