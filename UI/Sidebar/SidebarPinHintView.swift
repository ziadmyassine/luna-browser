//
//  SidebarPinHintView.swift
//  Luna
//
//  §3.3a: the dashed well a Space draws where its pinned things would be, in a
//  Space that has not pinned any yet.
//
//  Two of them, one shape each. The block stands in §3.3's grid and says a tab
//  can be dropped there; the row stands under it, where §3.4b's first folder
//  will be, and says the same about a folder.
//
//  Each well is the thing that is missing rather than a notice about it. The
//  block takes a §3.3 tile's height and corner and stands in the slot the first
//  pinned tab will stand in; the row takes a §3.4 pill's. Inside, both are a
//  §3.4 row: the glyph in the favicon column at `faviconSize`, the line at
//  `rowTitleInset` in the column's own face, the cross in the trailing slot
//  every tab row keeps. So the two wells and every row under them put their
//  glyph on one column and start their words on another.
//
//  And the line ends the way a row's title does — laid out at its natural width
//  in a clipping box, dissolving against the trailing edge — rather than in an
//  ellipsis. §3.4 does not spend three characters saying a name is longer than
//  its row, and neither does a well in a narrow column.
//
//  Neither carries a fill at rest. Nothing else in §3 does — an unselected row
//  has no background at all — and a well that was a dark recess at rest and a
//  white wash under a lift was answering the pointer by changing material.
//  Empty is drawn as a dashed line here, exactly as §3.3 draws its own drop
//  outline, and `Surface.hover` is what arriving over one looks like.
//
//  It is not a button. The well is somewhere a lift lands — §6.6 already
//  resolves both zones without being told about this view — so it answers a
//  drop, not a press, and the only thing in it that takes the pointer is the
//  cross.
//

import AppKit

@MainActor
final class SidebarPinHintView: NSView {

    /// Which of the two things the well is standing in for.
    enum Shape {
        /// A §3.3 tile, in the slot the first pinned tab takes.
        case block
        /// A §3.4b row, where the first folder's header goes.
        case row

        var height: CGFloat {
            switch self {
            case .block: Tokens.Metric.pinHintBlock
            case .row: Tokens.Metric.pinHintRow
            }
        }

        /// The corner of the thing it stands in for. The two are the same
        /// number today; they are read from their own tokens because a tile and
        /// a row pill are free to stop agreeing.
        var cornerRadius: CGFloat {
            switch self {
            case .block: Tokens.Metric.essentialsTile.cornerRadius
            case .row: Tokens.Metric.rowCornerRadius
            }
        }

    }

    var onDismiss: (() -> Void)?

    /// A §6.6 lift is over this zone. The well fills, exactly as a row does
    /// under the pointer — the advice and the drop target are the same shape,
    /// so they answer the same way.
    var isAimedAt = false {
        didSet {
            guard isAimedAt != oldValue else { return }
            Tokens.Motion.wash(layer, to: isAimedAt ? Tokens.Surface.hover : nil)
        }
    }

    private let shape: Shape
    private let icon = NSImageView()
    /// Clips and fades the line, exactly as §3.4's `titleClip` does — see
    /// `SidebarRowView+Title.swift`, which is the same idea on a row.
    private let lineClip = NSView()
    private let fadeMask = CAGradientLayer()
    private let label = NSTextField(labelWithString: "")
    private let close = RowGlyphView()
    /// The cross is revealed on hover, exactly as §3.4's close is. A tip is
    /// mostly read, not dismissed, and a cross standing in the well at rest
    /// took a quarter of the line's room and put a second mark in a box whose
    /// whole job is to hold one sentence.
    private var isHovered = false {
        didSet {
            revealTheCross()
            // The line gives the cross's slot back when the cross is not in it
            // — §3.4's own rule for a row with no trailing glyph — so the
            // column it runs in changes with the pointer.
            needsLayout = true
        }
    }
    private var hoverArea: NSTrackingArea?

    init(shape: Shape, symbolName: String, text: String, dismissLabel: String) {
        self.shape = shape
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = shape.cornerRadius

        icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: Tokens.Metric.faviconSize,
            weight: .regular
        )
        icon.contentTintColor = Tokens.Text.secondary
        icon.imageScaling = .scaleNone

        label.font = Tokens.TypeScale.sidebarRow
        label.textColor = Tokens.Text.secondary
        label.stringValue = text
        // Clipping, not truncating: the fade below is what ends an over-long
        // line, and an ellipsis would be drawn before it.
        label.lineBreakMode = .byClipping
        label.cell?.usesSingleLineMode = true
        lineClip.wantsLayer = true
        lineClip.layer?.masksToBounds = true
        lineClip.addSubview(label)
        fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMask.endPoint = CGPoint(x: 1, y: 0.5)

        close.configure(symbolName: "xmark", label: dismissLabel, pointSize: Tokens.Metric.rowTrailingGlyph)
        close.onActivate = { [weak self] in self?.onDismiss?() }
        close.isHidden = true
        close.alphaValue = 0

        for view in [icon, lineClip, close] { addSubview(view) }
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// §3.3's well, and §3.4b's. The two are made here rather than at their
    /// three call sites — the column, the grid and §30.9's still — so the
    /// wording of a piece of advice has one home.
    static func tabGrid() -> SidebarPinHintView {
        SidebarPinHintView(
            shape: .block,
            symbolName: "pin",
            text: String(localized: "Drag a tab here to pin it"),
            dismissLabel: dismissLabel
        )
    }

    static func folderTier() -> SidebarPinHintView {
        SidebarPinHintView(
            shape: .row,
            symbolName: "folder",
            text: String(localized: "Drag a folder here to pin it"),
            dismissLabel: dismissLabel
        )
    }

