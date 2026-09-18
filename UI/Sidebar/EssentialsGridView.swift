//
//  EssentialsGridView.swift
//  Luna
//
//  §3.3, and what the user calls **pinned tabs**: the two-across grid of tiles
//  directly under the URL pill. Icon only, no label (§30.5) — which is exactly
//  why each tile carries an explicit VoiceOver label naming the *site*, never
//  the URL (§8, §21.1).
//
//  A pinned tab is a `.essential` tab. Pinning closes the page but keeps the
//  tile, so clicking one wakes it again; the only way to remove a tile is to
//  unpin it (right-click, or drag it back down into the list). Both routes
//  come through `BrowserSession.unpinTab`.
//
//  Tile width flexes. §1's 128 pt tile is the design intent at a 280 pt
//  sidebar, but 10 + 128 + 12 + 128 + 10 is 288 — wider than the sidebar it
//  was measured from — and §1 says the sidebar's own content reflows when it
//  is resized. The height, radius, gap and icon size are the tokens; the width
//  is what is left over. Measured: 42 pt tall, 10 pt outer inset, 12 pt gap,
//  and a 16 pt icon — the same favicon a list row draws, not a 22 pt glyph.
//

import AppKit
import BrowserKit

@MainActor
final class EssentialsGridView: NSView {

    /// Tiles per row (§3.3: "2 across, wrapping").
    private static let columns = 2

    var onActivate: ((UUID) -> Void)?
    /// A tab dropped on the grid is **pinned** at this index (§6.6).
    var onDrop: ((UUID, Int) -> Void)?
    /// Right-click → Unpin. The tab goes back to the top of today's tabs.
    var onUnpin: ((UUID) -> Void)?

    /// A row is being dragged somewhere in the sidebar.
    ///
    /// **An empty grid is zero points tall, so it cannot be dropped on** — and
    /// dragging a tab up here is one of the two ways to pin one, which made
    /// pinning the *first* tab impossible. While a drag is live the grid opens
    /// to one tile's height and draws the slot the tab would land in.
    var isAwaitingDrop = false {
        didSet {
            guard isAwaitingDrop != oldValue, tabs.isEmpty else { return }
            reflow()
        }
    }

    /// The slot §6.6's lift is currently over, or nil when it is somewhere else
    /// in the sidebar. While it is set the grid lays out with that slot empty —
    /// the tiles step round it — and draws its outline there.
    var dropIndex: Int? {
        didSet {
            guard dropIndex != oldValue else { return }
            animatesNextPlacement = true
            reflow()
        }
    }

    private var tabs: [Tab] = []
    /// Keyed by tab, **not** an array, so a tile survives a pin, an unpin or a
    /// reorder and can animate from where it was to where it now belongs. A
    /// rebuilt array of fresh views has nowhere to animate from, which is what
    /// made pinning a tab a jump-cut.
    private var tiles: [UUID: GlassButton] = [:]
    private var order: [UUID] = []
    private var activeTabID: UUID?
    /// Set when the grid's contents changed; consumed by the next `layout()`.
    private var animatesNextPlacement = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([SidebarDrag.tabType])
        setAccessibilityLabel("Essentials")
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Content

    func show(_ tabs: [Tab], activeTabID: UUID?) {
        self.activeTabID = activeTabID
        guard tabs != self.tabs else {
            // Icons arrive after the tab does (§4.7), so they are re-read even
            // when the tabs themselves have not changed.
            for tab in tabs {
                guard let tile = tiles[tab.id] else { continue }
                tile.isSelected = tab.id == activeTabID
                if let icon = SidebarIcons.favicon(for: tab) { tile.setImage(icon) }
            }
            return
        }
        self.tabs = tabs
        rebuild()
    }

