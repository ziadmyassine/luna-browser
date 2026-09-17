//
//  SidebarRowView.swift
//  Luna
//
//  One 38 pt row (§3.4): `[status dot] [favicon 16] [title 13 pt] [trailing]`.
//  `Archive` and `+ Add Tab` are the same view with a symbol instead of a
//  favicon — §30.6 says they are first-class rows with identical metrics, so
//  they are literally the same class.
//
//  **No background is drawn here.** Unselected rows have none (§30.7), and the
//  selected pill and the hover fill are two single glass views that the list
//  moves between rows — see `TabListController`. That is what keeps a 40-row
//  scroll at 120 fps: a reused row view owns four subviews, lays them out with
//  arithmetic instead of constraints, and never allocates a glass effect.
//
//  Three spec deltas, all measured off `inspiration/main-tab-bar-and-ui.png`:
//
//  · §3.4's "favicon 12 pt from the pill's left edge, title 40 pt in" measures
//    17.5 / 45.5 — the favicon is square-inset inside the pill and the title
//    clears it by `rowIconGap`. The numbers live in `Metrics`, derived.
//  · §3.4's "single line, tail-truncated" is wrong: the reference **fades** an
//    over-long title out against the pill's trailing edge rather than spending
//    three characters on an `…`. That is what `titleClip` and `fade` are for —
//    the labels are laid out at their natural width inside a clipping box that
//    carries a gradient mask, so the last glyph dissolves instead of being cut.
//  · 13 pt, plain system font. See `Tokens.TypeScale.sidebarRow`.
//

import AppKit

/// Everything a row draws. A value type, so `configure` can no-op when nothing
/// changed — which is most of what a scroll does.
struct SidebarRowContent: Equatable {

    enum Trailing: Equatable {
        case none
        /// §3.4: click-to-mute.
        case audio(muted: Bool)
        /// Revealed on hover (§3.4).
        case close
    }

    var title: String = ""
    /// Drawn when there is no favicon — and for the command rows' own glyphs.
    var symbolName: String = "globe"
    var favicon: NSImage?
    var tintsSymbolWithAccent: Bool = false
    /// §3.4: leads the row only for unread/updated content.
    var hasUnread: Bool = false
    var isLoading: Bool = false
    var trailing: Trailing = .none
}

@MainActor
final class SidebarRowView: NSView {

    static let reuseIdentifier = NSUserInterfaceItemIdentifier("dk.novapps.luna.sidebar.row")

    /// The trailing affordance was clicked — mute, or close/archive.
    var onTrailing: (() -> Void)?

    var isSelected = false { didSet { refreshInk() } }
    var isHovered = false { didSet { refreshInk() } }

