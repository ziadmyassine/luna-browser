//
//  DownloadsPanel.swift
//  Luna
//
//  §15.3's downloads list, as a pop-out from the downloads button —
//  §6.4's History surface, one size wider.
//
//  It used to be an `NSPanel`: a standard utility window with a table in it,
//  on the argument that §30.15 makes the completion popover the primary surface
//  and this the secondary one, so it could afford to behave like every other
//  Mac panel. On screen that argument does not survive contact. Pressing a
//  button in Liquid Glass chrome and being handed a grey titled window with a
//  row of push buttons is a different application answering; it takes focus off
//  the page, it has to be closed rather than glanced away from, and it is the
//  only surface in Luna that looks like it was built in 2012.
//
//  History had exactly this argument and came to the same place. The pop-out is
//  the house shape for "what have I already got": it stands on the control that
//  opened it, the page stays where it was, and a click anywhere else is done
//  with it.
//
//  `DownloadsPopover` — §5's completion toast, an `NSPanel` floating outside
//  the window with a tail pointing down into the button — is untouched and is
//  still a panel, because that one genuinely has to draw past the window's edge.
//

import AppKit

enum DownloadsPanelMetrics {
    static let size = Tokens.Metric.downloadsPanel
    static var headerHeight: CGFloat { PopoutMetrics.headerHeight }
    static var padding: CGFloat { PopoutMetrics.padding }
    static var inset: CGFloat { PopoutMetrics.inset }
}

@MainActor
final class DownloadsPanel: PopoutPanelView {

    var onOpen: ((DownloadItem) -> Void)?
    var onReveal: ((DownloadItem) -> Void)?
    var onRetry: ((DownloadItem) -> Void)?
    var onClear: (() -> Void)?

    private let list = DownloadsPanelListView()
    private let scroll = NSScrollView()
    private let empty = NSTextField(labelWithString: "")
    private let clear = NSButton()

    init(frame frameRect: NSRect, edge: PopoutEdge) {
        super.init(frame: frameRect, size: DownloadsPanelMetrics.size, edge: edge)
        buildBody()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Content

    func setItems(_ items: [DownloadItem]) {
        list.setItems(items)
        empty.isHidden = !items.isEmpty
        scroll.isHidden = items.isEmpty
        // Nothing finished or failed means nothing to clear; a live download is
        // not history (`DownloadManager.clearCompleted`).
        clear.isHidden = !items.contains { $0.state != .inProgress }
        needsLayout = true
    }

    // MARK: - Build

    private func buildBody() {
        let title = NSTextField(labelWithString: String(localized: "Downloads"))
        title.font = Tokens.TypeScale.settingsHeading
        title.textColor = Tokens.Text.primary
        title.translatesAutoresizingMaskIntoConstraints = false

        // A borderless text button rather than a bezelled one: a push button's
        // system bezel is the one piece of stock AppKit chrome that cannot be
        // made to sit on glass, which is half of what was wrong with the panel
        // this replaces.
        clear.isBordered = false
        clear.title = ""
        clear.attributedTitle = NSAttributedString(
            string: String(localized: "Clear"),
            attributes: [
                .font: Tokens.TypeScale.settingsCaption,
                .foregroundColor: Tokens.Text.secondary
            ]
        )
        clear.target = self
        clear.action = #selector(clearPressed)
        clear.setAccessibilityLabel(String(localized: "Clear finished downloads"))
        clear.translatesAutoresizingMaskIntoConstraints = false

        list.translatesAutoresizingMaskIntoConstraints = false
        list.onOpen = { [weak self] item in self?.onOpen?(item) }
        list.onReveal = { [weak self] item in self?.onReveal?(item) }
        list.onRetry = { [weak self] item in self?.onRetry?(item) }

        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        // Overlay, so the scroller does not take width off the rows.
        scroll.scrollerStyle = .overlay
        scroll.contentInsets = NSEdgeInsets(
            top: DownloadsPanelMetrics.padding,
            left: 0,
            bottom: DownloadsPanelMetrics.padding,
            right: 0
        )
        scroll.documentView = list
        scroll.translatesAutoresizingMaskIntoConstraints = false

        empty.stringValue = String(localized: "Nothing downloaded yet. Files you save show up here.")
        empty.font = Tokens.TypeScale.sidebarRow
        empty.textColor = Tokens.Text.secondary
        empty.alignment = .center
        empty.lineBreakMode = .byWordWrapping
        empty.maximumNumberOfLines = 0
        empty.isHidden = true
        empty.translatesAutoresizingMaskIntoConstraints = false

        for view in [title, clear, scroll, empty] { body.addSubview(view) }
        constrain(title: title)
    }

    /// The other half of `buildBody`, split only because the two together cross
    /// SwiftLint's 50-line function limit.
    private func constrain(title: NSTextField) {
        let inset = DownloadsPanelMetrics.inset
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: inset),
            title.centerYAnchor.constraint(
                equalTo: body.topAnchor,
                constant: DownloadsPanelMetrics.headerHeight / 2
            ),
            clear.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -inset),
            clear.centerYAnchor.constraint(equalTo: title.centerYAnchor),

            scroll.topAnchor.constraint(equalTo: body.topAnchor, constant: DownloadsPanelMetrics.headerHeight),
            scroll.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: DownloadsPanelMetrics.padding),
            scroll.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -DownloadsPanelMetrics.padding),
            scroll.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -DownloadsPanelMetrics.padding),
            list.widthAnchor.constraint(equalTo: scroll.widthAnchor),

            empty.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: inset),
            empty.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -inset),
            empty.centerYAnchor.constraint(equalTo: body.centerYAnchor)
        ])

        body.setAccessibilityRole(.group)
        body.setAccessibilityLabel(String(localized: "Downloads"))
        body.setAccessibilityElement(true)
    }

    @objc private func clearPressed() {
        onClear?()
    }

    // MARK: - Keyboard (§20.2)

    /// There is no filter field here to take the keystrokes, so the panel takes
    /// them itself. `esc` is `PopoutController`'s monitor and never reaches
    /// this.
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125: list.move(by: 1)
        case 126: list.move(by: -1)
        case 36, 76: list.activateSelection()
        default: super.keyDown(with: event)
        }
    }
}
