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
//  **The tile you are on is lit, in that site's own colour.** One glow for the
//  whole grid, because only one tile can be the tab you are on — see
//  `EssentialGlowView` for what it draws and `FaviconTint` for where the colour
//  comes from. It lies *over* the tiles rather than under them and answers no
//  hit test, so the tile underneath still takes the click.
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
    ///
    /// Not private: the arithmetic that spends it lives next door, in
    /// `EssentialsGridView+Layout.swift`.
    static let maxColumns = 4

    var onActivate: ((UUID) -> Void)?
    /// Right-click → Unpin. The tab goes back to the top of today's tabs.
    var onUnpin: ((UUID) -> Void)?
    /// §3.4a's menu for a tile, which is the same menu §3.4's rows get — a tile is a tab.
    /// Nil leaves the tile with no menu at all rather than a shorter one: a second,
    /// smaller answer to the same right-click is the thing this is here to avoid.
    var menuActions: ((UUID) -> TabMenu.Actions?)?
    /// Whether that tab is muted, for the menu's wording.
    var isMuted: ((UUID) -> Bool)?
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
    /// Not private: `EssentialsGridView+Layout.swift` derives the grid's shape
    /// from it. Nothing outside that pair of files reads it.
    var order: [UUID] = []
    private var activeTabID: UUID?
    /// §3.3's light, and the tile it is currently on. One view for the grid:
    /// only one tile can be the tab you are on, and the header above has what
    /// a backing view per tile cost the sidebar the last time one was tried.
    private let glow = EssentialGlowView()
    private var litID: UUID?
    /// Set when the grid's contents changed; consumed by the next `layout()`.
    private var animatesNextPlacement = false
    /// Tiles made since the last placement, which have **nowhere to come from**.
    /// Consumed by `placeContents`; see the comment there.
    private var arriving: Set<UUID> = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // The glow reaches past the tile it is on, and a tile in the top row
        // stands `essentialsVerticalInset` from this view's own edge — so
        // clipping here would cut the light off square along the grid's top.
        clipsToBounds = false
        addSubview(glow)
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
            // The tabs are the same; which one you are *on* may not be, and on
            // this path nothing else would notice.
            relight(blooming: true)
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
            // §3.4a: the icon and the name the user chose outrank the site's, and a tile
            // outlives a rename — it is reused across `show`, so this is the only place
            // either can be re-read.
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
        relight(blooming: !wasEmpty)
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
            guard let self, let actions = menuActions?(tab.id) else { return nil }
            return TabMenu.build(for: tab, isMuted: isMuted?(tab.id) ?? false, actions: actions)
        }
        // Arrives at zero and fades up into its slot over the same spec the
        // list uses for a row arriving, so pinning reads as one movement.
        tile.alphaValue = order.isEmpty ? 1 : 0
        arriving.insert(tab.id)
        // Under the glow, which was added first and has to stay on top of every
        // tile there will ever be.
        addSubview(tile, positioned: .below, relativeTo: glow)
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
        tab.listTitle.isEmpty ? URLPillView.domain(of: tab.url) : tab.listTitle
    }

    // MARK: - The light

    /// Lights the pinned tile that is the tab you are on, and puts out the one
    /// that was.
    ///
    /// - Parameter blooming: whether this pass could have come from a click.
    ///   §3.3's glow *appears*, and the appear belongs to the press that caused
    ///   it: the pass that builds the sidebar has to arrive with the light
    ///   already on, and a refresh that leaves the same tile lit must not
    ///   replay it — which is why the tile has to have changed as well.
    private func relight(blooming: Bool) {
        let lit = activeTabID.flatMap { settled.contains($0) ? $0 : nil }
        let moved = lit != litID
        litID = lit
        // **Stood in the right place before it is lit**, or the pop plays at
        // the tile you came *from* and the light teleports afterwards: the
        // layout pass that would otherwise place it does not run until later
        // in the loop, and the appear starts here.
        placeGlow()
        glow.show(lit.flatMap(tint(for:)), blooming: blooming && moved && lit != nil)
    }

    /// Where the light stands: its tile's slot, or nowhere.
    private var litSlot: NSRect? {
        guard let litID, let index = settled.firstIndex(of: litID) else { return nil }
        // A live drag holds a slot open, exactly as it does for the tiles.
        let slot = dropIndex.map { index >= $0 ? index + 1 : index } ?? index
        return slotRect(at: slot)
    }

    /// **The light never travels.** It is one view moved between tiles, so an
    /// animated pass — a pin, an unpin, a reorder — would slide it across the
    /// grid from the tile you left to the tile you clicked, and that slide is
    /// the thing this is not: the glow goes out where it was and appears where
    /// it now is. Always immediate, inside an animated pass or out of one.
    private func placeGlow() {
        guard let frame = litSlot else { return }
        Tokens.Motion.immediately { glow.frame = frame }
    }

    /// The colour a tile glows in: the site's own, out of its favicon.
    private func tint(for id: UUID) -> NSColor? {
        tabs.first { $0.id == id }.map(FaviconTint.glow(for:))
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
        for (index, id) in settled.enumerated() {
            guard let tile = tiles[id] else { continue }
            // A live drag holds a slot open: everything from it onwards steps
            // along by one, which is the gap the lift drops into.
            let slot = dropIndex.map { index >= $0 ? index + 1 : index } ?? index
            let frame = slotRect(at: slot)
            // **A tile that has just been built has nowhere to come from.** It
            // is a fresh `NSView`, so its frame is the view's origin — the foot
            // of the grid's leading edge — and an animated pass therefore flew
            // it up and across to its slot. That is what a pin looked like: the
            // lift came to rest in the right place and a second tile then
            // arrived from the corner to stand in it. It lands where it belongs
            // and fades up there instead; the fade is `makeTile`'s.
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

    /// What §6.6's lift should look like while it is carrying `id` — the same
    /// title and favicon a list row would draw for that tab, because down there
    /// it *is* a list row.
    func content(for id: UUID) -> SidebarRowContent? {
        guard let tab = tabs.first(where: { $0.id == id }) else { return nil }
        return SidebarRowContent(
            title: Self.siteName(for: tab),
            symbolName: tab.customSymbolName ?? SidebarRowContent.siteFallbackSymbol,
            favicon: tab.customSymbolName == nil ? SidebarIcons.favicon(for: tab) : nil
        )
    }
}
