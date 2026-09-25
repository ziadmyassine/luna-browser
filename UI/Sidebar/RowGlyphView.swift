//
//  RowGlyphView.swift
//  Luna
//
//  The one glyph-that-is-a-button the sidebar uses everywhere a row or a pill
//  needs a trailing affordance: §3.4's close/mute on a tab row, §3.2's sliders
//  on the URL pill, §5's reveal-in-Finder on a downloads row.
//
//  It lived in `SidebarRowView.swift` until that file passed 400 lines. It is
//  a separate class used by four callers, so it is a separate file.
//

import AppKit

/// The row's trailing affordance: close on hover, speaker while a tab is making
/// noise (§3.4). Its own accessibility element so VoiceOver can reach mute and
/// archive without a mouse (§21.1).
///
/// The chip is the pointer's, not the row's. §3.4 describes no chrome around
/// the glyph; a first pass gave it a permanent translucent square, which put a
/// grey tile on every row the pointer merely passed over. The square is the
/// affordance for this control, so it appears when the pointer is on this
/// control and not a moment before — glyph alone while the row is hovered, chip
/// plus a "Close Tab" tip once you are actually on it.
///
/// And every one of these glyphs wears it. The two inside §3.2's pill lifted
/// their ink instead for a while, on the argument that a rounded rectangle
/// inside a capsule is two shapes. The reference for a non-glass button —
/// three captures of a reload glyph at rest, under the pointer and under a
/// press — is that chip, and it was asked for by name on "the close tab icon or
/// site settings icon in the search bar". Same control, same affordance.
///
/// The fill is §3.4's pair: `Surface.hover` under the pointer, `Surface.selected`
/// under a press, cross-fading on §6's `controlHover` — which is what the
/// reference measures at, near enough (7.6 % and 12.8 % of white over a dark
/// bar, against Luna's 6 and 12). It is painted by the view's own layer,
/// under the image rather than over it: an `NSImageView` draws its image into
/// that layer's contents, so a background is behind the glyph and a sublayer
/// would be in front of it.
@MainActor
final class RowGlyphView: NSImageView {

    var onActivate: (() -> Void)?
    var tint: NSColor = Tokens.Text.secondary { didSet { applyTint() } }
    /// Fully rounded rather than the row's rounded square. §3.2's pill is a
    /// capsule, and a square chip inside its round end was a second shape
    /// against its edge; a capsule takes the pill's own rounding.
    var isRound = false { didSet { needsLayout = true } }

    private var isHovering = false { didSet { applyState() } }
    private var isPressed = false { didSet { applyState() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = Tokens.Metric.rowTrailingChip.cornerCurve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func applyTint() {
        contentTintColor = isHovering || isPressed ? Tokens.Text.primary : tint
    }

    /// The chip's fill, or nil at rest.
    private var chip: NSColor? {
        if isPressed { return Tokens.Surface.selected }
        return isHovering ? Tokens.Surface.hover : nil
    }

    private func applyState(animated: Bool = true) {
        applyTint()
        Tokens.Motion.wash(layer, to: chip, animated: animated)
    }

    func configure(symbolName: String, label: String, pointSize: CGFloat = Tokens.Metric.faviconSize) {
        configure(image: Self.inkCentred(symbolName, pointSize: pointSize), label: label, pointSize: pointSize)
    }

    /// The symbol, redrawn as a plain template image with its ink centred in
    /// its own box.
    ///
    /// SF Symbols are centred on their box, not on what is drawn in it, and
    /// the boxes carry different margins: measured on a §4 tab at 11 pt, the
    /// sliders' ink stood 0.75 pt below the close glyph's beside it. Measured
    /// once per symbol and size, from the symbol's own pixels.
    static func inkCentred(_ name: String, pointSize: CGFloat) -> NSImage? {
        let key = "\(name)@\(pointSize)"
        if let cached = inkCache[key] { return cached }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else { return nil }
        let size = symbol.size
        let scale: CGFloat = 4
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return symbol }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        symbol.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        // Rows are top-down in the bitmap.
        let inked = (0..<rep.pixelsHigh).filter { y in
            (0..<rep.pixelsWide).contains { x in (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.3 }
        }
        guard let top = inked.first, let bottom = inked.last else { return symbol }
        let inkMid = CGFloat(top + bottom + 1) / 2 / scale
        // Positive when the ink sits low, which is a nudge up in AppKit's y.
        // Redrawn even when the nudge is nothing: `NSImageView` places a
        // symbol image by its own metrics and a plain one by its box, so a
        // glyph left as a symbol stood half a point off one that was redrawn.
        let lift = inkMid - size.height / 2
        let centred = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect.offsetBy(dx: 0, dy: lift))
            return true
        }
        centred.isTemplate = true
        inkCache[key] = centred
        return centred
    }

    private static var inkCache: [String: NSImage] = [:]

    /// The same, for the one glyph SF Symbols does not have — `SiteMenuGlyph`.
    func configure(image glyph: NSImage?, label: String, pointSize: CGFloat = Tokens.Metric.faviconSize) {
        image = glyph
        symbolConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        // The tip is what the chip says once you are on it. Same string as the
        // VoiceOver label, because they answer the same question.
        toolTip = label
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
    }

    override func layout() {
        super.layout()
        // The chip is the hit box, which is what the glyph's own frame is —
        // see `URLPillLayout.placeContents`. Never taller than it is round.
        let round = min(bounds.width, bounds.height) / 2
        layer?.cornerRadius = isRound ? round : min(Tokens.Metric.rowTrailingChip.cornerRadius, round)
        layer?.cornerCurve = isRound ? .circular : Tokens.Metric.rowTrailingChip.cornerCurve
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyState(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Both colours were resolved into the appearance they were set in, so
        // the chip is re-resolved rather than merely re-drawn.
        applyState(animated: false)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        // The press is swallowed rather than ignored: the row underneath
        // treats a `mouseDown` as a selection click, and this one is not.
        isPressed = true
        Tokens.Motion.swell(self, to: Tokens.Motion.pressSwell)
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        Tokens.Motion.swell(self, to: 1)
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onActivate?()
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }
}
