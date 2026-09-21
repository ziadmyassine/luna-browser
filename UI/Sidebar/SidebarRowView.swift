//
//  SidebarRowView.swift
//  Luna
//
//  One 38 pt row (§3.4): `[status dot] [favicon 16] [title 13 pt] [trailing]`.
//  `Archive` and `+ Add Tab` are the same view with a symbol instead of a
//  favicon — §30.6 says they are first-class rows with identical metrics, so
//  they are literally the same class.
//
//  No background is drawn here. Unselected rows have none (§30.7), and the
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
//  · §3.4's "single line, tail-truncated" is wrong: the reference fades an
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
    /// How far this row's contents step in — `Metric.groupIndent` for a tab
    /// inside a §3.4b group, zero for everything else. The spine is drawn in the
    /// space it opens.
    var indent: CGFloat = 0
    /// A §3.4b group header's chevron, and which way it points. Nil on every row
    /// that is not a group.
    var disclosure: Disclosure?
    /// §3.4b: a saved row whose page has been closed once. It is still a place
    /// the user kept, so it is dimmed rather than greyed out — the next press
    /// lets it go.
    var isDormant: Bool = false

    /// Whether a group is folded shut, on the row that folds it.
    enum Disclosure: Equatable { case expanded, collapsed }
}

@MainActor
final class SidebarRowView: NSView {

    static let reuseIdentifier = NSUserInterfaceItemIdentifier("dk.novapps.luna.sidebar.row")

    /// The trailing affordance was clicked, carrying what it was drawing at
    /// the time. The row cannot know whether that means close or mute — only
    /// the list does — but it is the one thing that knows which of the two the
    /// user actually pressed, so it is the one thing it reports.
    var onTrailing: ((SidebarRowContent.Trailing) -> Void)?

    /// The §3.4b chevron was pressed — fold this group, or open it.
    var onDisclosure: (() -> Void)?

    /// A §3.4b folder's name was typed and confirmed. Not called for Escape,
    /// and not called for a name that is only whitespace: both mean the folder
    /// keeps the name it had.
    var onRename: ((String) -> Void)?

    var isSelected = false { didSet { refreshInk() } }
    var isHovered = false { didSet { refreshInk() } }
    /// §6.6: a lift is aimed inside this §3.4b group. The one feedback a folded
    /// group can give — there are no rows in it to open a gap between — so the
    /// header itself is outlined at the pill's own shape.
    var isDropTarget = false { didSet { applyDropTarget() } }

