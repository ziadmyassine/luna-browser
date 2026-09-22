//
//  TopBarButton.swift
//  Luna
//
//  Every control on the top bar: the sidebar toggle, back, a tab tile, a
//  capsule item, a tab chip, a folder's header (UI-SPEC §4). One class, because
//  they differ only in their `RoundedMetric`, whether they carry glass, and
//  whether they carry a word.
//
//  `titleText` is what makes a chip out of a tile, and it is one property
//  rather than a second class because everything else about the two is the same
//  control: the same two washes, the same swell, the same right-click, the same
//  focus ring, the same `AXButton`. §4's strip draws a kept tab as an icon and
//  an open one as an icon with its title beside it, and that is the whole of
//  the difference.
//
//  It is an `NSButton` on purpose. §20.2 wants a visible focus ring, the key
//  view loop and space/return activation on every chrome control, and §21.1
//  wants an `AXButton` with a label — `NSButton` ships all four, and a bare
//  `NSView` would mean re-implementing them badly.
//
//  The one structural consequence: `Glass` hands back a subview, and a
//  subview draws over the cell, so the cell is left drawing nothing at all.
//  The stack is glass → hover fill → glyph, bottom to top, and `hitTest`
//  collapses it back onto the button so the decoration never eats a click.
//
//  It answers a press as well as a hover, on §3.4's two washes and §6's
//  `controlPress` — the same answer `GlassButton` gives in the sidebar, so the
//  toggle in one bar and the toggle in the other are the same control in the
//  hand. The bar had only the hover half for several builds, so a click read
//  as nothing happening until the page moved.
//
//  A button inside a capsule hands its press up (`ownsItsMaterial`): §4's
//  action capsule applies one material for all its items, and half a capsule
//  swelling inside the other half is not a press. `TopBarActionCapsule` takes
//  the gesture over; a tab tile, on the bare bar, keeps it. That is
//  `GlassButton.GlassMode.none`'s rule in the other bar.
//
//  Increase Contrast is not an appearance on macOS 26.5 (see the `Tokens`
//  header), so nothing here invalidates on its own: `TopBarView` owns the one
//  `NSWorkspace` observer for the whole bar and calls `applyTokens()` down the
//  tree.
//

import AppKit

@MainActor
final class TopBarButton: NSButton {

    /// The glyph, favicon or nothing at all. Favicons are not template images,
    /// so `contentTintColor` leaves their own colours alone.
    var icon: NSImage? {
        get { glyph.image }
        set { glyph.image = newValue }
    }

    /// The word beside the icon, or nil for an icon on its own. Setting it
    /// changes the button's width, which is why it invalidates the intrinsic
    /// size rather than only asking for a layout pass.
    var titleText: String? {
        didSet {
            guard titleText != oldValue else { return }
            label.stringValue = titleText ?? ""
            label.isHidden = titleText == nil
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    /// §3.4's selected fill, standing still: this is the tab the window is
    /// showing. The same 12 % plate and the same ring the column's pill wears,
    /// because it is the same statement in the other layout.
    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            refreshFill()
        }
    }

    /// Told when the button goes down and comes back up. For the one case a
    /// button cannot answer a press itself — see `ownsItsMaterial`.
    var onPressChange: ((Bool) -> Void)?
    /// Whether the swell is this button's to perform. False for an item inside
    /// §4's action capsule, whose material belongs to the capsule.
    var ownsItsMaterial = true

    /// The shape this button was built as. Read by §4's strip, which rebuilds
    /// a chip when its tier changes its shape — see `TopBarTabStrip.chip(for:)`.
    let metric: RoundedMetric
    private let hoverFill = NSView()
    private let glyph = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var tracking: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false

    /// - Parameters:
    ///   - metric: the drawn size and corner radius. Also the intrinsic size,
    ///     so an Auto Layout caller needs no size constraints.
    ///   - glass: §2's "Liquid Glass, clear" for controls and capsule items.
    ///     Tab tiles pass `false`: the reference draws them as a bare icon on
    ///     the bar, with no fill of their own until hover.
    init(metric: RoundedMetric, glass: Bool) {
        self.metric = metric
        super.init(frame: NSRect(origin: .zero, size: metric.size))

        isBordered = false
        title = ""
        wantsLayer = true

        if glass { Glass.apply(.control, to: self, cornerRadius: metric.cornerRadius) }

        hoverFill.wantsLayer = true
        hoverFill.layer?.cornerCurve = metric.cornerCurve
        hoverFill.layer?.cornerRadius = metric.cornerRadius
        addSubview(hoverFill)

        glyph.imageScaling = .scaleProportionallyUpOrDown
        addSubview(glyph)

        label.isHidden = true
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        addSubview(label)

        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code")
    }

    /// An SF Symbol sized to the bar's glyph size, and weighted so it draws the
    /// same line as the rest of them — see `TypeScale.glyphWeight(for:)`, for
    /// why one nominal weight is not one apparent weight. Nil only for a name
    /// the installed SF Symbols set does not have.
    static func symbol(_ name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: TopBarMetrics.glyph,
            weight: Tokens.TypeScale.glyphWeight(for: name)
        )
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    // MARK: - Geometry

