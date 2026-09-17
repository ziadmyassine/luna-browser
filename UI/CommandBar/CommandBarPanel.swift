//
//  CommandBarPanel.swift
//  Luna
//
//  §9.1's surface: "a floating rounded panel over the current tab with a blurred
//  backdrop scrim, anchored ~20 % from the window top".
//
//  A view in the browser window rather than a child `NSPanel`. A second window
//  would bring its own key-window dance, its own first-responder transfer and its
//  own follow-the-parent bookkeeping on every move and resize, to buy something
//  this does not need — the bar is modal over exactly one window and dies with it.
//
//  The scrim is real glass, not a dimming fill. `Glass` is the only permitted
//  route to Liquid Glass (contract rule 3), glass over in-window content is a
//  genuine backdrop blur, and it already falls back to a solid surface under
//  Reduce Transparency and gains a border under Increase Contrast (§21.2) — all
//  of which a hand-rolled scrim would have to reimplement, and one of which it
//  would forget.
//

import AppKit

/// The panel's geometry.
///
/// **Every value is derived from an existing `Tokens.Metric`, because `Design/`
/// has no command-bar entry yet and contract rule 2 forbids inlining one.** The
/// one value with no token at all is called out below; it belongs in
/// `Tokens.Metric` and is named in this agent's report.
enum CommandBarMetrics {
    /// §9.7's cap, and the reason the list is a stack rather than an
    /// `NSTableView`: eight rows never scroll, so there is no view reuse to do
    /// and no scroll position to keep honest across a re-rank.
    static let visibleRows = 8
    /// How many history rows to ask the store for before ranking and deduping.
    /// Wider than `visibleRows`, so dedupe against the open tabs has something
    /// left over to show.
    static let historyLimit = 24
    /// As wide as the narrowest window Luna allows, so the bar is the same size in
    /// every window instead of a fraction that moves while you resize.
    static let width = Tokens.Metric.windowMinWidth
    static let cornerRadius = Tokens.Metric.contentCardRadius
    /// The input row — the same height as the chrome bars it covers.
    static let inputHeight = Tokens.Metric.topBarHeight
    static let padding = Tokens.Metric.contentCardGap
    /// UI-SPEC §6: "anchored 20 % from window top". **Missing token** — it is a
    /// ratio rather than a length, so `Tokens.Metric` has nowhere to put it today.
    static let topAnchorFraction: CGFloat = 0.20
}

/// The full-window overlay: scrim, panel, input and results.
@MainActor
final class CommandBarPanel: NSView {

    let field = CommandBarInputField()
    let results: CommandBarResultsView

    /// A click that lands on the scrim rather than the panel (§9.1 dismissal).
    var onBackgroundClick: (() -> Void)?

    /// What VoiceOver notifications are posted against — the combo box itself.
    let body = CommandBarPanelBody()

    private var topAnchorConstraint: NSLayoutConstraint?

    init(frame frameRect: NSRect, resultsView: CommandBarResultsView) {
        self.results = resultsView
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        buildScrim()
        buildBody()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func buildScrim() {
        let scrim = Glass.backing(.sidebar)
        scrim.frame = bounds
        scrim.autoresizingMask = [.width, .height]
        addSubview(scrim)
    }

    private func buildBody() {
        body.wantsLayer = true
        body.translatesAutoresizingMaskIntoConstraints = false
        Glass.apply(.popover, to: body, cornerRadius: CommandBarMetrics.cornerRadius)
        addSubview(body)

        field.translatesAutoresizingMaskIntoConstraints = false
        results.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(field)
        body.addSubview(results)

        let inset = CommandBarMetrics.padding + Tokens.Metric.rowInset
        let top = body.topAnchor.constraint(
            equalTo: topAnchor,
            constant: bounds.height * CommandBarMetrics.topAnchorFraction
        )
        topAnchorConstraint = top

        NSLayoutConstraint.activate([
            body.centerXAnchor.constraint(equalTo: centerXAnchor),
            body.widthAnchor.constraint(equalToConstant: CommandBarMetrics.width),
            top,

            field.topAnchor.constraint(equalTo: body.topAnchor),
            field.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: inset),
            field.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -inset),
            field.heightAnchor.constraint(equalToConstant: CommandBarMetrics.inputHeight),

            results.topAnchor.constraint(equalTo: field.bottomAnchor),
            results.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            results.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            results.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -CommandBarMetrics.padding)
        ])

        // §21.1: an edit field plus a list of results is a combo box, and that is
        // what VoiceOver expects from a bar like this. The field and the list keep
        // their own roles as its children.
        body.setAccessibilityRole(.comboBox)
        body.setAccessibilityLabel("Command Bar")
        body.setAccessibilityElement(true)
    }

    /// UI-SPEC §6 anchors the panel to a *fraction* of the window, so a constant
    /// set once is wrong the moment the window is resized under an open bar.
    override func layout() {
        super.layout()
        topAnchorConstraint?.constant = bounds.height * CommandBarMetrics.topAnchorFraction
    }

    /// Clicks reach here up the responder chain: the scrim is a glass view with no
    /// `mouseDown` of its own, so its press walks up to this. `CommandBarPanelBody`
    /// stops the presses that land on the panel, which is the only reason it is a
    /// subclass — without it, clicking the bar's own background would dismiss it.
    override func mouseDown(with event: NSEvent) {
        onBackgroundClick?()
    }

    /// §6 `commandBarIn`: 0.18 s spring, scale 0.96 → 1.0 + fade.
    ///
    /// Reduce Motion degrades it to instant with no second code path:
    /// `springAnimation` returns nil, and `Motion.animate` runs at zero duration.
    func animateIn() {
        layoutSubtreeIfNeeded()
        guard let scale = Tokens.Motion.commandBarIn.springAnimation(keyPath: "transform.scale") else {
            alphaValue = 1
            return
        }
        scale.fromValue = 0.96
        scale.toValue = 1.0
        body.layer?.add(scale, forKey: "commandBarIn")
        alphaValue = 0
        Tokens.Motion.animate(Tokens.Motion.commandBarIn) { _ in
            self.animator().alphaValue = 1
        }
    }
}

/// The rounded panel itself. Swallows clicks so they do not reach the scrim.
@MainActor
final class CommandBarPanelBody: NSView {
    override func mouseDown(with event: NSEvent) {}
}
