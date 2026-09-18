//
//  URLPillView.swift
//  Luna
//
//  §3.2's address pill: the domain at rest, the full URL while editing, and a
//  sliders glyph on its trailing edge.
//
//  **It does not take the page's colour.** §2 made this the one page-derived
//  tint in the app: the site's `themeColor`, washed over `Surface.chromeFill`
//  and clamped until the pill's text still cleared §21.4. On screen that meant
//  the one fixed landmark in the sidebar changed shade with every navigation —
//  getroosta.app and YouTube lifted it, Apple's pages left it where it was —
//  and a control that is a different colour on every site is not a control you
//  stop noticing. It is `Surface.well` now, in every state and on every page:
//  the same recess a pinned tile rests in, so the head of the sidebar is one
//  surface rather than two that agree only sometimes.
//
//  The pill carries its glass when it is being *used* — hovered, or open for
//  editing — and is a bordered well the rest of the time. Constant glass made
//  it the brightest thing in the sidebar: a second lit surface directly under
//  three lit circles, with the eye drawn to an address the user already knows.
//

import AppKit
import BrowserKit

@MainActor
final class URLPillView: NSView, NSTextFieldDelegate {

    /// The text the user committed with Return. The coordinator decides whether
    /// it is a URL or a query and forwards it to `BrowserSession.load(_:)`;
    /// URL-or-query parsing is the Command Bar's, not the pill's.
    var onSubmit: ((String) -> Void)?
    /// The trailing sliders glyph (§3.2's site menu).
    var onSiteMenu: (() -> Void)?
    /// What §3.2's menu hangs off: the glyph itself, not the pill, so it opens
    /// from the control that was pressed.
    var siteMenuAnchor: NSView { sliders }

    private let field = NSTextField(labelWithString: "")
    /// The `.control` backing, built the first time the pill is reached for —
    /// see `updateGlass`.
    private var glass: NSView?
    /// The radius the backing was built at. A glass view's corner radius is
    /// fixed when it is constructed, so a pill that changes height — §3.2b's,
    /// collapsing — has to be given a new one rather than resized into a
    /// capsule with the wrong ends.
    private var glassRadius: CGFloat?
    private var isHovering = false
    // A bare glyph, not a `GlassButton`: the reference draws no bubble around
    // the sliders, and a glass control inside a glass pill is two materials.
    private let sliders = RowGlyphView()
    private var displayedURL: URL?
    private var isEditing = false

    /// §3.2b: the same pill, the other way round — the sliders glyph on the
    /// **leading** edge and the domain centred in what is left.
    ///
    /// Which way round it goes is a fact about what the pill is sitting in, not
    /// about the pill. In the sidebar it is one row in a column of left-aligned
    /// rows and its text starts where their text starts. On the page it is a
    /// lone capsule centred over a window, and a domain pinned to the leading
    /// edge of a 420 pt capsule reads as a mistake.
    var centresText = false {
        didSet {
            guard centresText != oldValue else { return }
            needsLayout = true
        }
    }

    /// **The material at rest**, rather than only while the pill is being
    /// reached for.
    ///
    /// In the sidebar the pill is a well cut into a glass plane, and constant
    /// glass made it the brightest thing in the column — a second lit surface
    /// directly under three lit circles. §3.2b's bar has no plane under it at
    /// all: it floats over a web page, where a bordered well is a recess in
    /// nothing and reads as a hole punched in the site. There the pill wears
    /// what its three neighbours wear, when they wear it, so the four controls
    /// are one set of objects rather than three and a gap.
    var alwaysGlass = false {
        didSet {
            guard alwaysGlass != oldValue else { return }
            needsDisplay = true
            updateGlass()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous


        field.font = Tokens.TypeScale.urlPill
        field.lineBreakMode = .byTruncatingTail
        field.focusRingType = .none
        field.delegate = self
        field.isBordered = false
        field.drawsBackground = false
        field.setAccessibilityLabel("Address")
        addSubview(field)

        sliders.configure(
            image: SiteMenuGlyph.image(size: Tokens.Metric.pillGlyphSize),
            label: String(localized: "Site settings"),
            pointSize: Tokens.Metric.pillGlyphSize
        )
        // The §3.4 close button's chip, on the §3.2 glyph: the affordance for
        // *this* control, appearing when the pointer is on this control. The
        // pill's own glass says the pill is live; the chip says the glyph is a
        // button rather than a badge on it.
        sliders.chromed = true
        sliders.onActivate = { [weak self] in self?.onSiteMenu?() }
        addSubview(sliders)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Tokens.Metric.urlPill.height)
    }

