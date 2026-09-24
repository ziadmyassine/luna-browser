//
//  TopBarView.swift
//  Luna
//
//  The sidebar-off layout (UI-SPEC §4, TODO.md §30.12–30.14): one 50 pt
//  bar spanning the window, with the page flush full-bleed below it. It is a
//  second layout, not a collapsed sidebar — `ContentCardView` already knows
//  that (`cardInsets` for `.topBar` has no gap and no corners).
//
//      [lights] [back · forward] [kept tabs] [open tabs …] [|] [capsule] [Space]
//
//  Back and forward stand before the tabs, as they do at the head of the
//  sidebar. The plate holds the Space's kept tabs; the Space's name, which is
//  the switcher, is a cylinder of its own after the action capsule. Between any
//  two things on the bar there is one gap (`TopBarMetrics.gap`).
//
//  Nothing stands under the bar: the page runs flush to it. The address is
//  edited from the tab on screen — a click opens the Command Bar on it, as
//  `⌘L` does — and reload is `⌘R` and the site menu. A double-click on a tab
//  renames it in place (`TopBarTabStrip+Rows`).
//
//  Four things are deliberately absent:
//    · No sidebar toggle. There is no sidebar in this layout to hide, so
//      the button was a control that either did nothing or silently changed a
//      preference. `⌘S` still works wherever there is a sidebar; which chrome
//      the window wears is Settings' decision (`Settings.chromeLayout`).
//    · No reload button. The reference omits it; §4 makes reload `⌘R` and
//      the site menu on the page.
//    · No address bar on it. The active tab used to swell into a URL pill in
//      the middle of the strip; a strip whose tabs carry their own titles has
//      no room for a fourth shape. The tab on screen is the address.
//    · No traffic-light layout. `TrafficLightLayoutManager` owns those
//      frames for every window state (§7.7). The bar asks `TrafficLightSpace`
//      where they landed and stands beside them on their centre line, as
//      §3.1's row does — so the corner reads the same in either layout.
//    · No page tint on the bar itself. §2: the chrome samples what is
//      behind the window.
//

import AppKit
import BrowserKit

/// Anything on the bar holding a token by value, and therefore needing to be
/// told when the accessibility display options flip.
///
/// On macOS 26.5 Increase Contrast is not an `NSAppearance` (see the `Tokens`
/// header: the high-contrast appearance is object-identical to `.aqua`), so no
/// appearance change fires and nothing invalidates on its own. `TopBarView`
/// owns the single `NSWorkspace` observer for the whole bar and walks the tree.
@MainActor
protocol TopBarThemed: NSView {
    func applyTokens()
}

@MainActor
final class TopBarView: NSView, WindowScoped, TrafficLightNeighbour {

    // MARK: - Seams

    /// The downloads pop-out (§5) anchors to the button it is passed.
    var onDownloads: ((NSView) -> Void)?
    /// §6.4's History pop-out, from the capsule button beside Downloads. The
    /// sidebar keeps its own at the foot of §3.5; this is that button's twin in
    /// the layout that has no sidebar to put it in.
    var onHistory: ((NSView) -> Void)?
    /// §3.5's Space switcher, in the layout that has no sidebar foot to put it
    /// in. The same four seams the sidebar's own copy exposes.
    var onSwitchSpace: ((UUID) -> Void)?
    var onSetGradient: ((UUID, GradientPair) -> Void)?
    var onEditSpaces: (() -> Void)?
    var onNewSpace: (() -> Void)?

    /// v2's extension action buttons (§16.4, §30.14). The capsule is built to
    /// host a variable number of items, so shipping them is an assignment here
    /// rather than a re-layout of the bar's whole right side.
    var extensionActions: [TopBarActionItem] = [] { didSet { rebuildCapsule() } }

    /// Where agent H's download popover points.
    var downloadsAnchor: NSView? { capsule.view(for: Self.downloadsItem) }

