//
//  ProfilePictureTests.swift
//  LunaTests
//
//  §9's profile picture: what is kept of the file the user chose, and what the
//  two places that draw it do with it — §3.5's Space pill and §6.2's card.
//
//  The size assertions are the point of the type. A profile picture is drawn in
//  a 34 pt circle and chosen from a photo library, so "what was picked" and
//  "what is worth storing" differ by three orders of magnitude — and the column
//  it goes into is in every backup of the database.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class ProfilePictureTests: XCTestCase {

    /// A wide picture, so the crop has something to take off.
    private func wide(_ size: NSSize = NSSize(width: 1200, height: 400)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: size).fill()
        // A mark off to one side, so a crop from the middle can be told from a
        // squeeze of the whole thing.
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: size.width / 4, height: size.height).fill()
        image.unlockFocus()
        return image
    }

    // MARK: - What is kept

    /// Square, at the one size the app stores — whatever shape arrived.
    func testAPictureIsCroppedSquareAndDownsampled() throws {
        let data = try XCTUnwrap(ProfilePicture.bytes(of: wide()))
        let stored = try XCTUnwrap(ProfilePicture.image(from: data))
        XCTAssertEqual(stored.size.width, ProfilePicture.side)
        XCTAssertEqual(stored.size.height, ProfilePicture.side)
    }

    /// Cropped from the middle, not squeezed: the band down the left of the
    /// source is outside the middle square and must not survive.
    func testTheCropTakesTheMiddleRatherThanSqueezingTheWhole() throws {
        let data = try XCTUnwrap(ProfilePicture.bytes(of: wide()))
        let stored = try XCTUnwrap(ProfilePicture.image(from: data))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: stored.tiffRepresentation ?? Data()))
        let left = try XCTUnwrap(rep.colorAt(x: 2, y: rep.pixelsHigh / 2))
        XCTAssertGreaterThan(left.redComponent, left.blueComponent, "the left band was kept — this is a fit, not a crop")
    }

    /// The reason the crop happens here rather than at draw time: what a
    /// photo library hands over is not what belongs in a database row.
    func testWhatIsStoredIsFarSmallerThanWhatWasChosen() throws {
        let huge = wide(NSSize(width: 3024, height: 4032))
        let original = try XCTUnwrap(huge.tiffRepresentation)
        let data = try XCTUnwrap(ProfilePicture.bytes(of: huge))
        XCTAssertLessThan(data.count, original.count / 10)
    }

    /// A zero-sized image has no middle to crop, and `NSImage` will hand one
    /// over for a file it could not really read.
    func testAnEmptyImageIsRefusedRatherThanStored() {
        XCTAssertNil(ProfilePicture.bytes(of: NSImage(size: .zero)))
    }

    /// Nil in, nil out — and bytes that are not an image are the same answer,
    /// because a database can be edited by hand or written by a later version.
    func testNothingAndNonsenseBothDrawNothing() {
        XCTAssertNil(ProfilePicture.image(from: nil))
        XCTAssertNil(ProfilePicture.image(from: Data([0x00, 0x01, 0x02, 0x03])))
    }

    // MARK: - §3.5's Space pill

    private func pill(picture: Data?) -> SidebarSpacePill {
        let bar = SidebarUtilityBar()
        bar.frame = NSRect(x: 0, y: 0, width: 280, height: Tokens.Metric.topBarHeight)
        bar.show(spaceName: "Personal", fanOut: nil, picture: picture)
        bar.layoutSubtreeIfNeeded()
        return bar.spacePill
    }

    /// The control that took the Profile avatar's place says Space, in its
    /// accessibility label, its tooltip and the header of its own menu.
    func testThePillSaysSpaceRatherThanProfile() throws {
        let bar = SidebarUtilityBar()
        bar.frame = NSRect(x: 0, y: 0, width: 280, height: Tokens.Metric.topBarHeight)
        bar.show(spaceName: "Personal", fanOut: "3 Favorites", picture: nil)
        let button = bar.spacePill.button
        let label = try XCTUnwrap(button.accessibilityLabel())
        let tip = try XCTUnwrap(button.toolTip)
        for text in [label, tip] {
            XCTAssertTrue(text.contains("Personal"), text)
            XCTAssertFalse(text.lowercased().contains("profile"), text)
        }
        let titles = SidebarMenu.profile(name: "Personal", manage: {}).items.map(\.title)
        XCTAssertFalse(titles.contains { $0.lowercased().contains("profile") }, "\(titles)")
        XCTAssertTrue(titles.contains { $0.contains("Manage Spaces") }, "\(titles)")
    }

    /// A picture fills the circle at the pill's leading end, round, and the
    /// name starts after it.
    func testAPictureSitsRoundAtThePillsEnd() throws {
        let data = try XCTUnwrap(ProfilePicture.bytes(of: wide()))
        let pill = pill(picture: data)
        let portrait = pill.portrait
        XCTAssertFalse(portrait.isHidden)
        XCTAssertEqual(portrait.frame.width, portrait.frame.height)
        XCTAssertEqual(portrait.frame.midY, pill.bounds.midY, accuracy: 0.5)
        XCTAssertEqual(portrait.layer?.cornerRadius, portrait.frame.width / 2)
        XCTAssertEqual(portrait.layer?.masksToBounds, true)
        XCTAssertGreaterThan(pill.clip.frame.minX, portrait.frame.maxX)
    }

    /// And with no picture there is nothing ahead of the name.
    func testTakingThePictureOffLeavesJustTheName() {
        let pill = pill(picture: nil)
        XCTAssertTrue(pill.portrait.isHidden)
        XCTAssertEqual(pill.clip.frame.minX, Tokens.Metric.sidebarSpacePillPad, accuracy: 0.5)
    }

    // MARK: - §6.2's row

    /// Remove is there when there is something to remove, and not when there
    /// is not: a permanently dimmed button beside every Space that has never
    /// had a picture is a control that mostly means nothing.
    func testRemoveAppearsOnlyOnceAPictureIsSet() throws {
        let data = try XCTUnwrap(ProfilePicture.bytes(of: wide()))
        let blank = Space(name: "Personal", symbolName: "moon", gradient: .defaultSpace)
        let pictured = Space(name: "Personal", symbolName: "moon", gradient: .defaultSpace, imageData: data)
        let bare = SpacesSection().pictureRow(blank, session: nil)
        let set = SpacesSection().pictureRow(pictured, session: nil)
        XCTAssertEqual(Self.buttons(in: bare.view), ["Choose…"])
        XCTAssertEqual(Self.buttons(in: set.view), ["Replace…", "Remove"])
    }

    private static func buttons(in row: NSView) -> [String] {
        var found: [String] = []
        var queue = row.subviews
        while let next = queue.first {
            queue.removeFirst()
            if let button = next as? SettingsPushButton { found.append(button.title) }
            queue.append(contentsOf: next.subviews)
        }
        return found
    }
}
