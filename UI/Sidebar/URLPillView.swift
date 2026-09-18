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
    private var isHovering = false
    // A bare glyph, not a `GlassButton`: the reference draws no bubble around
    // the sliders, and a glass control inside a glass pill is two materials.
    private let sliders = RowGlyphView()
    private var displayedURL: URL?
    private var isEditing = false

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

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = Tokens.Metric.urlPill.cornerRadius
        // §3.2: a well cut into the sidebar, not a plate sitting on it. The
        // glass fades in above this when the pill is reached for.
        layer.backgroundColor = Tokens.Surface.well.cgColor
        layer.borderWidth = Tokens.Metric.hairline
        // **Never the accent.** An editing pill used to take a system-blue
        // ring; the material is what says the pill is live, the same way it
        // does for a selected row and a pinned tile.
        layer.borderColor = Tokens.Line.border.cgColor
    }

    // MARK: - Dormant material

    /// The pill carries its glass when it is **being used** — hovered, or open
    /// for editing — and is a bordered plate on the sidebar's own plane the
    /// rest of the time.
    ///
    /// Constant glass is what made it the brightest thing in the sidebar: a
    /// second lit surface directly under three lit circles, with the eye drawn
    /// to an address the user already knows.
    private func updateGlass() {
        let target: CGFloat = (isHovering || isEditing) ? 1 : 0
        guard let view = glass ?? (target > 0 ? makeGlass() : nil), view.alphaValue != target else { return }
        Tokens.Motion.animate(Tokens.Motion.controlHover) { context in
            context.allowsImplicitAnimation = true
            view.animator().alphaValue = target
        }
    }

    private func makeGlass() -> NSView {
        let view = Glass.apply(.control, to: self, cornerRadius: Tokens.Metric.urlPill.cornerRadius)
        view.alphaValue = 0
        glass = view
        return view
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
        Tokens.Motion.immediately { placeContents() }
    }

    private func placeContents() {
        let glyph = Tokens.Metric.pillGlyphSize
        let chip = Tokens.Metric.rowTrailingChip
        let overhang = (chip.width - glyph) / 2
        sliders.frame = NSRect(
            x: bounds.maxX - Tokens.Metric.pillGlyphInset + overhang - chip.width,
            y: (bounds.height - chip.height) / 2,
            width: chip.width,
            height: chip.height
        ).integral
        // §3.2: two further slots, reserved and sized, rendering nothing.
        let reserved = 2 * (glyph + Tokens.Metric.chromeGap)
        let textRight = sliders.frame.minX - reserved
        let height = field.intrinsicContentSize.height
        let textLeft = Tokens.Metric.pillTextInset
        field.frame = NSRect(
            x: textLeft,
            y: (bounds.height - height) / 2,
            width: max(textRight - textLeft, 0),
            height: height
        ).integral
    }
}