    /// What the cross says, in both wells: it ends the advice, it does not
    /// answer it — nothing is pinned and nothing is dismissed but the tip.
    private static var dismissLabel: String { String(localized: "Hide this tip") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: shape.height)
    }

    // MARK: - The pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    /// The pointer arrived, or left. Its own method so that both states can be
    /// asserted without a window to hover in — the line gives the cross's slot
    /// back at rest and takes it away again here, and which of the two is on
    /// screen is the whole question in a narrow column.
    func setHovered(_ hovered: Bool) {
        isHovered = hovered
        layoutSubtreeIfNeeded()
    }

    private func revealTheCross() {
        guard !Tokens.Motion.reduceMotion else {
            close.isHidden = !isHovered
            close.alphaValue = 1
            return
        }
        if isHovered { close.isHidden = false }
        Tokens.Motion.animate(Tokens.Motion.rowHover) { context in
            context.allowsImplicitAnimation = true
            self.close.animator().alphaValue = self.isHovered ? 1 : 0
        } completion: { [self] in
            MainActor.assumeIsolated { close.isHidden = !isHovered }
        }
    }

    /// A cross that is not showing takes no press, however close the pointer
    /// gets to the corner it stands in.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        return !close.isHidden && close.frame.contains(local) ? close : self
    }

    // MARK: - Drawing

    /// The dashed line, in `Line.border` and §3.3's own dash: the well is drawn
    /// rather than layer-bordered because a layer border cannot be dashed on a
    /// continuous corner without stroking a path of its own anyway.
    override func draw(_ dirtyRect: NSRect) {
        let hairline = Tokens.Metric.hairline
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: hairline / 2, dy: hairline / 2),
            xRadius: shape.cornerRadius,
            yRadius: shape.cornerRadius
        )
        path.lineWidth = hairline
        let dash = Tokens.Metric.pinHintDash
        path.setLineDash(dash, count: dash.count, phase: 0)
        Tokens.Line.border.setStroke()
        path.stroke()
    }

    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately { placeContents() }
    }

    // MARK: - Layout

    /// The trailing slot, in the well's own bounds, centred as a row's is. A
    /// well is placed where a row's pill is placed, so it is already one
    /// `rowInset` inside the column and the chip keeps a second one inside the
    /// well — which is exactly what `SidebarRowView` does with the close it
    /// draws in the same column.
    private var chipBox: NSRect {
        let chip = Tokens.Metric.rowTrailingChip
        return NSRect(
            x: bounds.maxX - Tokens.Metric.rowInset - chip.width,
            y: bounds.midY - chip.height / 2,
            width: chip.width,
            height: chip.height
        ).integral
    }

    private func placeContents() {
        close.frame = chipBox
        let side = Tokens.Metric.faviconSize
        let inset = Tokens.Metric.rowInset
        // §3.4's own two columns, in both wells. A well is placed exactly where
        // a row's pill is placed, so taking one `rowInset` off the column's
        // insets puts the glyph and the line on the same two absolute x's as
        // every row under them.
        icon.frame = NSRect(
            x: Tokens.Metric.rowFaviconInset - inset,
            y: bounds.midY - side / 2,
            width: side,
            height: side
        ).pixelAligned
        // The trailing slot is the line's until the cross is in it, which is
        // §3.4's own rule: a row with no trailing glyph runs its title to the
        // pill's inner edge, and one drawing a chip stops half an inset short
        // of the slot. A well is hovered for a moment and read for however long
        // the Space stays empty, so the resting state wins here too — and it is
        // 22 pt, which is the difference between a sentence and most of one in
        // a narrow column.
        let left = Tokens.Metric.rowTitleInset - inset
        let right = isHovered ? chipBox.minX - inset / 2 : bounds.maxX - inset
        let line = label.intrinsicContentSize
        let box = NSRect(
            x: left,
            y: bounds.midY - line.height / 2,
            width: max(right - left, 0),
            height: line.height
        ).integral
        lineClip.frame = box
        // Laid out at its natural width so nothing truncates; the clip box and
        // the fade are what end the line.
        let natural = ceil(line.width)
        label.frame = NSRect(x: 0, y: 0, width: max(natural, box.width), height: box.height)
        // A standalone `CALayer` animates its own frame changes implicitly, and
        // the column is re-laid on every resize drag.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyFade(overflowing: natural > box.width, width: box.width)
        CATransaction.commit()
    }

    /// §3.4's fade, on a well. Nil mask when the line fits: a gradient that is
    /// opaque end to end is still a masked composite.
    private func applyFade(overflowing: Bool, width: CGFloat) {
        guard overflowing, width > Tokens.Metric.rowTitleFade else {
            lineClip.layer?.mask = nil
            return
        }
        let ink = Tokens.Text.primary
        fadeMask.frame = lineClip.bounds
        fadeMask.colors = [ink.cgColor, ink.cgColor, ink.withAlphaComponent(0).cgColor]
        fadeMask.locations = [0, NSNumber(value: Double(1 - Tokens.Metric.rowTitleFade / width)), 1]
        lineClip.layer?.mask = fadeMask
    }

    /// A frame set inside an animated pass leaves `layout()` reading the bounds
    /// the view still has, and nothing marks it dirty again when the animation
    /// lands. The column's head changes height under exactly such a pass — see
    /// `SidebarViewController.viewDidLayout` — and the row well came out of one
    /// with its line measured against a width it no longer had.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Every colour here was resolved into the appearance it was set in.
        layer?.backgroundColor = isAimedAt ? Tokens.Surface.hover.cgColor : nil
        icon.contentTintColor = Tokens.Text.secondary
        label.textColor = Tokens.Text.secondary
        // The fade's own colours were resolved too, and `layout` is what sets
        // them.
        needsLayout = true
        needsDisplay = true
    }
}
