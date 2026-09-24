//
//  TopBarTabStrip.swift
//  Luna
//
//  §4: the tab list, along a bar instead of down a column — drawn with the
//  column's own parts.
//
//  Kept tabs are §3.3's tiles: `GlassButton` in the grid's shape, dormant until
//  the pointer or the selection reaches it, with the grid's well, hairline and
//  swell, and the tile you are on lit by the same `EssentialGlowView` in its
//  site's own colour. Open tabs and folders' headers are §3.4's rows:
//  `SidebarRowView` itself, with the column's two `RowPillView`s — the
//  selected one and the hover one — sliding between them on the column's own
//  springs. Nothing on the bar is a copy of something in the sidebar; it is the
//  sidebar's thing, standing somewhere else.
//
//  Two runs: kept on the left, on one plate of glass headed by the Space's
//  name, and open on the right. `TopBarStripRun` holds the arrangement and
//  where a drop lands; the frames are `+Layout`, the pills and the pointer
//  `+Pills`.
//
//  A folder's tabs follow its header along the run, past a hairline divider,
//  and an open-tier folder stands on a plate of its own, as the kept run
//  stands on the Space's: the folder is one object on the bar. Folded and
//  open are the column's own `isCollapsed`.
//
//  The strip scrolls horizontally when it overflows and the active tab is
//  always scrolled back into view. An `NSScrollView` does the scrolling: it
//  already has the elastic bounce, the trackpad handling and the 120 fps path
//  §19.1 asks for, and a hand-rolled clipper would have none of them.
//
//  Where the run sits in the bar is `Settings.tabsPosition`, centred by
//  default, centred on the bar rather than on the strip's own span — see
//  `TopBarTabRun`.
//
//  Right-clicking opens the column's own menus — §3.4a on a tab, §3.4b on a
//  folder — from the same bindings on `BrowserSession`. A name is asked for in
//  a dialog rather than typed on the row: a bar row is as wide as its title,
//  and there is no room past the end of it to type a longer one.
//

import AppKit
import BrowserKit

/// What §6.6's lift is carrying off the bar.
enum TopBarLifted: Equatable, Sendable {
    case tab(UUID)
    case group(UUID)

    var id: UUID {
        switch self {
        case let .tab(id), let .group(id): id
        }
    }
}

/// Where the run opens room for a lift: in front of which block, how wide, and
/// what landing there means.
struct DropGap: Equatable {
    var block: Int
    var width: CGFloat
    var destination: SidebarDestination
    /// The lift is over one of the run's landings (`block`), which it fills
    /// rather than opening room beside.
    var fills = false
}

@MainActor
final class TopBarTabStrip: NSView, WindowScoped {

    let session: BrowserSession
    let windowID: UUID
    let scrollView = NSScrollView()
    let content = StripContentView()
    /// §4's plate, and the Space's name at the head of it.
    let plate = TopBarPlate()
    let spaceName = TopBarSpaceName()
    /// §3.4's two fills, one of each for the whole bar.
    let selectionPill = RowPillView(role: .selected)
    let hoverPill = RowPillView(role: .hover)
    /// §3.3's light, one for the whole bar: only one tab can be the one you
    /// are on.
    let glow = EssentialGlowView()
    /// The hairline between the pinned section and today's tabs.
    let rule = TopBarSeparator()
    /// §3.3's dashed slot, where a kept tab is about to land.
    let slot = TopBarSlotOutline()
    /// The dashed row at the end of §3.4b's tier, where a tab dropped starts a
    /// kept folder.
    let folderSlot = TopBarSlotOutline()

    var run = TopBarStripRun()
    var tiles: [UUID: GlassButton] = [:]
    var rows: [UUID: TopBarTabRow] = [:]
    /// Per folder, the hairline after its name, and for an open-tier folder
    /// the plate it stands on.
    var dividers: [UUID: TopBarSeparator] = [:]
    var folderPlates: [UUID: TopBarPlate] = [:]
    var activeID: UUID?
    var hoveredID: UUID?
    /// The Space the run was last read for — see `reload`.
    var shownSpace: UUID?
    /// Which kept tile the light is standing on, or nil for none.
    var litID: UUID?
    var scrolledTo: UUID?
    /// Set by `reload()` when a run already on screen changed, consumed by the
    /// next `layout()`. See `placeContents`.
    var animatesNextPlacement = false
    /// Folders whose tabs are still fading out on their plate — see
    /// `retire`. Their plate and divider stay put until the fade is over.
    var shuttingFolders: Set<UUID> = []
    /// §4's alignment, cached rather than read per layout pass.
    var tabsPosition = Settings.tabsPosition(in: .topBar)

