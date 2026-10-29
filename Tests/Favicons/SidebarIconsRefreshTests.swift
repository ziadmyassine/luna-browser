//
//  SidebarIconsRefreshTests.swift
//  LunaTests
//
//  §4.7: when `FaviconService` replaces a site's icon, the rows draw the new
//  one. `SidebarIcons` keeps one `NSImage` per host for the life of the app,
//  so without this the refreshed bytes would sit unseen until a relaunch.
//

import XCTest
@testable import BrowserKit
@testable import Luna

@MainActor
final class SidebarIconsRefreshTests: XCTestCase {

    func testAReplacedIconIsDrawnAndAnUnchangedOneKeepsItsImage() async throws {
        let directory = URL.temporaryDirectory.appending(path: "luna-icons-\(UUID().uuidString)")
        let service = FaviconService(directory: directory)
        let icons = SidebarIcons(service: service)
        let url = try XCTUnwrap(URL(string: "https://refresh.example/page"))
        let first = try XCTUnwrap(FaviconService.png(from: Self.png(red: 1)))
        let second = try XCTUnwrap(FaviconService.png(from: Self.png(red: 0)))

        await service.remember(first, for: "refresh.example")
        let before = try XCTUnwrap(icons.favicon(for: url))
        // The same bytes again (every load reports its icon): a row must not look changed.
        await service.remember(first, for: "refresh.example")
        XCTAssertTrue(icons.favicon(for: url) === before)

        await service.remember(second, for: "refresh.example")
        let after = try XCTUnwrap(icons.favicon(for: url))
        XCTAssertFalse(after === before, "the row still draws the old icon")
        XCTAssertEqual(after.tiffRepresentation, NSImage(data: second)?.tiffRepresentation)
    }

    private static func png(red: CGFloat) throws -> Data {
        let image = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { rect in
            NSColor(srgbRed: red, green: 0, blue: 1 - red, alpha: 1).setFill()
            rect.fill()
            return true
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }
}
