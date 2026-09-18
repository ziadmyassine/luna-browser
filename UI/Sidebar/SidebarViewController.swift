//
//  SidebarViewController.swift
//  Luna
//
//  §3, top to bottom: control row → URL pill → Essentials grid → list →
//  utility bar, with the §3.7 resize handle floating on the trailing divider.
//
//  The view itself draws **one thing**: §8.2a's Space wash, behind everything
//  else. `BrowserWindowController` already applies `Glass.sidebar` to the
//  window's root plane and butts the content pane against this view's trailing
//  edge (§3.6), so a second glass surface here would be a second render pass
//  showing the same thing — but a *tint* laid on that glass is not a second
//  surface, and it is the only thing that makes two Spaces look different.
//
//  Contract rule 4 lives here: this is the one place that observes
//  `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` and fans it
//  out. Increase Contrast is not an `NSAppearance` on macOS 26.5, so rows,
//  hairlines and the pill's contrast clamp would otherwise ignore it forever.
//

import AppKit
import BrowserKit

@MainActor
final class SidebarViewController: NSViewController {

    // Wired by the coordinator — none of these have a `BrowserSession` call.
    var onToggleSidebar: (() -> Void)?
    /// Text committed in the URL pill. Wire to `BrowserSession.load(_:)` via
    /// the Command Bar's URL-or-query parse — that parse is not the pill's job.
    var onSubmitURL: ((String) -> Void)?
    /// §3.5's bottom-bar History button. The one way into the page — it used
    /// to also be a row at the head of the list.
    var onOpenHistory: (() -> Void)?
    var onProfileMenu: (() -> Void)?
    /// Live during a §3.7 drag; the width constraint belongs to the window.
    var onWidthChange: ((CGFloat) -> Void)?
    /// §8.2a: the active Space's pair, for the two card corners this view
    /// cannot paint into — `ChromeHostView` clips, so the window fills them.
    /// See `SpaceCornerFillView`.
    var onSpaceGradientChange: ((GradientPair) -> Void)?
    /// No mute exists on `BrowserSession` or `TabController` (see the report);
    /// the sidebar draws the state and hands the intent over.
    var onToggleMute: ((UUID) -> Void)?

    /// The width §7.1 asks to be persisted, for the window to apply at launch.
    var preferredWidth: CGFloat { SidebarResizeHandle.storedWidth }

    private let session: BrowserSession
    /// §8.2a's sidebar wash — the active Space's gradient at 16 %, behind
    /// everything. First in `loadView`'s subview list so it stays behind.
    private let wash = SpaceWashView()
    private let controlRow = SidebarControlRow()
    private let pill = URLPillView()
    private let essentials = EssentialsGridView()
    private let list = TabListController()
    private let utility = SidebarUtilityBar()
    private let handle = SidebarResizeHandle()
    /// §6.6's lift. Built in `viewDidLoad`, because it needs the root view it
    /// floats a dragged tab over.
    private var drag: SidebarTabDragController?
    private var shownSpaceID: UUID?
    private var isAttached = false
    /// The Essentials grid's height on the last layout pass. When it changes —
    /// a tab was pinned or unpinned — everything below it moves, and that move
    /// is animated instead of snapping.
    private var lastGridHeight: CGFloat?