    // MARK: - §6.6's drag

    /// The tab or folder in the air. The run is rebuilt without it for the
    /// length of the gesture, so what is drawn is what a drop would leave —
    /// and so the drop index is the one `reorderTab` counts.
    var liftedID: UUID? {
        didSet {
            guard liftedID != oldValue else { return }
            // The run holds still under the hand. A centred run would otherwise
            // re-centre the moment its lifted tab left it, sliding every tab
            // half that tab's width under the pointer — so the drop landed one
            // place off from where it was aimed. The column never has this: its
            // list hangs from the top.
            frozenStart = liftedID == nil ? nil : lastStart
            reload()
            movePills()
        }
    }

    /// Where the run started on the last pass, and the start held for the
    /// length of a drag — see `liftedID`.
    var lastStart: CGFloat = 0
    var frozenStart: CGFloat?

    /// Where the gap opens and how wide it is — the lift's own width, so the
    /// run makes exactly the room the thing in the air will take.
    var dropGap: DropGap? {
        didSet {
            guard dropGap != oldValue else { return }
            animatesNextPlacement = true
            needsLayout = true
        }
    }

    /// The empty places the run offers while a lift is near the plate — see
    /// `TopBarStripRun.init`'s `landings`. Empty in a §5.6 window, which keeps
    /// nothing.
    var landings: Set<TabKind> = [] {
        didSet {
            guard landings != oldValue else { return }
            reload()
        }
    }

    /// The folder a drop would land inside.
    var dropFolder: UUID? {
        didSet {
            guard dropFolder != oldValue else { return }
            needsLayout = true
        }
    }

    /// Where the plate stands, in `content`'s coordinates — its target, for
    /// `targets`' reason.
    var plateFrame: NSRect = .zero
    /// Where the pinned section ends — the Space's plate and the kept
    /// folders beside it — in `content`'s coordinates.
    var keptEnd: CGFloat = 0
    /// Where the gap was laid, in `content`'s coordinates — what the lift
    /// comes to rest on.
    var gapFrame: NSRect?
    /// Every block's frame with no gap open, in `content`'s coordinates —
    /// what a pointer is resolved against.
    var blockFrames: [NSRect] = []
    /// Where the last pass put each tile and row. Read instead of their
    /// `frame`, which during an animated pass is still on its way there: a
    /// pill sent to a row's `frame` then would chase where the row was.
    var targets: [UUID: NSRect] = [:]

    /// What a press becomes once it moves: §6.6's lift, which
    /// `TopBarTabDragController` runs. Handed the view the gesture started on
    /// and the press itself, so the lift rises from exactly where it stood.
    var onDrag: ((TopBarLifted, NSView, NSEvent) -> Void)?

