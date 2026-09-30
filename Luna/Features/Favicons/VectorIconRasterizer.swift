//
//  VectorIconRasterizer.swift
//  Luna
//
//  The second half of §4.7's decoder, living up here because of where AppKit is
//  allowed to be.
//
//  `FaviconService` reads icons with ImageIO, which returns no images for an
//  SVG — and several sites serve only a vector, some from `/favicon.ico`.
//  `NSImage` reads SVG, but `BrowserKit` keeps AppKit out, hence the seam:
//  `FaviconService.rasterize`, installed here once at launch. Drawing at the
//  cache's own size is the point, so a 16-point mark comes out sharp at 128 px.
//
//  It renders, it does not run: the system's static image rep draws it with no
//  script and no layout engine, and the bytes are no more or less trusted than
//  the page that named them.
//

import AppKit
import BrowserKit

@MainActor
enum VectorIconRasterizer {

    /// Hands `BrowserKit` the decoder it cannot import. Process-wide and
    /// idempotent: there is one `FaviconService.shared` and one of these.
    static func install() {
        FaviconService.rasterize = { data, longestEdge in
            render(data, longestEdge: longestEdge)
        }
    }

    /// A PNG whose longest edge is `longestEdge` pixels, or nil for bytes even
    /// AppKit will not read.
    ///
    /// Reached only after ImageIO has refused the same bytes, so what arrives is
    /// a vector or it is rubbish. `NSImage` would decode a bitmap too; that is
    /// harmless and not worth a format check to prevent.
    static func render(_ data: Data, longestEdge: Int) -> Data? {
        guard longestEdge > 0, let image = NSImage(data: data), image.isValid else { return nil }
        let drawn = image.size
        // A rep that reports nothing has nothing to draw, and dividing by it
        // would be worse than declining.
        guard drawn.width >= 1, drawn.height >= 1 else { return nil }

        // Fit, not fill: a wordmark that is wider than it is tall keeps its
        // shape and simply gets fewer rows.
        let scale = CGFloat(longestEdge) / max(drawn.width, drawn.height)
        let size = NSSize(
            width: max(1, (drawn.width * scale).rounded()),
            height: max(1, (drawn.height * scale).rounded())
        )

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = size

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        // `.copy`, not `.sourceOver`: the bitmap is new and transparent, and a
        // favicon's own transparency has to survive into the PNG rather than be
        // composited against nothing.
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        context.flushGraphics()

        return bitmap.representation(using: .png, properties: [:])
    }
}