    /// §5.0's flight lands on the button and the capsule catches it — the
    /// glyph inside owns no material of its own, and half a cylinder bulging
    /// inside the other half is not a shelf catching anything. Same rule as
    /// the press (`TopBarActionCapsule`), same reason.
    var downloadsCatcher: NSView { capsule }

    /// Where §6.4's History pop-out stands.
    var historyAnchor: NSView? { capsule.view(for: Self.historyItem) }

    // MARK: - Views

    private static let newTabItem = "luna.topBar.newTab"
    private static let historyItem = "luna.topBar.history"
    private static let downloadsItem = "luna.topBar.downloads"

    let session: BrowserSession
    let windowID: UUID
    let strip: TopBarTabStrip
    /// §3.1's back and forward, before the tabs.
    private let nav = NavCluster()
    /// The Space's name, in its own cylinder at the trailing end.
    let spaceName = TopBarSpaceName()
    private lazy var spaceCapsule = TopBarSpaceCapsule(spaceName: spaceName)
    private let separator = TopBarSeparator()
    private let capsule = TopBarActionCapsule()
    private var leadingInset: NSLayoutConstraint?
    var drag: TopBarTabDragController?
    private var progressObservation: ObservationToken?

    init(session: BrowserSession, windowID: UUID) {
        self.session = session
        self.windowID = windowID
        strip = TopBarTabStrip(session: session, windowID: windowID)
        super.init(frame: .zero)

        wantsLayer = true
        // The bar's height animates 0 → 52 during the §4.1 switch; without this
        // its contents spill over the page on the way up.
        clipsToBounds = true
        // No glass of its own: the bar stands on the window's plane, as the
        // sidebar does (`BrowserWindowController.buildContent`). A second
        // sheet of glass over it ended in a visible line along the bar's
        // bottom edge, and the notches the page's rounded top corners leave
        // showed the plane, not the bar.

        buildControls()
        buildLayout()
        rebuildCapsule()
        wireDrag()
        subscribe(to: session)
        refresh()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code")
    }

    // MARK: - Build

    private func buildControls() {
        nav.onBack = { [weak self] in self?.session.goBack() }
        nav.onForward = { [weak self] in self?.session.goForward() }
        spaceName.onSwitch = { [weak self] id in self?.onSwitchSpace?(id) }
        spaceName.onSetGradient = { [weak self] id, gradient in self?.onSetGradient?(id, gradient) }
        spaceName.onEditSpaces = { [weak self] in self?.onEditSpaces?() }
        spaceName.onNewSpace = { [weak self] in self?.onNewSpace?() }
        spaceName.onTravel = { [weak self] travel in self?.slideTabs(travel) }
        spaceName.onArrive = { [weak self] direction, spec in self?.tabsArrive(from: direction, on: spec) }
    }

    /// `ChromeHostView` keeps both layouts alive and cross-fades them, and
    /// every hook on `BrowserSession` is a single closure — `AppDelegate`
    /// already owns `onChange`. So the bar chains rather than assigns: nothing
    /// it subscribes to displaces an existing subscriber, whatever order the
    /// chrome is built in. See the report — this wants to be an add-observer
    /// API before a third subscriber appears.
    private func subscribe(to session: BrowserSession) {
        let previousChange = session.onChange
        session.onChange = { [weak self] in
            previousChange?()
            self?.refresh()
        }
        // §3.4's read band on the selected tab, as its page scrolls.
        progressObservation = session.addScrollProgressObserver { [weak self] id, progress in
            guard let self, id == activeTabID else { return }
            strip.setScrollProgress(progress)
        }
        let previousTabState = session.onTabStateChange
        session.onTabStateChange = { [weak self] id, state in
            previousTabState?(id, state)
            self?.apply(state, for: id)
        }
        // `⌘L` is not claimed here. This layout has no address bar of its own
        // any more, so the command falls through to whatever does — §3.2b's
        // band when it is showing, and §9.1's Command Bar otherwise
        // (`AppDelegate.editLocation`). A layout that claimed the key and then
        // had nowhere to put the caret would be a dead shortcut.
    }

