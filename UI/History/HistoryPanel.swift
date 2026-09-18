//
//  HistoryPanel.swift
//  Luna
//
//  §6.4's archive, as a **pop-out from the §3.5 History button** — the same
//  shape §3.2's site menu takes from the sliders glyph.
//
//  It used to be `luna://archive`, an internal page in a new tab. That is the
//  wrong shape for it twice over: looking something up in your history is a
//  glance, and a glance should not cost a tab you then have to close — and a
//  page cannot be Liquid Glass, so the one surface in the app that is *about*
//  the tabs looked like a website. The page still exists and the route still
//  works; this is what §3.5's History button opens.
//
//  **And then it was the Command Bar's shell, which was the same mistake one
//  size smaller.** Scrim, 640 pt body, centred over the page: a glance at a
//  shelf took the whole page away and put a window-sized panel where the user
//  was not looking. The Command Bar earns that — you summon it, and it is the
//  thing you are doing. History is opened *from a button*, and a surface opened
//  from a button belongs on it.
//
//  So: no scrim, a pop-out standing on the button, and the page still there
//  behind it. What is left of the overlay is a transparent sheet that catches
//  the click that dismisses it, which is exactly what an `NSMenu` puts up and
//  for the same reason.
//

import AppKit
import BrowserKit

enum HistoryPanelMetrics {
    static let size = Tokens.Metric.historyPanel
    static let cornerRadius = Tokens.Metric.contentCardRadius
    /// The header — title and filter on one line, at the same height as the
    /// chrome rows the panel covers.
    static let headerHeight = Tokens.Metric.topBarHeight
    static let padding = Tokens.Metric.panelInset
    static let inset = Tokens.Metric.chromeGapWide
    /// How far the pop-out stands off the button it came from.
    static let gap = Tokens.Metric.historyPopoutGap
}

/// The full-window sheet and the pop-out standing on it: an invisible plane
/// that catches the click outside, plus the panel, its header and its list.
@MainActor
final class HistoryPanel: NSView {

    /// A click that lands on the scrim rather than the panel.
    var onBackgroundClick: (() -> Void)?
    /// The filter text changed.
    var onFilter: ((String) -> Void)?
    /// A row was chosen — the tab comes back where it was.
    var onChoose: ((UUID) -> Void)?
    /// An entry's icon, asked for at the moment the row is built. The panel
    /// holds no session of its own.
    var iconProvider: ((HistoryEntry) -> NSImage?)?

    let body = HistoryPanelBody()
    let field = HistoryFilterField()

    private let list = HistoryListView()
    private let scroll = NSScrollView()
    private let empty = NSTextField(labelWithString: "")

    /// The §3.5 History button, in this view's coordinates — the thing the
    /// pop-out stands on. Read live, so a sidebar resize or a window resize
    /// under an open pop-out moves it with the button rather than leaving it
    /// stranded. An empty rect falls back to the window's bottom-leading
    /// corner, which is where that button is.
    var anchorRect: (() -> NSRect)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        buildBody()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Content

    /// Replaces the list. Cheap enough to call on every keystroke: the archive
    /// is capped by §19.5's sweep and the rows are plain views.
    func setEntries(_ entries: [HistoryEntry]) {
        list.iconProvider = iconProvider
        list.setEntries(entries)
        empty.isHidden = !entries.isEmpty
        scroll.isHidden = entries.isEmpty
        needsLayout = true
    }

    func focusFilter() {
        window?.makeFirstResponder(field)
    }

    // MARK: - Build

    private func buildBody() {
        body.wantsLayer = true
        // **Positioned by frame, and its children by Auto Layout.** The panel's
        // own geometry is two clamps against a button that moves with a sidebar
        // drag — see `layout()` — and a constant assigned from inside `layout()`
        // lands one pass too late to be solved, which put the pop-out at the
        // window's corner with the right size and the wrong place. The standard
        // island: `body` keeps `translatesAutoresizingMaskIntoConstraints`, and
        // everything inside it constrains to its edges as before.
        Glass.apply(.popover, to: body, cornerRadius: HistoryPanelMetrics.cornerRadius)
        // **The shadow does what the scrim used to.** With a backdrop behind it
        // the panel was separated from the page by the veil; standing on the
        // page directly, its own edge is all it has, and §2's popover material
        // has no heavier weight to ask for (`Tokens.Shadow.popover`). This is
        // the same token the §6.6 drag lift carries, for the same reason.
        body.layer.map { Tokens.Shadow.popover.apply(to: $0, in: effectiveAppearance) }
        addSubview(body)

        let title = NSTextField(labelWithString: String(localized: "History"))
        title.font = Tokens.TypeScale.settingsHeading
        title.textColor = Tokens.Text.primary
        title.translatesAutoresizingMaskIntoConstraints = false

        field.translatesAutoresizingMaskIntoConstraints = false
        field.onChange = { [weak self] text in self?.onFilter?(text) }
        field.onCancel = { [weak self] in self?.onBackgroundClick?() }
        // The field has focus, so it is where ↓/↑/↩ arrive; the list is what
        // they mean. §9.1's bar does exactly this.
        field.onMoveSelection = { [weak self] offset in self?.list.move(by: offset) }
        field.onCommit = { [weak self] in self?.list.activateSelection() }

        list.translatesAutoresizingMaskIntoConstraints = false
        list.onActivate = { [weak self] entry in self?.onChoose?(entry.id) }

        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        // **Overlay, so the scroller does not take width off the rows.** A
        // legacy scroller is laid out *beside* the document, which would make
        // the rows a scroller narrower than the list they are measured
        // against — the one way they could stop being the same width.
        scroll.scrollerStyle = .overlay
        // And a row's height of clear space at each end, so the first and last
        // rows are whole rather than sliced by the header above them and the
        // panel's own edge below. Without it the top row sat half under the
        // title and read as a shorter row.
        scroll.contentInsets = NSEdgeInsets(
            top: HistoryPanelMetrics.padding,
            left: 0,
            bottom: HistoryPanelMetrics.padding,
            right: 0
        )
        scroll.documentView = list
        scroll.translatesAutoresizingMaskIntoConstraints = false

        empty.stringValue = String(localized: "Nothing here yet. Closed tabs are kept for a while and show up here.")
        empty.font = Tokens.TypeScale.sidebarRow
        empty.textColor = Tokens.Text.secondary
        empty.alignment = .center
        empty.lineBreakMode = .byWordWrapping
        empty.maximumNumberOfLines = 0
        empty.isHidden = true
        empty.translatesAutoresizingMaskIntoConstraints = false

        for view in [title, field, scroll, empty] { body.addSubview(view) }
        constrain(title: title)
    }

