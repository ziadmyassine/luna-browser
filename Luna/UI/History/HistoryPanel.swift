//
//  HistoryPanel.swift
//  Luna
//
//  §6.4's History, as a pop-out from the §3.5 History button — the same
//  shape §3.2's site settings take from the sliders glyph.
//
//  The pages the Space has visited, newest first. Not §6.3's archive of closed
//  tabs: a page that was open but never closed is in history and not in the
//  archive, so searching the archive for it found nothing. Closed tabs come
//  back through the Command Bar and `luna://archive`.
//
//  A pop-out standing on its button, with no scrim and the page still behind
//  it. Not a new tab — a glance should not cost a tab, and a page cannot be
//  Liquid Glass — and not the Command Bar's centred shell, because a surface
//  opened from a button belongs on it. The sheet, glass body, clamps and spring
//  are `PopoutPanelView`'s; this file is the header, the filter and the list.
//

import AppKit
import BrowserKit

enum HistoryPanelMetrics {
    static let size = Tokens.Metric.historyPanel
    /// The header — title and filter on one line, at the same height as the
    /// chrome rows the panel covers.
    static var headerHeight: CGFloat { PopoutMetrics.headerHeight }
    static var padding: CGFloat { PopoutMetrics.padding }
    static var inset: CGFloat { PopoutMetrics.inset }
}

/// §6.4's pop-out: a header with a search field, and the pages under it.
@MainActor
final class HistoryPanel: PopoutPanelView {

    /// The search text changed.
    var onFilter: ((String) -> Void)?
    /// A row was chosen: its page opens.
    var onChoose: ((HistoryEntry) -> Void)?
    /// An entry's icon, asked for at the moment the row is built. The panel
    /// holds no session of its own.
    var iconProvider: ((HistoryEntry) -> NSImage?)?

    let field = HistoryFilterField()

    private let list = HistoryListView()
    private let empty = NSTextField(labelWithString: "")
    /// What the field holds, so the empty state can tell "no history" apart
    /// from "nothing matched".
    private var query = ""

    init(frame frameRect: NSRect, edge: PopoutEdge) {
        super.init(frame: frameRect, size: HistoryPanelMetrics.size, edge: edge)
        buildBody()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Content

    /// Replaces the list. Cheap enough to call on every keystroke — which is
    /// what it is called on — because `HistoryListView` recycles its rows, so
    /// this costs the dozen rows the panel is tall however long history is.
    /// That file's header has the measurement.
    func setEntries(_ entries: [HistoryEntry]) {
        list.iconProvider = iconProvider
        list.setEntries(entries)
        empty.stringValue = Self.emptyMessage(filteredBy: query)
        empty.isHidden = !entries.isEmpty
        list.isHidden = entries.isEmpty
        needsLayout = true
    }

    /// An empty history and an empty search are not the same sentence.
    /// "Pages you visit show up here" is an answer to "why is this blank";
    /// typed over a search that matched nothing it answers a question nobody
    /// asked, and reads as if history had emptied itself.
    private static func emptyMessage(filteredBy query: String) -> String {
        query.isEmpty
            ? String(localized: "No history yet. Pages you visit show up here.")
            : String(localized: "No matches for “\(query)”.")
    }

    /// What the list holds, in order.
    var shownEntries: [HistoryEntry] { list.entries }

    func focusFilter() {
        window?.makeFirstResponder(field)
    }

    // MARK: - Build

    private func buildBody() {
        let title = NSTextField(labelWithString: String(localized: "History"))
        title.font = Tokens.TypeScale.settingsHeading
        title.textColor = Tokens.Text.primary
        title.translatesAutoresizingMaskIntoConstraints = false

        field.translatesAutoresizingMaskIntoConstraints = false
        field.onChange = { [weak self] text in
            self?.query = text
            self?.onFilter?(text)
        }
        field.onCancel = { [weak self] in self?.onBackgroundClick?() }
        // The field has focus, so it is where ↓/↑/↩ arrive; the list is what
        // they mean. §9.1's bar does exactly this.
        field.onMoveSelection = { [weak self] offset in self?.list.move(by: offset) }
        field.onCommit = { [weak self] in self?.list.activateSelection() }

        // The list brings its own scroll view — it is a table, and a table
        // that is not in one does not recycle anything.
        list.translatesAutoresizingMaskIntoConstraints = false
        list.onActivate = { [weak self] entry in self?.onChoose?(entry) }

        empty.stringValue = Self.emptyMessage(filteredBy: query)
        empty.font = Tokens.TypeScale.sidebarRow
        empty.textColor = Tokens.Text.secondary
        empty.alignment = .center
        empty.lineBreakMode = .byWordWrapping
        empty.maximumNumberOfLines = 0
        empty.isHidden = true
        empty.translatesAutoresizingMaskIntoConstraints = false

        for view in [title, field, list, empty] { body.addSubview(view) }
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

            list.topAnchor.constraint(equalTo: body.topAnchor, constant: HistoryPanelMetrics.headerHeight),
            list.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: HistoryPanelMetrics.padding),
            list.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -HistoryPanelMetrics.padding),
            list.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -HistoryPanelMetrics.padding),

            empty.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: inset),
            empty.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -inset),
            empty.centerYAnchor.constraint(equalTo: body.centerYAnchor)
        ])

        body.setAccessibilityRole(.group)
        body.setAccessibilityLabel(String(localized: "History"))
        body.setAccessibilityElement(true)
    }

}
