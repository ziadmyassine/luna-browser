//
//  SiteMonogram.swift
//  Luna
//
//  §4.7's last tier: a site with no favicon wears its first letter on the
//  Space's colour instead of a globe. A column of globes says nothing about
//  which row is which; a letter on the Space's own colour does, and it looks
//  like it belongs to the Space it is in.
//
//  The UI layer's, not `FaviconService`'s: the tile needs the Space's
//  gradient, and the engine has no Spaces to read it from.
//
//  Cached by letter, gradient and nothing else. `SidebarRowContent` is
//  `Equatable` and `NSImage` compares by identity, so a fresh tile per refresh
//  would make every row look changed — the trap `SidebarIcons` documents. The
//  appearance is not in the key: the tile resolves its colours each time it is
//  drawn, under whichever appearance is drawing it.
//

import AppKit
import BrowserKit

@MainActor
enum SiteMonogram {

    private struct Key: Hashable {
        let letter: String
        let gradient: GradientPair
    }

    private static var cache: [Key: NSImage] = [:]

    /// The tile for the site `url` is on, or nil for a page that is not on a
    /// site — `about:blank`, a file, one of Luna's own — which keeps its
    /// symbol. Square at `Metric.monogramTile`; drawn on demand, so it is
    /// sharp at any size it is scaled to.
    static func image(for url: URL?, on gradient: GradientPair) -> NSImage? {
        guard let letter = letter(for: url) else { return nil }
        let key = Key(letter: letter, gradient: gradient)
        if let cached = cache[key] { return cached }
        let image = draw(letter, on: gradient)
        cache[key] = image
        return image
    }

    /// The registrable domain's first letter, uppercased: `M` for
    /// `mail.google.com` would name the subdomain rather than the site, so
    /// that is `G`, and `bbc.co.uk` is `B`.
    ///
    /// Nil for an address with no name to take a letter from — an IP literal,
    /// or a host still in Punycode, whose first letter is the `x` of `xn--`.
    static func letter(for url: URL?) -> String? {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host(percentEncoded: false), !host.isEmpty
        else { return nil }
        let site = PublicSuffix.siteKey(forHost: host) ?? host.lowercased()
        guard !site.hasPrefix("xn--"), site.contains(where: \.isLetter),
              let first = site.first, first.isLetter || first.isNumber
        else { return nil }
        return String(first).uppercased()
    }

    private static func draw(_ letter: String, on gradient: GradientPair) -> NSImage {
        let shape = Tokens.Metric.monogramTile
        let image = NSImage(size: shape.size, flipped: false) { rect in
            let appearance = NSAppearance.currentDrawing()
            let tile = NSBezierPath(roundedRect: rect, xRadius: shape.cornerRadius, yRadius: shape.cornerRadius)
            let ink: NSColor
            // A Space nobody has coloured gets the chrome's own fill and ink,
            // for `SpaceDotView`'s reason: painted, `neutral`'s grey reads as
            // a thirteenth colour.
            if Tokens.Gradient.isNeutral(gradient) {
                Tokens.Surface.selected.setFill()
                tile.fill()
                ink = Tokens.Text.primary
            } else {
                // The direction `SpaceDotView` draws the same pair in.
                Tokens.Gradient.nsGradient(gradient, at: .full, in: appearance)?.draw(in: tile, angle: -45)
                ink = Tokens.Gradient.foreground(on: gradient, at: .full, in: appearance)
            }
            let font = Tokens.TypeScale.monogram
            let text = NSAttributedString(string: letter, attributes: [.font: font, .foregroundColor: ink])
            // Centred on the capital rather than on the line, whose box
            // carries the descender and would set the letter high.
            let origin = NSPoint(
                x: rect.midX - text.size().width / 2,
                y: rect.midY - font.capHeight / 2 + font.descender
            )
            text.draw(at: origin)
            return true
        }
        image.isTemplate = false
        // Drawn again under each appearance rather than kept from the first:
        // the neutral tile's fill and ink are the chrome's, and they flip.
        image.cacheMode = .never
        return image
    }
}

extension SidebarIcons {

    /// What a tab's icon slot shows: the site's favicon, else its monogram on
    /// `gradient`. Nil only for a page that is not on a site, which keeps the
    /// row's symbol.
    func mark(for url: URL?, on gradient: GradientPair) -> NSImage? {
        favicon(for: url) ?? SiteMonogram.image(for: url, on: gradient)
    }

    static func mark(for tab: Tab, on gradient: GradientPair) -> NSImage? {
        shared.mark(for: tab.url, on: gradient)
    }
}
