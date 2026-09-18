//
//  SidebarViewController.swift
//  Luna
//
//  §3, top to bottom: control row → URL pill → Essentials grid → list →
//  utility bar, with the §3.7 resize handle floating on the trailing divider.
//
//  The view itself draws **nothing**. `BrowserWindowController` already applies
//  `Glass.sidebar` to the window's root plane and butts the content pane
//  against this view's trailing edge (§3.6), so a second glass surface here
//  would be a second render pass showing the same thing.
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
    var onSiteMenu: (() -> Void)?
    /// §3.5's bottom-bar History button. The one way into the page — it used
    /// to also be a row at the head of the list.
    var onOpenHistory: (() -> Void)?
    var onProfileMenu: (() -> Void)?
    /// Live during a §3.7 drag; the width constraint belongs to the window.
    var onWidthChange: ((CGFloat) -> Void)?
    /// No mute exists on `BrowserSession` or `TabController` (see the report);
    /// the sidebar draws the state and hands the intent over.
    var onToggleMute: ((UUID) -> Void)?

    /// The width §7.1 asks to be persisted, for the window to apply at launch.
    var preferredWidth: CGFloat { SidebarResizeHandle.storedWidth }

    private let session: BrowserSession
    private let controlRow = SidebarControlRow()
    private let pill = URLPillView()
    private let essentials = EssentialsGridView()
    private let list = TabListController()
    private let utility = SidebarUtilityBar()
    private let handle = SidebarResizeHandle()
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
        for subview in [controlRow, pill, essentials, list.scrollView, utility, handle] {
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
        essentials.show(session.tabs.filter { $0.kind == .essential }, activeTabID: session.activeTabID)
        list.show(session.tabs, activeTabID: session.activeTabID)
        utility.show(spaces: session.spaces, activeSpaceID: session.activeSpaceID)
        refreshActiveTab()
        if switchingSpace {
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
        pill.show(url: state?.url ?? tab?.url, themeColor: state?.themeColor ?? tab?.themeColor)
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
        pill.onSiteMenu = { [weak self] in self?.onSiteMenu?() }
        handle.onWidthChange = { [weak self] width in self?.onWidthChange?(width) }
        handle.onWidthCommitted = { [weak self] width in self?.onWidthChange?(width) }

        utility.onProfile = { [weak self] in self?.onProfileMenu?() }
        utility.onHistory = { [weak self] in self?.onOpenHistory?() }
        utility.onSwitchSpace = { [weak self] id in self?.session.switchSpace(id) }
        utility.onMoveTabToSpace = { [weak self] tab, space in self?.session.moveTab(tab, toSpace: space) }

        essentials.onActivate = { [weak self] id in self?.session.activateTab(id) }
        // Dragging a row up into the grid is one of the two ways to pin
        // (§3.3); `pinTab` is what makes it also put the page away.
        essentials.onDrop = { [weak self] id, index in self?.session.pinTab(id, at: index) }
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
        list.onDragSessionChange = { [weak self] isDragging in
            guard let self else { return }
            essentials.isAwaitingDrop = isDragging
            view.needsLayout = true
        }
        list.onMoveTab = { [weak self] id, kind, index in
            self?.session.reorderTab(id, to: index, kind: kind)
        }
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

    private func layoutSubviews() {
        let bounds = view.bounds
        let inset = Tokens.Metric.rowInset
        let bar = Tokens.Metric.topBarHeight

        controlRow.frame = NSRect(x: 0, y: bounds.maxY - bar, width: bounds.width, height: bar)
        // The row places its buttons against the **traffic lights**, which move
        // and disappear without its own bounds changing — entering fullscreen
        // takes them away and leaves the row exactly 52 pt tall and exactly as
        // wide. Nothing would mark it dirty, so the row kept a hole at its head
        // where three lights used to be.
        controlRow.needsLayout = true
        let pillHeight = Tokens.Metric.urlPill.height
        // Flush under the control row, not §3.2's 12 pt below it: the row is
        // 52 pt and its buttons are only 35, so the row already carries ~8 pt
        // of clear space below them — which is exactly the gap the reference
        // measures between the reload button and the top of the pill. Adding a
        // second gap on top of it doubles a space that is already right.
        pill.frame = NSRect(
            x: inset,
            y: controlRow.frame.minY - pillHeight,
            width: max(bounds.width - 2 * inset, 0),
            height: pillHeight
        ).integral

        let gridHeight = essentials.intrinsicContentSize.height
        essentials.frame = NSRect(
            x: 0,
            y: pill.frame.minY - gridHeight,
            width: bounds.width,
            height: gridHeight
        ).integral

        utility.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bar)
        list.scrollView.frame = NSRect(
            x: 0,
            y: utility.frame.maxY,
            width: bounds.width,
            height: max(essentials.frame.minY - utility.frame.maxY, 0)
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
