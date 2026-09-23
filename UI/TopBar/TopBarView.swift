//
//  TopBarView.swift
//  Luna
//
//  The sidebar-off layout (UI-SPEC §4, TODO.md §30.12–30.14): one 52 pt glass
//  bar spanning the window, with the page flush full-bleed below it. It is a
//  second layout, not a collapsed sidebar — `ContentCardView` already knows
//  that (`cardInsets` for `.topBar` has no gap and no corners).
//
//      [lights] [Space] [back] [kept … | … open tabs] [|] [capsule]
//
//  Both ends of the bar are the same object: `TopBarActionCapsule`, with one
//  item in it on the left and four on the right. Back used to be a bare glass
//  circle of the same 28 pt diameter, which is not the same size — the
//  cylinder adds its padding, and one control at 28 beside three at 36 is the
//  mismatch that reads.
//
//  Four things are deliberately absent:
//    · No sidebar toggle. There is no sidebar in this layout to hide, so
//      the button was a control that either did nothing or silently changed a
//      preference. `⌘S` still works wherever there is a sidebar; which chrome
//      the window wears is Settings' decision (`Settings.chromeLayout`).
//    · No reload button. The reference omits it; §4 makes reload `⌘R` and
//      the site menu on the page.
//    · No address bar. The active tab used to swell into a URL pill in the
//      middle of the strip; a strip whose tabs carry their own titles has no
//      room for a fourth shape, and `⌘L` opens §9.1 over the page instead.
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
final class TopBarView: NSView, WindowScoped {

    // MARK: - Seams

    /// The downloads pop-out (§5) anchors to the button it is passed.
    var onDownloads: ((NSView) -> Void)?
    /// §6.4's History pop-out, from the capsule button beside Downloads. The
    /// sidebar keeps its own at the foot of §3.5; this is that button's twin in
    /// the layout that has no sidebar to put it in.
    var onHistory: ((NSView) -> Void)?
    var onProfile: ((NSView) -> Void)?
    /// §3.5's Space strip, in the layout that has no sidebar foot to put it in.
    /// The same four seams the sidebar's own copy exposes.
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

    private static let backItem = "luna.topBar.back"
    private static let newTabItem = "luna.topBar.newTab"
    private static let historyItem = "luna.topBar.history"
    private static let downloadsItem = "luna.topBar.downloads"
    private static let profileItem = "luna.topBar.profile"

    let session: BrowserSession
    let windowID: UUID
    /// A capsule of one, not a bare glass circle.
    ///
    /// Back and the three buttons at the other end of the bar were already the
    /// same 28 pt item — but only one of them wore its glass directly, so back
    /// read as a smaller control than the cylinder holding new-tab, downloads
    /// and profile. Same class, same padding, same radius: one item in it
    /// instead of four, and the two ends of the bar are made of the same thing.
    private let backCapsule = TopBarActionCapsule()
    let spacePill = TopBarSpacePill()
    let strip: TopBarTabStrip
    private let separator = TopBarSeparator()
    private let capsule = TopBarActionCapsule()
    private var leadingInset: NSLayoutConstraint?
    var drag: TopBarTabDragController?

