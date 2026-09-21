//
//  EssentialsGridView.swift
//  Luna
//
//  §3.3, and what the user calls pinned tabs: the grid of tiles directly
//  under the URL pill. Icon only, no label (§30.5) — which is exactly why each
//  tile carries an explicit VoiceOver label naming the site, never the URL
//  (§8, §21.1).
//
//  The grid reshapes around how many tiles are in it. Two across was fixed,
//  and a fixed number is wrong at both ends: one pinned tab sat in a half-width
//  tile with a hole beside it, and eight made four rows of the narrowest column
//  on screen. The shape is derived — see `columns` — so one tab is one wide
//  tile, four are a single row, five are 3 + 2 and eight are 4 + 4.
//
//  A pinned tab is a `.essential` tab. Pinning closes the page but keeps the
//  tile, so clicking one wakes it again; the only way to remove a tile is to
//  unpin it, by right-click or by dragging it back into the list. Both go
//  through `BrowserSession.unpinTab`.
//
//  Nothing here is an AppKit drop target. A tile is moved by the same tracked
//  gesture a list row is (`SidebarTabDrag.swift`), so during a drag the grid
//  only says where its slots are, holds one open, and hides the tile in the
//  air.
//
//  The tile you are on is lit, in that site's own colour. One glow for the
//  whole grid, because only one tile can be the tab you are on — see
//  `EssentialGlowView` and `FaviconTint`. It lies over the tiles and answers no
//  hit test, so the tile underneath still takes the click.
//
//  Tile width flexes. §1's 128 pt tile is the intent at a 280 pt sidebar, but
//  10 + 128 + 12 + 128 + 10 is 288 — wider than the sidebar it was measured
//  from — and §1 says the column's content reflows when it is resized. The
//  height, radius, gap and icon size are the tokens; the width is what is left.
//  Measured: 42 pt tall, 10 pt outer inset, 12 pt gap, 16 pt icon.
//

import AppKit
import BrowserKit

@MainActor
final class EssentialsGridView: NSView {

    /// The most tiles §3.3 will put in one row. Past four, a 42 pt tile in a
    /// 280 pt column is narrower than its own corner radius is round.
    ///
    /// Not private: the arithmetic that spends it lives next door, in
    /// `EssentialsGridView+Layout.swift`.
    static let maxColumns = 4

    var onActivate: ((UUID) -> Void)?
    /// Right-click → Unpin. The tab goes back to the top of today's tabs.
    var onUnpin: ((UUID) -> Void)?
    /// §3.4a's menu for a tile, which is the same menu §3.4's rows get — a tile
    /// is a tab. Nil leaves the tile with no menu rather than a shorter one: a
    /// second, smaller answer to the same right-click is what this avoids.
    var menuActions: ((UUID) -> TabMenu.Actions?)?
    /// Whether that tab is muted, for the menu's wording.
    var isMuted: ((UUID) -> Bool)?
    /// A tile is being carried (§6.6). The sidebar's drag controller runs the
    /// rest of the gesture from here — the grid does not move its own tiles.
    var onDragTile: ((UUID, NSView, NSEvent) -> Void)?
    /// §3.3a's cross was pressed: the user is finished with the advice.
    var onDismissHint: (() -> Void)?

    /// Whether §3.3a's well is still worth drawing. The grid decides nothing
    /// here — `Settings.showsPinnedTabHint` is the answer and the column asks
    /// it — but an empty grid is the only thing that knows there is room.
    var showsHint = false {
        didSet {
            guard showsHint != oldValue else { return }
            reflow()
        }
    }

    /// Whether the well is what this grid is currently drawing.
    ///
    /// `tabs`, not `settled`: a grid whose only tile is in the air still has a
    /// tile, and advice that appeared for the length of a drag and left again
    /// on the drop would be the third thing moving in that gesture.
    var isHinting: Bool { showsHint && tabs.isEmpty }

