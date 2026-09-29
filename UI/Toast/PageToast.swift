//
//  PageToast.swift
//  Luna
//
//  One line of feedback over the page: a copied link, a zoom step, a switch
//  in the Develop menu, a blocked pop-up. A glass pill that drops from the
//  page's top edge the way a Luna Control question does, stays a moment and
//  goes back up. It sits on `ControlSurfaceView`, the layer over the page that
//  already knows where the bar ends and what colour the page is.
//
//  It is Luna's one toast (CLAUDE.md, "One toast"). News that offers an answer
//  — Open, Always Allow — carries it as `actions`, words on the same pill,
//  and stays until the pointer has had time to reach them.
//

import AppKit
import BrowserKit

/// What a toast says, and what it offers.
struct PageToast: Equatable {

    /// A word on the pill that does something. The toast goes back up once
    /// it has run.
    struct Action {
        let title: String
        /// What VoiceOver says, when the title alone is not a sentence.
        var label: String?
        var toolTip: String?
        let run: @MainActor () -> Void
    }

    let symbol: String
    let text: String
    /// A second, quieter part of the line: a host, a name. Truncated in the
    /// middle before the text gives way.
    var detail: String?
    var actions: [Action] = []

    init(symbol: String, text: String, detail: String? = nil, actions: [Action] = []) {
        self.symbol = symbol
        self.text = text
        self.detail = detail
        self.actions = actions
    }

    /// Two toasts are the same news when they say the same thing; the
    /// closures behind their words cannot be compared, and need not be.
    static func == (lhs: PageToast, rhs: PageToast) -> Bool {
        lhs.symbol == rhs.symbol && lhs.text == rhs.text && lhs.detail == rhs.detail
            && lhs.actions.map(\.title) == rhs.actions.map(\.title)
    }

    /// How long it stays once down: a glance for news, long enough to reach a
    /// word for news that offers one.
    var dwell: TimeInterval {
        actions.isEmpty ? Tokens.Motion.toastDwell : Tokens.Motion.toastActionDwell
    }

    static let linkCopied = PageToast(symbol: "link", text: String(localized: "Link copied"))
    static let markdownCopied = PageToast(symbol: "doc.on.clipboard", text: String(localized: "Markdown link copied"))
    static let cachesEmptied = PageToast(symbol: "trash", text: String(localized: "Caches emptied"))

    static func zoom(_ level: CGFloat) -> PageToast {
        PageToast(symbol: "magnifyingglass", text: String(localized: "Zoom \(Int((level * 100).rounded())) %"))
    }

    static func favorite(added: Bool) -> PageToast {
        added
            ? PageToast(symbol: "star.fill", text: String(localized: "Added to Favorites"))
            : PageToast(symbol: "star.slash", text: String(localized: "Removed from Favorites"))
    }

    static func archived(_ count: Int) -> PageToast {
        PageToast(
            symbol: "archivebox",
            text: count == 1 ? String(localized: "1 tab archived") : String(localized: "\(count) tabs archived")
        )
    }

    static func javaScript(disabled: Bool) -> PageToast {
        disabled
            ? PageToast(symbol: "curlybraces", text: String(localized: "JavaScript off"))
            : PageToast(symbol: "curlybraces", text: String(localized: "JavaScript on"))
    }

    static func userAgent(_ name: String) -> PageToast {
        PageToast(symbol: "person.text.rectangle", text: String(localized: "User agent: \(name)"))
    }

    static func pictureInPicture(_ answer: PictureInPictureAnswer) -> PageToast {
        switch answer {
        case .floating: PageToast(symbol: "pip.enter", text: String(localized: "Picture in Picture on"))
        case .backInPage: PageToast(symbol: "pip.exit", text: String(localized: "Picture in Picture off"))
        case .noVideo: PageToast(symbol: "pip", text: String(localized: "No video to float"))
        }
    }

    static func reader(_ answer: ReaderAnswer) -> PageToast {
        switch answer {
        case .on: PageToast(symbol: "doc.plaintext", text: String(localized: "Reader on"))
        case .off: PageToast(symbol: "doc.plaintext", text: String(localized: "Reader off"))
        case .nothingToRead: PageToast(symbol: "doc.plaintext", text: String(localized: "Nothing to read on this page"))
        }
    }

    static let hidingStarted = PageToast(
        symbol: "eye.slash", text: String(localized: "Click anything to hide it. ⌘Z brings each one back. Esc to stop.")
    )

    static func hidden(_ label: String) -> PageToast {
        PageToast(symbol: "eye.slash", text: String(localized: "Hidden: \(label). ⌘Z brings it back."))
    }

    static func shownAgain(_ label: String) -> PageToast {
        PageToast(symbol: "eye", text: String(localized: "Showing \(label) again"))
    }

    /// On the page of `window`, or of the browser window in front: a menu
    /// item and a keystroke both act on the key window.
    ///
    /// `untilPutAway` keeps it down past its dwell, for an instruction that
    /// holds for as long as a mode does; `putAway(in:)` takes it back up.
    @MainActor
    func show(in window: NSWindow? = nil, untilPutAway: Bool = false) {
        Self.surface(in: window)?.showToast(self, dwells: !untilPutAway)
    }

    /// Takes this toast back up, and only this one: a newer toast already
    /// rewrote it and keeps its own dwell.
    @MainActor
    func putAway(in window: NSWindow? = nil) {
        guard let surface = Self.surface(in: window), surface.toast?.text == text else { return }
        surface.hideToast()
    }

    @MainActor
    private static func surface(in window: NSWindow?) -> ControlSurfaceView? {
        let host = window ?? NSApp.keyWindow ?? NSApp.mainWindow
        return (host?.windowController as? BrowserWindowController)?.controlSurface
    }
}

