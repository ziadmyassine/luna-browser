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
/// **The chip is the pointer's, not the row's.** §3.4 describes no chrome around
/// the glyph; a first pass gave it a permanent translucent square, which put a
/// grey tile on every row the pointer merely passed over. The square is the
/// affordance for *this* control, so it appears when the pointer is on this
/// control and not a moment before — glyph alone while the row is hovered, chip
/// plus a "Close Tab" tip once you are actually on it. §3.2's sliders glyph
/// asks for the same chip, for the same reason and out of the same two tokens.
@MainActor
final class RowGlyphView: NSImageView {

    var onActivate: (() -> Void)?
    var tint: NSColor = Tokens.Text.secondary { didSet { applyTint() } }

    /// **Hover lifts the ink instead of drawing a chip.** The chip is a badge's
    /// affordance — it says "this mark you are reading is also a button" — and
    /// it is right on a tab row, where the glyph appears inside a title. A
    /// glyph that is plainly one of a row of controls, like §3.2's two inside
    /// the pill, wants what every other control in Luna's chrome does: the
    /// secondary-to-primary step the `GlassButton`s beside it take. A rounded
    /// rectangle inside a capsule would be two shapes.
    var liftsInk = false { didSet { applyTint() } }

    /// Draws the chip. Off by default: a glyph that is its own button — the
    /// §3.1 circles, the §3.5 bar — already has a shape, and a second one
    /// inside it is two backgrounds.
    var chromed = false { didSet { needsDisplay = true } }

    private var isHovering = false { didSet { applyTint() } }

    private func applyTint() {
        contentTintColor = liftsInk && isHovering ? Tokens.Text.primary : tint
    }

    func configure(symbolName: String, label: String, pointSize: CGFloat = Tokens.Metric.faviconSize) {
        configure(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: nil), label: label, pointSize: pointSize)
    }

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

    /// The chip is painted here rather than on the layer because `NSImageView`
    /// draws its own image in `draw(_:)` — a layer background would sit on top
    /// of the glyph, not behind it.
    override func draw(_ dirtyRect: NSRect) {
        if chromed, isHovering {
            Tokens.Surface.selected.setFill()
            let radius = Tokens.Metric.rowTrailingChip.cornerRadius
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        }
        super.draw(dirtyRect)
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
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyTint()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        // Swallowed so the row does not also treat this as a selection click.
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