    init(session: BrowserSession, windowID: UUID) {
        self.session = session
        self.windowID = windowID
        super.init(frame: .zero)

        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        // Only when there is something to scroll. A run that fits bounced
        // under a two-finger swipe and could be left a few points along,
        // which stood the plate that much closer to the traffic lights.
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.verticalScrollElasticity = .none
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.documentView = content
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        content.setAccessibilityRole(.tabGroup)
        content.setAccessibilityLabel(String(localized: "Tabs"))
        // Bottom to top: the plate, the fills, then the marks, then the name
        // and the tabs as they arrive, and the light over all of them.
        //
        // The name above the fills and marks, not under them. They take no
        // click, but the window server's map of where a press moves the
        // window is built from frames and `mouseDownCanMoveWindow`, not from
        // `hitTest` — so a parked pill lying over the name made a press on
        // the name drag the window. The tabs were never under them.
        for view in [plate, rule, selectionPill, hoverPill, slot, folderSlot, spaceName, glow] as [NSView] {
            content.addSubview(view)
        }
        for pill in [selectionPill, hoverPill] { pill.alphaValue = 0 }
        folderSlot.symbolName = "folder.badge.plus"
        // Concentric with the plate, whose edge the ring stands on.
        glow.cornerRadius = TopBarMetrics.keptTile.cornerRadius + glowOutset
        content.menuBuilder = { [weak self] in self?.emptyMenu() }
        plate.menuBuilder = { [weak self] in self?.emptyMenu() }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: Settings.didChange,
            object: nil
        )
    }

    @objc private func settingsDidChange() {
        let position = Settings.tabsPosition(in: .topBar)
        guard position != tabsPosition else { return }
        tabsPosition = position
        needsLayout = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code")
    }

    // MARK: - Session

    /// Re-reads the tab list.
    func reload() {
        let previousActive = activeID
        run = TopBarStripRun(
            essentials: windowEssentials,
            saved: windowSlots(inTier: .pinned),
            today: windowSlots(inTier: .today),
            excluding: liftedID,
            landings: landings
        )
        activeID = activeTabID
        // Taken on arrival as well as listened to (`TopBarView`), so a tab
        // selected again shows where it was left.
        setScrollProgress(activeID.flatMap { session.controller(for: $0)?.scrollProgress })
        // Every change to a run already on screen slides into place: a switch,
        // a tab arriving or closing, a folder opening, a drop. A Space switch
        // does not — that is a different run, not this one moving — and nor
        // does the first pass, which has no "from" to slide out of.
        let space = activeSpaceID
        let onScreen = shownSpace == space && !(tiles.isEmpty && rows.isEmpty)
        animatesNextPlacement = onScreen
        shownSpace = space
        // Every reload re-honours §4's "the active tab is always scrolled into
        // view"; live title changes arrive through `apply(_:for:)` instead and
        // do not fight the user's own scrolling.
        scrolledTo = nil

        var live: Set<UUID> = []
        for block in run.blocks {
            switch block {
            case let .tab(tab, .tile):
                live.insert(tab.id)
                configureTile(tab, arriving: onScreen)
            case let .tab(tab, .row):
                live.insert(tab.id)
                configureRow(for: tab, arriving: onScreen)
            case let .group(group, _):
                live.insert(group.id)
                configureRow(for: group, arriving: onScreen)
            case .rule, .landing:
                break
            }
        }
        retire(keeping: live, animated: onScreen)
        relight(blooming: previousActive != nil && previousActive != activeID)
        needsLayout = true
    }

    /// One tab's live state (title, favicon, loading, sound) without a full
    /// reload.
    func apply(_ state: TabState, for id: UUID) {
        if let tab = session.tab(id), rows[id] != nil {
            rows[id]?.configure(rowContent(for: tab))
            needsLayout = true
        } else if let tile = tiles[id], let icon = session.favicon(for: id) {
            tile.setImage(icon)
        }
    }

    /// §3.3's light, on the kept tile that is the tab this window is showing —
    /// and only a kept one: an open tab says it is the current one with §3.4's
    /// pill, and a site's glow round a row wearing that pill would be the same
    /// sentence twice in two colours.
    private func relight(blooming: Bool) {
        let lit = activeID.flatMap { id in run.keptTab(id) }
        let moved = lit?.id != litID
        litID = lit?.id
        placeGlow()
        glow.show(lit.map(FaviconTint.glow(for:)), blooming: blooming && moved && lit != nil)
    }

    // MARK: - Kept tiles

    private func configureTile(_ tab: Tab, arriving: Bool) {
        let tile = tiles[tab.id] ?? makeTile(for: tab.id, arriving: arriving)
        tiles[tab.id] = tile
        // §3.4a: the icon the user chose outranks the site's — the grid's rule.
        if let symbol = tab.customSymbolName {
            tile.setSymbol(symbol)
        } else if let icon = session.icons.favicon(for: tab.url) ?? session.favicon(for: tab.id) {
            tile.setImage(icon)
        }
        let name = tab.listTitle.isEmpty ? URLPillView.domain(of: tab.url) : tab.listTitle
        tile.setAccessibilityLabel(name)
        tile.setAccessibilityHelp(position(of: tab.id))
        tile.toolTip = name
        tile.isSelected = tab.id == activeID
        tile.onActivate = { [weak self] in self?.activateTab(tab.id) }
        tile.onDragOut = { [weak self, weak tile] press in
            guard let self, let tile else { return }
            // Picking a tile up is choosing it, as a row's press is.
            activateTab(tab.id)
            onDrag?(.tab(tab.id), tile, press)
        }
        tile.menuBuilder = { [weak self] in self?.tabMenu(tab.id) }
    }

    private func makeTile(for id: UUID, arriving: Bool) -> GlassButton {
        let tile = GlassButton(
            shape: TopBarMetrics.keptTile,
            symbolName: SidebarRowContent.siteFallbackSymbol,
            pointSize: Tokens.Metric.essentialsIcon,
            label: "",
            // §3.3: dormant until it is the tab you are on or the pointer is
            // over it. Glass says "this one".
            glassMode: .dormant
        )
        tile.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
        tile.showsWell = false
        content.addSubview(tile, positioned: .below, relativeTo: glow)
        if arriving { fadeIn(tile) }
        return tile
    }

    // MARK: - Arriving and leaving

    /// A tab arriving fades up into its place on §6's `tabInsert`, the column's
    /// spec for a row arriving, so opening one reads as one movement.
    func fadeIn(_ view: NSView) {
        guard !Tokens.Motion.reduceMotion else { return }
        view.alphaValue = 0
        Tokens.Motion.animate(Tokens.Motion.tabInsert) { context in
            context.allowsImplicitAnimation = true
            view.animator().alphaValue = 1
        }
    }

    override func layout() {
        super.layout()
        layOutRun()
    }

    // MARK: - Shared

    /// §3.4b's one item for the bar's empty part: a folder, which is the one
    /// thing that needs no tab to exist. The column's own menu for its empty
    /// part.
    func emptyMenu() -> NSMenu {
        GroupMenu.plane { [weak self] in
            self?.session.createGroup(name: BrowserSession.untitledGroupName)
        }
    }

    func tabMenu(_ id: UUID) -> NSMenu? {
        guard let current = session.tab(id) else { return nil }
        return TabMenu.build(for: current, isMuted: session.isMuted(id), actions: session.tabMenuActions(for: id))
    }

    func position(of id: UUID) -> String {
        let index = run.tabs.firstIndex { $0.id == id } ?? 0
        return String(localized: "Tab \(index + 1) of \(run.tabs.count)")
    }
}

