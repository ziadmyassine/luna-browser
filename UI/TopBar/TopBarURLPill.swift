//
//  TopBarURLPill.swift
//  Luna
//
//  The active tab, expanded (UI-SPEC §4): favicon, domain and the sliders glyph
//  in a 266 × 32 glass pill. Inactive tabs are 28 pt tiles on either side of it,
//  which is why the pill is not window-centred — it sits wherever the active
//  tab falls in the strip.
//
//  This is the **only page-derived colour in the app** (§2). The chrome samples
//  what is behind the *window*; the pill alone blends `TabState.themeColor`
//  through `Tokens.wash`, which backs the fraction off in 2 % steps until the
//  text still clears §21.4's 4.5:1 and drops the wash entirely if it cannot.
//
//  §4 has no reload button by design. Reload is `⌘R` and the site menu behind
//  the sliders glyph, which is why that menu exists in M1 with one item in it.
//

import AppKit
import BrowserKit

/// §3.2: the pill shows a domain, never a URL.
enum TopBarDomain {

    /// Host minus `www.`. Not eTLD+1: Foundation ships no public-suffix list,
    /// and collapsing to the last two labels would turn `docs.github.com` into
    /// `github.com` — §3.2 keeps a subdomain when it is meaningful, and every
    /// subdomain except `www` is. Same rule as `BrowserKit`'s favicon key.
    static func display(for url: URL?) -> String {
        guard let url else { return "" }
        // Luna's own pages have a host, and it is not a name: a New Tab whose
        // `<title>` has not arrived yet was labelled `newtab` until it did.
        if let name = InternalPages.name(for: url) { return name }
        guard let host = url.host(percentEncoded: false), !host.isEmpty else {
            // `about:blank` — there is no host to shorten.
            return url.absoluteString
        }
        let lower = host.lowercased()
        return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
    }

    /// What the user typed in the pill, as something to navigate to — or nil,
    /// meaning "this was a search, not an address".
    ///
    /// Deliberately thin: dangerous schemes are not re-checked here because
    /// `NavigationPolicy` already blocks them at the one place every navigation
    /// passes through. A second copy would be a second thing to keep right.
    static func resolve(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        guard trimmed.contains(".") else { return nil }
        return URL(string: "https://" + trimmed)
    }
}

@MainActor
final class TopBarURLPill: NSView, TopBarThemed, NSTextFieldDelegate {

    var onNavigate: ((URL) -> Void)?
    /// Typed text that is not an address. The Command Bar owns search; with
    /// nothing wired the pill just reverts.
    var onSearch: ((String) -> Void)?

    private let wash = NSView()
    private let favicon = NSImageView()
    private let field = NSTextField()
    /// §3.2's sliders, at `pillGlyphSize` and wearing §3.4's chip — the same
    /// glyph in the same shape the sidebar's pill draws it in, and for the same
    /// reason: 16 pt is the size of a glyph that is its own button, and this one
    /// sits inside a control that is already a landmark. At 16 it was the
    /// loudest mark in a pill whose whole job is to be quiet.
    private let sliders = RowGlyphView()
    /// §3.2c's load line — the same line, at the same inset, as the one under
    /// §3.2's pill in the column. Three address bars, one progress indicator.
    private let loadLine = LoadProgressLine()

    private var url: URL?
    private var tintSource: NSColor?
    private var washColor: NSColor?
    private var isEditing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        Glass.apply(.control, to: self, cornerRadius: Tokens.Metric.urlPill.cornerRadius)

        wash.wantsLayer = true
        wash.layer?.cornerCurve = .continuous
        wash.layer?.cornerRadius = Tokens.Metric.urlPill.cornerRadius
        addSubview(wash)

        favicon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(favicon)

        configureField()
        addSubview(field)

        sliders.configure(
            image: SiteMenuGlyph.image(size: Tokens.Metric.pillGlyphSize),
            label: String(localized: "Site settings"),
            pointSize: Tokens.Metric.pillGlyphSize
        )
        sliders.onActivate = { [weak self] in self?.showSiteMenu() }
        addSubview(sliders)
        addSubview(loadLine)

