//
//  FaviconTint.swift
//  Luna
//
//  The colour a site glows in (§3.3): the one hue in its favicon, pulled
//  out of the icon's own pixels and cached per host beside the icon itself.
//
//  Not the page's `theme-color`, and the difference matters here more than it
//  does anywhere else in the chrome. A pinned tab's page is closed until you
//  click it — that is what pinning does — so there is no `TabState` to read a
//  theme colour from, and the glow would arrive a second after the click that
//  asked for it. The favicon is the one thing about a pinned site that Luna
//  already has on disk before the site is woken up.
//
//  Weighted by chroma, squared, so a minority of coloured pixels wins. The
//  reference case is X's tile: a black glyph on white, one red
//  notification dot, and a red glow. A plain average of those pixels is grey.
//  Squaring the chroma makes the sixteen red pixels outvote the thousand
//  colourless ones, which is what the eye does looking at the same icon.
//

import AppKit
import BrowserKit

@MainActor
enum FaviconTint {

    /// The colour §3.3's selected tile glows in.
    ///
    /// Never nil: every pinned tile lights up when it is the tab you are on,
    /// and an icon with no colour of its own glows in the chrome's own ink
    /// rather than in a hue this file invented for it. See `neutral`.
    static func glow(for tab: Tab) -> NSColor {
        // A tile wearing the icon the user chose (§3.4a) is not showing the
        // site's colours at all, so there are none of the site's to take.
        guard tab.customSymbolName == nil,
              let host = tab.url.host(percentEncoded: false), !host.isEmpty
        else { return neutral }
        if let cached = cache[host] { return cached }
        // Nothing is remembered until the icon lands. Favicons arrive after
        // the tab does (§4.7); caching "no colour" for a site pinned a moment
        // ago would outlive the fetch and the tile would glow grey for the rest
        // of the session.
        guard let icon = SidebarIcons.favicon(for: tab) else { return neutral }
        let tint = glow(of: icon)
        cache[host] = tint
        return tint
    }

    /// The colour one icon glows in, with no tab and no cache around it.
    ///
    /// Separate from `glow(for:)` because this is the half that can be wrong
    /// — the weighting, the floors — and the half a test can hand a picture to.
    static func glow(of icon: NSImage) -> NSColor {
        hue(of: icon).map(lit) ?? neutral
    }

    /// What a monochrome icon glows in — the same ink the chrome writes in,
    /// which is white on a dark sidebar and near-black on a light one.
    ///
    /// Deliberately not `Accent.tint`. The system accent is the blue
    /// highlight Luna does not have anywhere (`GlassButton.isSelected`), and
    /// reaching for it here would put it back on the one surface the whole
    /// feature is about. A glow in the ink reads as the tile being lit rather
    /// than as the tile being selected by macOS.
    ///
    /// `secondary`, not `primary`, and that was measured: rendered on both
    /// planes, ink at `primary`'s alpha stops reading as light on a light
    /// sidebar and starts reading as a drawn-on outline. This is the quiet
    /// case by definition — the site offered no colour — so it glows quietly.
    static var neutral: NSColor { Tokens.Text.secondary }

    private static var cache: [String: NSColor] = [:]

    /// The side of the grid the icon is sampled on. 32 × 32 is a little over a
    /// favicon's usual size, so nothing is thrown away on the way in and the
    /// loop is a thousand pixels rather than the four thousand a 64 pt mark
    /// would cost.
    private static let grid = 32

    /// The icon's own colour, or nil when it has none worth glowing in.
    ///
    /// Chroma — the spread between the brightest and dimmest channel — is what
    /// "coloured" means here, and it is squared so that the weighting is not a
    /// vote but a landslide. Alpha comes into it too: a favicon is mostly
    /// transparent at the corners and those pixels are nobody's colour.
    private static func hue(of icon: NSImage) -> NSColor? {
        guard let source = icon.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: grid, height: grid, bitsPerComponent: 8,
                  bytesPerRow: grid * 4, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(source, in: CGRect(x: 0, y: 0, width: CGFloat(grid), height: CGFloat(grid)))
        guard let pixels = context.data else { return nil }
        let bytes = pixels.bindMemory(to: UInt8.self, capacity: grid * grid * 4)

        var total = 0.0, red = 0.0, green = 0.0, blue = 0.0
        for index in stride(from: 0, to: grid * grid * 4, by: 4) {
            let alpha = Double(bytes[index + 3]) / 255
            guard alpha > 0.35 else { continue }
            // Premultiplied, which is the only alpha a bitmap context will
            // draw into: the ink has to be divided back out before the channels
            // can be compared, or every translucent pixel reads as dark.
            let channels = (
                Double(bytes[index]) / 255 / alpha,
                Double(bytes[index + 1]) / 255 / alpha,
                Double(bytes[index + 2]) / 255 / alpha
            )
            let chroma = max(channels.0, channels.1, channels.2)
                - min(channels.0, channels.1, channels.2)
            let weight = alpha * chroma * chroma
            total += weight
            red += channels.0 * weight
            green += channels.1 * weight
            blue += channels.2 * weight
        }
        guard total > 0 else { return nil }
        return saturated(NSColor(
            srgbRed: red / total, green: green / total, blue: blue / total, alpha: 1
        ))
    }

    /// The average, unless it came out colourless.
    ///
    /// A grey icon averages to grey, and so does one whose colours cancel —
    /// half red and half cyan. Both of those are icons with no hue to offer,
    /// and the honest answer to both is the neutral glow rather than a
    /// saturated guess at what the grey "meant".
    private static func saturated(_ colour: NSColor) -> NSColor? {
        colour.saturation >= 0.15 ? colour : nil
    }

    /// The icon's hue, turned up until it can be seen as light.
    ///
    /// A favicon's colour is chosen to be read at 16 pt against a page, not to
    /// be emitted at the edge of a tile: a navy or a maroon mark glows as a
    /// dark smudge on a dark sidebar. The floors lift the colour to something
    /// that carries, and the ceiling on saturation keeps a pure primary from
    /// turning into a neon that no site's mark actually is.
    private static func lit(_ colour: NSColor) -> NSColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 1
        colour.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(
            hue: hue,
            saturation: min(max(saturation, 0.55), 0.95),
            brightness: max(brightness, 0.70),
            alpha: 1
        )
    }
}

private extension NSColor {
    /// HSB saturation, for a colour already known to be in an RGB space.
    var saturation: CGFloat {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 1
        getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return saturation
    }
}
