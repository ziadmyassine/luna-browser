//
//  GroupRowFurnitureTests.swift
//  LunaTests
//
//  §3.4b's folder header, drawn: the fold mark that is not a button, the icon
//  that is drawn larger than a favicon, and the emoji that has to fit the slot
//  it is drawn into.
//
//  All three are things that look right in a mock-up and wrong on screen, and
//  none of them is reachable from the pure row maths in
//  `SidebarRowModelTests` — these build the view.
//

import XCTest
@testable import Luna

@MainActor
final class GroupRowFurnitureTests: XCTestCase {

    private static let width: CGFloat = 240

    private func row(_ content: SidebarRowContent) -> SidebarRowView {
        let view = SidebarRowView(frame: NSRect(x: 0, y: 0, width: Self.width, height: Tokens.Metric.rowHeight))
        view.configure(content)
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func folder(icon: String = "folder") -> SidebarRowContent {
        SidebarRowContent(title: "Trip", symbolName: icon, disclosure: .expanded)
    }

    /// The fold mark takes no press. The header is what folds the folder, and
    /// a glyph inside it that answered the pointer separately was a second
    /// target on a row that has one — so it is not in the hit test at all.
    func testTheFoldMarkIsNotAControl() {
        let view = row(folder())
        XCTAssertFalse(view.chevron.isHidden, "the folder has no fold mark")
        let centre = NSPoint(x: view.chevron.frame.midX, y: view.chevron.frame.midY)
        XCTAssertTrue(
            view.hitTest(view.convert(centre, to: view.superview)) === view,
            "the fold mark took the press that belongs to the header"
        )
    }

    /// A folder's icon is drawn larger than a favicon and on the same centre
    /// line, so the column still reads as one column.
    func testAFoldersIconIsBiggerThanAFaviconAndSharesItsCentre() {
        let folderIcon = row(folder()).subviews.compactMap { $0 as? NSImageView }.first
        let tabIcon = row(SidebarRowContent(title: "Page")).subviews.compactMap { $0 as? NSImageView }.first
        let folderBox = try? XCTUnwrap(folderIcon).frame
        let tabBox = try? XCTUnwrap(tabIcon).frame
        XCTAssertEqual(folderBox?.width, Tokens.Metric.groupIconSize)
        XCTAssertEqual(tabBox?.width, Tokens.Metric.faviconSize)
        XCTAssertGreaterThan(folderBox?.width ?? 0, tabBox?.width ?? 0)
        XCTAssertEqual(folderBox?.midX ?? 0, tabBox?.midX ?? 0, accuracy: 0.51, "the two icons are off one column")
    }

    /// An emoji is drawn at its own size, which is larger than the point size
    /// it is asked for: Apple Color Emoji at 16 pt puts 20 pt of picture on the
    /// row. Set at the slot's own size it was cut off on all four edges.
    ///
    /// Asserted on a filled square, whose rounded corner is the first thing a
    /// crop takes: clipped, the corner pixel is solid; fitted, it is the
    /// transparent outside of the curve.
    func testAnEmojiIsDrawnSmallEnoughToFitTheSlot() throws {
        let image = try XCTUnwrap(RowEmoji.image("⬛", pointSize: Tokens.Metric.faviconSize))
        XCTAssertEqual(image.size.width, Tokens.Metric.faviconSize)
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let corner = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent
        let centre = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
        XCTAssertEqual(centre.alphaComponent, 1, accuracy: 0.01, "nothing was drawn")
        XCTAssertLessThan(corner, 0.5, "the emoji is drawn past the edge of its slot and is cut off")
    }
}
