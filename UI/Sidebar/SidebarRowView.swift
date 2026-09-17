//
//  SidebarRowView.swift
//  Luna
//
//  One 40 pt row (§3.4): `[status dot] [favicon 18] [title 15 pt] [trailing]`.
//  `Archive` and `+ Add Tab` are the same view with a symbol instead of a
//  favicon — §30.6 says they are first-class rows with identical metrics, so
//  they are literally the same class.
//
//  **No background is drawn here.** Unselected rows have none (§30.7), and the
//  selected pill and the hover fill are two single glass views that the list
//  moves between rows — see `TabListController`. That is what keeps a 40-row
//  scroll at 120 fps: a reused row view owns four subviews, lays them out with
//  arithmetic instead of constraints, and never allocates a glass effect.
//
//  Two spec deltas, both measured off `inspiration/main-tab-bar-and-ui.png`:
//  §3.4's "favicon 12 pt from the pill's left edge" would leave a 2 pt gap to a
//  title starting 40 pt in; the reference measures ~15 pt and ~41 pt, which is
//  the favicon centred in a `rowHeight`-wide leading zone. And Luna has no
//  intra-row gap token, so `rowInset` is used as the row's single spacing unit.
//

import AppKit

/// Everything a row draws. A value type, so `configure` can no-op when nothing
/// changed — which is most of what a scroll does.
struct SidebarRowContent: Equatable {

    enum Trailing: Equatable {
        case none
        /// §3.4: click-to-mute.
        case audio(muted: Bool)
        /// Revealed on hover (§3.4).
        case close
    }

    var title: String = ""
    /// Drawn when there is no favicon — and for the command rows' own glyphs.
    var symbolName: String = "globe"
    var favicon: NSImage?
    var tintsSymbolWithAccent: Bool = false
    /// §3.4: leads the row only for unread/updated content.
    var hasUnread: Bool = false
    var isLoading: Bool = false
    var trailing: Trailing = .none
}

@MainActor
final class SidebarRowView: NSView {

    static let reuseIdentifier = NSUserInterfaceItemIdentifier("dk.novapps.luna.sidebar.row")

    /// The trailing affordance was clicked — mute, or close/archive.
    var onTrailing: (() -> Void)?

    var isSelected = false { didSet { refreshInk() } }
    var isHovered = false { didSet { refreshInk() } }

