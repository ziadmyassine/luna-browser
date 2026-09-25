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
    /// inside a §3.4b group, zero for everything else.
    var indent: CGFloat = 0
    /// How much sooner this row's pill ends on the trailing side —
    /// `Metric.groupMemberTrailingInset` for a tab inside a §3.4b group, zero
    /// for everything else. Its glyphs and title end that much sooner with it.
    var trailingInset: CGFloat = 0
    /// A §3.4b group header's chevron, and which way it points. Nil on every row
    /// that is not a group.
    var disclosure: Disclosure?
    /// §3.4b: a saved row whose page has been closed once. It is still a place
    /// the user kept, so it is dimmed rather than greyed out — the next press
    /// lets it go.
    var isDormant: Bool = false
    /// §4's selected tab: §3.2's site settings glyph, in the slot before the
    /// trailing one. The column's rows never draw it — its URL pill has the
    /// same glyph a row's height above.
    var siteSettings: Bool = false

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

    /// A §3.4b folder's name was typed and confirmed. Not called for Escape,
    /// and not called for a name that is only whitespace: both mean the folder
    /// keeps the name it had.
    var onRename: ((String) -> Void)?

    /// The site settings glyph was pressed, handing up the glyph for the
    /// pop-out to stand on.
    var onSiteSettings: ((NSView) -> Void)?

    var isSelected = false { didSet { refreshInk() } }
    var isHovered = false { didSet { refreshInk() } }
    private let icon = NSImageView()
    // §3.4b's three. Internal rather than private only because Swift's
    // `private` is file-scoped and `SidebarRowView+Group.swift` is the other
    // half of this class; nothing outside that pair touches them.
    /// §3.4b's fold mark. Not a button: the whole header folds, and a 16 pt
    /// glyph sitting inside the thing it is about, lighting its own chip and
    /// swelling under its own press, read as a second target on a row that has
    /// only one. It is a plain `NSImageView` so that it cannot take a press,
    /// cannot take a hover, and is not in the hit test at all.
    let chevron = NSImageView()
    private let dot = NSView()
    /// Clips and fades both title layers. See the header.
    let titleClip = NSView()
    private let title = NSTextField(labelWithString: "")
    /// The bright copy the §3.4 shimmer sweeps across. Hidden unless loading.
    private let shimmer = NSTextField(labelWithString: "")
    private let shimmerMask = CAGradientLayer()
    let fadeMask = CAGradientLayer()
    // Internal, not private, for `SidebarRowGeometry.swift`, which places them.
    let trailing = RowGlyphView()
    let siteButton = RowGlyphView()
    /// §3.4b's rename, typed on the row itself. Hidden until it is asked for —
    /// see `SidebarRowView+Rename.swift`, which is the rest of it.
    let editor = NSTextField()
    var onPickEmoji: ((String) -> Void)?
    /// Which question the field is asking: the row's name, or §3.4b's icon.
    /// The same field does both, standing over the title for one and over the
    /// icon for the other — see `SidebarRowView+Rename.swift`.
    var isPickingEmoji = false
    private var content = SidebarRowContent()

    /// The width the row's geometry is measured across: the row, less what
    /// its pill gives up at the trailing end (`SidebarRowContent.trailingInset`).
    var contentWidth: CGFloat { bounds.width - content.trailingInset }

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
        siteButton.configure(
            symbolName: SiteMenu.Glyph.advanced,
            label: String(localized: "Site Settings"),
            pointSize: Tokens.Metric.rowTrailingGlyph
        )
        siteButton.isHidden = true
        siteButton.onActivate = { [weak self] in
            guard let self else { return }
            onSiteSettings?(siteButton)
        }
        chevron.isHidden = true
        // The header is the control and carries the label; a second element
        // announcing the same fold is one more stop for no more reach.
        chevron.setAccessibilityElement(false)

        prepareEditor()
        for view in [icon, dot, titleClip, chevron, siteButton, trailing, editor] { addSubview(view) }
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
        // §3.4b: a folder's glyph is either an SF Symbol's name or an emoji,
        // and an emoji is never a template — see `RowEmoji`.
        let slot = Self.iconSlot(for: next)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: slot, weight: .regular)
        let emoji = RowEmoji.image(next.symbolName, pointSize: slot)
        icon.image = next.favicon
            ?? emoji
            ?? NSImage(systemSymbolName: next.symbolName, accessibilityDescription: nil)
        icon.image?.isTemplate = next.favicon == nil && emoji == nil
        dot.isHidden = !next.hasUnread
        setAccessibilityLabel(next.title)
        applyDisclosure(next.disclosure)
        applyGlyphs()
        refreshInk()
        if next.isLoading != wasLoading { updateShimmer() }
        needsLayout = true
    }

    /// The two trailing glyphs, as the content asks for them — and neither
    /// while the name is being typed. The field runs out to the pill's inner
    /// edge, which is where they stand, so left up they sat on the name.
    func applyGlyphs() {
        applyTrailing(content.trailing)
        siteButton.isHidden = !content.siteSettings
        guard isRenaming else { return }
        trailing.isHidden = true
        siteButton.isHidden = true
    }

    /// The name field is up, over the title. The emoji field stands in the
    /// icon's slot instead and takes nothing from the glyphs.
    var isRenaming: Bool { !editor.isHidden && !isPickingEmoji }

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
        // Not the hover, as a title is not: the chevron is only on a §3.4b
        // header, and the pill or the folder's plate answers the pointer for it.
        chevron.contentTintColor = isSelected ? Tokens.Text.primary : Tokens.Text.secondary
        // Ink, not accent. Luna's chrome carries no system blue: the unread
        // mark is a full-strength dot in the same ink the title is set in, and
        // it reads because it is bright, not because it is a different hue.
        dot.layer?.backgroundColor = Tokens.Text.primary.cgColor
        icon.contentTintColor = content.favicon != nil ? nil : Tokens.Text.secondary
        // The trailing glyph keeps the hover, because it is the hover: the
        // close chip is only reachable on the row the pointer is on, and it
        // has to be legible while it is being aimed at.
        trailing.tint = isSelected || isHovered ? Tokens.Text.primary : Tokens.Text.secondary
        siteButton.tint = trailing.tint
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
        if !siteButton.isHidden, siteButton.frame.contains(local) { return siteButton }
        return self
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately { placeContents() }
    }

    private func placeContents() {
        // §3.4b: a folder's header stands at the column's own left edge and its
        // tabs step in by `groupIndent`, so the indent alone says what is inside
        // it. The chevron follows the name instead of leading the row — see
        // `placeChevron`.
        let indent = content.indent
        let glyph = Self.iconSlot(for: content)
        icon.frame = NSRect(
            x: Tokens.Metric.rowFaviconInset + indent - (glyph - Tokens.Metric.faviconSize) / 2,
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

        placeChips()

        // The pill is `rowInset` inside the row, and the title keeps that same
        // inset inside the pill — so it ends two insets short of the row,
        // less the trailing slot on the rows that are drawing one.
        let column = Self.titleColumn(
            inRowOfWidth: contentWidth,
            hasUnread: content.hasUnread,
            slotOccupied: !trailing.isHidden,
            siteSlot: content.siteSettings,
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
        placeEditor(title: box, icon: icon.frame, reserving: chevronReserve)

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

    /// The square this row's icon is drawn in — a folder's is the larger one.
    /// See `Metric.groupIconSize`.
    static func iconSlot(for content: SidebarRowContent) -> CGFloat {
        content.disclosure == nil ? Tokens.Metric.faviconSize : Tokens.Metric.groupIconSize
    }

    /// What the title gives back to the chevron standing after it. Nothing on a
    /// row without one, and the slot plus its gap on a folder's header.
    private var chevronReserve: CGFloat {
        content.disclosure == nil ? 0 : Tokens.Metric.groupChevronSlot.width + Tokens.Metric.groupChevronGap
    }

}
