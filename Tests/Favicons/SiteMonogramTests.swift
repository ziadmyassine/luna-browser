//
//  SiteMonogramTests.swift
//  LunaTests
//
//  §4.7's last tier: the letter a site with no favicon wears, the tile it is
//  drawn on, and that the tile is one image per letter and colour.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class SiteMonogramTests: XCTestCase {

    func testTheLetterIsTheSitesNotTheSubdomains() {
        XCTAssertEqual(letter("https://mail.google.com/mail/u/0"), "G")
        XCTAssertEqual(letter("https://www.bbc.co.uk/news"), "B")
        XCTAssertEqual(letter("http://news.ycombinator.com"), "Y")
        XCTAssertEqual(letter("https://9gag.com"), "9")
        XCTAssertEqual(letter("http://localhost:8080/"), "L")
    }

    func testAPageThatIsNotOnASiteKeepsItsSymbol() {
        XCTAssertNil(letter("about:blank"))
        XCTAssertNil(letter("file:///Users/someone/notes.md"))
        XCTAssertNil(letter("luna://settings"))
        XCTAssertNil(letter("http://192.168.1.1/"), "an address has no name to take a letter from")
        XCTAssertNil(letter("http://[::1]:3000/"))
        XCTAssertNil(letter("https://xn--bcher-kva.example/"), "a Punycode host's first letter is the x of xn--")
        XCTAssertNil(SiteMonogram.letter(for: nil))
    }

    /// `SidebarRowContent` is `Equatable` and `NSImage` compares by identity:
    /// a new image per refresh would make every row look changed.
    func testOneImagePerLetterAndColour() throws {
        let indigo = Tokens.Gradient.spacePalette[0]
        let first = try XCTUnwrap(SiteMonogram.image(for: URL(string: "https://example.com"), on: indigo))
        let again = try XCTUnwrap(SiteMonogram.image(for: URL(string: "https://www.example.org/page"), on: indigo))
        let elsewhere = try XCTUnwrap(SiteMonogram.image(for: URL(string: "https://example.com"), on: Tokens.Gradient.neutral))
        XCTAssertTrue(first === again, "the same letter on the same colour was drawn twice")
        XCTAssertFalse(first === elsewhere, "two Spaces' colours shared one tile")
        XCTAssertEqual(first.size, Tokens.Metric.monogramTile.size)
        XCTAssertFalse(first.isTemplate, "a template would be tinted flat in the row's ink")
    }

    /// The tile is rounded, filled with the Space's colour, and the letter on
    /// it is the gradient's own ink, centred.
    func testTheTileIsTheSpacesColourWithALegibleLetterInTheMiddle() throws {
        for gradient in Tokens.Gradient.spacePalette {
            for name in [NSAppearance.Name.aqua, .darkAqua] {
                let appearance = try XCTUnwrap(NSAppearance(named: name))
                let image = try XCTUnwrap(SiteMonogram.image(for: URL(string: "https://example.com"), on: gradient))
                let bitmap = try render(image, in: appearance)
                let scale = CGFloat(bitmap.pixelsWide) / image.size.width

                XCTAssertLessThan(alpha(bitmap, x: 0, y: 0), 0.5, "the corner is square")
                let ink = Tokens.Gradient.foreground(on: gradient, at: .full, in: appearance)
                let fill = try XCTUnwrap(colour(bitmap, x: 1 * scale, y: image.size.height / 2 * scale))
                XCTAssertGreaterThanOrEqual(
                    ink.contrastRatio(over: fill, in: appearance), Tokens.Gradient.textFloor,
                    "the letter is not legible on \(gradient) in \(name.rawValue)"
                )
                let stops = Tokens.Gradient.planes(gradient, at: .full, in: appearance)
                let box = try XCTUnwrap(inkBox(bitmap, ink: ink.resolved(in: appearance), fills: [stops.start, stops.end]),
                                        "no letter was drawn")
                XCTAssertEqual(box.midX / scale, image.size.width / 2, accuracy: 0.75, "the letter is off centre across")
                XCTAssertEqual(box.midY / scale, image.size.height / 2, accuracy: 0.75, "the letter is off centre up and down")
            }
        }
    }

    /// No colour is the chrome's own fill under the chrome's own ink, not the
    /// neutral pair's grey — which would read as a thirteenth colour.
    func testNoColourIsTheChromesOwnFill() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let image = try XCTUnwrap(SiteMonogram.image(for: URL(string: "https://example.com"), on: Tokens.Gradient.neutral))
        let bitmap = try render(image, in: appearance)
        let fill = try XCTUnwrap(colour(bitmap, x: 3, y: 16))
        let selected = Tokens.Surface.selected.resolved(in: appearance)
        XCTAssertEqual(fill.alphaComponent, selected.alphaComponent, accuracy: 0.02)
    }

    func testASiteWithNoFaviconGetsItsMonogramInTheIconSlot() throws {
        let icons = SidebarIcons(service: FaviconService(directory: nil))
        let gradient = Tokens.Gradient.spacePalette[3]
        let url = URL(string: "https://no-favicon.example")
        XCTAssertTrue(icons.mark(for: url, on: gradient) === SiteMonogram.image(for: url, on: gradient))
        XCTAssertNil(icons.mark(for: URL(string: "about:blank"), on: gradient))
    }

    // MARK: - Helpers

    private func letter(_ string: String) -> String? {
        SiteMonogram.letter(for: URL(string: string))
    }

    /// At 2x, the scale the tile is drawn at on every Mac Luna supports.
    private func render(_ image: NSImage, in appearance: NSAppearance) throws -> NSBitmapImageRep {
        let side = Int(image.size.width * 2)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        appearance.performAsCurrentDrawingAppearance {
            image.draw(in: NSRect(origin: .zero, size: image.size))
        }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private func alpha(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> CGFloat {
        bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
    }

    /// Pixel coordinates from the bottom left, as the tile is drawn.
    private func colour(_ bitmap: NSBitmapImageRep, x: CGFloat, y: CGFloat) -> NSColor? {
        bitmap.colorAt(x: Int(x), y: bitmap.pixelsHigh - 1 - Int(y))
    }

    /// The box round every pixel nearer the ink than either end of the fill,
    /// in pixels from the bottom left: the letter. A strip a pixel and a half
    /// deep is left out at each edge, where the rounded rim is anti-aliased
    /// into the background.
    private func inkBox(_ bitmap: NSBitmapImageRep, ink: NSColor, fills: [NSColor]) -> CGRect? {
        let rim = 3
        var box: CGRect?
        for row in rim ..< bitmap.pixelsHigh - rim {
            for column in rim ..< bitmap.pixelsWide - rim {
                guard let pixel = bitmap.colorAt(x: column, y: row),
                      fills.allSatisfy({ distance(pixel, ink) < distance(pixel, $0) }) else { continue }
                let point = CGRect(x: column, y: bitmap.pixelsHigh - 1 - row, width: 1, height: 1)
                box = box?.union(point) ?? point
            }
        }
        return box
    }

    private func distance(_ a: NSColor, _ b: NSColor) -> CGFloat {
        guard let a = a.usingColorSpace(.deviceRGB), let b = b.usingColorSpace(.deviceRGB) else { return 0 }
        return max(abs(a.redComponent - b.redComponent), abs(a.greenComponent - b.greenComponent),
                   abs(a.blueComponent - b.blueComponent))
    }
}

private extension NSColor {
    func resolved(in appearance: NSAppearance) -> NSColor {
        var resolved = self
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(cgColor: cgColor) ?? self
        }
        return resolved
    }
}
