//
//  CommandBarPanel.swift
//  Luna
//
//  §9.1's surface: "a floating rounded panel over the current tab, anchored
//  ~20 % from the window top".
//
//  A view in the browser window rather than a child `NSPanel`. A second window
//  would bring its own key-window dance, first-responder transfer and
//  follow-the-parent bookkeeping on every move and resize, to buy something the
//  bar does not need: it is modal over one window and dies with it.
//
//  AND NO BACKDROP. §9.1 asked for a "blurred backdrop scrim" and Luna had one
//  in two shapes, neither of which earned its keep. At `alphaValue = 0.55` an
//  `NSVisualEffectView` does not thin — it cross-fades the blurred result back
//  over the sharp original, so the bar sat on a grey film over a perfectly
//  legible page. At full strength with §2's frost over it the frost followed
//  §2a's density, and `.opaque` is `Ink.frostOpaque`: 0.66 in dark mode, a
//  sheet two thirds of the way to solid with the blur buried under it. The
//  third version, the blur alone, was cut as well.
//
//  So the panel floats over the page as it is. This view still covers the
//  window — it is what stops a click reaching the page and what carries §9.1's
//  dismissal (`mouseDown` below) — it simply draws nothing while doing it.
//  `Glass.scrim()` and `GlassScrim.swift` went with the plane. The finding that
//  sent that surface to `NSVisualEffectView` in the first place, that glass
//  composites what is behind the window and so replaces a page rather than
//  blurring it, is kept where it still decides something: `Glass.peekPlane`.
//

import AppKit

/// The panel's geometry.
///
/// Every value is derived from an existing `Tokens.Metric`, because `Design/`
/// has no command-bar entry yet and contract rule 2 forbids inlining one. The
/// one value with no token is called out below.
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
    /// UI-SPEC §6: "anchored 20 % from window top". Missing token — it is a
    /// ratio rather than a length, so `Tokens.Metric` has nowhere to put it today.
    static let topAnchorFraction: CGFloat = 0.20
    /// How long the bar will wait, behind the pill, for the store to answer the
    /// query it is opening with — see `CommandBarController.openWhenReady`.
    ///
    /// A timeout rather than a duration: on a warm store the query lands in
    /// about 9 ms and this never fires. It guarantees a busy store cannot hold
    /// the bar shut, and 0.10 s is the longest a click may go unanswered before
    /// the delay reads as nothing having happened.
    static let openDeadline: TimeInterval = 0.10
}

/// The full-window overlay: scrim, panel, input and results.
@MainActor
final class CommandBarPanel: NSView {

    let field = CommandBarInputField()
    let results: CommandBarResultsView

    /// §9.1's leading mark: a magnifier while what is typed is a search, and
    /// the site's favicon — or a globe — the moment it reads as an address. The
    /// same glyph §3.2's pill wears, by the same rule.
    ///
    /// It sits in the rows' favicon column, so the mark is above their icons
    /// and the query above their titles: what you are typing lines up with what
    /// it is finding.
    private let mark = NSImageView()
    private var markState: URLPillView.LeadingMark?

    /// A click that lands on the scrim rather than the panel (§9.1 dismissal).
    var onBackgroundClick: (() -> Void)?

    /// What VoiceOver notifications are posted against — the combo box itself.
    let body = CommandBarPanelBody()

    var topAnchorConstraint: NSLayoutConstraint?
    var centreConstraint: NSLayoutConstraint?
    var widthConstraint: NSLayoutConstraint?
    /// The two constants the input row's height is spent on: where the field is
    /// centred, and where the list starts. Both move when the bar is wearing a
    /// pill's height rather than a chrome bar's.
    var fieldCentreConstraint: NSLayoutConstraint?
    var resultsTopConstraint: NSLayoutConstraint?
    /// The reveal's own height: required, and temporary. It exists only while
    /// an anchored bar is opening (`revealFromPill`), the one moment the glass
    /// may disagree with the list about how tall it should be.
    var revealConstraint: NSLayoutConstraint?