    /// A tile is its metric. A chip is as wide as its word needs, between the
    /// two ends `TopBarMetrics` names: narrower than the floor and the title is
    /// an ellipsis with nothing in front of it, wider than the ceiling and one
    /// long page title is the whole bar.
    override var intrinsicContentSize: NSSize {
        guard titleText != nil else { return metric.size }
        // `fittingSize`, not `intrinsicContentSize`: the latter reports the
        // glyph run without the cell's 2 pt title inset on each side, and a
        // chip framed to it tail-truncates a title that fits.
        let text = label.fittingSize.width.rounded(.up)
        let width = TopBarMetrics.chipInset * 2 + TopBarMetrics.glyph + TopBarMetrics.gap + text
        return NSSize(
            width: min(max(width, TopBarMetrics.chipFloor), TopBarMetrics.chipCeiling),
            height: metric.height
        )
    }

    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately { placeContents() }
    }

    private func placeContents() {
        hoverFill.frame = bounds
        let size = TopBarMetrics.glyph
        let y = ((bounds.height - size) / 2).rounded()
        guard titleText != nil else {
            glyph.frame = NSRect(x: ((bounds.width - size) / 2).rounded(), y: y, width: size, height: size)
            return
        }
        glyph.frame = NSRect(x: TopBarMetrics.chipInset, y: y, width: size, height: size)
        let textX = glyph.frame.maxX + TopBarMetrics.gap
        let line = label.font?.boundingRectForFont.height.rounded(.up) ?? size
        label.frame = NSRect(
            x: textX,
            y: ((bounds.height - line) / 2).rounded(),
            width: max(bounds.width - TopBarMetrics.chipInset - textX, 0),
            height: line
        )
    }

    /// The glass backing and the glyph are decoration. Without this they would
    /// win the hit test and swallow the click before the button saw it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled, let superview else { return nil }
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }

    // MARK: - Hover (§3.1: hover lifts the fill, not the border)

    /// §3.4a's right-click, built when it is asked for.
    ///
    /// Not `NSView.menu`, which is one menu assigned once: every item in a tab's menu
    /// states that tab's current answer — whether it is pinned, whether it is muted — and
    /// a menu held over from the last press would be checkmarks for another moment.
    var menuBuilder: (() -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        menuBuilder?() ?? super.menu(for: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ hovered: Bool) {
        guard isEnabled, hovered != isHovered else { return }
        isHovered = hovered
        refreshFill()
    }

    // MARK: - Press (§3.4's second wash, §6's `controlPress`)

    /// The press is taken around `NSControl`'s tracking, not instead of it.
    /// `super.mouseDown` does not return until the mouse comes back up — it
    /// runs the cell's own tracking loop, which is where `sendAction` happens —
    /// so the state is set on either side of that call. Re-implementing the
    /// tracking to get a notification in the middle of it would cost the key
    /// loop, the focus ring and `AXPress`, which are the four reasons this is
    /// an `NSButton` at all (see the file header).
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        setPressed(true)
        super.mouseDown(with: event)
        setPressed(false)
    }

    /// AppKit's own way of saying "this button is down", which a key equivalent
    /// takes rather than the tracking loop above. `setPressed` is idempotent,
    /// so the two routes cannot double up.
    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        setPressed(flag && isEnabled)
    }

    private func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        refreshFill()
        onPressChange?(pressed)
        guard ownsItsMaterial else { return }
        Tokens.Motion.swell(self, to: pressed ? Tokens.Motion.pressSwell : 1)
    }

    /// §3.4's two washes: the pointer's, and the press's at twice it. A
    /// disabled button is in neither — it does not answer a pointer at all.
    ///
    /// A selected button is already wearing the press's wash and stays there
    /// under the pointer, exactly as §3.4's row pill does: the plate says which
    /// tab this is, and brightening it for a hover would say it twice.
    private var fillColour: NSColor? {
        guard isEnabled else { return nil }
        if isPressed || isSelected { return Tokens.Surface.selected }
        return isHovered ? Tokens.Surface.hover : nil
    }

    private func refreshFill() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            Tokens.Motion.wash(self.hoverFill.layer, to: self.fillColour)
            // §3.4's selected pill is a fill and a ring. Written straight
            // rather than washed: a border animating its colour to nil leaves
            // a hairline of the old one on the frame it lands on.
            self.hoverFill.layer?.borderWidth = self.isSelected ? Tokens.Metric.hairline : 0
            self.hoverFill.layer?.borderColor = self.isSelected ? Tokens.Line.border.cgColor : nil
        }
    }

    // MARK: - Focus ring (§20.2)

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(
            roundedRect: bounds,
            xRadius: metric.cornerRadius,
            yRadius: metric.cornerRadius
        ).fill()
    }

    // MARK: - Tokens

    override var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            if !isEnabled {
                setHovered(false)
                setPressed(false)
            }
            applyTokens()
        }
    }

    /// Re-resolves every token this view holds by value. Called on creation, on
    /// an appearance change, and by `TopBarView` when the accessibility display
    /// options flip.
    func applyTokens() {
        // §3.1 dims a disabled control. There is no `disabledAlpha` token, and
        // the cell's own dimming is unavailable here (the glyph is a subview),
        // so the dimmest ink tier stands in — it is a real token and it is the
        // right direction. See the report: `Tokens.Text.disabled` is missing.
        glyph.contentTintColor = isEnabled ? Tokens.Text.primary : Tokens.Text.tertiary
        label.font = Tokens.TypeScale.sidebarRow
        label.textColor = isEnabled ? Tokens.Text.primary : Tokens.Text.tertiary
        // §3.4's 6 % lift, and 12 % under a press. This used to borrow
        // `Line.border` because the note said no hover token existed;
        // `Surface.hover` is that token and it is the same 6 %, so the
        // stand-in is gone.
        refreshFill()
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }
}