    private let icon = NSImageView()
    private let dot = NSView()
    /// Clips and fades both title layers. See the header.
    private let titleClip = NSView()
    private let title = NSTextField(labelWithString: "")
    /// The bright copy the §3.4 shimmer sweeps across. Hidden unless loading.
    private let shimmer = NSTextField(labelWithString: "")
    private let shimmerMask = CAGradientLayer()
    private let fadeMask = CAGradientLayer()
    private let trailing = RowGlyphView()
    private var content = SidebarRowContent()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseIdentifier
        wantsLayer = true

        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: Tokens.Metric.faviconSize,
            weight: .regular
        )
        dot.wantsLayer = true
        dot.layer?.cornerRadius = Tokens.Metric.spaceDot / 2
        trailing.chromed = true
        for label in [title, shimmer] {
            label.font = Tokens.TypeScale.sidebarRow
            // Clipping, not truncating: the fade below is what ends an
            // over-long title, and an ellipsis would be drawn *before* it.
            label.lineBreakMode = .byClipping
            label.cell?.usesSingleLineMode = true
            titleClip.addSubview(label)
        }
        titleClip.wantsLayer = true
        titleClip.layer?.masksToBounds = true
        shimmer.wantsLayer = true
        shimmerMask.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerMask.endPoint = CGPoint(x: 1, y: 0.5)
        fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        trailing.onActivate = { [weak self] in self?.onTrailing?() }

        for view in [icon, dot, titleClip, trailing] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.cell)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Content

    func configure(_ next: SidebarRowContent) {
        guard next != content else { return }
        let wasLoading = content.isLoading
        content = next
        title.stringValue = next.title
        shimmer.stringValue = next.title
        icon.image = next.favicon
            ?? NSImage(systemSymbolName: next.symbolName, accessibilityDescription: nil)
        icon.image?.isTemplate = next.favicon == nil
        dot.isHidden = !next.hasUnread
        setAccessibilityLabel(next.title)
        applyTrailing(next.trailing)
        refreshInk()
        if next.isLoading != wasLoading { updateShimmer() }
        needsLayout = true
    }

    private func applyTrailing(_ state: SidebarRowContent.Trailing) {
        switch state {
        case .none:
            trailing.isHidden = true
        case let .audio(muted):
            trailing.isHidden = false
            trailing.configure(
                symbolName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                label: muted ? "Unmute tab" : "Mute tab",
                pointSize: Tokens.Metric.rowTrailingGlyph
            )
        case .close:
            trailing.isHidden = false
            trailing.configure(
                symbolName: "xmark",
                label: "Archive tab",
                pointSize: Tokens.Metric.rowTrailingGlyph
            )
        }
    }

    // MARK: - Ink

    private func refreshInk() {
        // §3.4: the selected row has brighter text; hover promotes it the same
        // way, because Luna has no translucent hover-fill token to lift instead.
        let bright = isSelected || isHovered
        title.textColor = content.isLoading
            ? Tokens.Text.tertiary
            : (bright ? Tokens.Text.primary : Tokens.Text.secondary)
        shimmer.textColor = Tokens.Text.primary
        dot.layer?.backgroundColor = Tokens.Accent.tint.cgColor
        icon.contentTintColor = content.favicon != nil
            ? nil
            : (content.tintsSymbolWithAccent ? Tokens.Accent.tint : Tokens.Text.secondary)
        trailing.tint = bright ? Tokens.Text.primary : Tokens.Text.secondary
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshInk()
    }

    /// §21.2: Increase Contrast is not an appearance, so the list re-runs this
    /// on `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`.
    func accessibilityDisplayOptionsChanged() {
        refreshInk()
        updateShimmer()
    }

    // MARK: - Shimmer (§3.4 — a sweep across the title, never a spinner)

    private func updateShimmer() {
        shimmer.layer?.removeAnimation(forKey: "shimmer")
        // §21.2: Reduce Motion degrades this to a dimmed title and nothing else.
        guard content.isLoading, !Tokens.Motion.reduceMotion else {
            shimmer.isHidden = true
            shimmer.layer?.mask = nil
            return
        }
        shimmer.isHidden = false
        // A mask reads alpha only, so the token's *value* is irrelevant here —
        // what matters is that no literal colour is spelled out (contract rule 2).
        let opaque = Tokens.Text.primary
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shimmerMask.frame = shimmer.bounds
        shimmerMask.colors = [
            opaque.withAlphaComponent(0).cgColor,
            opaque.cgColor,
            opaque.withAlphaComponent(0).cgColor
        ]
        CATransaction.commit()
        shimmer.layer?.mask = shimmerMask
        let sweep = CABasicAnimation(keyPath: "locations")
        sweep.fromValue = [-0.6, -0.3, 0]
        sweep.toValue = [1, 1.3, 1.6]
        // No shimmer token exists in §6; the particle sweep is the nearest
        // published duration. See the report: `Tokens.Motion.rowShimmer`.
        sweep.duration = Tokens.Motion.downloadsParticleSweep.duration
        sweep.repeatCount = .infinity
        shimmerMask.add(sweep, forKey: "shimmer")
    }

    /// Everything but the trailing glyph belongs to the row: an `NSTextField`
    /// under the pointer would otherwise swallow the click that selects it, and
    /// the row itself has no `mouseDown`, so the event reaches the table.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        return (!trailing.isHidden && trailing.frame.contains(local)) ? trailing : self
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let inset = Tokens.Metric.rowInset
        let glyph = Tokens.Metric.faviconSize
        icon.frame = NSRect(
            x: Tokens.Metric.rowFaviconInset,
            y: (bounds.height - glyph) / 2,
            width: glyph,
            height: glyph
        ).integral

        let dotSize = Tokens.Metric.spaceDot
        dot.frame = NSRect(
            x: Tokens.Metric.rowTitleInset,
            y: (bounds.height - dotSize) / 2,
            width: dotSize,
            height: dotSize
        ).integral

        // **Inset from the pill, not from the row.** The pill is already
        // `rowInset` inside the row, so one inset put the chip flush against
        // the pill's edge; the reference keeps a full inset inside it.
        let chip = Tokens.Metric.rowTrailingChip
        trailing.frame = NSRect(
            x: bounds.maxX - 2 * inset - chip.width,
            y: (bounds.height - chip.height) / 2,
            width: chip.width,
            height: chip.height
        ).integral

        // The pill is `rowInset` inside the row, and the title keeps that same
        // inset inside the pill — so it ends two insets short of the row.
        let titleX = Tokens.Metric.rowTitleInset + (content.hasUnread ? dotSize + inset : 0)
        let titleRight = trailing.isHidden ? bounds.maxX - 2 * inset : trailing.frame.minX - Tokens.Metric.chromeGap
        let height = title.intrinsicContentSize.height
        let box = NSRect(
            x: titleX,
            y: (bounds.height - height) / 2,
            width: max(titleRight - titleX, 0),
            height: height
        ).integral
        titleClip.frame = box

        // Laid out at their *natural* width so nothing truncates; the clip box
        // and `fade` are what end the line.
        let natural = ceil(title.intrinsicContentSize.width)
        let inner = NSRect(x: 0, y: 0, width: max(natural, box.width), height: box.height)
        title.frame = inner
        shimmer.frame = inner
        // Standalone `CALayer`s animate their own frame changes implicitly, and
        // a scroll re-lays every visible row.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shimmerMask.frame = shimmer.bounds
        applyFade(overflowing: natural > box.width, width: box.width)
        CATransaction.commit()
    }

    /// §3.4's fade. Nil mask when the title fits: a gradient that is opaque
    /// end to end still costs a masked composite on every row of every scroll.
    private func applyFade(overflowing: Bool, width: CGFloat) {
        guard overflowing, width > Tokens.Metric.rowTitleFade else {
            titleClip.layer?.mask = nil
            return
        }
        let ink = Tokens.Text.primary
        fadeMask.frame = titleClip.bounds
        fadeMask.colors = [ink.cgColor, ink.cgColor, ink.withAlphaComponent(0).cgColor]
        fadeMask.locations = [0, NSNumber(value: Double(1 - Tokens.Metric.rowTitleFade / width)), 1]
        titleClip.layer?.mask = fadeMask
    }
}

