//
//  HistoryPanel.swift
//  Luna
//
//  §6.4's archive, as a **floating panel over the page** rather than as a tab.
//
//  It used to be `luna://archive`, an internal page in a new tab. That is the
//  wrong shape for it twice over: looking something up in your history is a
//  glance, and a glance should not cost a tab you then have to close — and a
//  page cannot be Liquid Glass, so the one surface in the app that is *about*
//  the tabs looked like a website. The page still exists and the route still
//  works; this is what §3.5's History button opens.
//
//  The shell is deliberately the Command Bar's: scrim, glass body, centred over
//  the page, dismissed by `esc` or by a click outside. They are the same kind of
//  surface over the same content and there is no reason for them to be two
//  different objects on screen.
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
}

/// The full-window overlay: scrim, panel, header and list.
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

    private let rows = NSStackView()
    private let scroll = NSScrollView()
    private let empty = NSTextField(labelWithString: "")
    private var centreConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?

    /// Where the page is inside the window — the panel belongs over the page,
    /// not over the window. See `CommandBarPanel.contentRegion`.
    var contentRegion: (() -> NSRect)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        buildScrim()
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
        for view in rows.arrangedSubviews { view.removeFromSuperview() }
        for entry in entries {
            let row = HistoryRowView(entry: entry, icon: iconProvider?(entry))
            row.onClick = { [weak self] in self?.onChoose?(entry.id) }
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        empty.isHidden = !entries.isEmpty
        scroll.isHidden = entries.isEmpty
        needsLayout = true
    }

    func focusFilter() {
        window?.makeFirstResponder(field)
    }

    // MARK: - Build

    private func buildScrim() {
        // The same within-window backdrop the Command Bar uses, and at full
        // strength for the same reason — see `CommandBarPanel.buildScrim`.
        let scrim = Glass.scrim()
        scrim.frame = bounds
        scrim.autoresizingMask = [.width, .height]
        addSubview(scrim)
    }

    private func buildBody() {
        body.wantsLayer = true
        body.translatesAutoresizingMaskIntoConstraints = false
        Glass.apply(.popover, to: body, cornerRadius: HistoryPanelMetrics.cornerRadius)
        addSubview(body)

        let title = NSTextField(labelWithString: String(localized: "History"))
        title.font = Tokens.TypeScale.settingsHeading
        title.textColor = Tokens.Text.primary
        title.translatesAutoresizingMaskIntoConstraints = false

        field.translatesAutoresizingMaskIntoConstraints = false
        field.onChange = { [weak self] text in self?.onFilter?(text) }
        field.onCancel = { [weak self] in self?.onBackgroundClick?() }

        rows.orientation = .vertical
        rows.spacing = 0
        rows.alignment = .leading
        rows.translatesAutoresizingMaskIntoConstraints = false

        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = rows
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

        let inset = HistoryPanelMetrics.inset
        let centre = body.centerXAnchor.constraint(equalTo: centerXAnchor)
        centreConstraint = centre
        let height = body.heightAnchor.constraint(equalToConstant: HistoryPanelMetrics.size.height)
        heightConstraint = height

        NSLayoutConstraint.activate([
            centre,
            body.centerYAnchor.constraint(equalTo: centerYAnchor),
            body.widthAnchor.constraint(equalToConstant: HistoryPanelMetrics.size.width),
            height,

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
            rows.widthAnchor.constraint(equalTo: scroll.widthAnchor),

            empty.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: inset),
            empty.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -inset),
            empty.centerYAnchor.constraint(equalTo: body.centerYAnchor)
        ])

        body.setAccessibilityRole(.group)
        body.setAccessibilityLabel(String(localized: "History"))
        body.setAccessibilityElement(true)
    }

    /// Centred on the **page**, and never taller than the window it floats in.
    override func layout() {
        super.layout()
        let reported = contentRegion?() ?? bounds
        let region = reported.isEmpty ? bounds : reported
        centreConstraint?.constant = region.midX - bounds.midX
        let ceiling = max(region.height - HistoryPanelMetrics.inset * 2, HistoryPanelMetrics.headerHeight)
        heightConstraint?.constant = min(HistoryPanelMetrics.size.height, ceiling)
    }

    override func mouseDown(with event: NSEvent) {
        onBackgroundClick?()
    }

    /// The same spec the Command Bar arrives on — they are the same surface.
    func animateIn() {
        layoutSubtreeIfNeeded()
        guard let scale = Tokens.Motion.commandBarIn.springAnimation(keyPath: "transform.scale") else {
            alphaValue = 1
            return
        }
        scale.fromValue = 0.96
        scale.toValue = 1.0
        body.layer?.add(scale, forKey: "historyIn")
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
