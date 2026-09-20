//
//  SpaceAppearance.swift
//  Luna
//
//  §6.2's icon and gradient, taken out of the row list and put behind the Space
//  card's corner button.
//
//  **Two popups were the wrong shape for both of these settings.** A colour
//  chosen from a menu of twelve words is a colour you have to open the menu
//  twelve times to compare, and `NSMenuItem.image` does not draw on this macOS
//  at all (see `SidebarMenu.label`) — so the swatches in that popup were words
//  with nothing beside them. An icon chosen from a list of nouns is the same
//  problem: "Flask" is not a picture of a flask. Both are grids of the thing
//  itself here, which is the only presentation in which "which one is that"
//  is not a question.
//
//  It is a popover rather than a sheet or a second pane because it is **two
//  settings**. A pane would need a way back; a sheet would need a Done button;
//  a popover is dismissed by looking away from it, which is the right cost for
//  a choice you can undo by making it again.
//
//  Neutral is in the grid, last, and is not a thirteenth colour: §13.6's one
//  click back. Arc needed a help article for "How Do I Restore the Default
//  Theme" and Zen has an open issue for being unable to unset a gradient at
//  all, both of which are what happens when the way out is somewhere other
//  than the way in.
//

import AppKit
import BrowserKit

/// The corner button's popover: every gradient and every icon, as themselves.
@MainActor
final class SpaceAppearanceView: NSView {

    /// §8.2's twelve, and §13.6's neutral after them.
    static var gradients: [GradientPair] { Tokens.Gradient.spacePalette + [Tokens.Gradient.neutral] }
    static var gradientNames: [String] { Tokens.Gradient.spacePaletteNames + [String(localized: "No Colour")] }

    /// How many chips fit a row before it wraps. Seven takes §8.2's twelve
    /// plus neutral in two rows, and the thirteen symbols in two more — so the
    /// popover is four rows of chips on one column grid, whichever half of it
    /// you are looking at.
    private static let columns = 7

    private var swatches: [SpaceSwatchChip] = []
    private var symbols: [SpaceSymbolChip] = []

    init(space: Space, onGradient: @escaping (GradientPair) -> Void, onIcon: @escaping (String) -> Void) {
        super.init(frame: .zero)
        swatches = zip(Self.gradients, Self.gradientNames).map { gradient, label in
            let chip = SpaceSwatchChip(gradient: gradient, label: label)
            chip.isChosen = gradient == space.gradient
            chip.onActivate = { [weak self] in
                self?.choose(gradient: gradient)
                onGradient(gradient)
            }
            return chip
        }
        symbols = SpacesSection.symbols.map { symbol in
            let chip = SpaceSymbolChip(symbolName: symbol.name, label: symbol.label)
            chip.isChosen = symbol.name == space.symbolName
            chip.onActivate = { [weak self] in
                self?.choose(symbol: symbol.name)
                onIcon(symbol.name)
            }
            return chip
        }

        let stack = NSStackView(views: [
            Self.heading(String(localized: "Colour"))
        ] + Self.grid(swatches, columns: Self.columns) + [
            Self.heading(String(localized: "Icon"))
        ] + Self.grid(symbols, columns: Self.columns))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Tokens.Metric.chromeGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let inset = Tokens.Metric.chromeGapWide
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// **The popover marks the choice itself rather than waiting to be rebuilt.**
    /// Both writes are `async` and both are followed by a section rebuild that
    /// throws this view away; until it lands, a grid that still shows the old
    /// ring reads as a click that did not register.
    private func choose(gradient: GradientPair) {
        for chip in swatches { chip.isChosen = chip.gradient == gradient }
    }

    private func choose(symbol: String) {
        for chip in symbols { chip.isChosen = chip.symbolName == symbol }
    }

    private static func heading(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = Tokens.TypeScale.sectionLabel
        label.textColor = Tokens.Text.secondary
        return label
    }

    /// `columns` chips a row, wrapping. Every row is a stack of its own so a
    /// short last row stays left-aligned under the one above it.
    private static func grid(_ chips: [NSView], columns: Int) -> [NSView] {
        stride(from: 0, to: chips.count, by: columns).map { start in
            let row = NSStackView(views: Array(chips[start..<min(start + columns, chips.count)]))
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = Tokens.Metric.chromeGap
            return row
        }
    }
}

/// One gradient, as itself.
@MainActor
final class SpaceSwatchChip: NSView {

    let gradient: GradientPair
    var onActivate: (() -> Void)?
    var isChosen = false { didSet { needsDisplay = true } }

    private let disc = CAGradientLayer()

    init(gradient: GradientPair, label: String) {
        self.gradient = gradient
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(disc)
        let side = Tokens.Metric.settingsControl
        widthAnchor.constraint(equalToConstant: side).isActive = true
        heightAnchor.constraint(equalToConstant: side).isActive = true
        toolTip = label
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        setAccessibilityValue(isChosen)
        Tokens.Motion.immediately {
            // The ring is drawn **outside** the disc rather than on it, so the
            // colour a swatch is showing is the whole of the colour it offers:
            // a border painted over the edge of a 28 pt circle takes a tenth of
            // it away, and that tenth is the darkest part of the ramp.
            let ring = Tokens.Metric.spaceSwatchRing
            disc.frame = bounds.insetBy(dx: ring * 2, dy: ring * 2)
            disc.cornerRadius = disc.frame.width / 2
            let stops = Tokens.Gradient.planes(gradient, at: .full, in: effectiveAppearance)
            disc.startPoint = CGPoint(x: 0, y: 1)
            disc.endPoint = CGPoint(x: 1, y: 0)
            disc.colors = [stops.start.cgColor, stops.end.cgColor]
            // §21.2 Differentiate Without Colour: the chosen swatch is the only
            // one wearing a ring, and a light gradient on a light popover needs
            // the hairline regardless to have a shape at all.
            disc.borderWidth = Tokens.Metric.hairline
            disc.borderColor = Tokens.Line.border.cgColor
            layer?.cornerRadius = bounds.width / 2
            layer?.borderWidth = isChosen ? ring : 0
            layer?.borderColor = Tokens.Text.primary.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onActivate?()
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }
}

/// One SF Symbol, as itself. §13.10: Arc takes emoji too and Luna does not yet
/// — that gap is in the report rather than pretended away.
@MainActor
final class SpaceSymbolChip: NSView {

    let symbolName: String
    var onActivate: (() -> Void)?
    var isChosen = false {
        didSet {
            needsDisplay = true
            applyInk()
        }
    }

    private let glyph = NSImageView()

    init(symbolName: String, label: String) {
        self.symbolName = symbolName
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        glyph.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: Tokens.Metric.glyphSize, weight: .regular))
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)
        let side = Tokens.Metric.settingsControl
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: side),
            heightAnchor.constraint(equalToConstant: side),
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        toolTip = label
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(label)
        applyInk()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        setAccessibilityValue(isChosen)
        Tokens.Motion.immediately {
            layer?.cornerRadius = Tokens.Metric.settingsControlCorner
            // A fill rather than a ring: a symbol is line art and a hairline
            // around it is one more line in a grid that is already all lines.
            layer?.backgroundColor = isChosen ? Tokens.Surface.selected.cgColor : nil
        }
    }

    private func applyInk() {
        glyph.contentTintColor = isChosen ? Tokens.Text.primary : Tokens.Text.secondary
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyInk()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onActivate?()
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }
}