    /// The narrowest this pill can be and still show its whole domain, in
    /// `centresText` layout. §3.2b's collapsed capsule is sized to this — it
    /// shrinks to the address rather than to a number someone picked.
    var fittingWidth: CGFloat {
        let overhang = (Tokens.Metric.rowTrailingChip.width - Tokens.Metric.pillGlyphSize) / 2
        let margin = Tokens.Metric.pillGlyphInset - overhang
            + Tokens.Metric.rowTrailingChip.width
            + Tokens.Metric.chromeGap
        return 2 * margin + ceil(field.intrinsicContentSize.width)
    }

    // MARK: - Content

    /// Domain at rest.
    func show(url: URL?) {
        displayedURL = url
        if !isEditing { field.stringValue = Self.domain(of: url) }
        field.setAccessibilityValue(url?.absoluteString ?? "")
    }

    /// `apple.com`, not `https://www.apple.com/iphone` (§30.3). `www.` is the
    /// one subdomain that is never meaningful.
    static func domain(of url: URL?) -> String {
        guard let host = url?.host(percentEncoded: false), !host.isEmpty else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // MARK: - Editing (§3.2, ⌘L)

    /// Expands to the full URL, selected. Idempotent, so ⌘L on an already-open
    /// pill just re-selects.
    func beginEditing() {
        isEditing = true
        updateGlass()
        field.stringValue = displayedURL?.absoluteString ?? ""
        field.isEditable = true
        field.isSelectable = true
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        needsDisplay = true
    }

    private func endEditing(commit: Bool) {
        let typed = field.stringValue
        isEditing = false
        updateGlass()
        field.isEditable = false
        field.isSelectable = false
        field.stringValue = Self.domain(of: displayedURL)
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        needsDisplay = true
        if commit, !typed.isEmpty { onSubmit?(typed) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            endEditing(commit: false) // §3.2: Esc reverts.
        case #selector(NSResponder.insertNewline(_:)):
            endEditing(commit: true)
        default:
            return false
        }
        return true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard isEditing else { return }
        endEditing(commit: false)
    }

    /// §30.1: the sidebar's plane moves the window; a control on it does not.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        beginEditing()
    }

    // MARK: - Appearance

    private func refresh() {
        field.textColor = Tokens.Text.primary
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    /// A capsule at any height. §3.2's is always 34 pt, so the token *is* the
    /// radius there; §3.2b's collapses, and a 17 pt radius on a 22 pt capsule
    /// is a rectangle with dents in it.
    private var cornerRadius: CGFloat {
        min(Tokens.Metric.urlPill.cornerRadius, bounds.height / 2)
    }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = cornerRadius
        // §3.2: a well cut into the sidebar, not a plate sitting on it. The
        // glass fades in above this when the pill is reached for.
        //
        // **Neither, once the glass is permanent.** A `GlassButton` at
        // `.always` carries no plate and no hairline either: the material is
        // the whole surface, and a well behind it is a shadow the buttons
        // beside it do not have.
        layer.backgroundColor = alwaysGlass ? nil : Tokens.Surface.well.cgColor
        layer.borderWidth = alwaysGlass ? 0 : Tokens.Metric.hairline
        // **Never the accent.** An editing pill used to take a system-blue
        // ring; the material is what says the pill is live, the same way it
        // does for a selected row and a pinned tile.
        layer.borderColor = alwaysGlass ? nil : Tokens.Line.border.cgColor
    }

    // MARK: - Dormant material

    /// The pill carries its glass when it is **being used** — hovered, or open
    /// for editing — and is a bordered plate on the sidebar's own plane the
    /// rest of the time.
    ///
    /// Constant glass is what made it the brightest thing in the sidebar: a
    /// second lit surface directly under three lit circles, with the eye drawn
    /// to an address the user already knows.
    private var glassTarget: CGFloat { (alwaysGlass || isHovering || isEditing) ? 1 : 0 }

