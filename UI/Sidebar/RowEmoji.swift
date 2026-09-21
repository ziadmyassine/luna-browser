//
//  RowEmoji.swift
//  Luna
//
//  An emoji as a §3.4 row's glyph, for §3.4b's folders.
//
//  Sixteen SF Symbols is a vocabulary; an emoji is a name. A folder called
//  "Trip" with an airplane on it is using the picture the way the symbol list
//  intends, and a folder with the flag of the country the trip is to is doing
//  something the list can never cover — so the picker offers both and the two
//  live in the same field. `TabGroup.symbolName` therefore holds either an SF
//  Symbol's name or the emoji itself, and which one it is is a question about
//  the string rather than a second column on the row.
//
//  Drawn rather than set as text, because the row's icon is an `NSImageView`
//  and every other glyph in the column is an image. It is also why the image is
//  cached: `SidebarRowContent` is `Equatable` and `NSImage` compares by
//  identity, so a fresh one per refresh would make every folder row look
//  changed — the same trap `SidebarIcons` documents.
//

import AppKit

@MainActor
enum RowEmoji {

    private static var cache: [String: NSImage] = [:]

    /// Whether this is an emoji rather than an SF Symbol's name.
    ///
    /// Asked of the string, not of a flag stored beside it: a symbol name is
    /// ASCII with dots in it and an emoji is not, and no SF Symbol name is a
    /// single emoji character. Sequences count — a flag is two scalars and a
    /// family is five — so the test is on the first scalar of a single
    /// `Character`, which is what the palette inserts.
    static func isEmoji(_ string: String) -> Bool {
        guard string.count == 1, let character = string.first,
              let scalar = character.unicodeScalars.first
        else { return false }
        return scalar.properties.isEmojiPresentation
            || (scalar.properties.isEmoji && character.unicodeScalars.count > 1)
    }

    /// The emoji drawn at `pointSize`, or nil if it is not one.
    ///
    /// Never a template image: a template is a shape tinted with the row's ink,
    /// and an emoji tinted flat is a black blob where a picture was.
    static func image(_ string: String, pointSize: CGFloat) -> NSImage? {
        guard isEmoji(string) else { return nil }
        let key = "\(string)@\(pointSize)"
        if let cached = cache[key] { return cached }

        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: pointSize)]
        let text = NSAttributedString(string: string, attributes: attributes)
        // The square the row's icon slot is, not the glyph's own bounds: every
        // other icon in the column is `faviconSize` square, and an emoji laid
        // out at its natural width would sit a point or two off that column.
        let side = ceil(pointSize)
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let drawn = text.size()
            text.draw(at: NSPoint(
                x: rect.midX - drawn.width / 2,
                y: rect.midY - drawn.height / 2
            ))
            return true
        }
        image.isTemplate = false
        cache[key] = image
        return image
    }
}
