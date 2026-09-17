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
        guard let host = url.host(percentEncoded: false), !host.isEmpty else {
            // `about:blank`, `luna:…` — there is no host to shorten.
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
    private let sliders = TopBarButton(metric: TopBarMetrics.tile, glass: false)

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

        sliders.icon = TopBarButton.symbol("slider.horizontal.3")
        sliders.setAccessibilityLabel(String(localized: "Site Settings"))
        sliders.target = self
        sliders.action = #selector(showSiteMenu)
        addSubview(sliders)

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
            washColor = Tokens.wash(tint, over: Tokens.Surface.raised, keeping: Tokens.Text.primary)
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

    /// §4 gives the top-bar layout no reload button; reload lives in `⌘R` and
    /// here. The item is nil-targeted, so it reaches the same `AppDelegate`
    /// method `⌘R` does rather than being a second implementation of reload.
    @objc private func showSiteMenu() {
        let menu = NSMenu()
        let reload = NSMenuItem(
            title: String(localized: "Reload"),
            action: #selector(AppDelegate.reloadPage(_:)),
            keyEquivalent: "r"
        )
        reload.keyEquivalentModifierMask = .command
        menu.addItem(reload)
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
        wash.frame = bounds

        let inset = Tokens.Metric.rowInset
        let tile = TopBarMetrics.tile
        sliders.frame = NSRect(
            x: bounds.maxX - inset - tile.width,
            y: ((bounds.height - tile.height) / 2).rounded(),
            width: tile.width,
            height: tile.height
        )

        let icon = TopBarMetrics.glyph
        let span = max(sliders.frame.minX - TopBarMetrics.gap - inset, 0)
        let textMax = max(span - icon - TopBarMetrics.gap, 0)
        let textWidth = isEditing ? textMax : min(field.intrinsicContentSize.width.rounded(.up), textMax)
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