/// The pill. Takes no clicks but its words': it is there to be read, and the
/// page under it keeps the rest.
@MainActor
final class PageToastView: NSView {

    /// The pointer came onto the pill or left it, which holds its dwell.
    var onHoverChanged: ((Bool) -> Void)?
    /// A word was pressed and its action has run.
    var onActed: (() -> Void)?

    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    let detail = NSTextField(labelWithString: "")
    private let row = NSStackView()
    private(set) var buttons: [PopoutTextButton] = []
    /// The dwell of the toast it is showing, for the hover to restart.
    var dwell = Tokens.Motion.toastDwell

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        let height = Tokens.Agent.capsuleHeight
        Glass.apply(.popover, to: self, cornerRadius: height / 2).pinToEdges()
        label.font = Tokens.TypeScale.settingsRow
        label.textColor = Tokens.Text.primary
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        detail.font = Tokens.TypeScale.settingsRow
        detail.textColor = Tokens.Text.secondary
        detail.lineBreakMode = .byTruncatingMiddle
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.widthAnchor.constraint(lessThanOrEqualToConstant: Tokens.Metric.urlPill.width / 2).isActive = true
        icon.contentTintColor = Tokens.Text.primary
        row.setViews([icon, label, detail], in: .leading)
        row.orientation = .horizontal
        row.spacing = Tokens.Metric.chromeGap
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 0, left: height / 2, bottom: 0, right: height / 2)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.setHuggingPriority(.defaultHigh, for: .horizontal)
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: height)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    var text: String { label.stringValue }

    func configure(_ toast: PageToast) {
        let size = NSImage.SymbolConfiguration(pointSize: label.font?.pointSize ?? 13, weight: .medium)
        icon.image = NSImage(systemSymbolName: toast.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(size)
        label.stringValue = toast.text
        detail.stringValue = toast.detail ?? ""
        detail.isHidden = toast.detail == nil
        for button in buttons { row.removeView(button) }
        buttons = toast.actions.map { action in
            // At the text's own ink and size: at a header's secondary ink the
            // words read as disabled beside the news they answer.
            let button = PopoutTextButton(
                title: action.title,
                label: action.label ?? action.title,
                restingInk: Tokens.Text.primary,
                font: Tokens.TypeScale.settingsRow
            )
            button.toolTip = action.toolTip
            button.onActivate = { [weak self] in
                action.run()
                self?.onActed?()
            }
            row.addView(button, in: .leading)
            return button
        }
        // The words carry their own padding, so the pill's trailing inset is
        // a chrome gap less beside them.
        let height = Tokens.Agent.capsuleHeight
        row.edgeInsets.right = buttons.isEmpty ? height / 2 : height / 2 - Tokens.Metric.chromeGap
    }

    /// Only the words take the pointer.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !buttons.isEmpty, let hit = super.hitTest(point) else { return nil }
        return buttons.contains { hit === $0 || hit.isDescendant(of: $0) } ? hit : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }
}

extension ControlSurfaceView {

    /// Drops `toast` from under the bar, or rewrites the one already down: a
    /// second copy is the same news again, not a new arrival.
    func showToast(_ toast: PageToast, dwells: Bool = true) {
        let view: PageToastView
        if let current = self.toast {
            view = current
            view.configure(toast)
            Tokens.Motion.immediately { layoutSubtreeIfNeeded() }
        } else {
            view = PageToastView()
            view.onHoverChanged = { [weak self, weak view] hovering in
                guard let self, let view, self.toast === view else { return }
                if hovering {
                    self.toastDismissal?.cancel()
                } else {
                    self.scheduleToastDismissal(after: view.dwell)
                }
            }
            view.onActed = { [weak self] in self?.hideToast() }
            view.configure(toast)
            view.alphaValue = 0
            addSubview(view)
            let top = view.topAnchor.constraint(equalTo: topAnchor, constant: toastTopConstant(for: view, shown: false))
            NSLayoutConstraint.activate([view.centerXAnchor.constraint(equalTo: centerXAnchor), top])
            self.toast = view
            toastTop = top
            Tokens.Motion.immediately { layoutSubtreeIfNeeded() }
            let shown = toastTopConstant(for: view, shown: true)
            Tokens.Motion.animate(Tokens.Motion.agentSheet) { _ in
                top.animator().constant = shown
                view.animator().alphaValue = 1
            }
        }
        NSAccessibility.post(
            element: view, notification: .announcementRequested,
            userInfo: [.announcement: toast.text, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
        view.dwell = toast.dwell
        toastDismissal?.cancel()
        guard dwells else { return }
        scheduleToastDismissal(after: toast.dwell)
    }

    private func scheduleToastDismissal(after dwell: TimeInterval) {
        toastDismissal?.cancel()
        toastDismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(dwell))
            guard !Task.isCancelled else { return }
            self?.hideToast()
        }
    }

    func hideToast() {
        guard let view = toast, let top = toastTop else { return }
        toast = nil
        toastTop = nil
        let hidden = toastTopConstant(for: view, shown: false)
        Tokens.Motion.animate(Tokens.Motion.agentSheet) { _ in
            top.animator().constant = hidden
            view.animator().alphaValue = 0
        } completion: {
            MainActor.assumeIsolated { view.removeFromSuperview() }
        }
    }

    /// Shown, a gap under the bar, or under the question if one is down;
    /// hidden, wholly under the bar it slides out of.
    private func toastTopConstant(for view: NSView, shown: Bool) -> CGFloat {
        guard shown else { return topInset - view.fittingSize.height }
        let below = sheet.map { topInset - ControlApprovalCardView.hiddenTop + $0.fittingSize.height } ?? topInset
        return below + Tokens.Metric.chromeGap
    }
}
