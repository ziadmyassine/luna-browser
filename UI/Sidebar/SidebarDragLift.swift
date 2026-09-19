//
//  SidebarDragLift.swift
//  Luna
//
//  The thing under the pointer while a tab is being moved — see
//  `SidebarTabDrag.swift` for the gesture that drives it.
//
//  **It is the row, not a picture of the row.** §3.4 draws a tab as a selected
//  glass pill with a favicon and a title on it, and that is what this is: the
//  same `RowPillView` the list moves between rows, with the same two pieces of
//  content laid out at the same insets. Martin asked for "the whole tab
//  rectangle, included the highlighted UI", and the cheapest way to be sure of
//  that is to build it out of the same parts rather than to snapshot them.
//
//  The **morph** is why the title and the icon are laid out by hand instead of
//  by constraints. A §3.3 tile is the same pill at a different size with the
//  title gone and the icon in the middle, so going from one to the other is two
//  frames and an alpha inside one animation — no view is created, destroyed or
//  re-parented on the way, which is what makes it read as the same object
//  changing shape.
//

import AppKit

@MainActor
final class SidebarDragLiftView: NSView {

    /// §3.4's row, or §3.3's tile.
    enum Shape { case row, tile }

    /// Which of §3's two shapes the lift is wearing. Set before the first
    /// placement by whoever started the gesture — a tile lifts as a tile.
    var shape: Shape = .row { didSet { needsLayout = true } }

    private let pill = RowPillView(role: .selected)
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")

    init(content: SidebarRowContent) {
        super.init(frame: .zero)
        wantsLayer = true
        // The lift floats above both the grid and the list, so it carries §5's
        // shadow — the one drop shadow in the chrome, and the only thing that
        // says "this is off the surface" without changing the row's own colour.
        layer?.masksToBounds = false

        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: Tokens.Metric.faviconSize,
            weight: .regular
        )
        icon.image = content.favicon
            ?? NSImage(systemSymbolName: content.symbolName, accessibilityDescription: nil)
        icon.image?.isTemplate = content.favicon == nil
        icon.contentTintColor = content.favicon != nil ? nil : Tokens.Text.primary

        title.font = Tokens.TypeScale.sidebarRow
        title.textColor = Tokens.Text.primary
        title.lineBreakMode = .byTruncatingTail
        title.cell?.usesSingleLineMode = true
        title.stringValue = content.title

        for view in [pill, icon, title] { addSubview(view) }
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Entrance and exit

    /// §6's `tabInsert`: the row leaves the surface. A shadow and a percent of
    /// scale, which together read as "picked up" without moving it — the
    /// pointer has not gone anywhere yet when this runs.
    func lift() {
        applyShadow()
        guard !Tokens.Motion.reduceMotion else { return }
        layer?.shadowOpacity = 0
        Tokens.Motion.animate(Tokens.Motion.tabInsert) { context in
            context.allowsImplicitAnimation = true
            self.layer?.shadowOpacity = 1
        }
    }

    /// Fades out where it stands and takes itself off the sidebar. The list has
    /// already been told to close its gap, so the row it is standing in for is
    /// on its way back under it.
    func drop() {
        Tokens.Motion.animate(Tokens.Motion.rowHover) { context in
            context.allowsImplicitAnimation = true
            animator().alphaValue = 0
        } completion: { [self] in
            MainActor.assumeIsolated { removeFromSuperview() }
        }
    }

    /// **Comes to rest in the slot, then hands over.** A tile carried around
    /// the §3.3 grid is not snapped to a slot while it is in the air — it goes
    /// where the hand goes — so letting go has to be the movement that puts it
    /// away. `commit` runs when it lands, not when it is released: the real
    /// tile stays hidden until the lift is standing exactly on top of it, which
    /// is what makes the hand-off invisible.
    func settle(into frame: NSRect, then commit: @escaping @MainActor @Sendable () -> Void) {
        guard !Tokens.Motion.reduceMotion else {
            self.frame = frame
            commit()
            removeFromSuperview()
            return
        }
        Tokens.Motion.animate(Tokens.Motion.tabInsert) { context in
            context.allowsImplicitAnimation = true
            animator().frame = frame
        } completion: { [self] in
            MainActor.assumeIsolated {
                layoutContents()
                commit()
                drop()
            }
        }
    }

    // MARK: - Geometry

    /// Moves the lift, and — when `animated` — morphs it between §3.4's row and
    /// §3.3's tile on the way.
    func apply(frame: NSRect, shape: Shape, animated: Bool) {
        self.shape = shape
        guard animated, !Tokens.Motion.reduceMotion else {
            Tokens.Motion.immediately {
                self.frame = frame
                layoutContents()
            }
            return
        }
        Tokens.Motion.animate(Tokens.Motion.tabInsert) { context in
            context.allowsImplicitAnimation = true
            animator().frame = frame
            layoutContents()
        }
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately { layoutContents() }
    }

    private func layoutContents() {
        pill.frame = bounds
        let glyph = Tokens.Metric.faviconSize
        switch shape {
        case .row:
            // The same insets §3.4 measures, less the pill's own inset from the
            // sidebar — the lift *is* the pill, so its bounds start where the
            // row's pill starts.
            let inset = Tokens.Metric.rowFaviconInset - Tokens.Metric.rowInset
            icon.frame = NSRect(x: inset, y: (bounds.height - glyph) / 2, width: glyph, height: glyph).pixelAligned
            // `rowTitleGap`, not `rowIconGap`: the lift is a tab row, and it
            // has to carry the tighter gap the rows it left are drawn with or
            // the title steps sideways the moment the tab is picked up.
            let titleX = icon.frame.maxX + Tokens.Metric.rowTitleGap
            let height = title.intrinsicContentSize.height
            title.frame = NSRect(
                x: titleX,
                y: (bounds.height - height) / 2,
                width: max(bounds.maxX - Tokens.Metric.rowInset - titleX, 0),
                height: height
            ).integral
            title.alphaValue = 1
        case .tile:
            // §3.3's tiles are icon only (§30.5).
            icon.frame = NSRect(
                x: (bounds.width - glyph) / 2,
                y: (bounds.height - glyph) / 2,
                width: glyph,
                height: glyph
            ).pixelAligned
            title.alphaValue = 0
        }
    }

    // MARK: - Appearance

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        applyShadow()
    }

    private func applyShadow() {
        guard let layer else { return }
        Tokens.Shadow.popover.apply(to: layer, in: effectiveAppearance)
    }

    /// The lift is under the pointer for the whole gesture and must never take
    /// an event: the tracking loop owns them.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
