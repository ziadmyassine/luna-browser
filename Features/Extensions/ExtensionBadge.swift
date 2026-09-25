//
//  ExtensionBadge.swift
//  Luna
//
//  §16.4: the puzzle piece that stands for extensions, and an extension's
//  badge — a count or a word an extension puts on its button.
//
//  The badge is drawn two ways. In the pop-out it is a view beside the name,
//  where a row has room. On a pinned button it is drawn into the icon itself:
//  the three surfaces hold their glyphs in three different controls, and an
//  icon with its badge already on it is something all three can show.
//

import AppKit

enum ExtensionsSymbol {
    static let name = "puzzlepiece.extension"
    static let label = String(localized: "Extensions")

    static var image: NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: label)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: Tokens.Metric.faviconSize, weight: .regular))
    }
}

/// A badge beside an extension's name: the text in a capsule of the accent.
@MainActor
final class ExtensionBadgeView: NSView {

    var text = "" {
        didSet {
            label.stringValue = text
            isHidden = text.isEmpty
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        label.font = Tokens.TypeScale.settingsCaption
        label.alignment = .center
        addSubview(label)
        isHidden = true
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var intrinsicContentSize: NSSize {
        let height = Tokens.Metric.extensionRowBadgeHeight
        let width = ceil(label.intrinsicContentSize.width) + height / 2 + height / 2
        return NSSize(width: max(width, height), height: height)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Tokens.Accent.tint.cgColor
        layer?.cornerRadius = bounds.height / 2
        label.textColor = Tokens.Accent.onTint
    }

    override func layout() {
        super.layout()
        let height = label.intrinsicContentSize.height
        label.frame = NSRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height).integral
    }
}

enum ExtensionBadge {

    /// `icon` with `badge` drawn across its lower trailing corner, as Chrome
    /// draws it — or `icon` itself when there is no badge. Drawn on demand, so
    /// it is sharp at whatever scale the screen asks for.
    @MainActor
    static func composite(_ icon: NSImage?, badge: String) -> NSImage? {
        guard !badge.isEmpty else { return icon }
        let side = Tokens.Metric.faviconSize
        let font = Tokens.TypeScale.extensionBadge
        let fill = Tokens.Accent.tint
        let ink = Tokens.Accent.onTint
        let text = NSAttributedString(string: String(badge.prefix(4)), attributes: [.font: font, .foregroundColor: ink])
        let height = Tokens.Metric.extensionBadgeHeight
        let width = min(max(ceil(text.size().width) + height / 2, height), side)
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { bounds in
            icon?.draw(in: bounds)
            let capsule = NSRect(x: bounds.maxX - width, y: bounds.minY, width: width, height: height)
            // A ring of clear space round the badge, so it reads as lying on
            // the icon rather than as part of its artwork.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(roundedRect: capsule.insetBy(dx: -1, dy: -1), xRadius: height / 2 + 1, yRadius: height / 2 + 1).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            fill.setFill()
            NSBezierPath(roundedRect: capsule, xRadius: height / 2, yRadius: height / 2).fill()
            let size = text.size()
            text.draw(at: NSPoint(x: capsule.midX - size.width / 2, y: capsule.midY - size.height / 2))
            return true
        }
    }
}