    private func buildLayout() {
        for view in [nav, strip, separator, capsule, spaceCapsule] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        // Not the bar's own centre: the traffic lights' (see the token). And
        // not the strip, which is pinned top and bottom — a centre line as
        // well is a third vertical constraint and one of the three gets
        // dropped. It stands its own tabs on the line instead.
        NSLayoutConstraint.activate([nav, separator, capsule, spaceCapsule].map {
            $0.centerYAnchor.constraint(
                equalTo: centerYAnchor,
                constant: TopBarMetrics.lightsCentreOffset
            )
        })
        // Set from the lights in `alignToTrafficLights`; this is the floor
        // until there is a window to ask.
        let leading = nav.leadingAnchor.constraint(
            equalTo: leadingAnchor,
            constant: Tokens.Metric.rowInset
        )
        leadingInset = leading

        NSLayoutConstraint.activate([
            leading,
            strip.leadingAnchor.constraint(equalTo: nav.trailingAnchor, constant: TopBarMetrics.gap),
            strip.topAnchor.constraint(equalTo: topAnchor),
            strip.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: strip.trailingAnchor, constant: TopBarMetrics.gap),
            capsule.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: TopBarMetrics.gap),
            spaceCapsule.leadingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: TopBarMetrics.gap),
            trailingAnchor.constraint(equalTo: spaceCapsule.trailingAnchor, constant: TopBarMetrics.clusterGap)
        ])
        // The strip is the only elastic element: everything else keeps its
        // intrinsic width and the tab list absorbs the rest of the window.
        strip.setContentHuggingPriority(.defaultLow, for: .horizontal)
        strip.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func rebuildCapsule() {
        let newTab = TopBarActionItem(
            id: Self.newTabItem,
            symbolName: "plus",
            label: String(localized: "New Tab")
        ) { [weak self] in
            // §9.1, not a blank tab — the same answer §3.4's New Tab row and
            // `⌘T` give. There is no New Tab page to land on any more, so a `+`
            // that made a tab would be making an empty one.
            self?.presentCommandBar?(.newTab, nil)
        }
        let history = TopBarActionItem(
            id: Self.historyItem,
            symbolName: "clock.arrow.circlepath",
            label: String(localized: "History")
        ) { [weak self] in
            guard let self, let anchor = historyAnchor else { return }
            onHistory?(anchor)
        }
        let downloads = TopBarActionItem(
            id: Self.downloadsItem,
            symbolName: "arrow.down.to.line",
            label: String(localized: "Downloads")
        ) { [weak self] in
            guard let self, let anchor = downloadsAnchor else { return }
            onDownloads?(anchor)
        }
        // History beside Downloads. The sidebar's foot pairs the same two —
        // they are the same kind of thing, the shelf of what you already have —
        // so the layout without a sidebar keeps the pair rather than inventing
        // a second arrangement. The Space stands after the capsule, on its own,
        // because it is about where, not about what.
        capsule.items = extensionActions + [newTab, history, downloads]
    }

    // MARK: - State

    /// Re-reads everything from the session. Safe to call from the coordinator
    /// as well as from `onChange`.
    func refresh() {
        spaceName.show(spaces: session.spaces, activeSpaceID: activeSpaceID)
        strip.reload(slidingSpace: spaceName.arrivesBySwipe)
        let state = activeTabID.flatMap { session.controller(for: $0)?.state }
        nav.update(canGoBack: state?.canGoBack ?? false, canGoForward: state?.canGoForward ?? false)
    }

    /// One tab's live state (§4.3): title, progress, `themeColor`.
    func apply(_ state: TabState, for id: UUID) {
        strip.apply(state, for: id)
        guard id == activeTabID else { return }
        nav.update(canGoBack: state.canGoBack, canGoForward: state.canGoForward)
    }

    // MARK: - §4.1 layout switch

    /// `ChromeHostView` un-hides this layout at the start of the switch and
    /// fades it in from there, which is exactly the moment §4.1's stagger
    /// belongs to — so the bar plays it itself and the coordinator does not
    /// have to remember to.
    override func viewDidUnhide() {
        super.viewDidUnhide()
        // Only when this really is the layout coming on screen. AppKit
        // un-hides views for reasons of its own — a window returning from
        // Stage Manager or from the Dock among them — and replaying a fade-in
        // stagger there is a flash of chrome nobody asked to see.
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return }
        playEntranceStagger()
    }

    /// The bar's half of the §4.1 switch: while the coordinator animates the
    /// frame and re-anchors the traffic lights, the contents come in 20 ms
    /// apart, landing together on §6's 0.30 s total.
    ///
    /// `viewDidUnhide` already calls it. It stays exposed so the coordinator
    /// can drive it explicitly from inside its own transaction instead.
    /// Reduce Motion (§21.2) makes it instant.
    func playEntranceStagger() {
        let views: [NSView] = [nav, strip, separator, capsule, spaceCapsule]
        for view in views {
            view.wantsLayer = true
            view.alphaValue = 1
            view.layer?.removeAnimation(forKey: Self.entranceKey)
        }
        guard !Tokens.Motion.reduceMotion else { return }

        let stagger = Tokens.Motion.layoutSwitchStagger
        let tail = Double(views.count - 1) * stagger
        let duration = max(Tokens.Motion.layoutSwitch.duration - tail, stagger)
        let start = CACurrentMediaTime()

        for (index, view) in views.enumerated() {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.beginTime = start + Double(index) * stagger
            fade.duration = duration
            fade.timingFunction = Tokens.Motion.layoutSwitch.timingFunction
            // Holds the view invisible until its turn instead of flashing it in
            // at full opacity and then fading from there.
            fade.fillMode = .backwards
            view.layer?.add(fade, forKey: Self.entranceKey)
        }
    }

    private static let entranceKey = "luna.topBar.entrance"

    // MARK: - Geometry

    /// Where the bar starts: after the traffic lights, `lightsGap` on.
    ///
    /// Derived, not read off the live buttons. AppKit resets their origins
    /// on every resize and `TrafficLightLayoutManager` puts them back a beat
    /// later, so a bar that believed what it saw in between laid its first control against
    /// the green light rather than a gap from it. `TrafficLightSpace` is the
    /// shared answer, and §3.1's control row asks it the very same question.
    ///
    /// The other half of standing beside them — their centre line — is a
    /// constant and is set once; see `TopBarMetrics.lightsCentreOffset`.
    private func updateTrafficLightReserve() {
        // No lights is no reserve: the bar starts its own inset from the edge,
        // as it ends its inset from the other.
        let reserve = TrafficLightSpace.rect(in: self).map { $0.maxX + TopBarMetrics.lightsGap } ?? TopBarMetrics.clusterGap
        guard let leadingInset, abs(leadingInset.constant - reserve) > .ulpOfOne else { return }
        leadingInset.constant = reserve
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrafficLightReserve()
    }

    override func layout() {
        super.layout()
        // Converges: the guard above stops the second pass from changing it.
        updateTrafficLightReserve()
    }

    /// §4 / §8: dragging the bar's background moves the window. The controls,
    /// the plate, the tiles and the tabs all opt out for themselves, so it is
    /// only ever the empty bar that moves it.
    override var mouseDownCanMoveWindow: Bool { true }

    /// The empty bar's right-click is the strip's — §3.4b's New Folder.
    override func menu(for event: NSEvent) -> NSMenu? {
        strip.emptyMenu()
    }

    // MARK: - Accessibility display options

    @objc private func accessibilityDisplayOptionsChanged() {
        Self.applyTokens(from: self)
    }

    private static func applyTokens(from view: NSView) {
        (view as? any TopBarThemed)?.applyTokens()
        for subview in view.subviews { applyTokens(from: subview) }
    }
}
