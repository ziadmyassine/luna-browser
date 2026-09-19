//
//  VectorIconRasterizerTests.swift
//  LunaTests
//
//  §4.7's vector half. The bitmap half is asserted in `BrowserKitTests`, where
//  `FaviconService` lives; this one cannot be, because drawing an SVG needs
//  AppKit and that is the whole reason the renderer sits up here.
//

import ImageIO
import UniformTypeIdentifiers
import XCTest
import BrowserKit
@testable import Luna

final class VectorIconRasterizerTests: XCTestCase {

    /// Deliberately not square, and deliberately tiny: it pins down both the
    /// aspect ratio and the fact that a vector is drawn *up* to the cache's size.
    private static let wideSVG = Data("""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 32" width="64" height="32">\
    <rect width="64" height="32" fill="#ff6600"/></svg>
    """.utf8)

    private func size(of png: Data) throws -> (width: Int, height: Int, type: String?) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        return (
            try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int),
            try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int),
            CGImageSourceGetType(source) as String?
        )
    }

    /// The point of accepting a vector at all: a 64-pixel mark comes out sharp
    /// at the cache's size rather than being blown up from 64 later.
    @MainActor
    func testAVectorIsDrawnAtTheCachesSizeAndKeepsItsShape() throws {
        let png = try XCTUnwrap(VectorIconRasterizer.render(Self.wideSVG, longestEdge: 128))
        let drawn = try size(of: png)

        XCTAssertEqual(drawn.type, UTType.png.identifier)
        XCTAssertEqual(drawn.width, 128)
        XCTAssertEqual(drawn.height, 64, "fit, not fill — a wide mark must not be stretched square")
    }

    /// §4.7's guarantee is that the sidebar's only two cases are a real icon or
    /// nil. A second decoder must not become a second way to cache rubbish.
    @MainActor
    func testBytesNothingCanReadAreStillNotAnIcon() {
        XCTAssertNil(VectorIconRasterizer.render(Data("<!doctype html><title>404</title>".utf8), longestEdge: 128))
        XCTAssertNil(VectorIconRasterizer.render(Data(), longestEdge: 128))
        XCTAssertNil(VectorIconRasterizer.render(Self.wideSVG, longestEdge: 0))
    }

    /// The seam itself. `FaviconService` asks a closure it cannot fill in, and
    /// the only thing that fills it is `install()` — so this is what stands
    /// between the renderer and its being unreachable from where it is needed.
    @MainActor
    func testInstallingIsWhatLetsBrowserKitReachTheRenderer() throws {
        let installed = FaviconService.rasterize
        defer { FaviconService.rasterize = installed }

        FaviconService.rasterize = nil
        VectorIconRasterizer.install()

        let rendered = try XCTUnwrap(FaviconService.rasterize?(Self.wideSVG, 128))
        XCTAssertEqual(try size(of: rendered).width, 128)
    }
}
