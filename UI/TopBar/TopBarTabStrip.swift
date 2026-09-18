//
//  TopBarTabStrip.swift
//  Luna
//
//  §4: **tabs are visible in the sidebar-off layout.** Inactive tabs are 28 pt
//  icon-only tiles; the active tab expands into the URL pill. That is why tiles
//  appear on both sides of the pill and why the pill is not window-centred —
//  the strip is one ordered run and the pill is simply the wide element in it.
//  (This supersedes §30.12, which claimed tabs are invisible here.)
//
//  The strip scrolls horizontally when it overflows and the active tab is
//  always scrolled back into view. An `NSScrollView` does the scrolling: it
//  already has the elastic bounce, the trackpad handling and the 120 fps path
//  §19.1 asks for, and a hand-rolled clipper would have none of them.
//
//  **Where the run sits in the bar is `Settings.tabsPosition`**, and it is
//  centred by default. The strip spans everything between Back and the
//  separator, so "centred" means centred in *that* span rather than in the
//  window: the two clusters it sits between are different widths, and a run
//  centred on the window would be visibly off-centre between them — which is
//  the thing the eye actually measures. When the tabs overflow the span the
//  alignment stops meaning anything and the run scrolls from its leading edge.
//
//  Tiles are icon-only, so §8 and §21.1 require an explicit VoiceOver label —
//  the page title, or the site name when there is no title, **never the URL**.
//  The strip itself is a tab list and each item carries its position and count.
//

import AppKit
import BrowserKit

@MainActor
final class TopBarTabStrip: NSView {

    private let session: BrowserSession
    private let scrollView = NSScrollView()
    private let content = StripContentView()
    private let pill = TopBarURLPill()

    private var tiles: [UUID: TopBarButton] = [:]
    private var order: [UUID] = []
    private var activeID: UUID?
    private var scrolledTo: UUID?
    /// Set by `reload()` when the active tab changed, consumed by the next
    /// `layout()`. See `placeContents`.
    private var animatesNextPlacement = false
    /// §4's alignment, cached rather than read per layout pass.
    private var tabsPosition = Settings.tabsPosition(in: .topBar)

