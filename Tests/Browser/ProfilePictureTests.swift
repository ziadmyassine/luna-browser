//
//  ProfilePictureTests.swift
//  LunaTests
//
//  §9's profile picture: what is kept of the file the user chose, and what the
//  two places that draw it do with it.
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

    // MARK: - §3.5's avatar

    private func avatar(picture: Data?) -> GlassButton? {
        let bar = SidebarUtilityBar()
        bar.frame = NSRect(x: 0, y: 0, width: 280, height: Tokens.Metric.topBarHeight)
        bar.show(profileName: "Personal", fanOut: nil, picture: picture)
        bar.layoutSubtreeIfNeeded()
        return bar.subviews.compactMap { $0 as? GlassButton }.first
    }

    private func mark(of button: GlassButton) -> NSImageView? {
        button.subviews.compactMap { $0 as? NSImageView }.first
    }

    /// A picture is the button, not a mark inside it: it fills the circle and
    /// takes its corner, where the glyph sits at `glyphSize` in the middle.
    func testAPictureFillsTheAvatarRatherThanSittingInIt() throws {
        let data = try XCTUnwrap(ProfilePicture.bytes(of: wide()))
        let button = try XCTUnwrap(avatar(picture: data))
        let mark = try XCTUnwrap(mark(of: button))
        XCTAssertEqual(mark.frame.size, button.bounds.size)
        XCTAssertEqual(mark.layer?.cornerRadius, Tokens.Metric.bottomCircle.cornerRadius)
        XCTAssertEqual(mark.layer?.masksToBounds, true)
    }

    /// And with no picture the glyph is back, at the size a glyph is — taking
    /// one off must not leave a circle-sized symbol behind.
    func testTakingThePictureOffPutsTheGlyphBack() throws {
        let button = try XCTUnwrap(avatar(picture: nil))
        let mark = try XCTUnwrap(mark(of: button))
        XCTAssertEqual(mark.frame.width, Tokens.Metric.glyphSize)
        XCTAssertNotEqual(mark.layer?.masksToBounds, true)
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
