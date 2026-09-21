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
    /// §3.5's bottom-bar History button. The one way into the page — it used
    /// to also be a row at the head of the list.
    var onOpenHistory: (() -> Void)?
    /// §3.5's Downloads button, History's pair.
    var onOpenDownloads: (() -> Void)?

    /// §6.4's pop-out stands on the bottom bar's History button.
    var historyAnchor: NSView { utility.historyAnchor }
    /// §15.3's stands on the one beside it.
    var downloadsAnchor: NSView { utility.downloadsAnchor }
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

    /// Which side of the window the column is standing on. The window
    /// controller owns the constraint; this is what the two things *inside* the
    /// sidebar that are not symmetric need to know — the resize handle's
    /// divider, and which way a drag means "wider".
    var sidebarEdge: SidebarEdge = .leading {
        didSet {
            guard sidebarEdge != oldValue else { return }
            handle.edge = sidebarEdge
            view.needsLayout = true
        }
    }

    /// §3.2b: the pill and §3.1's buttons have moved onto the page. The 52 pt
    /// row stays — it keeps the traffic lights' corner clear.
    func setSearchBarOnPage(_ onPage: Bool) {
        controlRow.showsButtons = !onPage
        pill.isHidden = onPage
        view.needsLayout = true
    }

    // **Internal rather than private from here down**, and only because Swift's
    // `private` is file-scoped: `SidebarViewController+Layout.swift` is the
    // other half of this class, and every position in the column is computed
    // there. Nothing outside this file's pair touches them.
    /// Not private: `+Drag.swift` makes the session calls each §6.6 landing
    /// means, for the same reason `+Layout.swift` reads the subviews.
    let session: BrowserSession
    /// §8.2a's sidebar wash — the active Space's gradient at 16 %, behind
    /// everything. First in `loadView`'s subview list so it stays behind.
    let wash = SpaceWashView()
    let controlRow = SidebarControlRow()
    let pill = URLPillView()
    let essentials = EssentialsGridView()
    let list = TabListController()
    let utility = SidebarUtilityBar()
    /// §3.5's profile line, directly above the Space strip. See the view.
    let profile = SidebarProfileLabel()
    let handle = SidebarResizeHandle()
    /// §30.9's page turn: the Space arriving, and the `+` standing in for the
    /// one that does not exist. Both draw nothing until the gesture asks.
    let preview = SpacePreviewView()
    let creation = SpaceCreationView()
    /// §30.9's swipe, §6.1's create and §6.2's way into Settings — everything
    /// the foot of the sidebar does *to* Spaces. Built in `viewDidLoad`.
    var spaces: SidebarSpaceGestures?
    /// §6.6's lift. Built in `viewDidLoad`, because it needs the root view it
    /// floats a dragged tab over. Not private: `+Drag.swift` is what builds it.
    var drag: SidebarTabDragController?
    private var shownSpaceID: UUID?
    private var isAttached = false
    /// The Essentials grid's height on the last layout pass. When it changes —
    /// a tab was pinned or unpinned — everything below it moves, and that move
    /// is animated instead of snapping.
    var lastGridHeight: CGFloat?

    init(session: BrowserSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func loadView() {
        let root = SidebarRootView()
        // §30.9 is caught here rather than on any one child: the gesture is
        // about the column, and the column is what the hand is resting on.
        root.onScroll = { [weak self] event in self?.spaces?.scrollWheel(with: event) ?? false }
        // The list is the part of the column a hand rests on, and a scroll view
        // consumes both axes — so it offers the swipe every event first.
        (list.scrollView as? SidebarScrollView)?.onScroll = { [weak self] event in
            self?.spaces?.scrollWheel(with: event) ?? false
        }
        // The still goes **under** the live column (an overlap belongs to the
        // Space the window is in) and the `+` over both, because it is the one
        // mark that has to stay visible while the two pass each other.
        for subview in [
            wash, preview, controlRow, pill, essentials, list.scrollView, creation, profile, utility, handle
        ] {
            root.addSubview(subview)
        }
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        spaces = SidebarSpaceGestures(
            session: session,
            utility: utility,
            wash: wash,
            content: [essentials, list.scrollView],
            preview: preview,
            creation: creation,
            host: view
        )
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
        // §6.1: a Space that has just been made is a Space switch like any
        // other, and this is the one switch whose column must not come back —
        // `SpaceEditorView` is standing where it would be. See
        // `SidebarSpaceGestures.isMakingSpace`.
        let makingSpace = spaces?.isMakingSpace == true
        if switchingSpace {
            // §6: the sidebar's content cross-fades over 0.18 s on a Space switch.
            essentials.alphaValue = 0
            list.scrollView.alphaValue = 0
            // **A Space switch replaces the column; it does not move it.** The
            // grid animates its height when a tab is pinned, because everything
            // below it travels. Two Spaces with different numbers of pinned
            // tabs are not that — nothing travelled — and left animating, the
            // new tiles slid in from the old grid's shape for 0.22 s after the
            // cross-fade was over. Forgetting the height snaps the next pass.
            lastGridHeight = nil
        }
        if let space = session.space(session.activeSpaceID) {
            wash.show(space.gradient)
            onSpaceGradientChange?(space.gradient)
        }
        essentials.show(session.tabs.filter { $0.kind == .essential }, activeTabID: session.activeTabID)
        // §3.4a: before `show`, so the rows are configured against the current answer
        // rather than the one from before a mute landed.
        list.mutedTabIDs = session.mutedTabIDs
        list.show(session.tabs, activeTabID: session.activeTabID)
        utility.show(spaces: session.spaces, activeSpaceID: session.activeSpaceID)
        // §3.5's line, and §9's fan-out made visible: the Profile is derived
        // from the Space, so it changes on a Space switch **and** on a
        // re-profile without one.
        profile.show(profileName: session.space(session.activeSpaceID).flatMap {
            session.profile(for: $0)?.name
        })
        refreshActiveTab()
        if makingSpace {
            // Whatever the column was doing, it is not doing it in front of the
            // editor. Set rather than animated: there is nothing to see.
            essentials.alphaValue = 0
            list.scrollView.alphaValue = 0
        } else if switchingSpace {
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
        // §3.2c. The id goes with the state so the line can tell a tab switch
        // from progress — a new tab's load is not the old one's, continued.
        pill.setLoad(state, for: session.activeTabID)
        controlRow.update(
            canGoBack: state?.canGoBack ?? false,
            canGoForward: state?.canGoForward ?? false,
            isLoading: state?.isLoading ?? false
        )
    }

    /// Called by `ChromeHostView` when this layout comes back on screen.
    /// Everything is re-read and the list's row views are rebuilt — see
    /// `ChromeHostView.onShowSidebar` for why the rebuild is not optional.
    func willAppear() {
        // A swipe whose fingers left while this column was off screen has no
        // release to wait for. Silent — see `SpaceSwipeController.cancel`.
        spaces?.cancel()
        list.reload()
        refresh()
        view.needsLayout = true
    }

    /// §3.2 / §20.1's `⌘L`: §9.1, standing on the pill.
    func beginEditingURL() {
        pill.handOff()
    }

    /// Whether §3.2's pill is the address bar the user can see — which is
    /// `⌘L`'s question, and not one this controller can answer from the
    /// setting alone: the whole sidebar is hidden in §4's layout.
    var showsURLPill: Bool {
        pill.window != nil && !pill.isHiddenOrHasHiddenAncestor
    }

    /// §7.4's `⌘⌥←/→`, for the window's key map.
    func selectAdjacentTab(offset: Int) {
        list.selectAdjacentTab(offset: offset)
    }

    // MARK: - Wiring

    private func wireControls() {
        controlRow.onToggleSidebar = { [weak self] in self?.onToggleSidebar?() }
        controlRow.onBack = { [weak self] in self?.session.goBack() }
        controlRow.onForward = { [weak self] in self?.session.goForward() }
        // **The pill hands off to §9.1 rather than opening itself**, and §9.1
        // opens *on the pill*: the bar takes its place, at its width, and grows
        // down out of it (`CommandBarAnchor`). The field, the history, the
        // ranking and the list are all already there, and none of them would
        // fit in a 260 pt column. §3.2b's pill now does exactly the same.
        pill.onHandOff = { [weak self] in
            guard let self else { return }
            session.presentCommandBar?(.editCurrentURL, CommandBarAnchor(view: pill))
        }
        controlRow.onReloadOrStop = { [weak self] isLoading in
            guard let self else { return }
            if isLoading { session.stop() } else { session.reload() }
        }
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
        // §6.2 lives in Settings and there is one window of it, so the foot of
        // the sidebar asks the app for it rather than growing its own copy —
        // the same route §3.2's site menu takes to the Privacy section.
        utility.onEditSpaces = { [weak self] in self?.spaces?.editSpaces() }
        utility.onNewSpace = { [weak self] in self?.spaces?.createSpace() }
        profile.onEditSpaces = { [weak self] in self?.spaces?.editSpaces() }
        profile.onNewSpace = { [weak self] in self?.spaces?.createSpace() }
        utility.onHistory = { [weak self] in self?.onOpenHistory?() }
        utility.onDownloads = { [weak self] in self?.onOpenDownloads?() }
        utility.onSwitchSpace = { [weak self] id in self?.session.switchSpace(id) }
        // §8.2 / §13.6. The failure is silent on purpose: a colour that did not
        // persist is a cosmetic disappointment on the next launch, not
        // something to interrupt the user mid-browse with a dialog.
        utility.onSetGradient = { [weak self] space, gradient in
            Task { try? await self?.session.setGradient(gradient, forSpace: space) }
        }

        essentials.onActivate = { [weak self] id in self?.session.activateTab(id) }
        essentials.onUnpin = { [weak self] id in self?.session.unpinTab(id) }
        // §3.4a's menu, on the §3.3 tiles as well as the §3.4 rows: a tile *is* a tab, and
        // a menu that changed its mind about what you can do to one depending on which
        // half of the sidebar it is standing in would be two menus, not one.
        essentials.menuActions = { [weak self] id in self?.session.tabMenuActions(for: id) }
        essentials.isMuted = { [weak self] id in self?.session.isMuted(id) ?? false }
    }

    private func wireList() {
        list.onActivateTab = { [weak self] id in self?.session.activateTab(id) }
        list.onCloseTab = { [weak self] id in self?.session.closeTab(id) }
        // §9.1, not a blank tab. The Command Bar opens in `.newTab` — so what
        // it lands on is a *new* tab — and closing it without choosing leaves
        // the list exactly as it was rather than one empty page longer.
        list.onAddTab = { [weak self] in self?.session.presentCommandBar?(.newTab, nil) }
        list.menuActions = { [weak self] id in self?.session.tabMenuActions(for: id) }
        wireDrag()
        list.onToggleMute = { [weak self] id in
            guard let self else { return }
            // The session owns the answer — it is what silences the page and what puts the
            // mute back when a cold tab wakes up. The list's copy follows it rather than
            // leading, so the row's speaker and the sound cannot disagree.
            session.setMuted(!session.isMuted(id), tab: id)
            list.mutedTabIDs = session.mutedTabIDs
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
        profile.accessibilityDisplayOptionsChanged()
        Self.redraw(view)
    }

    private static func redraw(_ view: NSView) {
        view.needsDisplay = true
        for subview in view.subviews { redraw(subview) }
    }
}
