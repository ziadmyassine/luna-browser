//
//  SpaceCard.swift
//  Luna
//
//  §3.7's Space card: one card per Space, headed by that Space's own gradient.
//
//  A list of Spaces should be navigable by looking at it. The section used to
//  be a column of identical grey cards, and finding "the blue one" meant
//  reading every heading. The dot at the foot of the sidebar identifies a Space
//  by its colour; so does the wash behind the column; so does its card now.
//
//  The header carries §8.2a's `.full` intensity and §13.6's derived ink, which
//  is what those APIs are for: `foreground(on:at:in:)` picks the ink that clears
//  §21.4 against this pair's stops in this theme, so a Space on Mint or Blush is
//  legible in dark mode. That is the bug Zen ships.
//
//  The name and the fan-out line are set in the same ink at full strength. A
//  subtitle would normally step down to `Text.secondary`, and there is no such
//  step here: the ink was derived to clear 4.5:1, and fading it lands under the
//  floor. Size and weight tell the two lines apart instead.
//
//  Neutral paints no plate at all, which is the rule the sidebar's wash already
//  follows — a Space nobody has coloured has to be indistinguishable from no
//  Space colour, or "no colour" is a thirteenth colour. The card painted
//  neutral's desaturated grey as a plate, which is a light surface, which made
//  §13.6 correctly derive black ink: one card wearing black text in a dark
//  window. With no plate the header is the card's own surface and the ink is
//  the chrome's.
//
//  The corner button opens §6.2's two appearance settings — the icon and the
//  gradient — in the one place the Space is actually showing them. See
//  `SpaceAppearanceView` for why they left the row list.
//

import AppKit
import BrowserKit

/// One Space's card: its gradient, its name, its fan-out, and its rows.
@MainActor
final class SpaceCardView: NSView {

    private let space: Space
    private let header = SpaceHeaderPlate()
    private let symbol = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let fanOut = NSTextField(labelWithString: "")
    private let palette = SpaceAppearanceButton()
    private let card = SettingsCardView()

    /// - Parameters:
    ///   - subtitle: §9's fan-out — `SpacesSection.fanOutLabel`. The one line
    ///     no other browser shows, and the card's header is the first place a
    ///     user looks for it.
    ///   - onAppearance: the corner button. Handed the button so a popover can
    ///     stand on it.
    init(space: Space, subtitle: String, rows: [NSView], onAppearance: @escaping (NSView) -> Void) {
        self.space = space
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        // The header's top corners are the card's, so the card has to clip. It
        // is the only card in Settings that paints to its own edge.
        card.wantsLayer = true
        card.layer?.masksToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        buildHeader(subtitle: subtitle, onAppearance: onAppearance)
        let body = NSStackView(views: [header] + Self.ruled(rows))
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 0
        body.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(body)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            body.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            body.topAnchor.constraint(equalTo: card.topAnchor),
            body.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ] + body.arrangedSubviews.map { $0.widthAnchor.constraint(equalTo: body.widthAnchor) })
        applyInk()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// The button a popover stands on.
    var appearanceAnchor: NSView { palette }

    private func buildHeader(subtitle: String, onAppearance: @escaping (NSView) -> Void) {
        symbol.image = NSImage(systemSymbolName: space.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: Tokens.Metric.glyphSize, weight: .regular))
        symbol.translatesAutoresizingMaskIntoConstraints = false
        name.stringValue = space.name
        name.font = Tokens.TypeScale.settingsHeading
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false
        fanOut.stringValue = subtitle
        fanOut.font = Tokens.TypeScale.settingsCaption
        fanOut.lineBreakMode = .byTruncatingTail
        fanOut.translatesAutoresizingMaskIntoConstraints = false
        palette.onActivate = { [weak self] in
            guard let self else { return }
            onAppearance(palette)
        }
        palette.translatesAutoresizingMaskIntoConstraints = false
        for view in [symbol, name, fanOut, palette] as [NSView] { header.addSubview(view) }

        let inset = SettingsMetrics.cardInset
        let gap = Tokens.Metric.chromeGap
        NSLayoutConstraint.activate([
            symbol.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: inset),
            symbol.centerYAnchor.constraint(equalTo: name.centerYAnchor),
            symbol.widthAnchor.constraint(equalToConstant: Tokens.Metric.glyphSize),
            name.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: gap),
            name.topAnchor.constraint(equalTo: header.topAnchor, constant: inset),
            name.trailingAnchor.constraint(lessThanOrEqualTo: palette.leadingAnchor, constant: -gap),
            fanOut.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            fanOut.topAnchor.constraint(equalTo: name.bottomAnchor, constant: Tokens.Metric.rowGap),
            fanOut.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -inset),
            fanOut.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -inset),
            palette.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -gap),
            palette.topAnchor.constraint(equalTo: header.topAnchor, constant: gap)
        ])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyInk()
    }

    private func applyInk() {
        let theme = effectiveAppearance
        header.show(space.gradient)
        // See the file header: no plate, no derived ink. The chrome's own.
        let ink = Tokens.Gradient.isNeutral(space.gradient)
            ? Tokens.Text.primary
            : Tokens.Gradient.foreground(on: space.gradient, at: .full, in: theme)
        name.textColor = ink
        fanOut.textColor = ink
        symbol.contentTintColor = ink
        palette.tint = ink
    }

    /// The rows with a hairline between each pair, and one above the first —
    /// which `SettingsRowGroupView` does not have, because there it is the card
    /// edge that ends the group. Here the thing above the first row is the
    /// gradient, and a rule is what stops the plate and the row reading as one
    /// bleeding surface.
    private static func ruled(_ rows: [NSView]) -> [NSView] {
        rows.flatMap { [SettingsRuleView(), $0] }
    }
}

