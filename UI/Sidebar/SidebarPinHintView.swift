//
//  SidebarPinHintView.swift
//  Luna
//
//  §3.3a: the dashed well a Space draws where its pinned things would be, in a
//  Space that has not pinned any yet.
//
//  Two of them, one shape each. The block stands in the §3.3 grid and says a
//  tab can be dropped there; the row stands under it, where §3.4b's first
//  folder will be, and says the same about a folder.
//
//  Each well is drawn as the thing that is missing rather than as a notice
//  about it. The row well is a §3.4 row: its glyph is in the favicon column at
//  a folder's own size, its line starts at `rowTitleInset` in the column's own
//  face, and its cross stands in the trailing slot every tab row keeps. The
//  block is the grid, so its content is centred the way a tile's is. That is
//  the whole of the difference between them — one fill, one dash, one corner,
//  one face.
//
//  It is not a button. The well is somewhere a lift lands — §6.6 already
//  resolves both zones without being told about this view — so it answers a
//  drop, not a press, and the only thing in it that takes the pointer is the
//  cross. `isAimedAt` is the lift's answer: the same `Surface.hover` a row
//  under the pointer wears.
//

import AppKit

@MainActor
final class SidebarPinHintView: NSView {

    /// Which way the well stacks its glyph and its line.
    enum Shape {
        /// The taller well, glyph over the line. §3.3's grid, which is a block.
        case block
        /// A row pill's height, glyph beside the line. §3.4b's tier, which is
        /// a list.
        case row

        var height: CGFloat {
            switch self {
            case .block: Tokens.Metric.pinHintBlock
            case .row: Tokens.Metric.pinHintRow
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
            Tokens.Motion.wash(layer, to: isAimedAt ? Tokens.Surface.hover : Tokens.Surface.well)
        }
    }

    private let shape: Shape
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let close = RowGlyphView()
    /// The cross is revealed on hover, exactly as §3.4's close is. A tip is
    /// mostly read, not dismissed, and a cross standing in the well at rest
    /// took a quarter of the line's room and put a second mark in a box whose
    /// whole job is to hold one sentence.
    private var isHovered = false { didSet { revealTheCross() } }
    private var hoverArea: NSTrackingArea?

    init(shape: Shape, symbolName: String, text: String, dismissLabel: String) {
        self.shape = shape
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Tokens.Metric.rowCornerRadius
        layer?.backgroundColor = Tokens.Surface.well.cgColor

        icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: Tokens.Metric.pinHintIcon,
            weight: .regular
        )
        icon.contentTintColor = Tokens.Text.secondary
        icon.imageScaling = .scaleNone

        label.font = Tokens.TypeScale.sidebarHint
        label.textColor = Tokens.Text.secondary
        label.stringValue = text
        label.alignment = shape == .block ? .center : .natural
        label.lineBreakMode = .byTruncatingTail

        close.configure(symbolName: "xmark", label: dismissLabel, pointSize: Tokens.Metric.rowTrailingGlyph)
        close.onActivate = { [weak self] in self?.onDismiss?() }
        close.isHidden = true
        close.alphaValue = 0

        for view in [icon, label, close] { addSubview(view) }
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

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

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
            xRadius: Tokens.Metric.rowCornerRadius,
            yRadius: Tokens.Metric.rowCornerRadius
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

    /// The trailing slot, in the well's own bounds. A well is placed where a
    /// row's pill is placed, so it is already one `rowInset` inside the column
    /// and the chip keeps a second one inside the well — which is exactly what
    /// `SidebarRowView` does with the close it draws in the same column.
    private var chipBox: NSRect {
        let chip = Tokens.Metric.rowTrailingChip
        let x = bounds.maxX - Tokens.Metric.rowInset - chip.width
        // Centred in the row, and up in the corner in the block: six points
        // down from the top of a 35 pt pill is two and a half off the middle
        // and reads as a slip, while a block has a corner to keep.
        let y = shape == .block
            ? bounds.maxY - Tokens.Metric.rowInset - chip.height
            : bounds.midY - chip.height / 2
        return NSRect(x: x, y: y, width: chip.width, height: chip.height).integral
    }

    private func placeContents() {
        close.frame = chipBox
        let side = Tokens.Metric.pinHintIcon
        let line = label.intrinsicContentSize
        guard shape == .block else {
            // §3.4's own two columns: the glyph where a favicon goes — centred
            // on that column, since a folder's icon is drawn larger than one —
            // and the line where a title starts. The well is then the row it
            // stands in for, rather than a banner lying where one will be.
            let column = Tokens.Metric.rowFaviconInset - Tokens.Metric.rowInset
            icon.frame = NSRect(
                x: column - (side - Tokens.Metric.faviconSize) / 2,
                y: bounds.midY - side / 2,
                width: side,
                height: side
            ).pixelAligned
            // The trailing slot is kept whether or not the cross is in it, so
            // the line does not step sideways when the pointer arrives.
            let left = Tokens.Metric.rowTitleInset - Tokens.Metric.rowInset
            label.frame = NSRect(
                x: left,
                y: bounds.midY - line.height / 2,
                width: max(chipBox.minX - Tokens.Metric.rowInset - left, 0),
                height: line.height
            ).integral
            return
        }
        // The line is under the glyph rather than beside it, so it has the
        // well's full width to run in — the cross is a row above it.
        let free = max(bounds.width - 2 * Tokens.Metric.rowInset, 0)
        let stack = side + Tokens.Metric.pinHintGap + line.height
        let top = bounds.midY + stack / 2
        icon.frame = NSRect(x: bounds.midX - side / 2, y: top - side, width: side, height: side).pixelAligned
        label.frame = NSRect(
            x: bounds.midX - free / 2,
            y: top - stack,
            width: free,
            height: line.height
        ).integral
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
        // Both colours were resolved into the appearance they were set in.
        layer?.backgroundColor = (isAimedAt ? Tokens.Surface.hover : Tokens.Surface.well).cgColor
        icon.contentTintColor = Tokens.Text.secondary
        label.textColor = Tokens.Text.secondary
        needsDisplay = true
    }
}