    /// The pill this bar grew out of, or nil for §9.1's floating panel.
    let anchor: CommandBarAnchor?

    /// True from the moment `animateIn` is called until the bar has finished
    /// opening. Nothing may rebuild the list while it is true — see
    /// `CommandBarController.apply`.
    private(set) var isOpening = false

    /// Called once, when the opening animation has finished — or immediately,
    /// when there was none to run.
    var onOpened: (() -> Void)?

    /// Ends the opening window, at most once.
    func finishOpening() {
        guard isOpening else { return }
        isOpening = false
        onOpened?()
    }

    /// Starts it. Only `animateIn` calls this.
    func beginOpening() { isOpening = true }

    /// How tall the input row is: a chrome bar's 52 pt when the panel floats,
    /// and the pill's own height plus a margin above and below when it grew
    /// from one. Read live, because §3.2b's pill is 22 pt collapsed and 34 open.
    ///
    /// The margin is the difference between a pill and a panel. 34 pt suits a
    /// capsule whose own edges hold the address off the chrome around it; the
    /// same 34 at the top of a panel puts the query against the glass with the
    /// first result under its chin. The field stays on the pill's centre line
    /// either way — the panel starts that margin higher, which keeps the two
    /// lined up.
    var inputHeight: CGFloat {
        guard let anchor else { return CommandBarMetrics.inputHeight }
        return anchor.view.bounds.height + 2 * inputPadding
    }

    /// Zero when the bar is floating: `CommandBarMetrics.inputHeight` is 52 pt
    /// for a field that is 20, and already all the room it needs.
    var inputPadding: CGFloat {
        anchor == nil ? 0 : CommandBarMetrics.padding
    }

    /// The region the bar belongs over: the page, not the window.
    ///
    /// The panel covers the whole window so nothing behind it is clickable, but
    /// centring the bar in the window put it half a sidebar's width to the left
    /// of where the user is looking. This
    /// is `ContentCardView`'s frame, read live so it survives a resize and a
    /// sidebar drag under an open bar.
    var contentRegion: (() -> NSRect)?

