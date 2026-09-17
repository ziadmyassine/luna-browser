//
//  URLPillView.swift
//  Luna
//
//  §3.2. Domain only at rest (`apple.com`, never the full URL — §30.3), the
//  full URL selected for editing on click or ⌘L, `Esc` reverts.
//
//  This is the **only** page-derived tint in the app (§2). The wash is applied
//  through `Tokens.wash`, which backs the fraction off until the pill's text
//  still clears §21.4's 4.5:1 and drops the wash entirely when even the floor
//  fails. Reduce Transparency disables it outright.
//
//  Material note: §2's table lists every glass surface in the chrome and the
//  URL pill is deliberately not among them — it is the one surface that *is*
//  page-tinted. `Tokens.wash` returns a fill, not a tint hook, and `Glass`
//  rightly exposes none, so the pill is glass while the page offers no theme
//  colour and a washed plate over that glass once it does.
//
//  Two icon slots sit reserved and sized to the left of the sliders glyph and
//  render nothing (§3.4/§30.4): AI and extension actions live in the top bar.
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

    private let field = NSTextField(labelWithString: "")
    private let wash = NSView()
    /// The `.control` backing, built the first time the pill is reached for —
    /// see `updateGlass`.
    private var glass: NSView?
    private var isHovering = false
    // A bare glyph, not a `GlassButton`: the reference draws no bubble around
    // the sliders, and a glass control inside a glass pill is two materials.
    private let sliders = RowGlyphView()
    private var displayedURL: URL?
    private var washTint: RGBA?
    private var washColor: NSColor?
    private var isEditing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous

        wash.wantsLayer = true
        wash.layer?.cornerCurve = .continuous
        wash.layer?.cornerRadius = Tokens.Metric.urlPill.cornerRadius
        wash.autoresizingMask = [.width, .height]
        addSubview(wash)

        field.font = Tokens.TypeScale.urlPill
        field.lineBreakMode = .byTruncatingTail
        field.focusRingType = .none
        field.delegate = self
        field.isBordered = false
        field.drawsBackground = false
        field.setAccessibilityLabel("Address")
        addSubview(field)

        sliders.configure(
            symbolName: "slider.horizontal.3",
            label: "Site settings",
            pointSize: Tokens.Metric.glyphSize
        )
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

    /// Domain at rest; the wash follows the page's theme colour (§2).
    func show(url: URL?, themeColor: RGBA?) {
        displayedURL = url
        if !isEditing { field.stringValue = Self.domain(of: url) }
        field.setAccessibilityValue(url?.absoluteString ?? "")
        setWash(themeColor)
    }

    /// `apple.com`, not `https://www.apple.com/iphone` (§30.3). `www.` is the
    /// one subdomain that is never meaningful.
    static func domain(of url: URL?) -> String {
        guard let host = url?.host(percentEncoded: false), !host.isEmpty else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // MARK: - The §2 wash

    private func setWash(_ tint: RGBA?, force: Bool = false) {
        // Compared on the *tint*, not the resulting colour: `Tokens.wash` hands
        // back a dynamic `NSColor`, and two of those are never usefully equal.
        guard force || tint != washTint else { return }
        washTint = tint
        // §2: the page-derived wash is disabled outright under Reduce Transparency.
        // **`over:` is `chromeFill`, not `raised`.** `raised` is an *opaque
        // plane*, so blending a page's theme colour on top of it produced an
        // opaque plate: on a site whose theme colour is a near-neutral grey
        // (getroosta.app is one) the pill stopped being translucent and simply
        // turned grey. `chromeFill` is the translucent wash base `Tokens` ships
        // for exactly this — blending is alpha-correct, so §2's 12–18 % stays
        // 12–18 % of what reaches the eye *through* the glass.
        washColor = if let tint, !Tokens.A11y.reduceTransparency {
            Tokens.wash(NSColor(tint), over: Tokens.Surface.chromeFill, keeping: Tokens.Text.primary)
        } else {
            nil
        }
        Tokens.Motion.animate(Tokens.Motion.themeWash) { context in
            context.allowsImplicitAnimation = true
            applyWash()
        }
    }

    private func applyWash() {
        wash.layer?.backgroundColor = washColor?.cgColor
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

    override func mouseDown(with event: NSEvent) {
        beginEditing()
    }

    // MARK: - Appearance

    private func refresh() {
        field.textColor = Tokens.Text.primary
        applyWash()
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
    /// border and the wash clamp have to be re-resolved on the workspace
    /// notification or the setting is ignored forever. `SidebarViewController`
    /// owns the single observer and calls this.
    func accessibilityDisplayOptionsChanged() {
        // Re-clamped, not cleared: the contrast floor that `Tokens.wash` checks
        // moves with Increase Contrast, and so does the Reduce Transparency veto.
        setWash(washTint, force: true)
        refresh()
    }

    // MARK: - Layout

    /// §3.2's own two insets, which until now were both silently `rowInset`:
    /// the domain starts 12 pt in and the sliders glyph sits 10 pt from the
    /// trailing edge. Both are measured, and they are deliberately unequal — a
    /// glyph is optically smaller than its box.
    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately { placeContents() }
    }

    private func placeContents() {
        let glyph = Tokens.Metric.glyphSize
        sliders.frame = NSRect(
            x: bounds.maxX - Tokens.Metric.pillGlyphInset - glyph,
            y: (bounds.height - glyph) / 2,
            width: glyph,
            height: glyph
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
