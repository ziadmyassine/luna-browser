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

    /// This is the tab the window is showing. A `.dormant` chip turns to glass
    /// for it — the same clear cylinder the kept run stands in, so "the tab you
    /// are on" and "the tabs you keep" are made of the one material the bar
    /// has. The glass fades in on §6's `controlHover` and out the same way.
    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            updateGlass(animated: true)
            refreshFill()
            updateClose()
        }
    }

    /// §3.4's close, on an open tab. Set, the chip grows a trailing
    /// `RowGlyphView` — the same control the column's rows carry — shown while
    /// the pointer is on the chip. Nil for anything that cannot be closed.
    var onClose: (() -> Void)? {
        didSet { updateClose() }
    }

    /// When the chip carries glass: always, only while it is the tab you are
    /// on, or never.
    enum GlassMode { case always, dormant, none }

    /// Makes the chip draggable (§6.6). Handed the press that started the
    /// gesture, not the drag that noticed it, so whoever takes over can lift
    /// from where the finger went down; nil for a control that does not travel.
    ///
    /// Setting it takes the press off `NSControl`'s tracking loop — see
    /// `mouseDown`.
    var onDragOut: ((NSEvent) -> Void)?

    /// Told when the button goes down and comes back up. For the one case a
    /// button cannot answer a press itself — see `ownsItsMaterial`.
    var onPressChange: ((Bool) -> Void)?
    /// Whether the swell is this button's to perform. False for an item inside
    /// §4's action capsule, whose material belongs to the capsule.
    var ownsItsMaterial = true

    /// The shape this button was built as. Read by §4's strip, which rebuilds
    /// a chip when its tier changes its shape — see `TopBarTabStrip.chip(for:)`.
    let metric: RoundedMetric
    private let glassMode: GlassMode
    /// Built the first time a `.dormant` chip is selected and kept, faded on
    /// its alpha after that. A dormant chip that is never the tab you are on
    /// never pays for a glass view.
    private var glassBacking: NSView?
    private let hoverFill = NSView()
    private let glyph = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let closeChip = RowGlyphView()
    private var tracking: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false

    /// - Parameters:
    ///   - metric: the drawn size and corner radius. Also the intrinsic size,
    ///     so an Auto Layout caller needs no size constraints.
    ///   - glass: §2's "Liquid Glass, clear". Tiles and capsule items pass
    ///     `.none` — the reference draws them bare on the bar, with no fill
    ///     until hover — and an open tab passes `.dormant`.
    init(metric: RoundedMetric, glass: GlassMode) {
        self.metric = metric
        glassMode = glass
        super.init(frame: NSRect(origin: .zero, size: metric.size))

        isBordered = false
        title = ""
        wantsLayer = true

        if glass == .always { glassBacking = makeGlass() }

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

        closeChip.isHidden = true
        closeChip.configure(
            symbolName: "xmark",
            label: String(localized: "Close Tab"),
            pointSize: Tokens.Metric.rowTrailingGlyph
        )
        closeChip.onActivate = { [weak self] in self?.onClose?() }
        addSubview(closeChip)

        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code")
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
        let chip = Tokens.Metric.rowTrailingChip.size
        closeChip.frame = NSRect(
            x: bounds.width - TopBarMetrics.chipInset / 2 - chip.width,
            y: ((bounds.height - chip.height) / 2).rounded(),
            width: chip.width,
            height: chip.height
        )
        // The title gives way to the close chip rather than the chip growing
        // for it: a chip that widened under the pointer would push every tab
        // after it along the bar, and the thing being reached for would move.
        let textX = glyph.frame.maxX + TopBarMetrics.gap
        let textEnd = closeChip.isHidden ? bounds.width - TopBarMetrics.chipInset : closeChip.frame.minX
        let line = label.font?.boundingRectForFont.height.rounded(.up) ?? size
        label.frame = NSRect(
            x: textX,
            y: ((bounds.height - line) / 2).rounded(),
            width: max(textEnd - textX, 0),
            height: line
        )
    }

    // MARK: - The chip's own two parts

    private func makeGlass() -> NSView {
        let view = Glass.apply(
            .control,
            to: self,
            cornerRadius: metric.cornerRadius,
            cornerCurve: metric.cornerCurve
        )
        view.alphaValue = glassMode == .always ? 1 : 0
        return view
    }

    private func updateGlass(animated: Bool) {
        guard glassMode == .dormant else { return }
        let target: CGFloat = isSelected ? 1 : 0
        // Nothing to fade out of: a chip that has never been selected has no
        // backing, and building one to set it to zero is the cost this avoids.
        guard let view = glassBacking ?? (target > 0 ? makeGlass() : nil) else { return }
        glassBacking = view
        guard animated, !Tokens.Motion.reduceMotion else {
            view.alphaValue = target
            return
        }
        Tokens.Motion.animate(Tokens.Motion.controlHover) { context in
            context.allowsImplicitAnimation = true
            view.animator().alphaValue = target
        }
    }

    /// §3.4's rule: the close chip is the pointer's. It comes out on the chip
    /// the pointer is on and nowhere else, so a run of twenty tabs is not a
    /// run of twenty crosses.
    private func updateClose() {
        let shows = onClose != nil && isHovered && isEnabled
        guard closeChip.isHidden == shows else { return }
        closeChip.isHidden = !shows
        needsLayout = true
    }

    /// The glass backing and the glyph are decoration. Without this they would
    /// win the hit test and swallow the click before the button saw it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled, let superview else { return nil }
        let local = convert(point, from: superview)
        // The close chip is the one piece of decoration that is a control of
        // its own, and it has to win the click on itself.
        if !closeChip.isHidden, closeChip.frame.contains(local) { return closeChip }
        return bounds.contains(local) ? self : nil
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
        updateClose()
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
        // A draggable chip cannot use the loop above at all: `sendAction`
        // happens inside it and it does not return until the mouse is back up,
        // so there is no moment in it at which a drag could be noticed. It runs
        // its own instead, which is what `GlassButton` does in the sidebar for
        // the same reason, and sends the action itself on a press that turned
        // out to be a click.
        if onDragOut != nil {
            trackPress(from: event)
            setPressed(false)
            return
        }
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

    func setPressed(_ pressed: Bool) {
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
    /// A selected chip is glass, and the washes go over the glass exactly as
    /// they go over the bar: §3.1's "hover lifts the fill", whatever the fill
    /// is made of.
    private var fillColour: NSColor? {
        guard isEnabled else { return nil }
        if isPressed { return Tokens.Surface.selected }
        return isHovered ? Tokens.Surface.hover : nil
    }

    func refreshFill() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            Tokens.Motion.wash(self.hoverFill.layer, to: self.fillColour)
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
