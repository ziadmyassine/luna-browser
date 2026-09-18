//
//  EssentialsGridView.swift
//  Luna
//
//  §3.3, and what the user calls **pinned tabs**: the grid of tiles directly
//  under the URL pill. Icon only, no label (§30.5) — which is exactly why each
//  tile carries an explicit VoiceOver label naming the *site*, never the URL
//  (§8, §21.1).
//
//  **The grid reshapes around how many tiles are in it.** Two across was a
//  fixed number, and a fixed number is wrong at both ends: one pinned tab sat
//  in a half-width tile with a hole beside it, and eight made four rows of a
//  column that is already the narrowest thing on screen. The shape is now
//  derived — see `columns` — so one tab is one wide tile, four are a single
//  row, five are 3 + 2 and eight are 4 + 4. The tiles change width to fill the
//  row; their height, radius and icon are the tokens they always were.
//
//  A pinned tab is a `.essential` tab. Pinning closes the page but keeps the
//  tile, so clicking one wakes it again; the only way to remove a tile is to
//  unpin it (right-click, or drag it back down into the list). Both routes
//  come through `BrowserSession.unpinTab`.
//
//  **Nothing here is an AppKit drop target any more.** A tile is moved by the
//  same tracked gesture a list row is — see `SidebarTabDrag.swift` — so the
//  grid's job during a drag is only to say where its slots are, to hold one
//  open, and to hide the tile that is currently in the air.
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

    /// The most tiles §3.3 will put in one row. Past four, a 42 pt tile in a
    /// 280 pt column is narrower than its own corner radius is round.
    private static let maxColumns = 4

    var onActivate: ((UUID) -> Void)?
    /// Right-click → Unpin. The tab goes back to the top of today's tabs.
    var onUnpin: ((UUID) -> Void)?
    /// A tile is being carried (§6.6). The sidebar's drag controller runs the
    /// rest of the gesture from here — the grid does not move its own tiles.
    var onDragTile: ((UUID, NSView, NSEvent) -> Void)?

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

    /// The tile currently in the air, if the lift started here. It is hidden
    /// and left out of the slot arithmetic for the length of the gesture, so
    /// `dropIndex` speaks in the same indices `reorderTab` will be given.
    var draggedID: UUID? {
        didSet {
            guard draggedID != oldValue else { return }
            // **Put it where it belongs before showing it.** A hidden tile is
            // not laid out, so it still carries the frame it had when it was
            // picked up — and the pass that reveals it is an animated one, so
            // it appeared back at its old slot and slid to the new one under
            // the lift that had just settled there. That slide is the "goes a
            // bit out and then rests": the tile, not the lift.
            if let revealed = oldValue, let tile = tiles[revealed],
               let slot = settled.firstIndex(of: revealed) {
                Tokens.Motion.immediately { tile.frame = slotRect(at: slot) }
            }
            for (id, tile) in tiles { tile.isHidden = id == draggedID }
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
        tile.onDragOut = { [weak self] event in self?.onDragTile?(tab.id, tile, event) }
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

    /// The tiles that are on the grid right now — everything but the one in
    /// the air.
    private var settled: [UUID] {
        order.filter { $0 != draggedID }
    }

    /// How many slots the grid is laying out: the settled tiles, plus the one a
    /// live drag is holding open.
    private var slotCount: Int {
        let open = dropIndex == nil ? 0 : 1
        return max(settled.count + open, isAwaitingDrop ? 1 : 0)
    }

    /// **As few rows as will hold them, then as evenly as they divide.**
    ///
    /// Rows first: four across is the ceiling, so five tiles need two rows and
    /// nine need three. Then the columns are whatever spreads that many tiles
    /// over that many rows — 5 over 2 is 3 and not 4, which is what makes five
    /// tiles read as 3 + 2 rather than as 4 + 1. A short last row is left-
    /// aligned, because the grid fills in reading order and a centred orphan
    /// would break the column the tiles above it stand in.
    ///
    /// Static and pure, for the same reason `ChromeState.cardInsets` is: §3.3's
    /// shape is arithmetic, and arithmetic can be asserted without a window.
    static func shape(for count: Int) -> (rows: Int, columns: Int) {
        guard count > 0 else { return (0, 1) }
        let rows = Int((Double(count) / Double(maxColumns)).rounded(.up))
        return (rows, max(Int((Double(count) / Double(rows)).rounded(.up)), 1))
    }

    private var rowCount: Int { Self.shape(for: slotCount).rows }

    private var columns: Int { Self.shape(for: slotCount).columns }

    override var intrinsicContentSize: NSSize {
        let margin = Tokens.Metric.essentialsVerticalInset
        guard rowCount > 0 else { return NSSize(width: NSView.noIntrinsicMetric, height: 0) }
        let height = CGFloat(rowCount) * Tokens.Metric.essentialsTile.height
            + CGFloat(rowCount - 1) * Tokens.Metric.essentialsRowGap + 2 * margin
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    /// One slot's frame, in reading order. The single piece of grid arithmetic:
    /// the tiles, the drop outline and the drag lift all place themselves with
    /// it, so they cannot disagree about where a slot is.
    func slotRect(at index: Int) -> NSRect {
        let inset = Tokens.Metric.essentialsInset
        let margin = Tokens.Metric.essentialsVerticalInset
        let gutter = Tokens.Metric.essentialsTileGap
        let rowGap = Tokens.Metric.essentialsRowGap
        let height = Tokens.Metric.essentialsTile.height
        let across = columns
        let width = (bounds.width - 2 * inset - CGFloat(across - 1) * gutter) / CGFloat(across)
        let column = index % across
        let row = index / across
        // Top-down in an unflipped view: the first row sits highest.
        return NSRect(
            x: inset + CGFloat(column) * (width + gutter),
            y: bounds.maxY - margin - CGFloat(row + 1) * height - CGFloat(row) * rowGap,
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
        for (index, id) in settled.enumerated() {
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
        return isAwaitingDrop && settled.isEmpty ? slotRect(at: 0) : nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// Which slot the pointer is over, in reading order — and **the index the
    /// tab would land at**, which is why it counts the settled tiles rather
    /// than all of them: the one in the air is already out of the way.
    func insertionIndex(at point: NSPoint) -> Int {
        let inset = Tokens.Metric.essentialsInset
        let gap = Tokens.Metric.essentialsTileGap
        let across = columns
        let tileWidth = (bounds.width - 2 * inset - CGFloat(across - 1) * gap) / CGFloat(across)
        let column = min(max(Int((point.x - inset) / max(tileWidth + gap, 1)), 0), across - 1)
        let fromTop = bounds.maxY - Tokens.Metric.essentialsVerticalInset - point.y
        let pitch = Tokens.Metric.essentialsTile.height + Tokens.Metric.essentialsRowGap
        let row = max(Int(fromTop / max(pitch, 1)), 0)
        return min(row * across + column, settled.count)
    }

    /// What §6.6's lift should look like while it is carrying `id` — the same
    /// title and favicon a list row would draw for that tab, because down there
    /// it *is* a list row.
    func content(for id: UUID) -> SidebarRowContent? {
        guard let tab = tabs.first(where: { $0.id == id }) else { return nil }
        return SidebarRowContent(
            title: Self.siteName(for: tab),
            favicon: SidebarIcons.favicon(for: tab)
        )
    }
}
