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
/// plus a "Close Tab" tip once you are actually on it.
///
/// **And every one of these glyphs wears it.** For a while the two inside §3.2's
/// pill lifted their ink instead, on the argument that a rounded rectangle
/// inside a capsule is two shapes. Martin's reference for a non-glass button —
/// the three captures of a reload glyph at rest, under the pointer and under a
/// press — is that chip, and he asked for it by name on "the close tab icon or
/// site settings icon in the search bar". It is the same control in both
/// places, so it is the same affordance, and one behaviour is one set of bugs.
///
/// The fill is §3.4's pair: `Surface.hover` under the pointer, `Surface.selected`
/// under a press, cross-fading on §6's `controlHover` — which is what the
/// reference measures at, near enough (7.6 % and 12.8 % of white over a dark
/// bar, against Luna's 6 and 12). It is painted by the view's **own layer**,
/// under the image rather than over it: an `NSImageView` draws its image into
/// that layer's contents, so a background is behind the glyph and a sublayer
/// would be in front of it.
@MainActor
final class RowGlyphView: NSImageView {

    var onActivate: (() -> Void)?
    var tint: NSColor = Tokens.Text.secondary { didSet { applyTint() } }

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

    override func layout() {
        super.layout()
        // The chip is the hit box, which is what the glyph's own frame is —
        // see `URLPillLayout.placeContents`. Never taller than it is round.
        layer?.cornerRadius = min(
            Tokens.Metric.rowTrailingChip.cornerRadius,
            min(bounds.width, bounds.height) / 2
        )
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
