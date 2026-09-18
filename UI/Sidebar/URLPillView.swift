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
    // §3.2b's suggestion list, and the only subscriber to any of these four.
    // The sidebar's pill leaves them nil and behaves as it always has: what was
    // typed goes out, the arrows move the list (true swallows the key), Return
    // asks it for a phrase, and the end of editing takes it away.
    var onTyping: ((String) -> Void)?
    var onMoveSelection: ((Int) -> Bool)?
    var chosenCompletion: (() -> String?)?
    var onEndEditing: (() -> Void)?
    /// What §3.2's menu hangs off: the glyph itself, not the pill, so it opens
    /// from the control that was pressed.
    var siteMenuAnchor: NSView { sliders }

    // Not `private`: `URLPillLayout.swift` places both. See its header.
    let field = NSTextField(labelWithString: "")
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
    let sliders = RowGlyphView()
    private var displayedURL: URL?
    private var isEditing = false

    /// §3.2b: the same pill, the other way round — the sliders glyph on the
    /// **leading** edge and the domain centred in what is left. Which way round
    /// it goes is a fact about what the pill sits in: a column of left-aligned
    /// rows, or a lone capsule centred over a window.
    var centresText = false {
        didSet {
            guard centresText != oldValue else { return }
            needsLayout = true
        }
    }

    /// What the pill is made of, which is a fact about what it is sitting in.
    enum Surface {
        /// §3.2: a bordered well cut into the sidebar's glass plane, lit only
        /// while the pill is being used. Constant glass here made it the
        /// brightest thing in the column — a second lit surface under three lit
        /// circles, with the eye drawn to an address the user knows.
        case well
        /// §3.2b, open: the material at rest and no plate under it, because its
        /// three neighbours on that bar are glass at rest and four controls in a
        /// row with one of them a recess reads as a gap in the set.
        case glass
        /// §3.2b, collapsed: nothing. The bar's own plane is the surface, and a
        /// capsule on it would be a control inside a control.
        case bare
    }

    var surface: Surface = .well {
        didSet {
            guard surface != oldValue else { return }
            // **The site menu goes with the surface.** A collapsed bar is the
            // page's own top edge with an address in it; a control floating in
            // that strip is the one thing on it that is not the site. The menu
            // is a scroll away — the bar opens again the moment the page moves
            // up — and §3.2's pill in the sidebar still carries it.
            sliders.isHidden = surface == .bare
            needsDisplay = true
            needsLayout = true
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
        // Asked before the field is torn down: the list is dismissed on the way
        // out, and a phrase read after that is a phrase read from nothing.
        let chosen = commit ? chosenCompletion?() : nil
        let typed = chosen ?? field.stringValue
        isEditing = false
        updateGlass()
        field.isEditable = false
        field.isSelectable = false
        field.stringValue = Self.domain(of: displayedURL)
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        needsDisplay = true
        onEndEditing?()
        if commit, !typed.isEmpty { onSubmit?(typed) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            endEditing(commit: false) // §3.2: Esc reverts.
        case #selector(NSResponder.insertNewline(_:)):
            endEditing(commit: true)
        case #selector(NSResponder.moveDown(_:)):
            return onMoveSelection?(1) ?? false
        case #selector(NSResponder.moveUp(_:)):
            return onMoveSelection?(-1) ?? false
        default:
            return false
        }
        return true
    }

    func controlTextDidChange(_ obj: Notification) {
        guard isEditing else { return }
        onTyping?(field.stringValue)
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


    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = cornerRadius
        // §3.2: a well cut into the sidebar, not a plate sitting on it. The
        // glass fades in above this when the pill is reached for.
        //
        // **Neither, off the sidebar.** A `GlassButton` at `.always` carries no
        // plate and no hairline either: the material is the whole surface, and
        // a well behind it is a shadow the buttons beside it do not have. A
        // `.bare` pill has no surface of its own at all — see `Surface`.
        let plated = surface == .well
        layer.backgroundColor = plated ? Tokens.Surface.well.cgColor : nil
        layer.borderWidth = plated ? Tokens.Metric.hairline : 0
        // **Never the accent.** An editing pill used to take a system-blue
        // ring; the material is what says the pill is live, the same way it
        // does for a selected row and a pinned tile.
        layer.borderColor = plated ? Tokens.Line.border.cgColor : nil
    }

    // MARK: - Dormant material

    /// The pill carries its glass when it is **being used** — hovered, or open
    /// for editing — and is a bordered plate on the sidebar's own plane the
    /// rest of the time.
    ///
    /// Constant glass is what made it the brightest thing in the sidebar: a
    /// second lit surface directly under three lit circles, with the eye drawn
    /// to an address the user already knows.
    private var glassTarget: CGFloat {
        switch surface {
        case .glass: 1
        // Bare on hover too: a material over a plane that is already the page's
        // colour is a second surface announcing itself on a bar built to
        // disappear into the site.
        case .bare: 0
        case .well: (isHovering || isEditing) ? 1 : 0
        }
    }

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

    /// Rebuilds the backing when the pill has changed height under it — only
    /// §3.2b's ever does; the sidebar's finds nothing to do.
    func refreshGlassShape() {
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

}
