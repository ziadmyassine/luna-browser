//
//  SidebarMenu.swift
//  Luna
//
//  The two things every sidebar menu needs: an item that runs a closure, and a title with
//  a glyph in it.
//
//  The closure item exists because `NSMenuItem` dispatches through target/action
//  and a closure has no target: without it every menu would need an `@objc`
//  method on some view that is still alive when the item fires, which for a row
//  view the table is free to recycle is a use-after-free waiting to happen.
//
//  The glyph exists because `NSMenuItem.image` is not drawn on this macOS —
//  `label(symbol:title:in:)` is the way round it.
//
//  `ClosureMenuItem` is its own target, so the action lives exactly as long as
//  the item does, and the menu owns both.
//

import AppKit
import BrowserKit

@MainActor
enum SidebarMenu {

    /// A menu item that runs `action`. The item retains the closure; nothing
    /// else has to stay alive for it to fire.
    static func item(title: String, action: @escaping () -> Void) -> NSMenuItem {
        ClosureMenuItem(title: title, action: action)
    }

    /// One item with the reference's glyph beside its word (§3.4a).
    ///
    /// The glyph rides in `attributedTitle` rather than in `image`, which is not
    /// drawn at all on this macOS — ``label(symbol:title:in:)`` has the
    /// measurement. The plain `title` is set as well and stays underneath: it is
    /// what VoiceOver reads and what `typeSelect` matches, and neither should
    /// have to step over an attachment.
    ///
    /// Here rather than in `TabMenu`, where it started, because §3.4b's group
    /// menu wants the same item and two copies of it would be two chances for
    /// one menu's glyphs to end up a different size from the other's.
    static func glyphItem(_ title: String, symbol name: String, action: @escaping () -> Void) -> NSMenuItem {
        let item = item(title: title, action: action)
        item.attributedTitle = label(symbol: name, title: title)
        return item
    }

