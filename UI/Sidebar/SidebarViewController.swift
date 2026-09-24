//
//  SidebarViewController.swift
//  Luna
//
//  §3, top to bottom: control row → URL pill → Essentials grid → list →
//  utility bar, with the §3.7 resize handle floating on the trailing divider.
//
//  The view itself draws one thing: §8.2a's Space wash, behind everything
//  else. `BrowserWindowController` already applies `Glass.sidebar` to the
//  window's root plane and butts the content pane against this view's trailing
//  edge (§3.6), so a second glass surface here would be a second render pass
//  showing the same thing — but a tint laid on that glass is not a second
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
final class SidebarViewController: NSViewController, WindowScoped {

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
    /// …and §5.0's flight is caught by the cylinder they are both in.
    var downloadsCatcher: NSView { utility.downloadsCatcher }
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
    /// controller owns the constraint; this is what the two things inside the
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

    // Internal rather than private from here down, and only because Swift's
    // `private` is file-scoped: `SidebarViewController+Layout.swift` is the
    // other half of this class, and every position in the column is computed
    // there. Nothing outside this file's pair touches them.
    /// Not private: `+Drag.swift` makes the session calls each §6.6 landing
    /// means, for the same reason `+Layout.swift` reads the subviews.
    let session: BrowserSession
    let windowID: UUID
    /// §8.2a's sidebar wash — the active Space's gradient at 16 %, behind
    /// everything. First in `loadView`'s subview list so it stays behind.
    let wash = SpaceWashView()
    let controlRow = SidebarControlRow()
    let pill = URLPillView()
    let essentials = EssentialsGridView()
    /// §3.3a's second well, under the grid: §3.4b's tier with no folder in it
    /// yet. Its own view rather than a row in the list, because the tier it
    /// describes has no rows — that is the state it exists for.
    let folderHint = SidebarPinHintView.folderTier()
    let list = TabListController()
    let utility = SidebarUtilityBar()
    /// §3.5's caption, directly above the Space strip: the active Space's
    /// name. See the view.
    let spaceLabel = SidebarSpaceLabel()
    let handle = SidebarResizeHandle()
    /// §30.9's page turn: the Space arriving, and the `+` standing in for the
    /// one that does not exist. Both draw nothing until the gesture asks.
    let preview = SpacePreviewView()
    let creation = SpaceCreationView()
    /// §30.9's swipe, §6.1's create and §6.2's way into Settings — everything
    /// the foot of the sidebar does to Spaces. Built in `viewDidLoad`.
    var spaces: SidebarSpaceGestures?
    /// §6.6's lift. Built in `viewDidLoad`, because it needs the root view it
    /// floats a dragged tab over. Not private: `+Drag.swift` is what builds it.
    var drag: SidebarTabDragController?
    private var shownSpaceID: UUID?
    private var isAttached = false
    /// The selected row's read band, as its page scrolls — see
    /// `BrowserSession.addScrollProgressObserver`.
    private var progressObservation: ObservationToken?
    /// The Essentials grid's height on the last layout pass. When it changes —
    /// a tab was pinned or unpinned — everything below it moves, and that move
    /// is animated instead of snapping.
    var lastHeadHeight: CGFloat?

