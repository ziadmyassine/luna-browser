//
//  TopBarTabStrip.swift
//  Luna
//
//  §4: the tab list, along a bar instead of down a column. It draws everything
//  §3.4's list draws — §3.3's tiles, §3.4b's kept tier, its folders, and the
//  day's tabs — in one run, with a hairline where the column has its rule.
//
//  Two shapes and one rule between them: a kept tab is a bare icon, an open one
//  carries its title. `TopBarStripRun` holds the arrangement and the reasons
//  for it; this file is the views, their frames, and the scrolling.
//
//  A folder stands on a plate (`TopBarGroupPlate`) and grows along the bar when
//  it is opened, which is the horizontal answer to the column's indentation:
//  the tabs in a folder are the ones standing on its plate. Folded and open are
//  the same `isCollapsed` the column writes, so a folder is open in both
//  layouts or shut in both.
//
//  The strip scrolls horizontally when it overflows and the active tab is
//  always scrolled back into view. An `NSScrollView` does the scrolling: it
//  already has the elastic bounce, the trackpad handling and the 120 fps path
//  §19.1 asks for, and a hand-rolled clipper would have none of them.
//
//  Where the run sits in the bar is `Settings.tabsPosition`, centred by
//  default. The strip only owns what is left between Back and the separator,
//  and those clusters are nothing like the same width — one capsule item on the
//  left, four and a separator on the right — so a run centred in the strip's
//  own span sat 25 pt off the window's middle. Centred means centred in the
//  bar, which is the line the eye measures against. Once the tabs overflow the
//  span the alignment stops meaning anything and the run scrolls from its
//  leading edge.
//
//  Right-clicking a tab opens §3.4a's menu and right-clicking a folder opens
//  §3.4b's, from the same bindings on `BrowserSession` the column uses. The
//  layout you are in does not change what you can do to a tab. The one
//  difference is where a name is typed: the column types it on the row, and
//  this asks in a dialog, because a chip is not a line of text there is room to
//  type on.
//
//  There is no address bar in this run any more. It used to be here — the
//  active tab swelled into a URL pill and every other tab was an icon — and
//  that could not survive tabs that carry their own titles: the pill was a
//  fourth shape among three, and the run jumped a pill's width every time the
//  selection moved. `⌘L` opens §9.1's bar over the page instead, which is the
//  same field with the same history behind it.
//

import AppKit
import BrowserKit

@MainActor
final class TopBarTabStrip: NSView, WindowScoped {

    let session: BrowserSession
    let windowID: UUID
    let scrollView = NSScrollView()
    let content = StripContentView()
    let rule = TopBarSeparator()
    let cylinder = TopBarKeptCylinder()
    /// §3.3's light, one for the whole strip: only one tab can be the one you
    /// are on, so only one kept chip can be lit.
    let glow = EssentialGlowView()

    var run = TopBarStripRun()
    /// Every chip on the bar, by the id of the tab or folder it draws. Reused
    /// across reloads so a title or favicon update does not rebuild the strip.
    var chips: [UUID: TopBarButton] = [:]
    var plates: [UUID: TopBarGroupPlate] = [:]
    var activeID: UUID?
    /// Which kept chip the light is standing on, or nil for none.
    var litID: UUID?
    var scrolledTo: UUID?
    /// Set by `reload()` when the active tab changed, consumed by the next
    /// `layout()`. See `placeContents`.
    var animatesNextPlacement = false
    /// §4's alignment, cached rather than read per layout pass.
    var tabsPosition = Settings.tabsPosition(in: .topBar)

    init(session: BrowserSession, windowID: UUID) {
        self.session = session
        self.windowID = windowID
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
        content.addSubview(cylinder)
        content.addSubview(rule)
        glow.cornerRadius = TopBarMetrics.tile.cornerRadius
        content.addSubview(glow)

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
            today: windowSlots(inTier: .today)
        )
        activeID = activeTabID
        // A switch between two tabs is the one reload worth animating: the
        // plate a folder stands on grows or shrinks, and the tabs after it
        // slide along. A first load, or a tab arriving or leaving, is not —
        // there is no "from" to slide out of.
        animatesNextPlacement = previousActive != nil && activeID != nil && previousActive != activeID
        // Every reload re-honours §4's "the active tab is always scrolled into
        // view"; live title changes arrive through `apply(_:for:)` instead and
        // do not fight the user's own scrolling.
        scrolledTo = nil

