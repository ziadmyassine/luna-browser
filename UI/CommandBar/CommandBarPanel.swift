//
//  CommandBarPanel.swift
//  Luna
//
//  §9.1's surface: "a floating rounded panel over the current tab, anchored
//  ~20 % from the window top".
//
//  A view in the browser window rather than a child `NSPanel`. A second window
//  would bring its own key-window dance, its own first-responder transfer and its
//  own follow-the-parent bookkeeping on every move and resize, to buy something
//  this does not need — the bar is modal over exactly one window and dies with it.
//
//  **AND NO BACKDROP.** §9.1 asked for a "blurred backdrop scrim" and Luna had
//  one, in two shapes, and neither earned its keep. At `alphaValue = 0.55` an
//  `NSVisualEffectView` does not thin — it cross-fades the blurred result back
//  over the sharp original, so the bar sat on a grey film over a perfectly
//  legible page. At full strength with §2's frost over it, the frost followed
//  §2a's density, and at `.opaque` that is `Ink.frostOpaque`: **0.66 in dark
//  mode**, a sheet two thirds of the way to solid with the blur buried under
//  it. Martin looked at the third version — the blur on its own, no plane —
//  and said the backdrop is not needed at all: *"just remove the blur around
//  it completely."*
//
//  So the panel floats over the page as it is. This view still covers the
//  window, because it is what stops a click reaching the page and what carries
//  §9.1's dismissal (`mouseDown` below) — it simply draws nothing while doing
//  it. `Glass.scrim()` and `GlassScrim.swift` went with the plane; the finding
//  that sent that surface to `NSVisualEffectView` in the first place — glass
//  composites what is behind the *window*, so it replaces a page rather than
//  blurring it, and goes near-black in fullscreen — is kept where it is still
//  load-bearing, in `Glass.peekPlane`.
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
    static let padding = Tokens.Metric.panelInset
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
    private var centreConstraint: NSLayoutConstraint?

    /// The region the bar belongs over: the **page**, not the window.
    ///
    /// The panel covers the whole window so nothing behind it is clickable, but
    /// centring the bar in the window put it visibly off-centre over the page
    /// — half a sidebar's width to the left of where the user is looking. This
    /// is `ContentCardView`'s frame, read live so it survives a resize and a
    /// sidebar drag under an open bar.
    var contentRegion: (() -> NSRect)?

    init(frame frameRect: NSRect, resultsView: CommandBarResultsView) {
        self.results = resultsView
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        buildBody()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func buildBody() {
        body.wantsLayer = true
        body.translatesAutoresizingMaskIntoConstraints = false
        // §2's popover material: `.regular` glass, **untinted**. The chrome's
        // tint darkens a dark theme by design (it is what makes the sidebar
        // read as dense), and a bar floating over a page wants the opposite —
        // it should look like a pane of the desktop, not like more chrome.
        Glass.apply(.popover, to: body, cornerRadius: CommandBarMetrics.cornerRadius)
        addSubview(body)

        field.translatesAutoresizingMaskIntoConstraints = false
        results.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(field)
        body.addSubview(results)

        // **Flush with the rows, not with their titles.** Indenting the query
        // by a favicon's width lined it up with the text it filters and left
        // the panel with a visible notch out of its top-left corner — the
        // field started a centimetre in from everything below it. The list's
        // own leading edge is the panel's left margin, and that is where the
        // query starts too.
        let rowInset = CommandBarMetrics.padding + Tokens.Metric.rowInset
        let top = body.topAnchor.constraint(equalTo: topAnchor, constant: 0)
        topAnchorConstraint = top
        let centre = body.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 0)
        centreConstraint = centre

        NSLayoutConstraint.activate([
            centre,
            body.widthAnchor.constraint(equalToConstant: CommandBarMetrics.width),
            top,

            // **Centred in the input row, not stretched over it.** An
            // `NSTextField` draws its single line at the *top* of whatever
            // frame it is given, so a 52 pt field put the placeholder hard
            // against the panel's top edge, above the rounded corners — the
            // misalignment in Martin's capture. The row is still 52 pt; the
            // field is its own height inside it.
            field.centerYAnchor.constraint(
                equalTo: body.topAnchor,
                constant: CommandBarMetrics.inputHeight / 2
            ),
            field.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: rowInset),
            field.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -rowInset),

            results.topAnchor.constraint(
                equalTo: body.topAnchor,
                constant: CommandBarMetrics.inputHeight
            ),
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

    /// UI-SPEC §6 anchors the panel to a *fraction* of the surface it is over,
    /// so a constant set once is wrong the moment the window is resized — or
    /// the sidebar dragged — under an open bar. Both constants are re-derived
    /// here, against the page rather than the window.
    override func layout() {
        super.layout()
        // An empty region means nobody told us where the page is; the window
        // is the honest fallback, not a zero-sized rect at the origin.
        let reported = contentRegion?() ?? bounds
        let region = reported.isEmpty ? bounds : reported
        // Auto Layout measures a top constant downwards; `region` is in this
        // view's own bottom-left coordinates.
        topAnchorConstraint?.constant =
            (bounds.maxY - region.maxY) + region.height * CommandBarMetrics.topAnchorFraction
        centreConstraint?.constant = region.midX - bounds.midX
    }

    /// §9.1's dismissal: a press anywhere but the bar closes it.
    ///
    /// It lands here directly now that there is no backdrop in the way — this
    /// view is empty but not absent, and `hitTest` answers with it for every
    /// point the bar itself does not claim. `CommandBarPanelBody` stops the
    /// presses that land on the panel, which is the only reason it is a
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