    private func updateGlass() {
        let target = glassTarget
        guard let view = glass ?? (target > 0 ? makeGlass() : nil), view.alphaValue != target else { return }
        Tokens.Motion.animate(Tokens.Motion.controlHover) { context in
            context.allowsImplicitAnimation = true
            view.animator().alphaValue = target
        }
    }

    @discardableResult
    private func makeGlass() -> NSView {
        let view = Glass.apply(.control, to: self, cornerRadius: cornerRadius)
        view.alphaValue = 0
        glass = view
        glassRadius = cornerRadius
        return view
    }

    /// Rebuilds the backing when the pill has changed height under it. Only
    /// §3.2b's pill ever does; the sidebar's calls this and finds nothing to do.
    private func refreshGlassShape() {
        guard glass != nil, glassRadius != cornerRadius else { return }
        makeGlass().alphaValue = glassTarget
        needsDisplay = true
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

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateGlass()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateGlass()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    /// §21.2 / contract rule 4: Increase Contrast is not an appearance, so the
    /// border has to be re-resolved on the workspace notification or the
    /// setting is ignored forever. `SidebarViewController` owns the single
    /// observer and calls this.
    func accessibilityDisplayOptionsChanged() {
        refresh()
    }

    // MARK: - Layout

    /// §3.2's own two insets, which until now were both silently `rowInset`:
    /// the domain starts 12 pt in and the sliders glyph sits 10 pt from the
    /// trailing edge. Both are measured, and they are deliberately unequal — a
    /// glyph is optically smaller than its box.
    ///
    /// **The inset is the glyph's, and the chip grows past it.** `pillGlyphInset`
    /// is measured to the mark the eye sees, so the hover chip — which is
    /// bigger than the glyph inside it — is placed by centring it on where the
    /// glyph would have been rather than by being inset itself. Insetting the
    /// chip instead would move the glyph 2.5 pt further in the moment it gained
    /// a background it only shows on hover.
    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately {
            placeContents()
            refreshGlassShape()
        }
    }

    private func placeContents() {
        let glyph = Tokens.Metric.pillGlyphSize
        let chip = Tokens.Metric.rowTrailingChip
        let overhang = (chip.width - glyph) / 2
        let height = field.intrinsicContentSize.height
        let inset = Tokens.Metric.pillGlyphInset
        // §3.2: two further slots, reserved and sized, rendering nothing.
        let reserved = 2 * (glyph + Tokens.Metric.chromeGap)
        let chipY = (bounds.height - chip.height) / 2
        let textY = (bounds.height - height) / 2

        guard !centresText else {
            sliders.frame = NSRect(
                x: bounds.minX + inset - overhang,
                y: chipY,
                width: chip.width,
                height: chip.height
            ).integral
            // Symmetric margins, so the text is centred in the **pill** rather
            // than in the space the glyph leaves: an off-centre domain in a
            // centred capsule is worse than no centring at all.
            //
            // **And no reserved slots.** §3.2 holds two glyph-sized places open
            // for controls that are not built; they belong to a pill that is one
            // row of a column, where the column's other rows will grow the same
            // controls. A capsule floating on the page is sized to what it
            // shows, and 42 pt of held-open nothing at each end is what made it
            // read as an empty bar with a word in it.
            let margin = sliders.frame.maxX + Tokens.Metric.chromeGap
            field.frame = NSRect(
                x: margin,
                y: textY,
                width: max(bounds.width - 2 * margin, 0),
                height: height
            ).integral
            field.alignment = .center
            return
        }
        field.alignment = .natural
        sliders.frame = NSRect(
            x: bounds.maxX - inset + overhang - chip.width,
            y: chipY,
            width: chip.width,
            height: chip.height
        ).integral
        let textRight = sliders.frame.minX - reserved
        let textLeft = Tokens.Metric.pillTextInset
        field.frame = NSRect(
            x: textLeft,
            y: textY,
            width: max(textRight - textLeft, 0),
            height: height
        ).integral
    }
}