/// The row's trailing affordance: close on hover, speaker while a tab is making
/// noise (§3.4). Its own accessibility element so VoiceOver can reach mute and
/// archive without a mouse (§21.1).
///
/// **A chip, not a bare glyph.** §3.4 describes no chrome around it and that is
/// what shipped — a floating `xmark` that read as part of the title. Martin's
/// close-button reference draws a rounded square with its own translucent fill
/// behind the glyph, and the fill is the only thing that says "click me".
/// `chromed` is off for the URL pill's sliders, which the reference genuinely
/// does draw bare.
@MainActor
final class RowGlyphView: NSImageView {

    var onActivate: (() -> Void)?
    var tint: NSColor = Tokens.Text.secondary { didSet { contentTintColor = tint } }

    /// Draws the chip. Off by default so the §3.2 sliders glyph stays bare.
    var chromed = false { didSet { needsDisplay = true } }

    private var isHovering = false

    func configure(symbolName: String, label: String, pointSize: CGFloat = Tokens.Metric.faviconSize) {
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        symbolConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
    }

    /// The chip is painted here rather than on the layer because `NSImageView`
    /// draws its own image in `draw(_:)` — a layer background would sit on top
    /// of the glyph, not behind it.
    override func draw(_ dirtyRect: NSRect) {
        if chromed {
            (isHovering ? Tokens.Surface.selected : Tokens.Surface.hover).setFill()
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
