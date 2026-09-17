//
//  SettingsDetailPane.swift
//  Luna
//
//  §1's detail pane: **opaque**, not glass. "A form is read, not looked
//  through" — the same reasoning that makes the §3.6 content card opaque, and
//  the same token: `Tokens.Surface.base`.
//
//  (§1 names the token `Tokens.Surface.card`. There is no such token; `base` is
//  what `ContentCardView` paints the content card with and is what §1 means.
//  Reported rather than added, because `Design/` is agent D's.)
//

import AppKit

@MainActor
final class SettingsDetailPane: NSView {

    private let header = NSTextField(labelWithString: "")
    private let rule = NSView()
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
        rule.layer?.backgroundColor = Tokens.Line.hairline.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: - Hosting a section

    /// Swaps in `view` on §5's `spaceSwitchCrossfade`.
    ///
    /// The new pane fades up from nothing rather than dissolving through the
    /// old one: two opaque forms cross-dissolving reads as a double image on
    /// text. Under Reduce Motion `Motion.animate` runs the same change at zero
    /// duration, so the pane still changes — it just does not fade (§5).
    func show(_ view: NSView, title: String, animated: Bool) {
        header.stringValue = title
        hosted?.removeFromSuperview()
        hosted = view
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            view.topAnchor.constraint(equalTo: content.topAnchor),
            view.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor)
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
    /// index and **capped at 6** so a long section does not ripple.
    ///
    /// Core Animation rather than a timer: `beginTime` + `fillMode = .backwards`
    /// holds a row invisible until its turn without a dispatch hop per row, and
    /// without handing a non-`Sendable` view to a `@Sendable` closure.
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
    /// built — the window does not need to know how it was assembled.
    func highlight(_ query: String) {
        for row in SettingsRowView.rows(in: content) { row.highlight(query) }
    }

    /// What the pane says when the search has hidden everything in it. §2 puts
    /// the "which sections still match" answer in the list; this is the other
    /// half, because a blank form reads as a broken one.
    func setEmpty(_ message: String?) {
        empty.stringValue = message ?? ""
        empty.isHidden = message == nil
        scroll.isHidden = message != nil
    }

    // MARK: - Construction

    private func build() {
        header.font = Tokens.TypeScale.sectionLabel
        header.textColor = Tokens.Text.secondary

        rule.wantsLayer = true
        rule.translatesAutoresizingMaskIntoConstraints = false

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

        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        addSubview(rule)
        addSubview(scroll)
        addSubview(empty)

        let inset = SettingsMetrics.paneInset
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            header.topAnchor.constraint(equalTo: topAnchor, constant: inset),

            rule.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            rule.topAnchor.constraint(equalTo: header.bottomAnchor, constant: SettingsMetrics.controlRowGap),
            rule.heightAnchor.constraint(equalToConstant: Tokens.Metric.hairline),

            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            scroll.topAnchor.constraint(equalTo: rule.bottomAnchor, constant: SettingsMetrics.controlRowGap),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),

            content.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            content.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            empty.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            empty.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            empty.topAnchor.constraint(equalTo: scroll.topAnchor, constant: inset)
        ])
    }
}

/// AppKit scrolls from the bottom up unless the document view says otherwise,
/// and a settings form starts at the top.
@MainActor
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
