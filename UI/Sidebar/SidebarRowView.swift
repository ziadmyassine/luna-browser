//
//  SidebarRowView.swift
//  Luna
//
//  One 38 pt row (§3.4): `[status dot] [favicon 16] [title 13 pt] [trailing]`.
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
//  Three spec deltas, all measured off `inspiration/main-tab-bar-and-ui.png`:
//
//  · §3.4's "favicon 12 pt from the pill's left edge, title 40 pt in" measures
//    17.5 / 45.5 — the favicon is square-inset inside the pill and the title
//    clears it by `rowIconGap`. The numbers live in `Metrics`, derived.
//  · §3.4's "single line, tail-truncated" is wrong: the reference **fades** an
//    over-long title out against the pill's trailing edge rather than spending
//    three characters on an `…`. That is what `titleClip` and `fade` are for —
//    the labels are laid out at their natural width inside a clipping box that
//    carries a gradient mask, so the last glyph dissolves instead of being cut.
//  · 13 pt, plain system font. See `Tokens.TypeScale.sidebarRow`.
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

    /// What a tab row draws when the site has no favicon and the user has chosen no icon
    /// of their own (§3.4a).
    static let siteFallbackSymbol = "globe"

    var title: String = ""
    /// Drawn when there is no favicon — and for the command rows' own glyphs.
    var symbolName: String = SidebarRowContent.siteFallbackSymbol
    var favicon: NSImage?
    /// §3.4: leads the row only for unread/updated content.
    var hasUnread: Bool = false
    var isLoading: Bool = false
    var trailing: Trailing = .none
}

@MainActor
final class SidebarRowView: NSView {

    static let reuseIdentifier = NSUserInterfaceItemIdentifier("dk.novapps.luna.sidebar.row")

    /// The trailing affordance was clicked, carrying **what it was drawing at
    /// the time**. The row cannot know whether that means close or mute — only
    /// the list does — but it is the one thing that knows which of the two the
    /// user actually pressed, so it is the one thing it reports.
    var onTrailing: ((SidebarRowContent.Trailing) -> Void)?

    var isSelected = false { didSet { refreshInk() } }
    var isHovered = false { didSet { refreshInk() } }

    private let icon = NSImageView()
    private let dot = NSView()
    /// Clips and fades both title layers. See the header.
    private let titleClip = NSView()
    private let title = NSTextField(labelWithString: "")
    /// The bright copy the §3.4 shimmer sweeps across. Hidden unless loading.
    private let shimmer = NSTextField(labelWithString: "")
    private let shimmerMask = CAGradientLayer()
    private let fadeMask = CAGradientLayer()
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
        trailing.chromed = true
        for label in [title, shimmer] {
            label.font = Tokens.TypeScale.sidebarRow
            // Clipping, not truncating: the fade below is what ends an
            // over-long title, and an ellipsis would be drawn *before* it.
            label.lineBreakMode = .byClipping
            label.cell?.usesSingleLineMode = true
            titleClip.addSubview(label)
        }
        titleClip.wantsLayer = true
        titleClip.layer?.masksToBounds = true
        shimmer.wantsLayer = true
        // **Hidden from the start, not from the first load.** `updateShimmer`
        // is what shows and hides this, and `configure` only calls it when
        // `isLoading` *changes* — which is right for a recycled view, whose
        // `content` describes the shimmer it is currently wearing, and wrong
        // for a new one, which starts with `isLoading` false and an
        // `NSTextField` that is visible by default. So a row built for a tab
        // that never loads kept a full-strength copy of its own title sitting
        // on top of the dimmer one, and the list came out in two inks with no
        // pattern to them: which rows were bright depended on which came out
        // of the reuse pool having once carried a load.
        shimmer.isHidden = true
        shimmerMask.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerMask.endPoint = CGPoint(x: 1, y: 0.5)
        fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        trailing.onActivate = { [weak self] in
            guard let self else { return }
            onTrailing?(content.trailing)
        }

