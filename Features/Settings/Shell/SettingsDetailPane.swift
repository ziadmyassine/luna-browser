//
//  SettingsDetailPane.swift
//  Luna
//
//  §1's detail pane: opaque, not glass — a form is read, not looked
//  through. The same reasoning and the same token as the §3.6 content card,
//  `Tokens.Surface.base`.
//

import AppKit

@MainActor
final class SettingsDetailPane: NSView {

    /// §1's back/forward pair. It stands where the pane's title used to —
    /// see `SettingsNavCapsule` for why that is a trade worth making.
    let nav = SettingsNavCapsule()
    private let scroll = NSScrollView()
    private let content = FlippedView()
    private let empty = NSTextField(wrappingLabelWithString: "")
    private var hosted: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - The opaque plane

    override var wantsUpdateLayer: Bool { true }

    override var isOpaque: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Tokens.Surface.base.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: - Hosting a section

    /// Swaps in `view` on §5's `spaceSwitchCrossfade`. The new pane fades up
    /// from nothing rather than dissolving through the old one — two opaque
    /// forms cross-dissolving reads as a double image on text.
    func show(_ view: NSView, title: String, animated: Bool) {
        setAccessibilityLabel(title)
        hosted?.removeFromSuperview()
        hosted = view
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view)
        // The margins are inside the scroll view, not around it: the clip
        // view cuts at its own edge, and a control on the page's edge — a mode
        // card, New Space — swelling on a press was cut there. `build` moves
        // the scroll view out by the same amounts, so the page does not move.
        let inset = SettingsMetrics.paneInset
        let fit = view.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -inset)
        fit.priority = .defaultHigh
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),
            view.topAnchor.constraint(equalTo: content.topAnchor, constant: SettingsMetrics.paneSwellRoom),
            view.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -inset),
            fit
        ])
        guard animated else {
            content.alphaValue = 1
            return
        }
        content.alphaValue = 0
        Tokens.Motion.animate(Tokens.Motion.spaceSwitchCrossfade) { _ in
            self.content.animator().alphaValue = 1
        }
    }

    /// §5: rows that survive a search fade back in on `rowHover`, staggered by
    /// index and capped at 6 so a long section does not ripple. Core Animation
    /// rather than a timer — `beginTime` + `fillMode = .backwards` holds a row
    /// invisible until its turn with no dispatch hop per row.
    func staggerVisibleRows() {
        guard !Tokens.Motion.reduceMotion else { return }
        let spec = Tokens.Motion.rowHover
        let start = CACurrentMediaTime()
        for (index, row) in SettingsRowView.rows(in: content).enumerated() where !row.isHiddenOrHasHiddenAncestor {
            row.wantsLayer = true
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = spec.duration
            fade.timingFunction = spec.timingFunction
            fade.beginTime = start + Double(min(index, SettingsMetrics.searchStaggerCap)) * SettingsMetrics.searchStagger
            fade.fillMode = .backwards
            row.layer?.add(fade, forKey: "settingsSearchFade")
        }
    }

    /// §2's "the match highlighted", applied to whatever the hosted section
    /// built.
    func highlight(_ query: String) {
        for row in SettingsRowView.rows(in: content) { row.highlight(query) }
    }

    /// What the pane says when the search has hidden everything in it — §2 puts
    /// the other half of that answer in the list, and a blank form reads as a
    /// broken one.
    func setEmpty(_ message: String?) {
        empty.stringValue = message ?? ""
        empty.isHidden = message == nil
        scroll.isHidden = message != nil
    }

    // MARK: - Construction

    private func build() {
        nav.translatesAutoresizingMaskIntoConstraints = false

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = content
        content.translatesAutoresizingMaskIntoConstraints = false

        empty.font = Tokens.TypeScale.sidebarRow
        empty.textColor = Tokens.Text.secondary
        empty.alignment = .center
        empty.isHidden = true
        empty.translatesAutoresizingMaskIntoConstraints = false

        addSubview(nav)
        addSubview(scroll)
        addSubview(empty)

        let inset = SettingsMetrics.paneInset
        NSLayoutConstraint.activate([
            // Level with the traffic lights across the divider, so the two
            // halves of the window start on the same line.
            nav.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            nav.topAnchor.constraint(equalTo: topAnchor, constant: Tokens.Metric.trafficLightInset),

            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(
                equalTo: nav.bottomAnchor,
                constant: SettingsMetrics.groupGap - SettingsMetrics.paneSwellRoom
            ),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            content.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            content.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            empty.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: inset),
            empty.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -inset),
            empty.topAnchor.constraint(equalTo: scroll.topAnchor, constant: SettingsMetrics.paneSwellRoom + inset)
        ])
    }
}

/// AppKit scrolls from the bottom up unless the document view says otherwise,
/// and a settings form starts at the top.
@MainActor
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