    /// A caption: a disabled item that titles a group or states a rule.
    ///
    /// Not `NSMenuItem.sectionHeader(title:)` — that one is a heading, and
    /// the second use here is a sentence ("Light and Dark apply to every
    /// Space") rather than a label for what follows it.
    static func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// §6.2 from the foot of the sidebar — the two verbs every surface down
    /// there offers on a right-click.
    ///
    /// One builder rather than three copies because the region is what
    /// carries the menu, not any one control in it: the profile line, the Space
    /// strip and the bar they sit in are one thing to a user aiming at "the
    /// Spaces bit", and a menu that appeared on two of the three would read as
    /// a menu that sometimes fails.
    static func spaces(edit: @escaping () -> Void, new: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item(title: String(localized: "Edit Spaces…"), action: edit))
        menu.addItem(item(title: String(localized: "New Space"), action: new))
        return menu
    }

    /// §8.2 / §13.6's colours for one Space, with the way back out of them.
    ///
    /// Shared because there are two places a Space is visible now — §3.5's dot
    /// and §4's Space cylinder — and a menu that offered the palette in one of
    /// them and not the other would make the colour a property of the layout.
    ///
    /// The way out is always present, never conditional on the Space already
    /// carrying a colour: Arc needed a help article for getting out of a theme,
    /// and a way out that only appears once you are lost is not a way out.
    static func colours(
        for space: Space,
        in appearance: NSAppearance,
        setGradient: @escaping (GradientPair) -> Void,
        edit: @escaping () -> Void
    ) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(header("Colour for \(space.name)"))
        for (index, gradient) in Tokens.Gradient.spacePalette.enumerated() {
            let entry = item(title: Tokens.Gradient.spacePaletteNames[index]) { setGradient(gradient) }
            entry.image = swatch(gradient, in: appearance)
            entry.state = gradient == space.gradient ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let reset = item(title: "No Colour") { setGradient(Tokens.Gradient.neutral) }
        reset.image = swatch(Tokens.Gradient.neutral, in: appearance)
        reset.state = Tokens.Gradient.isNeutral(space.gradient) ? .on : .off
        menu.addItem(reset)
        menu.addItem(.separator())
        menu.addItem(item(title: String(localized: "Edit “\(space.name)”…"), action: edit))
        menu.addItem(.separator())
        // Arc's own documentation shouts this, and it is the combination that
        // works: colour is per Space, Light/Dark is not. Saying so here is
        // cheaper than the support article that follows from not saying it.
        menu.addItem(header("Light and Dark apply to every Space"))
        return menu
    }

    /// A menu item's title with its glyph drawn into it, which is the only way to put
    /// an icon in a menu on this macOS.
    ///
    /// `NSMenuItem.image` is the documented API and does nothing. Measured
    /// twice, most recently with a five-way probe in a bare AppKit app: a plain
    /// system symbol, one through `withSymbolConfiguration`, one with an
    /// explicit size and `isTemplate` on, a hand-drawn red square and a named
    /// AppKit template — none appeared, in Luna or in the probe. The property
    /// is set correctly and the system declines.
    ///
    /// An `NSTextAttachment` in `attributedTitle` is drawn, because it is text
    /// rather than a menu image, and it keeps what a custom `NSMenuItem.view`
    /// would cost: the native highlight, arrow-key navigation, the
    /// key-equivalent column, and the plain `title` underneath for VoiceOver.
    ///
    /// The tab stop makes the labels line up in a column rather than each
    /// starting after its own glyph, derived from the two tokens §3.4's rows
    /// use for the same relationship.
    ///
    /// - Parameter appearance: resolved here rather than at draw time. A dynamic
    ///   `NSColor` inside an `NSImage` draw block picks up whatever appearance happens to
    ///   be current, which in a menu being built from a right-click is not reliably the
    ///   window's.
    static func label(
        symbol name: String,
        title: String,
        in appearance: NSAppearance = NSApp.effectiveAppearance
    ) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(
            textAlignment: .left,
            location: Tokens.Metric.menuGlyph + Tokens.Metric.rowIconGap
        )]
        let label = NSMutableAttributedString()
        if let glyph = glyph(name, in: appearance) {
            let attachment = NSTextAttachment()
            attachment.image = glyph
            // Sat on the baseline, a glyph reads as hanging below the word beside it.
            // Centred on the cap height is where the eye puts it.
            attachment.bounds = NSRect(
                x: 0,
                y: (font.capHeight - glyph.size.height) / 2,
                width: glyph.size.width,
                height: glyph.size.height
            )
            label.append(NSAttributedString(attachment: attachment))
        }
        label.append(NSAttributedString(string: "\t" + title))
        label.addAttributes(
            [.font: font, .paragraphStyle: paragraph],
            range: NSRange(location: 0, length: label.length)
        )
        return label
    }

    /// The symbol in §2.3's primary ink, which is what a menu draws its words in.
    ///
    /// Tinted by hand, not by `isTemplate`. A template image is tinted by the control
    /// drawing it, and the thing drawing this one is a text run, which does no such thing —
    /// so an untinted template comes out black on a dark menu. `sourceAtop` paints the ink
    /// through the glyph's own coverage, which keeps its antialiasing.
    private static func glyph(_ name: String, in appearance: NSAppearance) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: Tokens.Metric.menuGlyph, weight: .regular))
        else { return nil }
        let tinted = NSImage(size: base.size, flipped: false) { rect in
            var drawn = false
            appearance.performAsCurrentDrawingAppearance {
                base.draw(in: rect)
                Tokens.Text.primary.setFill()
                rect.fill(using: .sourceAtop)
                drawn = true
            }
            return drawn
        }
        tinted.isTemplate = false
        return tinted
    }

    /// §8.2a's gradient, drawn small enough to sit in a menu.
    ///
    /// Not a template image: a swatch whose whole content is its colour would
    /// come back as a grey blob if AppKit were allowed to tint it.
    static func swatch(_ gradient: GradientPair, in appearance: NSAppearance) -> NSImage {
        let side = Tokens.Metric.menuSwatch
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            var drawn = false
            appearance.performAsCurrentDrawingAppearance {
                let path = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
                Tokens.Gradient.nsGradient(gradient, at: .full, in: appearance)?
                    .draw(in: path, angle: -45)
                // §21.2 Differentiate Without Colour, and legibility besides: a
                // light swatch on a light menu needs an edge to have a shape.
                Tokens.Line.border.setStroke()
                path.lineWidth = Tokens.Metric.hairline
                path.stroke()
                drawn = true
            }
            return drawn
        }
        image.isTemplate = false
        return image
    }
}

@MainActor
private final class ClosureMenuItem: NSMenuItem {

    private let body: () -> Void

    init(title: String, action: @escaping () -> Void) {
        body = action
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    @objc private func fire() {
        body()
    }
}