        setAccessibilityRole(.textField)
        setAccessibilityLabel(String(localized: "Address"))
        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code")
    }

    private func configureField() {
        field.isBordered = false
        field.drawsBackground = false
        field.isEditable = false
        field.isSelectable = false
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.truncatesLastVisibleLine = true
        field.font = Tokens.TypeScale.topBarURL
        field.focusRingType = .none
        field.delegate = self
    }

    // MARK: - Content

    /// - Parameters:
    ///   - icon: the tab's favicon, or nil for the globe placeholder.
    ///   - tint: `TabState.themeColor`, already bridged. Nil removes the wash.
    func apply(url: URL?, icon: NSImage?, tint: NSColor?) {
        self.url = url
        favicon.image = icon ?? TopBarButton.symbol("globe")
        if !isEditing { applyDisplay() }
        setWash(tint)
    }

    /// §3.2c: how far the active tab has loaded. Fed from the same `TabState`
    /// the wash and the title come from, and carrying the tab's id — the pill
    /// is reused across a tab switch, and a switch is not progress.
    func setLoad(_ state: TabState, for tab: UUID) {
        loadLine.show(state, for: tab)
    }

    private func applyDisplay() {
        field.stringValue = TopBarDomain.display(for: url)
        setAccessibilityValue(field.stringValue)
        needsLayout = true
    }

    // MARK: - §2 page-derived wash

    private func setWash(_ tint: NSColor?) {
        guard tint != tintSource else { return }
        tintSource = tint
        // §2: Reduce Transparency disables the wash outright.
        if let tint, !Tokens.A11y.reduceTransparency {
            // `chromeFill`, not `raised`: `raised` is an opaque plane and a
            // theme colour blended onto it becomes an opaque plate — the pill
            // simply turned grey on any site with a near-neutral theme colour.
            washColor = Tokens.wash(tint, over: Tokens.Surface.chromeFill, keeping: Tokens.Text.primary)
        } else {
            washColor = nil
        }
        applyWash(animated: true)
    }

    /// The wash is a dynamic colour, and `cgColor` freezes whatever appearance
    /// is current — so it is resolved under this view's own appearance every
    /// time, rather than once at assignment.
    private func applyWash(animated: Bool) {
        var resolved: CGColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = self.washColor?.cgColor
        }
        let assign: () -> Void = { self.wash.layer?.backgroundColor = resolved }
        guard animated else { return assign() }
        Tokens.Motion.animate(Tokens.Motion.themeWash) { context in
            context.allowsImplicitAnimation = true
            assign()
        }
    }

    // MARK: - Editing (§3.2: click or ⌘L → full URL, selected; Esc reverts)

    func beginEditing() {
        guard !isEditing else { return }
        isEditing = true
        field.isEditable = true
        field.isSelectable = true
        field.lineBreakMode = .byClipping
        field.stringValue = url?.absoluteString ?? ""
        needsLayout = true
        layoutSubtreeIfNeeded()
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    private func endEditing(commit: Bool) {
        guard isEditing else { return }
        let typed = field.stringValue
        isEditing = false
        field.isEditable = false
        field.isSelectable = false
        field.lineBreakMode = .byTruncatingTail
        if window?.firstResponder is NSText { window?.makeFirstResponder(self) }
        applyDisplay()
        guard commit else { return }
        if let target = TopBarDomain.resolve(typed) {
            onNavigate?(target)
        } else if !typed.isEmpty {
            onSearch?(typed)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            endEditing(commit: true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            endEditing(commit: false)
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        endEditing(commit: false)
    }

    // MARK: - Site menu

    /// §3.2's menu, which the top bar shows from the same glyph the sidebar
    /// does — one menu, two places it hangs off, so a user who switches layout
    /// does not have to learn a second one.
    ///
    /// §4 gives this layout no reload button, so Reload is added here and
    /// nowhere else. The item is nil-targeted, which puts it through the same
    /// `AppDelegate` method `⌘R` does rather than being a second implementation.
    private func showSiteMenu() {
        let menu = SiteMenu.build(from: sliders)
        let reload = NSMenuItem(
            title: String(localized: "Reload"),
            action: #selector(AppDelegate.reloadPage(_:)),
            keyEquivalent: "r"
        )
        reload.keyEquivalentModifierMask = .command
        // Dressed the way every other row in this menu is dressed. `image` is not drawn
        // on this macOS (§3.2a), so this row — the first one, and the only one this
        // layout adds — was the one item in a menu of glyphs that had none.
        menu.insertItem(SiteMenu.glyph(SiteMenu.Glyph.reload, on: reload), at: 0)
        menu.insertItem(.separator(), at: 1)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sliders.bounds.maxY), in: sliders)
    }

    // MARK: - Keyboard and focus (§20.2)

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func becomeFirstResponder() -> Bool {
        noteFocusRingMaskChanged()
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        noteFocusRingMaskChanged()
        return super.resignFirstResponder()
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        let radius = Tokens.Metric.urlPill.cornerRadius
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }

    override func keyDown(with event: NSEvent) {
        let keys = event.charactersIgnoringModifiers
        if keys == " " || keys == "\r" {
            beginEditing()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        beginEditing()
    }

    /// A non-editable `NSTextField` still wins the hit test and swallows the
    /// click without forwarding it, so clicking the domain would do nothing.
    /// Everything inside the pill belongs to the pill except the sliders glyph,
    /// and the field itself once it is actually being edited.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if let glyph = sliders.hitTest(local) { return glyph }
        if isEditing, let editor = field.hitTest(local) { return editor }
        return self
    }

    /// The pill is a control, not a window drag handle.
    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: - Geometry

    override var intrinsicContentSize: NSSize { Tokens.Metric.urlPill.size }

    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately { placeContents() }
    }

    private func placeContents() {
        wash.frame = bounds
        loadLine.frame = LoadProgressLine.frame(inPill: bounds)

        let inset = Tokens.Metric.rowInset
        // **The inset is the glyph's, and the chip grows past it** — the same
        // placement `URLPillView` records: `pillGlyphInset` is measured to the
        // mark the eye lands on, so the hover chip is centred on where the
        // glyph would have been rather than being inset itself.
        let mark = Tokens.Metric.pillGlyphSize
        let chip = Tokens.Metric.rowTrailingChip
        let overhang = (chip.width - mark) / 2
        sliders.frame = NSRect(
            x: bounds.maxX - Tokens.Metric.pillGlyphInset + overhang - chip.width,
            y: ((bounds.height - chip.height) / 2).rounded(),
            width: chip.width,
            height: chip.height
        )

        let icon = TopBarMetrics.glyph
        let span = max(sliders.frame.minX - TopBarMetrics.gap - inset, 0)
        let textMax = max(span - icon - TopBarMetrics.gap, 0)
        // `fittingSize`, not `intrinsicContentSize`: measured on macOS 26.5, a
        // label's intrinsic width is the glyph run alone (91 pt for
        // "example.com" at 15 pt) while the cell insets its title by 2 pt on
        // each side and needs 95 pt to draw it — so a frame sized to the
        // intrinsic width tail-truncates a domain that fits the pill twice over.
        let textWidth = isEditing ? textMax : min(field.fittingSize.width.rounded(.up), textMax)
        // Centred as a group at rest (as the reference draws it); pinned left
        // while editing, where the text is a full URL and needs the room.
        let group = icon + TopBarMetrics.gap + textWidth
        let originX = isEditing ? inset : inset + max((span - group) / 2, 0).rounded()

        favicon.frame = NSRect(
            x: originX,
            y: ((bounds.height - icon) / 2).rounded(),
            width: icon,
            height: icon
        )
        let textHeight = field.intrinsicContentSize.height.rounded(.up)
        field.frame = NSRect(
            x: originX + icon + TopBarMetrics.gap,
            y: ((bounds.height - textHeight) / 2).rounded(),
            width: textWidth,
            height: textHeight
        )
    }

    // MARK: - Tokens

    func applyTokens() {
        field.textColor = Tokens.Text.primary
        applyWash(animated: false)
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }
}