/// The gradient behind a card's header.
///
/// Its own view so the layer is sized by the pass that sizes the view: a
/// `CAGradientLayer` framed from the card's `layout()` is framed against a
/// header whose constraints have not been solved yet, which is a plate one
/// layout behind on every resize.
@MainActor
final class SpaceHeaderPlate: NSView {

    private let plate = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Top-leading to bottom-trailing, the same ramp the sidebar's wash and
        // the §3.5 dots use, so one Space is one gradient wherever it appears.
        plate.startPoint = CGPoint(x: 0, y: 1)
        plate.endPoint = CGPoint(x: 1, y: 0)
        layer?.addSublayer(plate)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// Neutral paints nothing, exactly as `SpaceWashView.washColors` does
    /// and for the same reason — see `SpaceCardView`'s header.
    func show(_ gradient: GradientPair) {
        guard !Tokens.Gradient.isNeutral(gradient) else {
            return Tokens.Motion.immediately { plate.colors = [] }
        }
        let stops = Tokens.Gradient.planes(gradient, at: .full, in: effectiveAppearance)
        Tokens.Motion.immediately { plate.colors = [stops.start.cgColor, stops.end.cgColor] }
    }

    override func layout() {
        super.layout()
        // Bounds-derived, so it may never animate — see `Motion.immediately`.
        Tokens.Motion.immediately { plate.frame = bounds }
    }
}

/// §3.7's corner button: §6.2's icon and gradient, in the corner of the card
/// that is already showing them.
///
/// No bezel and no glass. It stands on the Space's own gradient, and every
/// plate Luna could put under it would have to be measured against twelve pairs
/// in two themes to stay legible. The glyph in §13.6's derived ink is already
/// the ink that was proved against those pairs, so the button is the glyph.
@MainActor
final class SpaceAppearanceButton: NSView {

    var onActivate: (() -> Void)?
    var tint: NSColor = Tokens.Text.primary {
        didSet {
            glyph.contentTintColor = tint
        }
    }

    private let glyph = NSImageView()
    private var isHovering = false { didSet { if isHovering != oldValue { refresh() } } }
    private var isPressed = false {
        didSet {
            guard isPressed != oldValue else { return }
            refresh()
            Tokens.Motion.swell(self, to: isPressed ? Tokens.Motion.pressSwell : 1)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Tokens.Metric.settingsControlCorner
        glyph.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)?
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
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(String(localized: "Appearance"))
        toolTip = String(localized: "Icon and colour")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// §3.4's two washes and §6's swell — the answer every other button in
    /// the app gives. It had none: a bare glyph that did nothing at all until
    /// the popover appeared, which is the longest a button in Luna goes
    /// without admitting it has been clicked.
    private func refresh() {
        Tokens.Motion.wash(layer, to: isPressed
            ? Tokens.Surface.selected
            : (isHovering ? Tokens.Surface.hover : nil))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }

    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseDragged(with event: NSEvent) {
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        guard inside else { return }
        onActivate?()
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }
}