    init(session: BrowserSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func loadView() {
        let root = NSView()
        for subview in [wash, controlRow, pill, essentials, list.scrollView, utility, handle] {
            root.addSubview(subview)
        }
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        wireControls()
        wireList()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        attach()
        refresh()
    }

    // MARK: - Session

    /// Chains onto whatever the coordinator (or the top bar) already installed.
    /// `BrowserSession` exposes a single closure per event, so an observer that
    /// simply assigns `onChange` silently unsubscribes everyone else.
    func attach() {
        guard !isAttached else { return }
        isAttached = true
        let previousChange = session.onChange
        session.onChange = { [weak self] in
            previousChange?()
            self?.refresh()
        }
        let previousState = session.onTabStateChange
        session.onTabStateChange = { [weak self] id, state in
            previousState?(id, state)
            self?.apply(id, state)
        }
    }

    /// Re-reads everything. Cheap: the list diffs its rows and only visible
    /// ones are reconfigured.
    func refresh() {
        let switchingSpace = shownSpaceID != nil && shownSpaceID != session.activeSpaceID
        shownSpaceID = session.activeSpaceID
        if switchingSpace {
            // §6: the sidebar's content cross-fades over 0.18 s on a Space switch.
            essentials.alphaValue = 0
            list.scrollView.alphaValue = 0
        }
        if let space = session.space(session.activeSpaceID) {
            wash.show(space.gradient)
            onSpaceGradientChange?(space.gradient)
        }
        essentials.show(session.tabs.filter { $0.kind == .essential }, activeTabID: session.activeTabID)
        list.show(session.tabs, activeTabID: session.activeTabID)
        utility.show(spaces: session.spaces, activeSpaceID: session.activeSpaceID)
        refreshActiveTab()
        if switchingSpace {
            // §21.2: Reduce Motion takes the fade away rather than shortening
            // it. `Motion.animate` already degrades to a zero duration, so the
            // two lines below land in this frame — the content does not sit at
            // alpha 0 waiting for an animation that is not going to run.
            Tokens.Motion.animate(Tokens.Motion.spaceSwitchCrossfade) { context in
                context.allowsImplicitAnimation = true
                essentials.animator().alphaValue = 1
                list.scrollView.animator().alphaValue = 1
            }
        }
        view.needsLayout = true
    }

    private func apply(_ id: UUID, _ state: TabState) {
        list.update(id, state: state)
        if id == session.activeTabID { refreshActiveTab() }
    }

    private func refreshActiveTab() {
        let tab = session.tabs.first { $0.id == session.activeTabID }
        let state = session.activeTabID.flatMap { session.controller(for: $0)?.state }
        pill.show(url: state?.url ?? tab?.url)
        controlRow.update(canGoBack: state?.canGoBack ?? false, isLoading: state?.isLoading ?? false)
    }

    /// Called by `ChromeHostView` when this layout comes back on screen.
    /// Everything is re-read and the list's row views are rebuilt — see
    /// `ChromeHostView.onShowSidebar` for why the rebuild is not optional.
    func willAppear() {
        list.reload()
        refresh()
        view.needsLayout = true
    }

    /// §3.2 / §20.1's `⌘L`.
    func beginEditingURL() {
        pill.beginEditing()
    }

    /// §7.4's `⌘⌥←/→`, for the window's key map.
    func selectAdjacentTab(offset: Int) {
        list.selectAdjacentTab(offset: offset)
    }

    // MARK: - Wiring

    private func wireControls() {
        controlRow.onToggleSidebar = { [weak self] in self?.onToggleSidebar?() }
        controlRow.onBack = { [weak self] in self?.session.goBack() }
        controlRow.onReloadOrStop = { [weak self] isLoading in
            guard let self else { return }
            if isLoading { session.stop() } else { session.reload() }
        }
        pill.onSubmit = { [weak self] text in self?.onSubmitURL?(text) }
        // §3.2's menu is about the page, and every answer in it is one the
        // session already holds — so it opens itself rather than being routed
        // out to the coordinator and straight back in.
        pill.onSiteMenu = { [weak self] in
            guard let self else { return }
            SiteMenu.present(from: pill.siteMenuAnchor)
        }
        handle.onWidthChange = { [weak self] width in self?.onWidthChange?(width) }
        handle.onWidthCommitted = { [weak self] width in self?.onWidthChange?(width) }

        utility.onProfile = { [weak self] in self?.onProfileMenu?() }
        utility.onHistory = { [weak self] in self?.onOpenHistory?() }
        utility.onSwitchSpace = { [weak self] id in self?.session.switchSpace(id) }
        // §8.2 / §13.6. The failure is silent on purpose: a colour that did not
        // persist is a cosmetic disappointment on the next launch, not
        // something to interrupt the user mid-browse with a dialog.
        utility.onSetGradient = { [weak self] space, gradient in
            Task { try? await self?.session.setGradient(gradient, forSpace: space) }
        }

        essentials.onActivate = { [weak self] id in self?.session.activateTab(id) }
        essentials.onUnpin = { [weak self] id in self?.session.unpinTab(id) }
    }

    private func wireList() {
        list.onActivateTab = { [weak self] id in self?.session.activateTab(id) }
        list.onCloseTab = { [weak self] id in self?.session.closeTab(id) }
        list.onAddTab = { [weak self] in
            guard let self else { return }
            session.activateTab(session.newTab(url: nil, kind: .today))
        }
        list.onPinTab = { [weak self] id in self?.session.pinTab(id) }
        wireDrag()
        list.onToggleMute = { [weak self] id in
            guard let self else { return }
            if list.mutedTabIDs.contains(id) {
                list.mutedTabIDs.remove(id)
            } else {
                list.mutedTabIDs.insert(id)
            }
            if let state = session.controller(for: id)?.state { list.update(id, state: state) }
            onToggleMute?(id)
        }
    }

    /// §6.6's lift. Both ends of the sidebar hand their press over to it — a
    /// list row and a grid tile are the same gesture wearing two shapes — and
    /// exactly one of these three fires on release.
    private func wireDrag() {
        let controller = SidebarTabDragController(host: view, grid: essentials, list: list, utility: utility)
        // **Crossing the grid's edge selects the tab.** Dragging a tab up into
        // §3.3 or down out of it is a decision about *that* tab, taken with it
        // under the hand — and a drop that left the old page on screen made the
        // tile you had just made look like it belonged to something else. A
        // reorder *within* a section is not that: shuffling the list is
        // housekeeping, and it leaves the selection alone.
        controller.onDropInList = { [weak self] id, kind, index, wasPinned in
            guard let self else { return }
            session.reorderTab(id, to: index, kind: kind)
            // Unpinning does not wake a page on its own (§19.2), so this is
            // also what loads it.
            if wasPinned { session.activateTab(id) }
        }
        controller.onDropInEssentials = { [weak self] id, index, wasPinned in
            guard let self else { return }
            // **Two different verbs for one landing place.** A tile moving
            // between slots is a reorder inside the Essentials section; a row
            // arriving is a *pin*, which also puts its page away (§19.2), and
            // `pinTab` refuses a tab that is already pinned.
            if wasPinned {
                session.reorderTab(id, to: index, kind: .essential)
            } else {
                session.pinTab(id, at: index, selecting: true)
            }
        }
        controller.onDropOnSpace = { [weak self] id, space in
            self?.session.moveTab(id, toSpace: space)
        }
        list.onTabPress = { [weak controller] row, event in controller?.track(row: row, event: event) }
        essentials.onDragTile = { [weak controller] id, tile, event in
            controller?.track(essential: id, from: tile, event: event)
        }
        drag = controller
    }

    // MARK: - Accessibility

    /// Contract rule 4: the setting is invisible to `NSAppearance`, so every
    /// surface that draws text or a hairline is told by hand.
    @objc private func accessibilityDisplayOptionsChanged() {
        pill.accessibilityDisplayOptionsChanged()
        list.accessibilityDisplayOptionsChanged()
        Self.redraw(view)
    }

    private static func redraw(_ view: NSView) {
        view.needsDisplay = true
        for subview in view.subviews { redraw(subview) }
    }

    // MARK: - Layout

    override func viewDidLayout() {
        super.viewDidLayout()
        // Every frame below is computed from `bounds`, so none of them may
        // animate — see `Motion.immediately`. Without this the §4.1 layout
        // switch's own transaction swallowed the whole pass.
        //
        // The one exception is the pass where the Essentials grid changed
        // height: the list and the scroll view below it have to travel, and
        // snapping them is what made pinning a tab look like a redraw rather
        // than a movement.
        let gridHeight = essentials.intrinsicContentSize.height
        let moved = lastGridHeight.map { $0 != gridHeight } ?? false
        lastGridHeight = gridHeight
        guard moved, !Tokens.Motion.reduceMotion else {
            Tokens.Motion.immediately { layoutSubviews() }
            return
        }
        Tokens.Motion.animate(Tokens.Motion.tabInsert) { context in
            context.allowsImplicitAnimation = true
            layoutSubviews()
        }
    }

    /// **Every position is computed, and none is read back.**
    ///
    /// This used to walk down the column asking each view where the one above
    /// it had ended up — `pill.frame.minY`, `essentials.frame.minY`. Inside an
    /// animated pass that read is a frame behind: setting a frame under
    /// `allowsImplicitAnimation` routes it through the animator, and the getter
    /// hands back the value the view still has. So on the pass where the grid
    /// *shrank*, the scroll view under it was sized against the grid's old
    /// bottom edge and stayed a tile-row short — an unpinned tab left a 47 pt
    /// hole between the tiles and the list that only a window resize cleared.
    /// The column's geometry is arithmetic; it is done here, once, in locals.
    private func layoutSubviews() {
        let bounds = view.bounds
        wash.frame = bounds
        let inset = Tokens.Metric.rowInset
        let bar = Tokens.Metric.topBarHeight
        let pillHeight = Tokens.Metric.urlPill.height
        let gridHeight = essentials.intrinsicContentSize.height
        let controlTop = bounds.maxY - bar
        let pillTop = controlTop - pillHeight
        let gridTop = pillTop - gridHeight

        controlRow.frame = NSRect(x: 0, y: controlTop, width: bounds.width, height: bar)
        // The row places its buttons against the **traffic lights**, which move
        // and disappear without its own bounds changing — entering fullscreen
        // takes them away and leaves the row exactly 52 pt tall and exactly as
        // wide. Nothing would mark it dirty, so the row kept a hole at its head
        // where three lights used to be.
        controlRow.needsLayout = true
        // Flush under the control row, not §3.2's 12 pt below it: the row is
        // 52 pt and its buttons are only 35, so the row already carries ~8 pt
        // of clear space below them — which is exactly the gap the reference
        // measures between the reload button and the top of the pill. Adding a
        // second gap on top of it doubles a space that is already right.
        pill.frame = NSRect(
            x: inset,
            y: pillTop,
            width: max(bounds.width - 2 * inset, 0),
            height: pillHeight
        ).integral

        essentials.frame = NSRect(x: 0, y: gridTop, width: bounds.width, height: gridHeight).integral

        utility.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bar)
        list.scrollView.frame = NSRect(
            x: 0,
            y: bar,
            width: bounds.width,
            height: max(gridTop - bar, 0)
        ).integral

        // Placed so its 8 pt hit strip is the sidebar's own trailing 8 pt: hit
        // testing stops at a superview's bounds, so a handle centred on the
        // divider would have half a dead hit area. The drawn glyph still
        // overhangs into the §3.6 gap, which is where §3.7 wants it.
        let handleWidth = Tokens.Metric.resizeHandle.width
        handle.frame = NSRect(
            x: bounds.maxX - (handleWidth + Tokens.Metric.resizeHandleHitWidth) / 2,
            y: 0,
            width: handleWidth,
            height: bounds.height
        ).integral
    }
}
