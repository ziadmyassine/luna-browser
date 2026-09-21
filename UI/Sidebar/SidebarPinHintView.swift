//
//  SidebarPinHintView.swift
//  Luna
//
//  §3.3a: the dashed well a Space draws where its pinned things would be, in a
//  Space that has not pinned any yet.
//
//  Two of them, one shape each. The block stands in the §3.3 grid and says a
//  tab can be dropped there; the row stands under it, where §3.4b's first
//  folder will be, and says the same about a folder. Both are advice, so both
//  carry the cross that ends it.
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
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail

        close.configure(symbolName: "xmark", label: dismissLabel, pointSize: Tokens.Metric.rowTrailingGlyph)
        close.onActivate = { [weak self] in self?.onDismiss?() }

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

    private func placeContents() {
        let side = Tokens.Metric.pinHintIcon
        let gap = Tokens.Metric.pinHintGap
        let chip = Tokens.Metric.rowTrailingChip
        let inset = Tokens.Metric.pinHintChipInset
        let line = label.intrinsicContentSize
        // The cross clears its own corner in the block; in a row pill it is
        // centred instead, because 6 pt down from the top of a 35 pt well is
        // two and a half points off the middle and reads as a slip rather than
        // as a corner.
        close.frame = NSRect(
            x: bounds.maxX - inset - chip.width,
            y: shape == .block ? bounds.maxY - inset - chip.height : bounds.midY - chip.height / 2,
            width: chip.width,
            height: chip.height
        ).integral
        guard shape == .block else {
            // Centred in the well, but stopped short of the cross's column, so
            // a narrow sidebar truncates the line rather than running its last
            // words under the glyph that ends them. Both ends are clamped: at
            // the width where the run no longer fits, it starts at the margin
            // and the tail is what goes.
            let ceiling = bounds.maxX - inset - chip.width - gap
            let margin = bounds.minX + Tokens.Metric.rowInset
            let run = min(side + gap + line.width, max(ceiling - margin, 0))
            let left = min(max(bounds.midX - run / 2, margin), max(ceiling - run, margin))
            icon.frame = NSRect(x: left, y: bounds.midY - side / 2, width: side, height: side).integral
            label.frame = NSRect(
                x: left + side + gap,
                y: bounds.midY - line.height / 2,
                width: max(run - side - gap, 0),
                height: line.height
            ).integral
            return
        }
        // The line is under the glyph rather than beside it, so it has the
        // well's full width to run in — the cross is a row above it.
        let free = max(bounds.width - 2 * Tokens.Metric.rowInset, 0)
        let stack = side + gap + line.height
        let top = bounds.midY + stack / 2
        icon.frame = NSRect(x: bounds.midX - side / 2, y: top - side, width: side, height: side).integral
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
