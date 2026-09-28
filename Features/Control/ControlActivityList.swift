//
//  ControlActivityList.swift
//  Luna
//
//  Every call the agents have made since launch, newest first, as a pop-out
//  standing on the activity pill: the house shape of History and Downloads,
//  growing up out of the page's corner. Live while it is open.
//

import AppKit

@MainActor
final class ControlActivityController: PopoutController {

    private unowned let service: ControlService

    init(service: ControlService) {
        self.service = service
        super.init()
    }

    override func makePanel(in root: NSView) -> PopoutPanelView {
        ControlActivityPanel(frame: root.bounds)
    }

    override func panelDidAppear(_ panel: PopoutPanelView) {
        reload()
    }

    /// The pill stays while the list stands on it, so it may go now — once
    /// the list has folded back into it, not under it.
    override func panelDidDisappear() {
        Task { [weak service] in
            try? await Task.sleep(for: .seconds(Tokens.Motion.agentSheet.duration))
            service?.refreshSurface()
        }
    }

    func reload() {
        (presented as? ControlActivityPanel)?.setEntries(service.activity)
    }
}

@MainActor
final class ControlActivityPanel: PopoutPanelView {

    private let list = FlippedView()
    private let rows = NSStackView()
    private let scroll = NSScrollView()
    private let empty = NSTextField(labelWithString: String(localized: "Nothing yet."))

    init(frame frameRect: NSRect) {
        super.init(frame: frameRect, size: Tokens.Metric.historyPanel, edge: .above)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private(set) var shownEntries: [ControlActivity.Entry] = []

    func setEntries(_ entries: [ControlActivity.Entry]) {
        guard entries != shownEntries else { return }
        shownEntries = entries
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for entry in entries { rows.addArrangedSubview(ControlActivityRow(entry)) }
        empty.isHidden = !entries.isEmpty
        needsLayout = true
    }

    private func build() {
        let title = NSTextField(labelWithString: String(localized: "Activity"))
        title.font = Tokens.TypeScale.settingsHeading
        title.textColor = Tokens.Text.primary
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        rows.translatesAutoresizingMaskIntoConstraints = false
        list.addSubview(rows)
        list.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = list
        empty.font = Tokens.TypeScale.sidebarRow
        empty.textColor = Tokens.Text.secondary
        for view in [title, scroll, empty] {
            view.translatesAutoresizingMaskIntoConstraints = false
            body.addSubview(view)
        }
        let inset = PopoutMetrics.inset
        let padding = PopoutMetrics.padding
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: inset),
            title.centerYAnchor.constraint(equalTo: body.topAnchor, constant: PopoutMetrics.headerHeight / 2),
            scroll.topAnchor.constraint(equalTo: body.topAnchor, constant: PopoutMetrics.headerHeight),
            scroll.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: padding),
            scroll.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -padding),
            scroll.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -padding),
            list.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            rows.topAnchor.constraint(equalTo: list.topAnchor),
            rows.leadingAnchor.constraint(equalTo: list.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: list.trailingAnchor),
            rows.bottomAnchor.constraint(equalTo: list.bottomAnchor),
            empty.centerXAnchor.constraint(equalTo: body.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: body.centerYAnchor)
        ])
        body.setAccessibilityRole(.group)
        body.setAccessibilityLabel(String(localized: "Agent activity"))
        body.setAccessibilityElement(true)
    }
}

/// One call: what it did, and where, when and how it ended underneath. A
/// line to read, not a control — nothing here is clicked.
@MainActor
final class ControlActivityRow: NSView {

    let entry: ControlActivity.Entry

    init(_ entry: ControlActivity.Entry) {
        self.entry = entry
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let icon = NSImageView(image: NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = entry.state == .running
            ? Tokens.Agent.tint(forApp: entry.appID) : Tokens.Text.secondary
        let title = NSTextField(labelWithString: entry.title)
        title.font = Tokens.TypeScale.sidebarRow
        title.textColor = Tokens.Text.primary
        title.lineBreakMode = .byTruncatingTail
        let detail = NSTextField(labelWithString: Self.detail(of: entry))
        detail.font = Tokens.TypeScale.settingsCaption
        detail.textColor = Tokens.Text.tertiary
        detail.lineBreakMode = .byTruncatingTail
        let text = NSStackView(views: [title, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 0
        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Tokens.Metric.chromeGap
        row.edgeInsets = NSEdgeInsets(top: 0, left: PopoutMetrics.inset - PopoutMetrics.padding, bottom: 0, right: 0)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: Tokens.Metric.essentialsIcon),
            icon.heightAnchor.constraint(equalToConstant: Tokens.Metric.essentialsIcon),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: Tokens.Metric.rowHeight + Tokens.Metric.rowGap * 2)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("\(entry.title), \(Self.detail(of: entry))")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let superview else { return }
        widthAnchor.constraint(equalTo: superview.widthAnchor).isActive = true
    }

    /// Site, how it ended if not simply done, and when.
    static func detail(of entry: ControlActivity.Entry, now: Date = Date()) -> String {
        let state: String? = switch entry.state {
        case .running: String(localized: "Running…")
        case .done: nil
        case .failed: String(localized: "Failed")
        case .declined: String(localized: "Declined")
        case .stopped: String(localized: "Stopped")
        }
        let when = now.timeIntervalSince(entry.started) < 10
            ? String(localized: "now")
            : entry.started.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        return [entry.site, state, when].compactMap { $0 }.joined(separator: " · ")
    }
}