        for view in [icon, dot, titleClip, trailing] { addSubview(view) }
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
                label: muted ? "Unmute tab" : "Mute tab",
                pointSize: Tokens.Metric.rowTrailingGlyph
            )
        case .close:
            trailing.isHidden = false
            trailing.configure(
                symbolName: "xmark",
                label: "Close Tab",
                pointSize: Tokens.Metric.rowTrailingGlyph
            )
        }
    }

    // MARK: - Ink

    /// §3.4's title ink.
    ///
    /// **The selected row is the only bright title in the list**, and hover is
    /// not an input here — which is the point of the signature. The hover used
    /// to promote the ink too, on the grounds that there was no translucent
    /// hover fill to lift instead; there is one now, `hoverPill`, so the reason
    /// has outlived itself. Two bright rows at once is one too many: the list
    /// answers "which tab am I on" by having exactly one title brighter than
    /// the rest, and a pointer resting anywhere must not add a second.
    ///
    /// Colour is only half of it: a title can also dim by being re-laid, and
    /// ``titleColumn`` is where that half is held.
    ///
    /// Pure, so the rule can be asserted without a window to hover in.
    static func titleInk(isSelected: Bool, isLoading: Bool) -> NSColor {
        if isLoading { return Tokens.Text.tertiary }
        return isSelected ? Tokens.Text.primary : Tokens.Text.secondary
    }

    private func refreshInk() {
        title.textColor = Self.titleInk(isSelected: isSelected, isLoading: content.isLoading)
        shimmer.textColor = Tokens.Text.primary
        // **Ink, not accent.** Luna's chrome carries no system blue: the unread
        // mark is a full-strength dot in the same ink the title is set in, and
        // it reads because it is bright, not because it is a different hue.
        dot.layer?.backgroundColor = Tokens.Text.primary.cgColor
        icon.contentTintColor = content.favicon != nil ? nil : Tokens.Text.secondary
        // The trailing glyph keeps the hover, because it *is* the hover: the
        // close chip is only reachable on the row the pointer is on, and it
        // has to be legible while it is being aimed at.
        trailing.tint = isSelected || isHovered ? Tokens.Text.primary : Tokens.Text.secondary
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
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately { placeContents() }
    }

    /// §3.4's title column: where the title starts, and how wide it may be.
    ///
    /// **The trailing slot is reserved on every row, drawn in or not.** The
    /// column used to take the slot back whenever the row had no glyph in it,
    /// which meant it grew and shrank as the pointer moved: the close chip is
    /// revealed on hover, the title gives up 26 pt, and a title long enough to
    /// need §3.4's trailing fade starts dissolving 26 pt earlier than it did a
    /// frame ago. That reads as the title dimming under the pointer — the one
    /// thing ``titleInk`` exists to prevent, reached through geometry rather
    /// than through colour, which is why taking hover out of the ink rule did
    /// not settle it. Reserving the slot costs every row those 26 pt and buys
    /// a column that does not move.
    ///
    /// Pure, like ``titleInk``, and taking no hover for the same reason: the
    /// rule is in the signature, so it cannot quietly grow one back.
    static func titleColumn(inRowOfWidth width: CGFloat, hasUnread: Bool) -> (x: CGFloat, width: CGFloat) {
        let x = Tokens.Metric.rowTitleInset
            + (hasUnread ? Tokens.Metric.spaceDot + Tokens.Metric.rowInset : 0)
        // Half an inset before the slot, not the full `chromeGap` two controls
        // would take between them. The title's last glyphs are already
        // dissolving by the time they reach here — `rowTitleFade` is the gap,
        // and 8 pt of clearance on top of it is 8 pt of pill left empty.
        let right = trailingSlotX(inRowOfWidth: width) - Tokens.Metric.rowInset / 2
        return (x, max(right - x, 0))
    }

    /// Where the trailing glyph's slot begins, occupied or not. See
    /// ``titleColumn``.
    static func trailingSlotX(inRowOfWidth width: CGFloat) -> CGFloat {
        width - 2 * Tokens.Metric.rowInset - Tokens.Metric.rowTrailingChip.width
    }

    private func placeContents() {
        let glyph = Tokens.Metric.faviconSize
        icon.frame = NSRect(
            x: Tokens.Metric.rowFaviconInset,
            y: (bounds.height - glyph) / 2,
            width: glyph,
            height: glyph
        ).pixelAligned

        let dotSize = Tokens.Metric.spaceDot
        dot.frame = NSRect(
            x: Tokens.Metric.rowTitleInset,
            y: (bounds.height - dotSize) / 2,
            width: dotSize,
            height: dotSize
        ).pixelAligned

        // **Inset from the pill, not from the row.** The pill is already
        // `rowInset` inside the row, so one inset put the chip flush against
        // the pill's edge; the reference keeps a full inset inside it.
        let chip = Tokens.Metric.rowTrailingChip
        trailing.frame = NSRect(
            x: Self.trailingSlotX(inRowOfWidth: bounds.width),
            y: (bounds.height - chip.height) / 2,
            width: chip.width,
            height: chip.height
        ).pixelAligned

        // The pill is `rowInset` inside the row, and the title keeps that same
        // inset inside the pill — so it ends two insets short of the row, less
        // the trailing slot, which `titleColumn` reserves whether or not this
        // row is currently drawing anything in it.
        let column = Self.titleColumn(inRowOfWidth: bounds.width, hasUnread: content.hasUnread)
        let height = title.intrinsicContentSize.height
        let box = NSRect(
            x: column.x,
            y: (bounds.height - height) / 2,
            width: column.width,
            height: height
        ).integral
        titleClip.frame = box

        // Laid out at their *natural* width so nothing truncates; the clip box
        // and `fade` are what end the line.
        let natural = ceil(title.intrinsicContentSize.width)
        let inner = NSRect(x: 0, y: 0, width: max(natural, box.width), height: box.height)
        title.frame = inner
        shimmer.frame = inner
        // Standalone `CALayer`s animate their own frame changes implicitly, and
        // a scroll re-lays every visible row.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shimmerMask.frame = shimmer.bounds
        applyFade(overflowing: natural > box.width, width: box.width)
        CATransaction.commit()
    }

    /// §3.4's fade. Nil mask when the title fits: a gradient that is opaque
    /// end to end still costs a masked composite on every row of every scroll.
    private func applyFade(overflowing: Bool, width: CGFloat) {
        guard overflowing, width > Tokens.Metric.rowTitleFade else {
            titleClip.layer?.mask = nil
            return
        }
        let ink = Tokens.Text.primary
        fadeMask.frame = titleClip.bounds
        fadeMask.colors = [ink.cgColor, ink.cgColor, ink.withAlphaComponent(0).cgColor]
        fadeMask.locations = [0, NSNumber(value: Double(1 - Tokens.Metric.rowTitleFade / width)), 1]
        titleClip.layer?.mask = fadeMask
    }
}
