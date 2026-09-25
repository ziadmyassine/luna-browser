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
        /// Luna Control's own glyph, drawn rather than a symbol: three rings
        /// joined by dotted lines, in a gradient from the first colour at the
        /// top-left to the second at the bottom-right.
        case connected(NSColor, NSColor)
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
        case let .symbol(colour): drawGlyph(colour)
        case let .connected(from, to): drawConnected(in: context, colours: [from, to])
        }
    }

    private func drawGlyph(_ colour: NSColor) {
        let point = side * Self.glyphPointRatio
        let config = NSImage.SymbolConfiguration(pointSize: point, weight: .medium)
            .applying(.init(paletteColors: [colour]))
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let size = image.size
        let scale = min(side * Self.glyphRatio / max(size.width, size.height), 1)
        let drawn = NSSize(width: size.width * scale, height: size.height * scale)
        image.draw(in: NSRect(
            x: bounds.midX - drawn.width / 2, y: bounds.midY - drawn.height / 2,
            width: drawn.width, height: drawn.height
        ))
    }

    // MARK: Luna Control's glyph

    /// The glyph's width as a part of the side, and its line. The gear and
    /// the info circle beside it measure 0.54 of the side with a 0.045 line,
    /// but three open rings carry less ink than a solid outline, and at that
    /// size this read as the smallest tile in the list.
    private static let connectedInk: CGFloat = 0.6
    private static let connectedLine: CGFloat = 0.05
    /// A ring's radius to the middle of its line: small enough that two dots
    /// fit between neighbours, which a larger ring cut to one, and the rings
    /// stopped reading as connected.
    private static let connectedRing: CGFloat = 0.075
    /// From one dot's centre to the next, in lines: close enough for two,
    /// far enough that they stay two dots on the 22 pt list tile.
    private static let connectedPitch: CGFloat = 1.8

    /// Two rings above and one below, like the symbol this replaces, with
    /// the ink's box, not the triangle's centroid, on the tile's centre: that
    /// is how every symbol beside it is centred.
    private func drawConnected(in context: CGContext, colours: [NSColor]) {
        let line = side * Self.connectedLine
        let ring = side * Self.connectedRing
        let outer = ring + line / 2
        let edge = side * Self.connectedInk - 2 * outer
        let height = edge * sqrt(3) / 2 + 2 * outer
        let top = bounds.midY - height / 2 + outer
        let nodes = [
            CGPoint(x: bounds.midX - edge / 2, y: top),
            CGPoint(x: bounds.midX + edge / 2, y: top),
            CGPoint(x: bounds.midX, y: top + edge * sqrt(3) / 2)
        ]

        let ink = CGMutablePath()
        for node in nodes {
            let circle = CGPath(
                ellipseIn: CGRect(x: node.x - ring, y: node.y - ring, width: 2 * ring, height: 2 * ring), transform: nil
            )
            ink.addPath(circle.copy(strokingWithWidth: line, lineCap: .round, lineJoin: .round, miterLimit: 1))
        }
        // Dots of the line's width, as many as fit in the gap between two
        // rings, centred in it.
        let pitch = line * Self.connectedPitch
        let gap = edge - 2 * outer
        let count = max(1, Int((gap + line) / pitch - 0.5))
        for (from, to) in [(nodes[0], nodes[1]), (nodes[1], nodes[2]), (nodes[2], nodes[0])] {
            let run = (x: (to.x - from.x) / edge, y: (to.y - from.y) / edge)
            let span = CGFloat(count - 1) * pitch
            for index in 0..<count {
                let along = edge / 2 - span / 2 + CGFloat(index) * pitch
                let dot = CGPoint(x: from.x + run.x * along, y: from.y + run.y * along)
                ink.addEllipse(in: CGRect(x: dot.x - line / 2, y: dot.y - line / 2, width: line, height: line))
            }
        }

        let box = ink.boundingBoxOfPath
        context.saveGState()
        context.addPath(ink)
        context.clip()
        fill(context, colours, from: CGPoint(x: box.minX, y: box.minY), to: CGPoint(x: box.maxX, y: box.maxY))
        context.restoreGState()
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