    private let icon = NSImageView()
    private let dot = NSView()
    private let title = NSTextField(labelWithString: "")
    /// The bright copy the §3.4 shimmer sweeps across. Hidden unless loading.
    private let shimmer = NSTextField(labelWithString: "")
    private let shimmerMask = CAGradientLayer()
    private let trailing = RowGlyphView()
    private var content = SidebarRowContent()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseIdentifier
        wantsLayer = true

        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: Tokens.Metric.faviconSize,
            weight: .regular
        )
        dot.wantsLayer = true
        dot.layer?.cornerRadius = Tokens.Metric.spaceDot / 2
        for label in [title, shimmer] {
            label.font = Tokens.TypeScale.sidebarRow
            label.lineBreakMode = .byTruncatingTail
            label.cell?.usesSingleLineMode = true
        }
        shimmer.wantsLayer = true
        shimmerMask.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerMask.endPoint = CGPoint(x: 1, y: 0.5)
        trailing.onActivate = { [weak self] in self?.onTrailing?() }

        for view in [icon, dot, title, shimmer, trailing] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.cell)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Content

    func configure(_ next: SidebarRowContent) {
        guard next != content else { return }
        let wasLoading = content.isLoading
        content = next
        title.stringValue = next.title
        shimmer.stringValue = next.title
        icon.image = next.favicon
            ?? NSImage(systemSymbolName: next.symbolName, accessibilityDescription: nil)
        icon.image?.isTemplate = next.favicon == nil
        dot.isHidden = !next.hasUnread
        setAccessibilityLabel(next.title)
        applyTrailing(next.trailing)
        refreshInk()
        if next.isLoading != wasLoading { updateShimmer() }
        needsLayout = true
    }

    private func applyTrailing(_ state: SidebarRowContent.Trailing) {
        switch state {
        case .none:
            trailing.isHidden = true
        case let .audio(muted):
            trailing.isHidden = false
            trailing.configure(
                symbolName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                label: muted ? "Unmute tab" : "Mute tab"
            )
        case .close:
            trailing.isHidden = false
            trailing.configure(symbolName: "xmark", label: "Archive tab")
        }
    }

    // MARK: - Ink

    private func refreshInk() {
        // §3.4: the selected row has brighter text; hover promotes it the same
        // way, because Luna has no translucent hover-fill token to lift instead.
        let bright = isSelected || isHovered
        title.textColor = content.isLoading
            ? Tokens.Text.tertiary
            : (bright ? Tokens.Text.primary : Tokens.Text.secondary)
        shimmer.textColor = Tokens.Text.primary
        dot.layer?.backgroundColor = Tokens.Accent.tint.cgColor
        icon.contentTintColor = content.favicon != nil
            ? nil
            : (content.tintsSymbolWithAccent ? Tokens.Accent.tint : Tokens.Text.secondary)
        trailing.tint = bright ? Tokens.Text.primary : Tokens.Text.secondary
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshInk()
    }

    /// §21.2: Increase Contrast is not an appearance, so the list re-runs this
    /// on `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`.
    func accessibilityDisplayOptionsChanged() {
        refreshInk()
        updateShimmer()
    }

    // MARK: - Shimmer (§3.4 — a sweep across the title, never a spinner)

    private func updateShimmer() {
        shimmer.layer?.removeAnimation(forKey: "shimmer")
        // §21.2: Reduce Motion degrades this to a dimmed title and nothing else.
        guard content.isLoading, !Tokens.Motion.reduceMotion else {
            shimmer.isHidden = true
            shimmer.layer?.mask = nil
            return
        }
        shimmer.isHidden = false
        // A mask reads alpha only, so the token's *value* is irrelevant here —
        // what matters is that no literal colour is spelled out (contract rule 2).
        let opaque = Tokens.Text.primary
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shimmerMask.frame = shimmer.bounds
        shimmerMask.colors = [
            opaque.withAlphaComponent(0).cgColor,
            opaque.cgColor,
            opaque.withAlphaComponent(0).cgColor
        ]
        CATransaction.commit()
        shimmer.layer?.mask = shimmerMask
        let sweep = CABasicAnimation(keyPath: "locations")
        sweep.fromValue = [-0.6, -0.3, 0]
        sweep.toValue = [1, 1.3, 1.6]
        // No shimmer token exists in §6; the particle sweep is the nearest
        // published duration. See the report: `Tokens.Motion.rowShimmer`.
        sweep.duration = Tokens.Motion.downloadsParticleSweep.duration
        sweep.repeatCount = .infinity
        shimmerMask.add(sweep, forKey: "shimmer")
    }

    /// Everything but the trailing glyph belongs to the row: an `NSTextField`
    /// under the pointer would otherwise swallow the click that selects it, and
    /// the row itself has no `mouseDown`, so the event reaches the table.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        return (!trailing.isHidden && trailing.frame.contains(local)) ? trailing : self
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let inset = Tokens.Metric.rowInset
        let glyph = Tokens.Metric.faviconSize
        let iconX = inset + (Tokens.Metric.rowHeight - inset - glyph) / 2
        icon.frame = NSRect(x: iconX, y: (bounds.height - glyph) / 2, width: glyph, height: glyph).integral

        let dotSize = Tokens.Metric.spaceDot
        dot.frame = NSRect(
            x: Tokens.Metric.rowHeight,
            y: (bounds.height - dotSize) / 2,
            width: dotSize,
            height: dotSize
        ).integral

        trailing.frame = NSRect(
            x: bounds.maxX - inset - glyph,
            y: (bounds.height - glyph) / 2,
            width: glyph,
            height: glyph
        ).integral

        let titleX = Tokens.Metric.rowHeight + (content.hasUnread ? dotSize + inset : 0)
        let titleRight = trailing.isHidden ? bounds.maxX - inset : trailing.frame.minX - inset
        let height = title.intrinsicContentSize.height
        let box = NSRect(
            x: titleX,
            y: (bounds.height - height) / 2,
            width: max(titleRight - titleX, 0),
            height: height
        ).integral
        title.frame = box
        shimmer.frame = box
        // A standalone `CALayer` animates its own frame changes implicitly, and
        // a scroll re-lays every visible row.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shimmerMask.frame = shimmer.bounds
        CATransaction.commit()
    }
}

/// The row's trailing glyph: a button with no chrome of its own, because §3.4
/// gives it none. Its own accessibility element so VoiceOver can reach mute and
/// archive without a mouse (§21.1).
@MainActor
final class RowGlyphView: NSImageView {

    var onActivate: (() -> Void)?
    var tint: NSColor = Tokens.Text.secondary { didSet { contentTintColor = tint } }

    func configure(symbolName: String, label: String) {
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: Tokens.Metric.faviconSize,
            weight: .regular
        )
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
    }

    override func mouseDown(with event: NSEvent) {
        // Swallowed so the row does not also treat this as a selection click.
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onActivate?()
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }
}