    init(frame frameRect: NSRect, resultsView: CommandBarResultsView, anchor: CommandBarAnchor? = nil) {
        self.results = resultsView
        self.anchor = anchor
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
        // §2's popover material: `.regular` glass, untinted. The chrome's
        // tint darkens a dark theme by design (it is what makes the sidebar
        // read as dense), and a bar floating over a page wants the opposite —
        // it should look like a pane of the desktop, not like more chrome.
        // A pill's own corner when the bar grew out of one. The panel's
        // 25 pt card radius on a capsule 34 pt tall is rounder than the capsule
        // it is replacing, so the first frame of the reveal changes the shape
        // of the thing the user clicked. `urlPill.cornerRadius` is that shape.
        Glass.apply(.popover, to: body, cornerRadius: bodyRadius)
        addSubview(body)

        field.translatesAutoresizingMaskIntoConstraints = false
        results.translatesAutoresizingMaskIntoConstraints = false
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.imageScaling = .scaleProportionallyUpOrDown
        mark.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: Tokens.Metric.faviconSize,
            weight: .regular
        )
        // It is a mark, not a control: it says what the field already says, and
        // the field is what VoiceOver should land on.
        mark.setAccessibilityElement(false)
        body.addSubview(mark)
        body.addSubview(field)
        body.addSubview(results)
        showMark(for: "")
        activateBodyConstraints()
        finishBody()
    }

    /// The body's geometry: the five constraints the panel keeps a handle on,
    /// and the fixed ones around them.
    ///
    /// Split from `buildBody` because the two halves are read for different
    /// reasons — one is what the panel is made of, the other is where each piece
    /// sits — and the second is the half that changes when a placement does.
    private func activateBodyConstraints() {
        // Flush with the rows, not with their titles. Indenting the query
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
        // A constant rather than a constant value: anchored, the bar is as
        // wide as the pill it grew from, and that width follows a sidebar drag.
        let width = body.widthAnchor.constraint(equalToConstant: CommandBarMetrics.width)
        widthConstraint = width
        let fieldCentre = field.centerYAnchor.constraint(
            equalTo: body.topAnchor,
            constant: CommandBarMetrics.inputHeight / 2
        )
        fieldCentreConstraint = fieldCentre
        let resultsTop = results.topAnchor.constraint(
            equalTo: body.topAnchor,
            constant: CommandBarMetrics.inputHeight
        )
        resultsTopConstraint = resultsTop

        NSLayoutConstraint.activate([
            centre,
            width,
            top,

            // Centred in the input row, not stretched over it. An
            // `NSTextField` draws its single line at the top of whatever
            // frame it is given, so a 52 pt field put the placeholder hard
            // against the panel's top edge, above the rounded corners — the
            // misalignment the capture shows. The row is still 52 pt; the
            // field is its own height inside it.
            fieldCentre,
            // The mark takes the rows' icon column and the query starts where
            // their titles do — the same `rowInset` and the same gap the result
            // rows' own stack uses, so the two line up exactly.
            mark.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: rowInset),
            mark.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            mark.widthAnchor.constraint(equalToConstant: Tokens.Metric.faviconSize),
            mark.heightAnchor.constraint(equalToConstant: Tokens.Metric.faviconSize),
            field.leadingAnchor.constraint(
                equalTo: mark.trailingAnchor,
                constant: Tokens.Metric.panelInset
            ),
            field.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -rowInset),

            resultsTop,
            results.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            results.trailingAnchor.constraint(equalTo: body.trailingAnchor)
        ])

        // The list is what makes the glass as tall as it is — on both
        // placements, and through Auto Layout rather than through a number this
        // file would have to keep up to date. That matters because the list
        // changes size after the bar is already on screen: the history query
        // lands, then the engine's suggestions, and each one re-ranks the rows.
        //
        // Anchored it is almost required. The reveal needs the glass to be
        // shorter than the list for 0.18 s, so it puts a required height on the
        // body and takes it off again at the end (`revealFromPill`); this
        // constraint is the one that is violated for exactly that long, and
        // `masksToBounds` is what makes the difference a reveal rather than
        // rows floating over the page.
        let bottom = results.bottomAnchor.constraint(
            equalTo: body.bottomAnchor,
            constant: -CommandBarMetrics.padding
        )
        if anchor != nil {
            bottom.priority = NSLayoutConstraint.Priority(999)
            body.layer?.masksToBounds = true
        }
        bottom.isActive = true
    }

    private func finishBody() {

        // §21.1: an edit field plus a list of results is a combo box, and that is
        // what VoiceOver expects from a bar like this. The field and the list keep
        // their own roles as its children.
        body.setAccessibilityRole(.comboBox)
        body.setAccessibilityLabel("Command Bar")
        body.setAccessibilityElement(true)
    }

    /// Point the mark at what is in the field now. Called on every keystroke —
    /// `apply` is a no-op when the answer has not changed, which most
    /// keystrokes do not change.
    func showMark(for text: String) {
        let next = URLPillView.LeadingMark.reading(text)
        guard next != markState else { return }
        markState = next
        switch next {
        case .search:
            mark.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
            mark.image?.isTemplate = true
            mark.contentTintColor = Tokens.Text.secondary
        case .link:
            mark.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
            mark.image?.isTemplate = true
            mark.contentTintColor = Tokens.Text.secondary
        case let .site(favicon):
            mark.image = favicon
            mark.contentTintColor = nil
        }
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
}

/// The rounded panel itself. Swallows clicks so they do not reach the scrim.
@MainActor
final class CommandBarPanelBody: NSView {
    override func mouseDown(with event: NSEvent) {}
}
