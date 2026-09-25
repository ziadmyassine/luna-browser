//
//  SettingsSymbolTile.swift
//  Luna
//
//  A section's symbol on its tile (`Tokens.Tile`): 22 pt in the section list,
//  44 pt at the head of the page. One view for both so the list and the page
//  cannot drift apart.
//

import AppKit

@MainActor
final class SettingsSymbolTile: NSView {

    enum Style: Equatable {
        /// A black tile with the symbol in the section's colour.
        case symbol(NSColor)
        /// The symbol in a gradient from the first colour at the top-left to
        /// the second at the bottom-right: Luna Control's.
        case gradient(NSColor, NSColor)
    }

    private let style: Style
    private let symbolName: String
    private let side: CGFloat

    init(symbolName: String, style: Style, side: CGFloat) {
        self.symbolName = symbolName
        self.style = style
        self.side = side
        super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var intrinsicContentSize: NSSize { NSSize(width: side, height: side) }

    override var isFlipped: Bool { true }

    /// The corner is macOS's own proportion for an icon tile: a little over
    /// a quarter of the side.
    static let cornerRatio: CGFloat = 0.28
    /// How much of the tile the glyph may fill, and the point size it is
    /// drawn at before it is fitted: half the side, which is how large
    /// macOS's own settings tiles set theirs.
    static let glyphRatio: CGFloat = 0.64
    static let glyphPointRatio: CGFloat = 0.5

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let tile = bounds.insetBy(dx: Tokens.Metric.hairline / 2, dy: Tokens.Metric.hairline / 2)
        let path = CGPath(
            roundedRect: tile, cornerWidth: side * Self.cornerRatio, cornerHeight: side * Self.cornerRatio, transform: nil
        )
        let colours = [Tokens.Tile.top, Tokens.Tile.bottom]

        context.saveGState()
        context.addPath(path)
        context.clip()
        fill(context, colours, from: CGPoint(x: tile.midX, y: tile.minY), to: CGPoint(x: tile.midX, y: tile.maxY))
        context.restoreGState()

        context.addPath(path)
        context.setStrokeColor(Tokens.Tile.rim.cgColor)
        context.setLineWidth(Tokens.Metric.hairline / 2)
        context.strokePath()

        switch style {
        case let .symbol(colour): drawGlyph([colour])
        case let .gradient(from, to): drawGlyph([from, to])
        }
    }

    /// One colour is the glyph's; two are a diagonal gradient, painted over
    /// the glyph in an image of its own so it fills only the glyph's shape.
    private func drawGlyph(_ colours: [NSColor]) {
        let point = side * Self.glyphPointRatio
        let config = NSImage.SymbolConfiguration(pointSize: point, weight: .medium)
            .applying(.init(paletteColors: [colours[0]]))
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let size = symbol.size
        let scale = min(side * Self.glyphRatio / max(size.width, size.height), 1)
        let drawn = NSSize(width: size.width * scale, height: size.height * scale)
        var image = symbol
        if colours.count > 1, let gradient = NSGradient(colors: colours) {
            image = NSImage(size: size, flipped: false) { rect in
                symbol.draw(in: rect)
                NSGraphicsContext.current?.compositingOperation = .sourceIn
                gradient.draw(in: rect, angle: -45)
                return true
            }
        }
        image.draw(in: NSRect(
            x: bounds.midX - drawn.width / 2, y: bounds.midY - drawn.height / 2,
            width: drawn.width, height: drawn.height
        ))
    }

    private func fill(_ context: CGContext, _ colours: [NSColor], from: CGPoint, to: CGPoint) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colours.map(\.cgColor) as CFArray, locations: nil
        ) else { return }
        context.drawLinearGradient(gradient, start: from, end: to, options: [])
    }
}

/// The top of a section's page: its tile, its name and one line on what it
/// is for. The name used to live only in the list; a pane that opened on a
/// card had nothing to say which pane it was.
@MainActor
final class SettingsPageHeader: NSView {

    init(title: String, summary: String, symbolName: String, style: SettingsSymbolTile.Style) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let tile = SettingsSymbolTile(symbolName: symbolName, style: style, side: Tokens.Metric.settingsPageTile)
        let name = NSTextField(labelWithString: title)
        name.font = Tokens.TypeScale.settingsPageTitle
        let line = NSTextField(wrappingLabelWithString: summary)
        line.font = Tokens.TypeScale.settingsCaption
        line.textColor = Tokens.Text.secondary
        let words = NSStackView(views: [name, line])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 2
        for view in [tile, words] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            tile.leadingAnchor.constraint(equalTo: leadingAnchor),
            tile.topAnchor.constraint(equalTo: topAnchor),
            tile.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            words.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: SettingsMetrics.controlInset),
            words.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            words.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            words.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("\(title). \(summary)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }
}
