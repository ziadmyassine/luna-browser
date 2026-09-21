//
//  HistoryPanel.swift
//  Luna
//
//  §6.4's archive, as a pop-out from the §3.5 History button — the same
//  shape §3.2's site menu takes from the sliders glyph.
//
//  It used to be `luna://archive`, an internal page in a new tab. That is the
//  wrong shape for it twice over: looking something up in your history is a
//  glance, and a glance should not cost a tab you then have to close — and a
//  page cannot be Liquid Glass, so the one surface in the app that is about
//  the tabs looked like a website. The page still exists and the route still
//  works; this is what §3.5's History button opens.
//
//  And then it was the Command Bar's shell, which was the same mistake one
//  size smaller. Scrim, 640 pt body, centred over the page: a glance at a
//  shelf took the whole page away and put a window-sized panel where the user
//  was not looking. The Command Bar earns that — you summon it, and it is the
//  thing you are doing. History is opened from a button, and a surface opened
//  from a button belongs on it.
//
//  So: no scrim, a pop-out standing on the button, and the page still there
//  behind it. What is left of the overlay is a transparent sheet that catches
//  the click that dismisses it, which is exactly what an `NSMenu` puts up and
//  for the same reason.
//
//  The sheet, the glass body, the two clamps and the spring are
//  `PopoutPanelView`'s now — Downloads wanted the same surface, and the only
//  thing that differed was which way it grows out of its button. What is left
//  here is the header, the filter and the list.
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

/// §6.4's pop-out: a header with a filter, and the archive under it.
@MainActor
final class HistoryPanel: PopoutPanelView {

    /// The filter text changed.
    var onFilter: ((String) -> Void)?
    /// A row was chosen — the tab comes back where it was.
    var onChoose: ((UUID) -> Void)?
    /// An entry's icon, asked for at the moment the row is built. The panel
    /// holds no session of its own.
    var iconProvider: ((HistoryEntry) -> NSImage?)?

    let field = HistoryFilterField()

    private let list = HistoryListView()
    private let empty = NSTextField(labelWithString: "")
    /// What the filter holds, so the empty state can tell "nothing archived"
    /// apart from "nothing matched".
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
    /// this costs the dozen rows the panel is tall however long the archive is.
    /// It was not, once: see that file's header for the measurement.
    func setEntries(_ entries: [HistoryEntry]) {
        list.iconProvider = iconProvider
        list.setEntries(entries)
        empty.stringValue = Self.emptyMessage(filteredBy: query)
        empty.isHidden = !entries.isEmpty
        list.isHidden = entries.isEmpty
        needsLayout = true
    }

    /// **An empty shelf and an empty search are not the same sentence.** "Closed
    /// tabs show up here" is an answer to "why is this blank"; typed over a
    /// filter that matched nothing it answers a question nobody asked, and
    /// reads as if the archive had emptied itself.
    private static func emptyMessage(filteredBy query: String) -> String {
        query.isEmpty
            ? String(localized: "Nothing here yet. Closed tabs are kept for a while and show up here.")
            : String(localized: "No matches for “\(query)”.")
    }

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
        list.onActivate = { [weak self] entry in self?.onChoose?(entry.id) }

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
