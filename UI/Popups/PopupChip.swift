//
//  PopupChip.swift
//  Luna
//
//  §17: the one-line chip that says a pop-up was blocked, with Open and
//  Always Allow. `SavePasswordChip`'s panel — non-activating, a child of the
//  browser window, gone on its own after a while — cut down to a single line,
//  because this is news rather than a question: most blocked pop-ups are
//  meant to stay blocked, and a chip that asks to be read gets in the way of
//  the page it is protecting.
//
//  A solid plate, not glass. The URL pill's glass stands on the window's own
//  chrome; this stands over the page, and Liquid Glass composites whatever is
//  behind it, so over a white page it went pale under dark-appearance white ink
//  and no appearance choice could fix that. The plate is `Surface.raised`, the
//  control glass's own Reduce Transparency fill, in the appearance of the view
//  it stands on (`ChipPanel`), so fill and ink always resolve together.
//
//  Where it stands is a setting: under the site-menu glyph, where the same
//  pop-ups are listed afterwards (the content area's top-right corner when no
//  glyph is showing), or at the foot of the page, centred.
//

import AppKit
import BrowserKit

enum PopupChipPosition: String, CaseIterable {
    case underSiteSettings
    case bottomCentre
}

/// The chip's two settings, beside the blocking mode in Privacy.
@MainActor
enum PopupChipSettings {
    static let notifiesKey = "privacy.popupNotify"
    static let positionKey = "privacy.popupChipPosition"

    /// Off, pop-ups are still blocked and listed in the site menu, and the
    /// shortcut still opens the last one; nothing appears over the page.
    static var notifies: Bool {
        get { UserDefaults.standard.object(forKey: notifiesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: notifiesKey) }
    }

    static var position: PopupChipPosition {
        get {
            UserDefaults.standard.string(forKey: positionKey).flatMap(PopupChipPosition.init(rawValue:))
                ?? .underSiteSettings
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: positionKey) }
    }
}

@MainActor
final class PopupChip {

    /// Opaque in both appearances, so the page never shows through.
    static var fill: NSColor { Tokens.Surface.raised }

    /// The most recent blocked pop-up, to open in a new tab.
    var onOpen: ((URL) -> Void)?
    /// The same, after the site is allowed.
    var onAlwaysAllow: ((URL) -> Void)?

    private(set) var view: PopupChipView?
    private(set) var panel: NSPanel?
    private var url: URL?
    private var count = 0
    private var dismissTimer: Timer?
    private var appearance: NSKeyValueObservation?
    private var resizing: NSObjectProtocol?

    /// The save chip's interval (`SavePasswordChip.autoDismiss`): long enough to
    /// reach a button, and it waits while the pointer is on it.
    private static let autoDismiss: TimeInterval = 12

    var isShowing: Bool { panel != nil }

    /// Shows the chip for `url`, or — when it is already up — counts one more
    /// and starts its timer again. It never stacks.
    func present(
        _ url: URL,
        in host: NSWindow,
        over content: NSView,
        below anchor: NSView? = nil,
        position: PopupChipPosition = PopupChipSettings.position
    ) {
        self.url = url
        count = isShowing ? count + 1 : 1
        let shortcut = KeyBindings.primary(for: .openBlockedPopup)?.display
        let showsAddress = PopupPolicy.showsAddress()
        let glyph = position == .underSiteSettings ? anchor : nil

        let view: PopupChipView
        let panel: NSPanel
        let isNew = !isShowing
        if let shown = self.view, let shownPanel = self.panel {
            (view, panel) = (shown, shownPanel)
            view.update(count: count, url: url, showsAddress: showsAddress, shortcut: shortcut)
        } else {
            view = PopupChipView(count: count, url: url, showsAddress: showsAddress, shortcut: shortcut)
            view.onOpen = { [weak self] in self?.finish(with: self?.onOpen) }
            view.onAllow = { [weak self] in self?.finish(with: self?.onAlwaysAllow) }
            view.onHoverChanged = { [weak self] hovering in
                hovering ? self?.cancelTimer() : self?.startTimer()
            }
            panel = ChipPanel.make()
            panel.contentView = view
            self.view = view
            self.panel = panel
        }
        appearance = ChipPanel.follow(glyph ?? content, with: panel)
        place(in: host, over: content, below: glyph, position: position)
        if isNew {
            host.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
            view.animateIn()
        }
        resizing.map(NotificationCenter.default.removeObserver)
        resizing = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: content, queue: nil
        ) { [weak self, weak host, weak content, weak glyph] _ in
            MainActor.assumeIsolated {
                guard let host, let content else { return }
                self?.place(in: host, over: content, below: glyph, position: position)
            }
        }
        startTimer()