    /// The other half of `buildBody`, split only because the two together
    /// crossed SwiftLint's 50-line function limit. Configuring the subviews and
    /// constraining them were already the two halves.
    private func constrain(title: NSTextField) {
        let inset = HistoryPanelMetrics.inset
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: inset),
            title.centerYAnchor.constraint(
                equalTo: body.topAnchor,
                constant: HistoryPanelMetrics.headerHeight / 2
            ),
            field.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: inset),
            field.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -inset),
            field.centerYAnchor.constraint(equalTo: title.centerYAnchor),

            scroll.topAnchor.constraint(equalTo: body.topAnchor, constant: HistoryPanelMetrics.headerHeight),
            scroll.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: HistoryPanelMetrics.padding),
            scroll.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -HistoryPanelMetrics.padding),
            scroll.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -HistoryPanelMetrics.padding),
            list.widthAnchor.constraint(equalTo: scroll.widthAnchor),

            empty.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: inset),
            empty.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -inset),
            empty.centerYAnchor.constraint(equalTo: body.centerYAnchor)
        ])

        body.setAccessibilityRole(.group)
        body.setAccessibilityLabel(String(localized: "History"))
        body.setAccessibilityElement(true)
    }

    /// **Standing on the button, and never off the window.**
    ///
    /// It grows upward from the button's top edge and rightward from its leading
    /// edge, which is the only direction there is room in: the button is at the
    /// bottom-leading corner of the sidebar, so up and across is where the
    /// window is. Both are then clamped, because the sidebar can be dragged to
    /// 420 and the window can be short.
    override func layout() {
        super.layout()
        let anchor = anchorRect?() ?? .zero
        // No anchor is the window's bottom-leading corner, which is where that
        // button is anyway.
        let button = anchor.isEmpty ? NSRect(origin: bounds.origin, size: .zero) : anchor
        let gap = HistoryPanelMetrics.gap
        let inset = HistoryPanelMetrics.inset
        let size = HistoryPanelMetrics.size

        // The foot sits a gap above the button's head; the head goes as far as
        // §1's ceiling or the top of the window, whichever comes first. The
        // header alone is the floor — a pop-out with no room for a single row
        // still has to be a pop-out.
        let foot = button.maxY + gap
        let height = min(size.height, max(bounds.maxY - foot - inset, HistoryPanelMetrics.headerHeight))
        let x = min(max(button.minX, inset), max(bounds.maxX - size.width - inset, inset))
        body.frame = NSRect(x: x, y: foot, width: size.width, height: height).integral
        body.layoutSubtreeIfNeeded()
    }

    override func mouseDown(with event: NSEvent) {
        onBackgroundClick?()
    }

    /// §6's `commandBarIn`, **grown from the button** rather than from its own
    /// centre. The anchor point is the panel's bottom-leading corner, which is
    /// the corner standing on the control that opened it, so the pop-out
    /// unfolds out of the button instead of appearing around it.
    func animateIn() {
        layoutSubtreeIfNeeded()
        guard let layer = body.layer,
              let scale = Tokens.Motion.commandBarIn.springAnimation(keyPath: "transform.scale")
        else {
            alphaValue = 1
            return
        }
        let frame = layer.frame
        layer.anchorPoint = CGPoint(x: 0, y: 0)
        layer.position = CGPoint(x: frame.minX, y: frame.minY)
        scale.fromValue = 0.96
        scale.toValue = 1.0
        layer.add(scale, forKey: "historyIn")
        alphaValue = 0
        Tokens.Motion.animate(Tokens.Motion.commandBarIn) { _ in
            self.animator().alphaValue = 1
        }
    }
}

/// The rounded panel itself. Swallows clicks so they do not reach the scrim.
@MainActor
final class HistoryPanelBody: NSView {
    override func mouseDown(with event: NSEvent) {}
}