    init(session: BrowserSession, windowID: UUID) {
        self.session = session
        self.windowID = windowID
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
        // The still goes under the live column (an overlap belongs to the
        // Space the window is in) and the `+` over both, because it is the one
        // mark that has to stay visible while the two pass each other.
        for subview in [
            wash, preview, controlRow, pill, essentials, folderHint, list.scrollView,
            creation, spaceLabel, utility, handle
        ] {
            root.addSubview(subview)
        }
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        spaces = SidebarSpaceGestures(
            session: session,
            windowID: windowID,
            utility: utility,
            wash: wash,
            content: [essentials, folderHint, list.scrollView],
            preview: preview,
            creation: creation,
            host: view
        )
        wireControls()
        wireList()
        wirePinHints()
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
        let switchingSpace = shownSpaceID != nil && shownSpaceID != activeSpaceID
        shownSpaceID = activeSpaceID
        // §6.1: a Space that has just been made is a Space switch like any
        // other, and this is the one switch whose column must not come back —
        // `SpaceEditorView` is standing where it would be. See
        // `SidebarSpaceGestures.isMakingSpace`.
        let makingSpace = spaces?.isMakingSpace == true
        if switchingSpace {
            // §6: the sidebar's content cross-fades over 0.18 s on a Space switch.
            essentials.alphaValue = 0
            list.scrollView.alphaValue = 0
            // A Space switch replaces the column; it does not move it. The
            // grid animates its height when a tab is pinned, because everything
            // below it travels. Two Spaces with different numbers of pinned
            // tabs are not that — nothing travelled — and left animating, the
            // new tiles slid in from the old grid's shape for 0.22 s after the
            // cross-fade was over. Forgetting the height snaps the next pass.
            lastHeadHeight = nil
        }
        if let space = session.space(activeSpaceID) {
            wash.show(space.gradient)
            onSpaceGradientChange?(space.gradient)
        }
        // `replacing:` is the same claim `lastHeadHeight = nil` makes, made to
        // the two halves of the column. Both of them animate a tab leaving —
        // the row fades over §6's `tabInsert`, the tile fades where it stood —
        // and `NSTableView` and the grid alike keep what is leaving on screen
        // for the length of that fade. Across a Space switch that is every row
        // and every tile at once, so the Space just left stayed drawn, fading,
        // over the Space just arrived in: the flash of the previous Space's
        // tabs. One transition per switch, and it is the column's cross-fade.
        let tiles = windowTabs.filter { $0.kind == .essential }
        let folders = session.slots(inTier: .pinned)
        // §3.3a: advice for a Space that has pinned nothing, in the two places
        // the pinned things would be. Set before `show`, so the grid is the
        // right height on the pass that places it rather than one pass later.
        showPinHints(tiles: tiles.isEmpty, folders: folders.isEmpty)
        essentials.show(
            tiles,
            activeTabID: activeTabID,
            replacing: switchingSpace
        )
        // §3.4a: before `show`, so the rows are configured against the current answer
        // rather than the one from before a mute landed.
        list.mutedTabIDs = session.mutedTabIDs
        list.controlledGroupIDs = session.controlledGroupIDs
        // §3.4b: the two tiers arrive already arranged — `TabList` owns the
        // order, including where a group stands among the loose tabs, so the
        // column has no arrangement of its own to disagree with it.
        list.show(
            saved: folders,
            today: session.slots(inTier: .today),
            essentials: tiles,
            activeTabID: activeTabID,
            replacing: switchingSpace
        )
        utility.show(spaces: session.spaces, activeSpaceID: activeSpaceID)
        // §3.5's caption names the Space; §3.5's avatar wears its picture. One
        // thing said twice on purpose — the strip below identifies a Space by
        // colour alone, and a name and a face are what a glance actually reads.
        let active = session.space(activeSpaceID)
        spaceLabel.show(spaceName: active?.name)
        utility.show(
            spaceName: active?.name,
            fanOut: active.map { SpacesSection.fanOut($0, session: session) },
            picture: active?.imageData
        )
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
        if id == activeTabID { refreshActiveTab() }
    }

    private func refreshActiveTab() {
        let tab = windowTabs.first { $0.id == activeTabID }
        let state = activeTabID.flatMap { session.controller(for: $0)?.state }
        pill.show(url: state?.url ?? tab?.url)
        // §3.2c. The id goes with the state so the line can tell a tab switch
        // from progress — a new tab's load is not the old one's, continued.
        pill.setLoad(state, for: activeTabID)
        controlRow.update(
            canGoBack: state?.canGoBack ?? false,
            canGoForward: state?.canGoForward ?? false,
            isLoading: state?.isLoading ?? false
        )
        followScrollProgress()
    }

    /// The selected row fills as its page is read. Taken on arrival as well as
    /// listened to, so a tab selected again shows where it was left.
    private func followScrollProgress() {
        if progressObservation == nil {
            progressObservation = session.addScrollProgressObserver { [weak self] id, progress in
                guard let self, id == activeTabID else { return }
                list.setScrollProgress(progress)
            }
        }
        list.setScrollProgress(activeTabID.flatMap { session.controller(for: $0)?.scrollProgress })
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

    // MARK: - Accessibility

    /// Contract rule 4: the setting is invisible to `NSAppearance`, so every
    /// surface that draws text or a hairline is told by hand.
    @objc private func accessibilityDisplayOptionsChanged() {
        pill.accessibilityDisplayOptionsChanged()
        list.accessibilityDisplayOptionsChanged()
        spaceLabel.accessibilityDisplayOptionsChanged()
        Self.redraw(view)
    }

    private static func redraw(_ view: NSView) {
        view.needsDisplay = true
        for subview in view.subviews { redraw(subview) }
    }
}