    init(session: BrowserSession, windowID: UUID) {
        self.session = session
        self.windowID = windowID
        strip = TopBarTabStrip(session: session, windowID: windowID)
        super.init(frame: .zero)

        wantsLayer = true
        // The bar's height animates 0 → 52 during the §4.1 switch; without this
        // its contents spill over the page on the way up.
        clipsToBounds = true
        Glass.apply(.topBar, to: self)

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

    /// The leading capsule: Back, and nothing else for now.
    private func buildControls() {
        backCapsule.items = [TopBarActionItem(
            id: Self.backItem,
            symbolName: "chevron.backward",
            label: String(localized: "Back")
        ) {
            // Sent to nil so it travels the responder chain to the same
            // `AppDelegate` method the menu item calls — §22.5's "declared
            // once, implemented once".
            NSApp.sendAction(#selector(AppDelegate.goBack(_:)), to: nil, from: nil)
        }]
        backCapsule.setAccessibilityLabel(String(localized: "Back"))

        spacePill.onSwitch = { [weak self] id in self?.onSwitchSpace?(id) }
        spacePill.onSetGradient = { [weak self] id, gradient in self?.onSetGradient?(id, gradient) }
        spacePill.onEditSpaces = { [weak self] in self?.onEditSpaces?() }
        spacePill.onNewSpace = { [weak self] in self?.onNewSpace?() }
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
        for view in [spacePill, backCapsule, strip, separator, capsule] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        // Not the bar's own centre: the traffic lights' (see the token). And
        // not the strip, which is pinned top and bottom — a centre line as
        // well is a third vertical constraint and one of the three gets
        // dropped. It stands its own tabs on the line instead.
        NSLayoutConstraint.activate([spacePill, backCapsule, separator, capsule].map {
            $0.centerYAnchor.constraint(
                equalTo: centerYAnchor,
                constant: TopBarMetrics.lightsCentreOffset
            )
        })
        // Set from the lights in `alignToTrafficLights`; this is the floor
        // until there is a window to ask.
        let leading = spacePill.leadingAnchor.constraint(
            equalTo: leadingAnchor,
            constant: Tokens.Metric.rowInset
        )
        leadingInset = leading

        NSLayoutConstraint.activate([
            leading,
            backCapsule.leadingAnchor.constraint(equalTo: spacePill.trailingAnchor, constant: TopBarMetrics.clusterGap),
            strip.leadingAnchor.constraint(equalTo: backCapsule.trailingAnchor, constant: TopBarMetrics.clusterGap),
            strip.topAnchor.constraint(equalTo: topAnchor),
            strip.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: strip.trailingAnchor, constant: TopBarMetrics.clusterGap),
            capsule.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: TopBarMetrics.clusterGap),
            trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: TopBarMetrics.clusterGap)
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
        let profile = TopBarActionItem(
            id: Self.profileItem,
            symbolName: "person.crop.circle",
            label: String(localized: "Space")
        ) { [weak self] in
            guard let self, let anchor = capsule.view(for: Self.profileItem) else { return }
            onProfile?(anchor)
        }
        // History beside Downloads, and both before the Space button. The
        // sidebar's foot pairs the same two — they are the same kind of thing,
        // the shelf of what you already have — so the layout without a sidebar
        // keeps the pair rather than inventing a second arrangement. The Space
        // button stays last because it is about where, not about what.
        capsule.items = extensionActions + [newTab, history, downloads, profile]
    }

    // MARK: - State

    /// Re-reads everything from the session. Safe to call from the coordinator
    /// as well as from `onChange`.
    func refresh() {
        backCapsule.setEnabled(activeState?.canGoBack ?? false, for: Self.backItem)
        spacePill.show(spaces: session.spaces, activeSpaceID: activeSpaceID)
        strip.reload()
    }

    /// One tab's live state (§4.3): title, progress, `themeColor`.
    func apply(_ state: TabState, for id: UUID) {
        if id == activeTabID { backCapsule.setEnabled(state.canGoBack, for: Self.backItem) }
        strip.apply(state, for: id)
    }

    private var activeState: TabState? {
        activeTabID.flatMap { session.controller(for: $0)?.state }
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
        let views: [NSView] = [spacePill, backCapsule, strip, separator, capsule]
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

    /// Where the bar starts: after the traffic lights, a cluster gap on.
    ///
    /// Derived, not read off the live buttons. AppKit resets their origins
    /// on every resize and `TrafficLightLayoutManager` puts them back a beat
    /// later, so a bar that believed what it saw in between laid Back against
    /// the green light rather than a gap from it. `TrafficLightSpace` is the
    /// shared answer, and §3.1's control row asks it the very same question.
    ///
    /// The other half of standing beside them — their centre line — is a
    /// constant and is set once; see `TopBarMetrics.lightsCentreOffset`.
    private func updateTrafficLightReserve() {
        guard let lights = TrafficLightSpace.rect(in: self) else { return }
        let reserve = lights.maxX + TopBarMetrics.clusterGap
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
    /// the strip's tiles and the pill all opt out for themselves.
    override var mouseDownCanMoveWindow: Bool { true }

    // MARK: - Accessibility display options

    @objc private func accessibilityDisplayOptionsChanged() {
        Self.applyTokens(from: self)
    }

    private static func applyTokens(from view: NSView) {
        (view as? any TopBarThemed)?.applyTokens()
        for subview in view.subviews { applyTokens(from: subview) }
    }
}