    /// A row is being dragged somewhere in the sidebar.
    ///
    /// An empty grid is zero points tall and so cannot be dropped on, which
    /// made pinning the first tab impossible. While a drag is live the grid
    /// opens to one tile's height and draws the slot the tab would land in.
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
            // Put it where it belongs before showing it. A hidden tile is not
            // laid out, so it still carries the frame it had when it was picked
            // up, and the pass that reveals it is animated — so it appeared at
            // its old slot and slid to the new one under the lift that had just
            // settled there.
            if let revealed = oldValue, let tile = tiles[revealed],
               let slot = settled.firstIndex(of: revealed) {
                Tokens.Motion.immediately { tile.frame = slotRect(at: slot) }
            }
            for (id, tile) in tiles { tile.isHidden = id == draggedID }
            // A tile in the air is out of `settled`, so this puts its light out
            // with it rather than leaving a glow round an empty slot.
            relight(blooming: false)
            reflow()
        }
    }

    /// The slot §6.6's lift is currently over, or nil when it is somewhere else
    /// in the sidebar. While it is set the grid lays out with that slot empty —
    /// the tiles step round it — and draws its outline there.
    var dropIndex: Int? {
        didSet {
            guard dropIndex != oldValue else { return }
            hint.isAimedAt = dropIndex != nil
            animatesNextPlacement = true
            reflow()
        }
    }

    /// Not private: `+Light.swift` reads a tile's tab to get its favicon's
    /// tint, for the same reason `+Layout.swift` reads `order` — Swift's
    /// `private` is file-scoped and this class is three files.
    var tabs: [Tab] = []
    /// Keyed by tab, not an array, so a tile survives a pin, an unpin or a
    /// reorder and can animate from where it was to where it belongs. A rebuilt
    /// array of fresh views has nowhere to animate from, which made pinning a
    /// tab a jump-cut.
    private var tiles: [UUID: GlassButton] = [:]
    /// Not private: `EssentialsGridView+Layout.swift` derives the grid's shape
    /// from it. Nothing outside that pair of files reads it.
    var order: [UUID] = []
    var activeTabID: UUID?
    /// §3.3's light, and the tile it is on. One view for the grid, because only
    /// one tile can be the tab you are on. Both are `+Light.swift`'s; see
    /// `tabs`.
    let glow = EssentialGlowView()
    /// §3.3a's well. Built with the grid rather than on demand: it is one view
    /// and it is hidden almost always, which is cheaper than a grid that has to
    /// remember whether it has one.
    private let hint = SidebarPinHintView.tabGrid()
    var litID: UUID?
    /// Set when the grid's contents changed; consumed by the next `layout()`.
    private var animatesNextPlacement = false
    /// Tiles made since the last placement, which have nowhere to come from.
    /// Consumed by `placeContents`; see the comment there.
    private var arriving: Set<UUID> = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // The glow reaches past the tile it is on, and a tile in the top row
        // stands `essentialsVerticalInset` from this view's edge, so clipping
        // here would cut the light off square along the grid's top.
        clipsToBounds = false
        hint.isHidden = true
        hint.onDismiss = { [weak self] in self?.onDismissHint?() }
        addSubview(hint)
        addSubview(glow)
        setAccessibilityLabel("Essentials")
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Content

    /// The tiles, and whether what changed is an edit to this grid or a
    /// different grid entirely.
    ///
    /// A Space switch is the second. A tile that leaves fades out where it
    /// stood, because an unpin that deleted the tile outright read as the tab
    /// being thrown away — but across a Space switch every tile leaves at once,
    /// and the fade would hold the old Space drawn over the new one for a fifth
    /// of a second. `SidebarViewController` already cross-fades the whole
    /// column; the tiles must not add a second transition.
    func show(_ tabs: [Tab], activeTabID: UUID?, replacing: Bool = false) {
        self.activeTabID = activeTabID
        guard tabs != self.tabs else {
            // Icons arrive after the tab does (§4.7), so they are re-read even
            // when the tabs themselves have not changed.
            for tab in tabs {
                guard let tile = tiles[tab.id] else { continue }
                tile.isSelected = tab.id == activeTabID
                if let icon = SidebarIcons.favicon(for: tab) { tile.setImage(icon) }
            }
            // The tabs are the same; which one you are on may not be, and on
            // this path nothing else would notice.
            relight(blooming: true)
            return
        }
        self.tabs = tabs
        rebuild(replacing: replacing)
    }

    private func rebuild(replacing: Bool) {
        // A replacement is the same as the first population: there is no "from"
        // for anything to arrive out of, so nothing arrives — it is simply
        // already there when the column fades up.
        let wasEmpty = order.isEmpty || replacing
        let next = tabs.map(\.id)
        // Gone: faded out where it stood, then dropped. Removing it outright is
        // what made an unpin look like the tile had been deleted off-screen.
        for (id, tile) in tiles where !next.contains(id) {
            tiles.removeValue(forKey: id)
            guard !replacing else {
                tile.removeFromSuperview()
                continue
            }
            Tokens.Motion.animate(Tokens.Motion.tabInsert) { context in
                context.allowsImplicitAnimation = true
                tile.animator().alphaValue = 0
            } completion: {
                MainActor.assumeIsolated { tile.removeFromSuperview() }
            }
        }
        for tab in tabs {
            let tile = tiles[tab.id] ?? makeTile(for: tab, quietly: replacing)
            tiles[tab.id] = tile
            // §3.4a: the icon and name the user chose outrank the site's, and a
            // tile outlives a rename — it is reused across `show`, so this is
            // the only place either can be re-read.
            if let symbol = tab.customSymbolName {
                tile.setSymbol(symbol)
            } else if let icon = SidebarIcons.favicon(for: tab) {
                tile.setImage(icon)
            }
            tile.setAccessibilityLabel(Self.siteName(for: tab))
            tile.isSelected = tab.id == activeTabID
        }
        order = next
        // The first population is the sidebar being built; there is no "from".
        animatesNextPlacement = !wasEmpty
        relight(blooming: !wasEmpty, replacing: replacing)
        reflow()
    }

    /// `quietly` is a tile that is not arriving — the grid it belongs to is
    /// being replaced wholesale, so it is already there when the column comes
    /// back rather than fading up inside it.
    private func makeTile(for tab: Tab, quietly: Bool = false) -> GlassButton {
        let tile = GlassButton(
            shape: Tokens.Metric.essentialsTile,
            symbolName: "globe",
            pointSize: Tokens.Metric.essentialsIcon,
            // §8/§21.1: the site's name, never its URL.
            label: Self.siteName(for: tab),
            // A pinned tile is dormant until it is the tab you are on or the
            // pointer is over it. Glass says "this one"; there is no accent ring
            // anywhere in Luna's chrome.
            glassMode: .dormant
        )
        tile.onActivate = { [weak self] in self?.onActivate?(tab.id) }
        tile.onDragOut = { [weak self] event in self?.onDragTile?(tab.id, tile, event) }
        tile.menuBuilder = { [weak self] in
            guard let self, let actions = menuActions?(tab.id) else { return nil }
            return TabMenu.build(for: tab, isMuted: isMuted?(tab.id) ?? false, actions: actions)
        }
        // Arrives at zero and fades up into its slot over the same spec the
        // list uses for a row arriving, so pinning reads as one movement.
        let arrives = !quietly && !order.isEmpty
        tile.alphaValue = arrives ? 0 : 1
        arriving.insert(tab.id)
        // Under the glow, which was added first and has to stay on top of every
        // tile there will ever be.
        addSubview(tile, positioned: .below, relativeTo: glow)
        if arrives {
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
    /// Twice, the second time on the next tick. The sidebar reads this view's
    /// `intrinsicContentSize` to place everything under it, and a pin or unpin
    /// changes that size from inside work that is already running — a drop
    /// handler, or the completion of the fade that removes a tile. If the
    /// sidebar's layout pass has been and gone by then the grid keeps its old
    /// height: an unpinned tile left it a full row taller than its tiles, with
    /// the list stranded 47 pt below.
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
        tab.listTitle.isEmpty ? URLPillView.domain(of: tab.url) : tab.listTitle
    }

    // MARK: - Layout

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
        hint.isHidden = !isHinting
        if isHinting {
            hint.frame = bounds
                .insetBy(dx: Tokens.Metric.essentialsInset, dy: Tokens.Metric.essentialsVerticalInset)
                .integral
        }
        for (index, id) in settled.enumerated() {
            guard let tile = tiles[id] else { continue }
            // A live drag holds a slot open: everything from it onwards steps
            // along by one, which is the gap the lift drops into.
            let slot = dropIndex.map { index >= $0 ? index + 1 : index } ?? index
            let frame = slotRect(at: slot)
            // A tile that has just been built has nowhere to come from: its
            // frame is the view's origin, the foot of the grid's leading edge,
            // so an animated pass flew it up and across to its slot. That is
            // what a pin looked like — the lift came to rest and a second tile
            // then arrived from the corner to stand in it. It lands where it
            // belongs and fades up there instead; the fade is `makeTile`'s.
            guard arriving.remove(id) == nil else {
                Tokens.Motion.immediately { tile.frame = frame }
                continue
            }
            tile.frame = frame
        }
        placeGlow()
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
        let dash = Tokens.Metric.pinHintDash
        path.setLineDash(dash, count: dash.count, phase: 0)
        Tokens.Line.border.setStroke()
        path.stroke()
    }

    /// Which slot the outline goes round: the one a lift is over, or — with
    /// nothing pinned yet and a drag in the air — the first one.
    private var outlinedSlot: NSRect? {
        // §3.3a's well is already a dashed box saying a tab goes here, and it
        // fills under the lift. A second outline inside it would be two marks
        // for one slot.
        guard !isHinting else { return nil }
        if let dropIndex { return slotRect(at: dropIndex) }
        return isAwaitingDrop && settled.isEmpty ? slotRect(at: 0) : nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// What §6.6's lift should look like while it is carrying `id` — the same
    /// title and favicon a list row would draw for that tab, because down there
    /// it is a list row.
    func content(for id: UUID) -> SidebarRowContent? {
        guard let tab = tabs.first(where: { $0.id == id }) else { return nil }
        return SidebarRowContent(
            title: Self.siteName(for: tab),
            symbolName: tab.customSymbolName ?? SidebarRowContent.siteFallbackSymbol,
            favicon: tab.customSymbolName == nil ? SidebarIcons.favicon(for: tab) : nil
        )
    }
}