    private func rebuild() {
        let wasEmpty = order.isEmpty
        let next = tabs.map(\.id)
        // Gone: faded out where it stood, then dropped. Removing it outright is
        // what made an unpin look like the tile had been deleted off-screen.
        for (id, tile) in tiles where !next.contains(id) {
            tiles.removeValue(forKey: id)
            Tokens.Motion.animate(Tokens.Motion.tabInsert) { context in
                context.allowsImplicitAnimation = true
                tile.animator().alphaValue = 0
            } completion: {
                MainActor.assumeIsolated { tile.removeFromSuperview() }
            }
        }
        for tab in tabs {
            let tile = tiles[tab.id] ?? makeTile(for: tab)
            tiles[tab.id] = tile
            if let icon = SidebarIcons.favicon(for: tab) { tile.setImage(icon) }
            tile.isSelected = tab.id == activeTabID
        }
        order = next
        // The first population is the sidebar being built; there is no "from".
        animatesNextPlacement = !wasEmpty
        reflow()
    }

    private func makeTile(for tab: Tab) -> GlassButton {
        let tile = GlassButton(
            shape: Tokens.Metric.essentialsTile,
            symbolName: "globe",
            pointSize: Tokens.Metric.essentialsIcon,
            // §8/§21.1: the site's name, never its URL.
            label: Self.siteName(for: tab),
            // A pinned tile is dormant until it is the tab you are on, or the
            // pointer is over it. Glass is what says "this one" — there is no
            // accent ring anywhere in Luna's chrome.
            glassMode: .dormant
        )
        tile.onActivate = { [weak self] in self?.onActivate?(tab.id) }
        tile.dragItem = { SidebarDrag.item(for: tab.id) }
        tile.menuBuilder = { [weak self] in
            let menu = NSMenu()
            menu.addItem(SidebarMenu.item(title: "Unpin Tab") { self?.onUnpin?(tab.id) })
            return menu
        }
        // Arrives at zero and fades up into its slot over the same spec the
        // list uses for a row arriving, so pinning reads as one movement.
        tile.alphaValue = order.isEmpty ? 1 : 0
        addSubview(tile)
        if !order.isEmpty {
            Tokens.Motion.animate(Tokens.Motion.tabInsert) { context in
                context.allowsImplicitAnimation = true
                tile.animator().alphaValue = 1
            }
        }
        return tile
    }

