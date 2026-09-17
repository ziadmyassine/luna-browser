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
        Glass.apply(.control, to: self, cornerRadius: Tokens.Metric.urlPill.cornerRadius)

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
        washColor = if let tint, !Tokens.A11y.reduceTransparency {
            Tokens.wash(NSColor(tint), over: Tokens.Surface.raised, keeping: Tokens.Text.primary)
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
        layer.borderWidth = Tokens.Metric.hairline
        layer.borderColor = (isEditing ? Tokens.Accent.tint : Tokens.Line.border).cgColor
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
