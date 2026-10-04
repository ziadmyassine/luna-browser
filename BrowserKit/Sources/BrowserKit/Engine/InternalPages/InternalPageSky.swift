import CoreGraphics
import Foundation
import ImageIO

/// The colour along the top edge of an error page's painting, so the page bar
/// over it can wear the painting's sky rather than the page's plain plane.
///
/// The bar takes the colour under its edge from the page, and that sample
/// steps over a picture to the first solid colour behind it
/// (`TabController.scrollScript`). A painted page therefore puts this colour
/// under its painting, where the picture hides it and the sample finds it.
///
/// Read off the painting rather than written down: `BrowserKit` holds no
/// colour values, and a value copied from a picture drifts the first time the
/// picture is painted again.
enum InternalPageSky {

    /// Per painting, once: a page renders on every failed load, and the same
    /// painting gives the same answer every time. A miss is asked again, since
    /// it costs only a lookup and the paintings can be handed over later.
    @MainActor private static var cache: [String: String] = [:]

    /// `rgb(r g b)` for the painting's top edge, or nil when there is none.
    @MainActor
    static func css(forPainting name: String) -> String? {
        if let known = cache[name] { return known }
        let found = InternalPages.artwork?(name).flatMap(topEdge).map {
            "rgb(\($0.r) \($0.g) \($0.b))"
        }
        cache[name] = found
        return found
    }

    /// Smallest size the painting is decoded at. JPEG scales on decode, so a
    /// painting this narrow costs a fraction of its full size, and the sky it
    /// is read from is a gradient with nothing finer than this to lose.
    static let sampleWidth = 64

    /// The mean of the top two rows, in sRGB. Two rows rather than one: the
    /// very first is where a JPEG's block edge sits.
    static func topEdge(_ jpeg: Data) -> (r: Int, g: Int, b: Int)? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: sampleWidth
              ] as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        let width = image.width
        let rows = min(2, image.height)
        var pixels = [UInt8](repeating: 0, count: width * rows * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: rows,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            // Drawn so that only the image's top rows land in the context: its
            // origin is bottom left, so the image hangs down past the bottom.
            context.draw(image, in: CGRect(x: 0, y: rows - image.height, width: width, height: image.height))
            return true
        }
        guard drawn, width > 0, rows > 0 else { return nil }
        var sum = (r: 0, g: 0, b: 0)
        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            sum.r += Int(pixels[pixel])
            sum.g += Int(pixels[pixel + 1])
            sum.b += Int(pixels[pixel + 2])
        }
        let count = width * rows
        return (sum.r / count, sum.g / count, sum.b / count)
    }
}

extension InternalPages {

    /// The colour along a painting's top edge, for the app's own painted
    /// surfaces: the empty content pane stands on one of these paintings, and
    /// the page bar over it wears this the way it wears an error page's sky.
    public static func skyColour(ofPainting jpeg: Data) -> RGBA? {
        InternalPageSky.topEdge(jpeg).map {
            RGBA(r: Double($0.r) / 255, g: Double($0.g) / 255, b: Double($0.b) / 255, a: 1)
        }
    }
}