    init(session: BrowserSession) {
        self.session = session
        super.init(frame: .zero)

        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .allowed
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

        pill.onNavigate = { [weak self] url in self?.session.load(url) }
        // Search is the Command Bar's surface (§9.1), not the pill's, and
        // `presentCommandBar` is already the way in.
        pill.onSearch = { [weak self] text in self?.session.presentCommandBar?(.search(text)) }
        content.addSubview(pill)

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

    /// Re-reads the tab list. Tiles are reused across reloads so a title or
    /// favicon update does not rebuild the strip.
    func reload() {
        let tabs = session.tabs
        let previousActive = activeID
        order = tabs.map(\.id)
        activeID = session.activeTabID
        // A switch between two tabs is the one reload worth animating: the
        // outgoing tab collapses from pill to tile and the incoming one
        // expands. A first load, or a tab arriving or leaving, is not — there
        // is no "from" to slide out of.
        let isSwitch = previousActive != nil && activeID != nil && previousActive != activeID
        animatesNextPlacement = isSwitch
        // Every reload re-honours §4's "the active tab is always scrolled into
        // view"; live title changes arrive through `apply(_:for:)` instead and
        // do not fight the user's own scrolling.
        scrolledTo = nil

        for (id, tile) in tiles where !order.contains(id) {
            tile.removeFromSuperview()
            tiles.removeValue(forKey: id)
        }
        // Where the two views that swap roles should start from, so the swap
        // reads as one shape growing and another shrinking rather than as two
        // views teleporting past each other.
        var pillSeed: NSRect?
        let pillWas = pill.frame
        for (index, tab) in tabs.enumerated() {
            let help = Self.position(index, of: tabs.count)
            if tab.id == activeID {
                if let stale = tiles.removeValue(forKey: tab.id) {
                    pillSeed = stale.frame
                    stale.removeFromSuperview()
                }
                pill.setAccessibilityHelp(help)
                applyActive(state(for: tab), id: tab.id)
            } else {
                let fresh = tiles[tab.id] == nil
                configureTile(for: tab, help: help)
                // The tab that just stopped being active: its tile is brand new
                // and belongs where the pill is standing right now.
                if isSwitch, fresh, tab.id == previousActive, let tile = tiles[tab.id] {
                    Tokens.Motion.immediately { tile.frame = pillWas }
                }
            }
        }
        pill.isHidden = activeID == nil
        if isSwitch, let pillSeed {
            Tokens.Motion.immediately { pill.frame = pillSeed }
        }
        needsLayout = true
    }

    /// One tab's live state (title, `themeColor`) without a full reload.
    func apply(_ state: TabState, for id: UUID) {
        guard id != activeID else { return applyActive(state, id: id) }
        guard let tile = tiles[id] else { return }
        let title = state.title.isEmpty ? TopBarDomain.display(for: state.url) : state.title
        tile.setAccessibilityLabel(title)
        tile.toolTip = title
        tile.icon = session.favicon(for: id) ?? TopBarButton.symbol("globe")
    }

    /// `⌘L` (§20.1).
    func beginURLEditing() {
        pill.beginEditing()
    }

    private func applyActive(_ state: TabState, id: UUID) {
        pill.apply(
            url: state.url,
            icon: session.favicon(for: id),
            tint: state.themeColor.map { NSColor($0) }
        )
    }

    /// The live state when the tab is warm, the persisted row when it is not —
    /// §19.2's whole point is that a hibernated tab still renders without
    /// costing a web view.
    private func state(for tab: Tab) -> TabState {
        session.controller(for: tab.id)?.state
            ?? TabState(url: tab.url, title: tab.title, themeColor: tab.themeColor)
    }

    // MARK: - Tiles

    private func configureTile(for tab: Tab, help: String) {
        let tile = tiles[tab.id] ?? makeTile(tab.id)
        tiles[tab.id] = tile
        tile.icon = session.favicon(for: tab.id) ?? TopBarButton.symbol("globe")
        let label = tab.title.isEmpty ? TopBarDomain.display(for: tab.url) : tab.title
        tile.setAccessibilityLabel(label)
        tile.setAccessibilityHelp(help)
        tile.toolTip = label
    }

    private func makeTile(_ id: UUID) -> TopBarButton {
        let tile = TopBarButton(metric: TopBarMetrics.tile, glass: false)
        tile.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
        tile.setAccessibilityRole(.radioButton)
        tile.target = self
        tile.action = #selector(tilePressed)
        content.addSubview(tile)
        return tile
    }

    @objc private func tilePressed(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        session.activateTab(id)
    }

    private static func position(_ index: Int, of count: Int) -> String {
        String(localized: "Tab \(index + 1) of \(count)")
    }

    // MARK: - Geometry

    /// Bounds-derived frames never animate — see `Motion.immediately` — with
    /// one exception: the frame a tab's view lands on is bounds-derived *and*
    /// role-derived, and when the role changed, the move from the old frame to
    /// the new one is exactly the thing that should be seen. §4's strip is one
    /// ordered run and the pill is the wide element in it, so a switch slides
    /// every tile after it along; without this it all jumped.
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

    /// The clear run in front of the first tile, which is what the alignment
    /// actually is.
    ///
    /// It is padding *inside* the document view rather than an offset applied
    /// to it: a document narrower than its clip view is anchored at the clip's
    /// leading edge and stays there whatever origin it is given, so the space
    /// has to be part of the content for the scroll view to keep honouring it.
    private var leadingPad: CGFloat {
        let total = contentWidth
        let span = bounds.width
        guard total < span else { return 0 }
        return switch tabsPosition {
        case .left: 0
        case .centre: ((span - total) / 2).rounded()
        case .right: span - total
        }
    }

    /// The run's own width — every tile plus the pill, with a gap between.
    private var contentWidth: CGFloat {
        let gap = TopBarMetrics.gap
        let total = order.reduce(CGFloat.zero) { running, id in
            running + (id == activeID ? Tokens.Metric.urlPill.width : TopBarMetrics.tile.width) + gap
        }
        return max(total - gap, 0)
    }

    private func placeContents() {
        let height = bounds.height
        var originX = leadingPad
        var activeFrame: NSRect?

        for id in order {
            let isActive = id == activeID
            let candidate: NSView? = isActive ? pill : tiles[id]
            guard let view = candidate else { continue }
            let size = isActive ? Tokens.Metric.urlPill.size : TopBarMetrics.tile.size
            let frame = NSRect(
                x: originX,
                y: ((height - size.height) / 2).rounded(),
                width: size.width,
                height: size.height
            )
            view.frame = frame
            if isActive { activeFrame = frame }
            originX += size.width + TopBarMetrics.gap
        }

        content.frame = NSRect(
            x: 0,
            y: 0,
            width: max(originX - TopBarMetrics.gap, 0),
            height: height
        )

        guard let activeFrame, activeID != scrolledTo else { return }
        scrolledTo = activeID
        // A gap of slack on each side, so the active tab never lands flush
        // against a clipped neighbour.
        content.scrollToVisible(activeFrame.insetBy(dx: -TopBarMetrics.gap, dy: 0))
    }
}

/// The scroll view's document view. Dragging the empty part of the strip drags
/// the window (§4) — the tiles and the pill opt out for themselves.
private final class StripContentView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}