        var live: Set<UUID> = []
        for block in run.blocks {
            switch block {
            case let .tab(tab, style):
                live.insert(tab.id)
                configure(tab, style: style)
            case let .group(group, members, style):
                live.insert(group.id)
                configure(group, memberCount: members.count)
                for member in members {
                    live.insert(member.id)
                    configure(member, style: style)
                }
            case .rule:
                break
            }
        }
        retire(keeping: live)
        rule.isHidden = !run.blocks.contains(.rule)
        cylinder.isHidden = run.kept == 0
        relight(blooming: previousActive != nil && previousActive != activeID)
        needsLayout = true
    }

    /// §3.3's light, on the kept chip that is the tab this window is showing.
    ///
    /// Only a kept one. An open tab already says it is the current one with
    /// §3.4's plate, and a site's glow around a chip carrying that plate as
    /// well would be the same sentence twice in two different colours.
    private func relight(blooming: Bool) {
        let lit = activeID.flatMap { id in run.keptTab(id) }
        let moved = lit?.id != litID
        litID = lit?.id
        placeGlow()
        glow.show(lit.map(FaviconTint.glow(for:)), blooming: blooming && moved && lit != nil)
    }

    /// One tab's live state (title, `themeColor`) without a full reload.
    func apply(_ state: TabState, for id: UUID) {
        guard let chip = chips[id], let tab = session.tab(id) else { return }
        let title = tab.listTitle.isEmpty ? TopBarDomain.display(for: state.url) : tab.listTitle
        chip.setAccessibilityLabel(title)
        chip.toolTip = title
        if chip.titleText != nil { chip.titleText = title }
        chip.icon = tab.customSymbolName.flatMap(TopBarButton.symbol)
            ?? session.favicon(for: id)
            ?? TopBarButton.symbol("globe")
        needsLayout = true
    }

    // MARK: - Chips

    private func configure(_ tab: Tab, style: TopBarTabStyle) {
        let chip = chip(for: tab.id, metric: style == .icon ? TopBarMetrics.tile : TopBarMetrics.chip)
        // §3.4a: the icon and the name the user chose outrank the site's.
        chip.icon = tab.customSymbolName.flatMap(TopBarButton.symbol)
            ?? session.favicon(for: tab.id)
            ?? TopBarButton.symbol("globe")
        let label = tab.listTitle.isEmpty ? TopBarDomain.display(for: tab.url) : tab.listTitle
        // Icon-only, so §8 and §21.1 require the label spelled out — the page
        // title, or the site name when there is no title, never the URL.
        chip.setAccessibilityLabel(label)
        chip.setAccessibilityRole(.radioButton)
        chip.setAccessibilityHelp(position(of: tab.id))
        chip.toolTip = label
        chip.titleText = style == .chip ? label : nil
        // A kept chip says it is the current tab with §3.3's light instead —
        // see `relight`.
        chip.isSelected = style == .chip && tab.id == activeID
        chip.target = self
        chip.action = #selector(tabPressed)
        // The tab is re-read inside the closure rather than captured: a chip is
        // reused across reloads, so the `tab` this pass was configured from is a
        // snapshot and the menu has to state what is true when it opens.
        chip.menuBuilder = { [weak self] in
            guard let self, let current = session.tab(tab.id) else { return nil }
            return TabMenu.build(
                for: current,
                isMuted: session.isMuted(tab.id),
                actions: session.tabMenuActions(for: tab.id)
            )
        }
    }

    private func configure(_ group: TabGroup, memberCount: Int) {
        let chip = chip(for: group.id, metric: TopBarMetrics.chip)
        chip.icon = RowEmoji.image(group.symbolName, pointSize: TopBarMetrics.glyph)
            ?? TopBarButton.symbol(group.symbolName)
            ?? TopBarButton.symbol(TabGroup.defaultSymbolName)
        chip.titleText = group.name
        chip.setAccessibilityRole(.disclosureTriangle)
        chip.setAccessibilityLabel(group.name)
        chip.setAccessibilityValue(group.isCollapsed ? 0 : 1)
        chip.setAccessibilityHelp(String(localized: "Folder, \(memberCount) tabs"))
        chip.toolTip = group.name
        chip.isSelected = false
        chip.target = self
        chip.action = #selector(groupPressed)
        chip.menuBuilder = { [weak self] in
            guard let self, let current = session.group(group.id) else { return nil }
            return GroupMenu.build(for: current, actions: session.groupMenuActions(for: group.id))
        }
        let plate = plates[group.id] ?? {
            let fresh = TopBarGroupPlate()
            plates[group.id] = fresh
            content.addSubview(fresh, positioned: .below, relativeTo: nil)
            return fresh
        }()
        plate.isHidden = false
    }

    /// A chip's shape is fixed at birth — `TopBarButton` takes its radius and
    /// its focus ring from the metric it was built with — so a tab that crosses
    /// the rule is rebuilt rather than reshaped. That is the only thing a
    /// change of tier costs, and it happens once per drag.
    private func chip(for id: UUID, metric: RoundedMetric) -> TopBarButton {
        if let existing = chips[id], existing.metric == metric { return existing }
        chips[id]?.removeFromSuperview()
        let fresh = TopBarButton(metric: metric, glass: false)
        fresh.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
        // Under the light, which has to stay over every chip there will be.
        content.addSubview(fresh, positioned: .below, relativeTo: glow)
        chips[id] = fresh
        return fresh
    }

    private func retire(keeping live: Set<UUID>) {
        for (id, chip) in chips where !live.contains(id) {
            chip.removeFromSuperview()
            chips.removeValue(forKey: id)
        }
        for (id, plate) in plates where !live.contains(id) {
            plate.removeFromSuperview()
            plates.removeValue(forKey: id)
        }
    }

    private func position(of id: UUID) -> String {
        let index = run.tabs.firstIndex { $0.id == id } ?? 0
        return String(localized: "Tab \(index + 1) of \(run.tabs.count)")
    }

    @objc private func tabPressed(_ sender: NSButton) {
        guard let id = Self.identity(of: sender) else { return }
        activateTab(id)
    }

    /// A folder's header opens and shuts it, and does nothing else. It is not a
    /// tab, so pressing it cannot take the window anywhere — and a header that
    /// also switched tab would mean folding a folder always moved you.
    @objc private func groupPressed(_ sender: NSButton) {
        guard let id = Self.identity(of: sender), let group = session.group(id) else { return }
        session.setGroupCollapsed(!group.isCollapsed, forGroup: id)
    }

    private static func identity(of sender: NSButton) -> UUID? {
        sender.identifier.flatMap { UUID(uuidString: $0.rawValue) }
    }

    /// Bounds-derived frames never animate — see `Motion.immediately` — with
    /// one exception: a folder opening or closing moves every tab after it
    /// along the bar, and that move is exactly the thing that should be seen.
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

}