        // §21.1: a chip that only appears in a corner is one a VoiceOver user is
        // never told about.
        NSAccessibility.post(element: view, notification: .announcementRequested, userInfo: [
            .announcement: view.headline.stringValue,
            .priority: NSAccessibilityPriorityLevel.low.rawValue
        ])
    }

    func dismiss() {
        cancelTimer()
        appearance = nil
        resizing.map(NotificationCenter.default.removeObserver)
        resizing = nil
        guard let panel else { return }
        self.panel = nil
        view = nil
        url = nil
        count = 0
        Tokens.Motion.fadePanelOut(panel)
    }

    private func finish(with action: ((URL) -> Void)?) {
        guard let url else { return }
        dismiss()
        action?(url)
    }

    // MARK: - Placement

    /// Re-run whenever the page's frame changes — a window resize or a sidebar
    /// drag moves the page, and the chip stands on the page.
    private func place(in host: NSWindow, over content: NSView, below anchor: NSView?, position: PopupChipPosition) {
        guard let panel, let view else { return }
        let size = view.fittingChipSize()
        view.frame = CGRect(origin: .zero, size: size)
        let area = host.convertToScreen(content.convert(content.bounds, to: nil))
        var glyph: CGRect?
        if let anchor, anchor.window === host, !anchor.isHiddenOrHasHiddenAncestor, anchor.alphaValue > 0 {
            glyph = host.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        }
        panel.setFrame(Self.frame(size: size, in: area, below: glyph, position: position), display: true)
    }

    /// Where a chip of `size` stands, in screen coordinates. Under the glyph,
    /// a chrome gap below it and kept inside the page; the page's top-right
    /// corner with no glyph; or centred a chrome gap above the page's foot.
    static func frame(size: CGSize, in area: CGRect, below glyph: CGRect?, position: PopupChipPosition) -> CGRect {
        let inset = Tokens.Metric.chromeGapWide
        var origin = CGPoint(x: area.maxX - size.width - inset, y: area.maxY - size.height - inset)
        switch position {
        case .bottomCentre:
            origin = CGPoint(x: area.midX - size.width / 2, y: area.minY + Tokens.Metric.chromeGap)
        case .underSiteSettings:
            if let glyph {
                origin.x = min(max(glyph.midX - size.width / 2, area.minX + inset), area.maxX - size.width - inset)
                origin.y = glyph.minY - Tokens.Metric.chromeGap - size.height
            }
        }
        return CGRect(origin: origin, size: size)
    }

    // MARK: - Timer

    private func startTimer() {
        cancelTimer()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: Self.autoDismiss, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    private func cancelTimer() {
        dismissTimer?.invalidate()
        dismissTimer = nil
    }
}

/// The chip's line: what happened, optionally where to, and the two answers.
@MainActor
final class PopupChipView: NSView {

    var onOpen: (() -> Void)?
    var onAllow: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    let headline = NSTextField(labelWithString: "")
    let address = AddressLabel(labelWithString: "")
    let open = PopoutTextButton(
        title: String(localized: "Open"),
        label: String(localized: "Open the pop-up"),
        restingInk: Tokens.Text.primary,
        font: Tokens.TypeScale.sidebarRow
    )
    let allow = PopoutTextButton(
        title: String(localized: "Always Allow"),
        label: String(localized: "Always allow pop-ups on this site"),
        restingInk: Tokens.Text.primary,
        font: Tokens.TypeScale.sidebarRow
    )
    private let stack = NSStackView()
    private var tracking: NSTrackingArea?

    private static var height: CGFloat { Tokens.Metric.urlPill.height }

    init(count: Int, url: URL, showsAddress: Bool, shortcut: String?) {
        super.init(frame: .zero)
        build()
        update(count: count, url: url, showsAddress: showsAddress, shortcut: shortcut)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = Self.height / 2
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1

        headline.font = Tokens.TypeScale.sidebarRow
        headline.textColor = Tokens.Text.primary
        headline.setContentCompressionResistancePriority(.required, for: .horizontal)

        address.font = Tokens.TypeScale.sidebarRow
        address.textColor = Tokens.Text.secondary
        address.lineBreakMode = .byTruncatingMiddle
        address.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        open.onActivate = { [weak self] in self?.onOpen?() }
        allow.onActivate = { [weak self] in self?.onAllow?() }

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Tokens.Metric.chromeGap
        stack.setViews([headline, address, open, allow], in: .leading)
        stack.setHuggingPriority(.required, for: .horizontal)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // The leading inset is the pill's text inset; the buttons carry their own
        // padding, so the trailing one is a chrome gap less.
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.height / 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Tokens.Metric.panelInset / 2),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            address.widthAnchor.constraint(lessThanOrEqualToConstant: Tokens.Metric.urlPill.width / 2)
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = PopupChip.fill.cgColor
            layer?.borderColor = Tokens.Line.hairline.cgColor
        }
    }

    func update(count: Int, url: URL, showsAddress: Bool, shortcut: String?) {
        headline.stringValue = count == 1
            ? String(localized: "Pop-up blocked")
            : String(localized: "\(count) pop-ups blocked")
        address.isHidden = !showsAddress
        address.stringValue = url.host(percentEncoded: false) ?? url.absoluteString
        address.toolTip = url.absoluteString
        open.title = shortcut.map { String(localized: "Open \($0)") } ?? String(localized: "Open")
        open.toolTip = shortcut.map { String(localized: "Open the pop-up (\($0))") }
        setAccessibilityLabel(headline.stringValue)
        needsLayout = true
    }

    /// One line at the pill's height, no wider than the save chip.
    func fittingChipSize() -> CGSize {
        layoutSubtreeIfNeeded()
        let width = stack.fittingSize.width + Self.height / 2 + Tokens.Metric.panelInset / 2
        return CGSize(width: min(ceil(width), Tokens.Metric.passwordChip.width), height: Self.height)
    }

    /// A fade only, as `SavePasswordChipView.animateIn`: built and shown in one
    /// breath, it has no earlier position to travel from.
    func animateIn() {
        guard !Tokens.A11y.reduceMotion else { return }
        alphaValue = 0
        Tokens.Motion.animate(Tokens.Motion.popoverIn) { _ in
            animator().alphaValue = 1
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    // The pointer on its way to a button pauses the auto-dismiss.
    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }
}

/// The host on screen, the whole address to VoiceOver. A label's value is its
/// string, and `setAccessibilityValue` on one is overwritten by it, so the
/// full URL is answered here — the same string as the tooltip.
@MainActor
final class AddressLabel: NSTextField {
    override func accessibilityValue() -> String? { toolTip ?? stringValue }
}