// MARK: - Leaving

extension TopBarTabStrip {

    /// Gone: faded out where it stood, then dropped — the grid's rule, because
    /// removing it outright read as the tab having been deleted off-screen.
    func retire(keeping live: Set<UUID>, animated: Bool) {
        let (gone, goneRows) = takeLeaving(keeping: live)
        if let hoveredID, !live.contains(hoveredID) { self.hoveredID = nil }
        // A tab in the air is out of the run but not gone, and the lift is
        // standing in for it: it goes at once, or it would fade out behind the
        // lift that has just picked it up.
        guard animated, liftedID == nil, !Tokens.Motion.reduceMotion else {
            for view in gone { view.removeFromSuperview() }
            return
        }
        // Behind everything still on the bar, so what slides in over the
        // place it leaves covers it as it fades. On top, a folder's tabs lay
        // over the tabs sliding in.
        for view in gone { content.addSubview(view, positioned: .below, relativeTo: selectionPill) }
        // A folder shutting is its opening played backwards. Opening, the
        // plate is at its full width at once — glass does not animate its
        // shape — and the tabs fade in on it while the run slides. So
        // shutting, the plate keeps its width while the tabs fade out and the
        // run slides, and takes the name's size as they finish. Shrunk first,
        // it left the tabs flashing out on the bare bar.
        let shutting = foldersShutting(leaving: goneRows, live: live)
        shuttingFolders.formUnion(shutting)
        Tokens.Motion.animate(Tokens.Motion.tabInsert) { context in
            context.allowsImplicitAnimation = true
            for view in gone + shutting.compactMap({ self.dividers[$0] }) { view.animator().alphaValue = 0 }
        } completion: { [weak self] in
            MainActor.assumeIsolated {
                for view in gone { view.removeFromSuperview() }
                guard let self, !shutting.isEmpty else { return }
                self.shuttingFolders.subtract(shutting)
                for id in shutting { self.dividers[id]?.alphaValue = 1 }
                self.needsLayout = true
            }
        }
    }

    /// Everything not in `live`, out of the strip's tables: the views to fade
    /// and which of them were rows.
    private func takeLeaving(keeping live: Set<UUID>) -> ([NSView], [UUID]) {
        var gone: [NSView] = []
        for (id, tile) in tiles where !live.contains(id) {
            tiles.removeValue(forKey: id)
            gone.append(tile)
        }
        let goneRows = rows.keys.filter { !live.contains($0) }
        for id in goneRows { rows.removeValue(forKey: id).map { gone.append($0) } }
        for (id, divider) in dividers where !live.contains(id) {
            dividers.removeValue(forKey: id)
            divider.removeFromSuperview()
        }
        for (id, folderPlate) in folderPlates where !live.contains(id) {
            folderPlates.removeValue(forKey: id)
            gone.append(folderPlate)
        }
        return (gone, goneRows)
    }

    /// The folders whose tabs are all that is leaving — shut, not deleted.
    private func foldersShutting(leaving ids: [UUID], live: Set<UUID>) -> Set<UUID> {
        var folders: Set<UUID> = []
        for id in ids {
            guard let groupID = session.tab(id)?.groupID, live.contains(groupID),
                  session.group(groupID)?.isCollapsed == true
            else { return [] }
            folders.insert(groupID)
        }
        return folders
    }
}
