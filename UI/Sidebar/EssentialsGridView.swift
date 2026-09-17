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
            invalidateIntrinsicContentSize()
            needsDisplay = true
            superview?.needsLayout = true
        }
    }

    private var tabs: [Tab] = []
    private var tiles: [GlassButton] = []
    private var activeTabID: UUID?

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
            for (tile, tab) in zip(tiles, tabs) {
                tile.isAccented = tab.id == activeTabID
                if let icon = SidebarIcons.favicon(for: tab) { tile.setImage(icon) }
            }
            return
        }
        self.tabs = tabs
        rebuild()
    }

    private func rebuild() {
        for tile in tiles { tile.removeFromSuperview() }
        tiles = tabs.map { tab in
            let tile = GlassButton(
                shape: Tokens.Metric.essentialsTile,
                symbolName: "globe",
                pointSize: Tokens.Metric.essentialsIcon,
                // §8/§21.1: the site's name, never its URL.
                label: Self.siteName(for: tab)
            )
            if let icon = SidebarIcons.favicon(for: tab) { tile.setImage(icon) }
            tile.isAccented = tab.id == activeTabID
            tile.onActivate = { [weak self] in self?.onActivate?(tab.id) }
            tile.dragItem = { SidebarDrag.item(for: tab.id) }
            tile.menuBuilder = { [weak self] in
                let menu = NSMenu()
                menu.addItem(SidebarMenu.item(title: "Unpin Tab") { self?.onUnpin?(tab.id) })
                return menu
            }
            addSubview(tile)
            return tile
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private static func siteName(for tab: Tab) -> String {
        tab.title.isEmpty ? URLPillView.domain(of: tab.url) : tab.title
    }

    // MARK: - Layout

    private var rowCount: Int {
        Int((Double(tabs.count) / Double(Self.columns)).rounded(.up))
    }

    override var intrinsicContentSize: NSSize {
        let tile = Tokens.Metric.essentialsTile.height
        guard rowCount > 0 else {
            let open = tile + 2 * Tokens.Metric.essentialsInset
            return NSSize(width: NSView.noIntrinsicMetric, height: isAwaitingDrop ? open : 0)
        }
        let gap = Tokens.Metric.essentialsTileGap
        let height = CGFloat(rowCount) * tile + CGFloat(rowCount - 1) * gap
            + 2 * Tokens.Metric.essentialsInset
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    override func layout() {
        super.layout()
        let inset = Tokens.Metric.essentialsInset
        let gap = Tokens.Metric.essentialsTileGap
        let tileHeight = Tokens.Metric.essentialsTile.height
        let tileWidth = (bounds.width - 2 * inset - CGFloat(Self.columns - 1) * gap) / CGFloat(Self.columns)
        for (index, tile) in tiles.enumerated() {
            let column = index % Self.columns
            let row = index / Self.columns
            // Top-down in an unflipped view: the first row sits highest.
            tile.frame = NSRect(
                x: inset + CGFloat(column) * (tileWidth + gap),
                y: bounds.maxY - inset - CGFloat(row + 1) * tileHeight - CGFloat(row) * gap,
                width: max(tileWidth, 0),
                height: tileHeight
            ).integral
        }
    }

    /// The empty grid's drop slot. Drawn only while a drag is live, because the
    /// rest of the time there is nothing here and nothing to hint at.
    override func draw(_ dirtyRect: NSRect) {
        guard isAwaitingDrop, tabs.isEmpty else { return }
        let inset = Tokens.Metric.essentialsInset
        let slot = bounds.insetBy(dx: inset, dy: inset)
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
    private func insertionIndex(at point: NSPoint) -> Int {
        let inset = Tokens.Metric.essentialsInset
        let gap = Tokens.Metric.essentialsTileGap
        let tileWidth = (bounds.width - 2 * inset - CGFloat(Self.columns - 1) * gap) / CGFloat(Self.columns)
        let column = min(max(Int((point.x - inset) / max(tileWidth + gap, 1)), 0), Self.columns - 1)
        let fromTop = bounds.maxY - inset - point.y
        let row = max(Int(fromTop / max(Tokens.Metric.essentialsTile.height + gap, 1)), 0)
        return min(row * Self.columns + column, tabs.count)
    }
}
