//
//  ProfilePicture.swift
//  Luna
//
//  The one place a file the user picked becomes bytes worth keeping (§9).
//
//  A profile's picture is drawn small — at the end of §3.5's Space pill, and
//  on the Space's card in Settings — so the file chosen for it is almost always enormous next to
//  what is shown: a photo off a phone is three thousand points wide and eight
//  megabytes, of which the circle uses about a thousandth. Persisting the
//  original would put that in every backup and every read of the row for the
//  sake of detail no screen here will ever draw.
//
//  So the crop and the downsample happen on the way in, once, and the column
//  holds what is drawn. `side` is generous rather than exact — three times the
//  circle, which covers the pill's at any scale factor and leaves room for
//  the picture to appear somewhere larger without asking the user for the file
//  again.
//

import AppKit

enum ProfilePicture {

    /// The square the stored picture is drawn into: 102 pt of circle at 3×.
    ///
    /// Not `bottomCircle.width * 3` spelled out at the call site, because the
    /// number is a decision about storage rather than about layout — the
    /// Space pill asks for whatever size it is and gets this scaled down.
    static let side: CGFloat = 3 * Tokens.Metric.bottomCircle.width

    /// A chosen file as PNG bytes, cropped square from the middle and
    /// downsampled, or nil if the file is not an image this Mac can read.
    ///
    /// Cropped rather than fitted: the Space pill draws it in a circle, and a portrait
    /// letterboxed into one shows two bands of background where a face should
    /// be. Cropping from the middle is what every other app does with a
    /// profile picture, and it is what makes the stored square drawable by
    /// anything that wants it without knowing the original's shape.
    static func bytes(ofFileAt url: URL) -> Data? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return bytes(of: image)
    }

    static func bytes(of image: NSImage) -> Data? {
        let source = image.size
        guard source.width > 0, source.height > 0 else { return nil }
        // The largest square the image contains, centred — then drawn into
        // `side` points, which is a downsample for any picture worth picking
        // and an upsample for a tiny one.
        let edge = min(source.width, source.height)
        let crop = NSRect(
            x: (source.width - edge) / 2,
            y: (source.height - edge) / 2,
            width: edge,
            height: edge
        )
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(side),
            pixelsHigh: Int(side),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: side, height: side)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: side, height: side),
            from: crop,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// The stored bytes as something to draw, or nil if the column holds
    /// something that is not an image — which a database edited by hand, or
    /// synced from a future version, can contain.
    static func image(from data: Data?) -> NSImage? {
        guard let data, let image = NSImage(data: data) else { return nil }
        image.isTemplate = false
        return image
    }
}