    private let icon = NSImageView()
    // §3.4b's three. Internal rather than private only because Swift's
    // `private` is file-scoped and `SidebarRowView+Group.swift` is the other
    // half of this class; nothing outside that pair touches them.
    /// §3.4b's fold control. Its own glyph button, so it answers a hover and a
    /// press like every other one (`RowGlyphView`).
    let chevron = RowGlyphView()
    /// The hairline down the leading edge of a group's tabs.
    let spine = NSView()
    /// The outline `isDropTarget` draws. Its own view for `spine`'s reason: this
    /// class allocates no glass and overrides no `draw`, so a border is a layer.
    let outline = NSView()
    private let dot = NSView()
    /// Clips and fades both title layers. See the header.
    private let titleClip = NSView()
    private let title = NSTextField(labelWithString: "")
    /// The bright copy the §3.4 shimmer sweeps across. Hidden unless loading.
    private let shimmer = NSTextField(labelWithString: "")
    private let shimmerMask = CAGradientLayer()
    private let fadeMask = CAGradientLayer()
    private let trailing = RowGlyphView()
    /// §3.4b's rename, typed on the row itself. Hidden until it is asked for —
    /// see `SidebarRowView+Rename.swift`, which is the rest of it.
    let editor = NSTextField()
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
            // Clipping, not truncating: the fade below is what ends an
            // over-long title, and an ellipsis would be drawn before it.
            label.lineBreakMode = .byClipping
            label.cell?.usesSingleLineMode = true
            titleClip.addSubview(label)
        }
        titleClip.wantsLayer = true
        titleClip.layer?.masksToBounds = true
        shimmer.wantsLayer = true
        // Hidden from the start, not from the first load. `updateShimmer`
        // is what shows and hides this, and `configure` only calls it when
        // `isLoading` changes — which is right for a recycled view, whose
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
        chevron.onActivate = { [weak self] in self?.onDisclosure?() }
        chevron.isHidden = true
        spine.wantsLayer = true
        spine.isHidden = true
        outline.wantsLayer = true
        outline.isHidden = true
        outline.layer?.borderWidth = Tokens.Metric.hairline
        outline.layer?.cornerRadius = Tokens.Metric.rowCornerRadius
        outline.layer?.cornerCurve = .continuous

        prepareEditor()
        for view in [outline, spine, icon, dot, titleClip, chevron, trailing, editor] { addSubview(view) }
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
        applyDisclosure(next.disclosure)
        spine.isHidden = next.indent == 0
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
    /// The selected row is the only bright title in the list, and hover is not
    /// an input here — which is the point of the signature. Hover used to
    /// promote the ink too, because there was no translucent fill to lift
    /// instead; `hoverPill` is that fill. The list answers "which tab am I on"
    /// by having exactly one title brighter than the rest, and a pointer
    /// resting anywhere must not add a second.
    ///
    /// Colour is only half of it: a title also dims by being re-laid, which
    /// is ``titleColumn``'s half and is deliberately not held still.
    ///
    /// Pure, so the rule can be asserted without a window to hover in.
    private func refreshInk() {
        title.textColor = Self.titleInk(
            isSelected: isSelected,
            isLoading: content.isLoading,
            isDormant: content.isDormant
        )
        shimmer.textColor = Tokens.Text.primary
        icon.alphaValue = content.isDormant ? Tokens.Metric.dormantIconOpacity : 1
        chevron.tint = isSelected || isHovered ? Tokens.Text.primary : Tokens.Text.secondary
        spine.layer?.backgroundColor = Tokens.Line.hairline.cgColor
        outline.layer?.borderColor = Tokens.Line.border.cgColor
        // Ink, not accent. Luna's chrome carries no system blue: the unread
        // mark is a full-strength dot in the same ink the title is set in, and
        // it reads because it is bright, not because it is a different hue.
        dot.layer?.backgroundColor = Tokens.Text.primary.cgColor
        icon.contentTintColor = content.favicon != nil ? nil : Tokens.Text.secondary
        // The trailing glyph keeps the hover, because it is the hover: the
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
        // A mask reads alpha only, so the token's value is irrelevant here —
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
        sweep.duration = Tokens.Motion.rowShimmer.duration
        sweep.repeatCount = .infinity
        shimmerMask.add(sweep, forKey: "shimmer")
    }

    /// Everything but the trailing glyph belongs to the row: an `NSTextField`
    /// under the pointer would otherwise swallow the click that selects it, and
    /// the row itself has no `mouseDown`, so the event reaches the table.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        // The field first, and the whole row while it is up: a press anywhere
        // on a row being renamed belongs to the text, not to the list. Clicking
        // past the end of a short name to put the caret there is the gesture
        // every rename in every list has.
        if !editor.isHidden { return editor }
        if !trailing.isHidden, trailing.frame.contains(local) { return trailing }
        if !chevron.isHidden, chevron.frame.contains(local) { return chevron }
        return self
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately { placeContents() }
    }

    func placeGroupFurniture() {
        outline.frame = bounds
            .insetBy(dx: Tokens.Metric.rowInset, dy: Tokens.Metric.rowPillInset)
            .pixelAligned
        spine.frame = NSRect(
            x: Tokens.Metric.rowInset + Tokens.Metric.groupSpineInset,
            y: 0,
            width: Tokens.Metric.hairline,
            height: bounds.height
        ).pixelAligned
    }

    private func placeContents() {
        placeGroupFurniture()
        // §3.4b: a folder's header stands at the column's own left edge and its
        // tabs step in by `groupIndent`, so the indent alone says what is inside
        // it. The chevron follows the name instead of leading the row — see
        // `placeChevron`.
        let indent = content.indent
        let glyph = Tokens.Metric.faviconSize
        icon.frame = NSRect(
            x: Tokens.Metric.rowFaviconInset + indent,
            y: (bounds.height - glyph) / 2,
            width: glyph,
            height: glyph
        ).pixelAligned

        let dotSize = Tokens.Metric.spaceDot
        dot.frame = NSRect(
            x: Tokens.Metric.rowTitleInset + indent,
            y: (bounds.height - dotSize) / 2,
            width: dotSize,
            height: dotSize
        ).pixelAligned

        // Inset from the pill, not from the row. The pill is already
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
        // inset inside the pill — so it ends two insets short of the row,
        // less the trailing slot on the rows that are drawing one.
        let column = Self.titleColumn(
            inRowOfWidth: bounds.width,
            hasUnread: content.hasUnread,
            slotOccupied: !trailing.isHidden,
            indent: indent
        )
        let height = title.intrinsicContentSize.height
        let box = NSRect(
            x: column.x,
            y: (bounds.height - height) / 2,
            width: column.width - chevronReserve,
            height: height
        ).integral
        titleClip.frame = box
        placeEditor(startingAt: box.minX, reserving: chevronReserve)

        // Laid out at their natural width so nothing truncates; the clip box
        // and `fade` are what end the line.
        let natural = ceil(title.intrinsicContentSize.width)
        placeChevron(afterTitleEnding: box.minX + min(natural, box.width))
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

    /// What the title gives back to the chevron standing after it. Nothing on a
    /// row without one, and the slot plus its gap on a folder's header.
    private var chevronReserve: CGFloat {
        content.disclosure == nil ? 0 : Tokens.Metric.groupChevronSlot.width + Tokens.Metric.rowTitleGap
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