    /// The grid changed size or shape: re-measure, re-place, re-draw, and tell
    /// the sidebar that everything below it has moved.
    ///
    /// **Twice, the second time on the next tick.** The sidebar reads this
    /// view's `intrinsicContentSize` to place everything under it, and a pin or
    /// an unpin changes that size from inside work that is already running —
    /// a drop handler, or the completion of the fade that removes a tile. If
    /// the sidebar's layout pass has been and gone by then, the grid keeps the
    /// height it had: an unpinned tile left the grid a full row taller than its
    /// tiles, with the list stranded 47 pt below them until the window was
    /// resized. One more pass costs nothing and cannot be missed.
    private func reflow() {
        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
        superview?.needsLayout = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            invalidateIntrinsicContentSize()
            superview?.needsLayout = true
        }
    }

    private static func siteName(for tab: Tab) -> String {
        tab.title.isEmpty ? URLPillView.domain(of: tab.url) : tab.title
    }

    // MARK: - Layout

    /// How many slots the grid is laying out: its tiles, plus the one a live
    /// drag is holding open.
    private var slotCount: Int {
        let open = dropIndex == nil ? 0 : 1
        return max(tabs.count + open, isAwaitingDrop ? 1 : 0)
    }

    private var rowCount: Int {
        Int((Double(slotCount) / Double(Self.columns)).rounded(.up))
    }

    override var intrinsicContentSize: NSSize {
        let margin = Tokens.Metric.essentialsVerticalInset
        guard rowCount > 0 else { return NSSize(width: NSView.noIntrinsicMetric, height: 0) }
        let gap = Tokens.Metric.essentialsTileGap
        let height = CGFloat(rowCount) * Tokens.Metric.essentialsTile.height
            + CGFloat(rowCount - 1) * gap + 2 * margin
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    /// One slot's frame, in reading order. The single piece of grid arithmetic:
    /// the tiles, the drop outline and the drag lift all place themselves with
    /// it, so they cannot disagree about where a slot is.
    func slotRect(at index: Int) -> NSRect {
        let inset = Tokens.Metric.essentialsInset
        let margin = Tokens.Metric.essentialsVerticalInset
        let gap = Tokens.Metric.essentialsTileGap
        let height = Tokens.Metric.essentialsTile.height
        let width = (bounds.width - 2 * inset - CGFloat(Self.columns - 1) * gap) / CGFloat(Self.columns)
        let column = index % Self.columns
        let row = index / Self.columns
        // Top-down in an unflipped view: the first row sits highest.
        return NSRect(
            x: inset + CGFloat(column) * (width + gap),
            y: bounds.maxY - margin - CGFloat(row + 1) * height - CGFloat(row) * gap,
            width: max(width, 0),
            height: height
        ).pixelAligned
    }

    /// Bounds-derived frames never animate — see `Motion.immediately` — except
    /// on the pass that follows a pin, an unpin or a reorder, where the move
    /// from the old slot to the new one is the whole point.
    override func layout() {
        super.layout()
        let animated = animatesNextPlacement && !Tokens.Motion.reduceMotion
        animatesNextPlacement = false
        guard animated else {
            Tokens.Motion.immediately { placeContents() }
            return
        }
        Tokens.Motion.animate(Tokens.Motion.tabInsert) { context in
            context.allowsImplicitAnimation = true
            placeContents()
        }
    }

    private func placeContents() {
        for (index, id) in order.enumerated() {
            guard let tile = tiles[id] else { continue }
            // A live drag holds a slot open: everything from it onwards steps
            // along by one, which is the gap the lift drops into.
            let slot = dropIndex.map { index >= $0 ? index + 1 : index } ?? index
            tile.frame = slotRect(at: slot)
        }
    }

    /// The slot a drop would land in. Drawn only while a drag is live, because
    /// the rest of the time there is nothing to hint at.
    override func draw(_ dirtyRect: NSRect) {
        guard let slot = outlinedSlot else { return }
        let path = NSBezierPath(
            roundedRect: slot,
            xRadius: Tokens.Metric.essentialsTile.cornerRadius,
            yRadius: Tokens.Metric.essentialsTile.cornerRadius
        )
        path.lineWidth = Tokens.Metric.hairline
        path.setLineDash([6, 4], count: 2, phase: 0)
        Tokens.Line.border.setStroke()
        path.stroke()
    }

    /// Which slot the outline goes round: the one a lift is over, or — with
    /// nothing pinned yet and a drag in the air — the first one.
    private var outlinedSlot: NSRect? {
        if let dropIndex { return slotRect(at: dropIndex) }
        return isAwaitingDrop && tabs.isEmpty ? slotRect(at: 0) : nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: - Drop (§6.6)

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        SidebarDrag.tabID(in: sender) == nil ? [] : .move
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        SidebarDrag.tabID(in: sender) == nil ? [] : .move
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let id = SidebarDrag.tabID(in: sender) else { return false }
        onDrop?(id, insertionIndex(at: convert(sender.draggingLocation, from: nil)))
        return true
    }

    /// Which slot the pointer is over, in reading order.
    func insertionIndex(at point: NSPoint) -> Int {
        let inset = Tokens.Metric.essentialsInset
        let gap = Tokens.Metric.essentialsTileGap
        let tileWidth = (bounds.width - 2 * inset - CGFloat(Self.columns - 1) * gap) / CGFloat(Self.columns)
        let column = min(max(Int((point.x - inset) / max(tileWidth + gap, 1)), 0), Self.columns - 1)
        let fromTop = bounds.maxY - Tokens.Metric.essentialsVerticalInset - point.y
        let row = max(Int(fromTop / max(Tokens.Metric.essentialsTile.height + gap, 1)), 0)
        return min(row * Self.columns + column, tabs.count)
    }
}
