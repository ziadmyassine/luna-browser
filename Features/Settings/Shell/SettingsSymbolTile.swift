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
        /// Luna Control: its sky in small, the moon with its glow and one
        /// app on its orbit, drawn rather than a symbol so the list shows the
        /// same picture the page opens on.
        case moon
        /// About: the app's own icon in place of a tile.
        case appIcon
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
        if style == .appIcon {
            NSApp.applicationIconImage?.draw(in: bounds)
            return
        }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let tile = bounds.insetBy(dx: Tokens.Metric.hairline / 2, dy: Tokens.Metric.hairline / 2)
        let path = CGPath(
            roundedRect: tile, cornerWidth: side * Self.cornerRatio, cornerHeight: side * Self.cornerRatio, transform: nil
        )
        let colours = style == .moon ? [Tokens.Moon.skyBottom, Tokens.Moon.skyTop] : [Tokens.Tile.top, Tokens.Tile.bottom]

        context.saveGState()
        context.addPath(path)
        context.clip()
        fill(context, colours, from: CGPoint(x: tile.midX, y: tile.minY), to: CGPoint(x: tile.midX, y: tile.maxY))
        if style == .moon { drawSky(in: context) }
        context.restoreGState()

        context.addPath(path)
        context.setStrokeColor(Tokens.Tile.rim.cgColor)
        context.setLineWidth(Tokens.Metric.hairline / 2)
        context.strokePath()

        if case let .symbol(colour) = style { drawGlyph(colour) }
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

    // MARK: Luna Control's sky

    /// The moon's radius, the orbit's two half-axes and the satellite's
    /// radius, as parts of the side. Measured on the 22 pt list tile: a
    /// smaller moon lost its craters to the pixel grid, and a flatter orbit
    /// stopped reading as a ring round it.
    private static let moonRatio: CGFloat = 0.25
    private static let orbitRatio = CGSize(width: 0.42, height: 0.14)
    private static let satelliteRatio: CGFloat = 0.06
    /// The sky's own orbit tilt and a gibbous moon, the phase the page's
    /// switch rises to.
    private static let moonPhase: CGFloat = 0.8
    private static let earthshine: CGFloat = 0.35
    /// Half the page's glow: the glow reaches three radii out, which on a
    /// tile this size is the whole tile, and at full strength it turned the
    /// night grey.
    private static let glow: CGFloat = 0.5
    /// Stronger than the page's orbits: at 22 pt the ring is a hairline, and
    /// at their strength it disappeared into the glow.
    private static let orbitAlpha: CGFloat = 0.6

    /// The orbit behind the moon, the moon and its glow, then the orbit's near
    /// half and the app on it over the moon: the ring passes round it rather
    /// than across it.
    private func drawSky(in context: CGContext) {
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        let orbit = CGSize(width: side * Self.orbitRatio.width, height: side * Self.orbitRatio.height)
        let turn = CGAffineTransform(translationX: centre.x, y: centre.y)
            .rotated(by: Tokens.Metric.controlOrbitTilt)
        let ring = CGPath(
            ellipseIn: CGRect(x: -orbit.width, y: -orbit.height, width: 2 * orbit.width, height: 2 * orbit.height),
            transform: [turn]
        )
        let line = max(Tokens.Metric.hairline / 2, side * 0.03)
        context.setLineWidth(line)
        context.setStrokeColor(Tokens.Moon.orbit.withAlphaComponent(Self.orbitAlpha).cgColor)
        context.addPath(ring)
        context.strokePath()

        ControlMoon.draw(
            in: context, center: centre, radius: side * Self.moonRatio,
            light: ControlMoon.Light(phase: Self.moonPhase, glow: Self.glow, earthshine: Self.earthshine),
            scale: window?.backingScaleFactor ?? 2
        )

        // The near half is the half below the orbit's long axis, which is the
        // half in front of the moon in a sky seen from a little above.
        context.saveGState()
        context.concatenate(turn)
        context.clip(to: CGRect(x: -side, y: 0, width: 2 * side, height: side))
        context.setStrokeColor(Tokens.Moon.orbit.withAlphaComponent(Self.orbitAlpha).cgColor)
        context.addEllipse(in: CGRect(x: -orbit.width, y: -orbit.height, width: 2 * orbit.width, height: 2 * orbit.height))
        context.strokePath()
        let angle = CGFloat.pi * 0.28
        let light = CGPoint(x: orbit.width * cos(angle), y: orbit.height * sin(angle))
        drawSatellite(in: context, at: light, radius: side * Self.satelliteRatio)
        context.restoreGState()
    }

    private func drawSatellite(in context: CGContext, at point: CGPoint, radius: CGFloat) {
        let colour = Tokens.Moon.satellite(1)
        let glow = [colour.withAlphaComponent(0.55).cgColor, colour.withAlphaComponent(0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: glow, locations: nil) {
            context.drawRadialGradient(
                gradient, startCenter: point, startRadius: radius, endCenter: point, endRadius: radius * 3.2, options: []
            )
        }
        context.setFillColor(colour.cgColor)
        context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius))
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
