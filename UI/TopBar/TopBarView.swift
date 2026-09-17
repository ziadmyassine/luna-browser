//
//  TopBarView.swift
//  Luna
//
//  The sidebar-off layout (UI-SPEC §4, TODO.md §30.12–30.14): one 52 pt glass
//  bar spanning the window, with the page flush full-bleed below it. It is a
//  second layout, not a collapsed sidebar — `ContentCardView` already knows
//  that (`cardInsets` for `.topBar` has no gap and no corners).
//
//      [traffic lights] [back 28] [tiles … PILL … tiles] [|] [capsule]
//
//  Four things are deliberately absent:
//    · **No sidebar toggle.** There is no sidebar in this layout to hide, so
//      the button was a control that either did nothing or silently changed a
//      preference. `⌘S` still works wherever there is a sidebar; which chrome
//      the window wears is Settings' decision (`Settings.chromeLayout`).
//    · **No reload button.** The reference omits it; §4 makes reload `⌘R` and
//      the site menu inside the pill.
//    · **No traffic-light layout.** `TrafficLightLayoutManager` owns those
//      frames for every window state (§7.7). The bar only measures how much
//      room they take and starts after it.
//    · **No page tint on the bar itself.** §2: the chrome samples what is
//      *behind the window*. The URL pill carries the only page-derived colour.
//

import AppKit
import BrowserKit

/// §4 gives no gap table of its own, so the bar borrows §3.1's: 8 pt between
/// tight neighbours, 16 pt between clusters. Both are derived from an existing
/// token rather than written down again — there is no `chromeGap` token yet,
/// and rule 2 forbids inventing one here.
enum TopBarMetrics {
    /// §3.1's "gap 8".
    static var gap: CGFloat { Tokens.Metric.rowInset }
    /// §3.1's "gap 16", and the bar's own leading / trailing inset.
    static var clusterGap: CGFloat { Tokens.Metric.rowInset * 2 }
    /// §4: inactive tabs are 28 pt icon-only tiles.
    static var tile: RoundedMetric { Tokens.Metric.controlSquircle }
    /// One capsule item, and the diameter **every** button on this bar uses —
    /// back included. Round because the capsule it sits in is a cylinder with
    /// rounded ends.
    static var capsuleItem: RoundedMetric { .circle(Tokens.Metric.controlSquircle.width) }
    /// The capsule's padding around its items. Half a `rowInset`, which lands
    /// the capsule at 36 pt tall — the measured height in the reference.
    static var capsuleInset: CGFloat { Tokens.Metric.rowInset / 2 }
    /// Glyph and favicon size for every control on the bar.
    static var glyph: CGFloat { Tokens.Metric.faviconSize }
}

/// Anything on the bar holding a token *by value*, and therefore needing to be
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
final class TopBarView: NSView {

    // MARK: - Seams

    /// The downloads popover (§5) anchors to the button it is passed.
    var onDownloads: ((NSView) -> Void)?
    var onProfile: ((NSView) -> Void)?

    /// v2's extension action buttons (§16.4, §30.14). The capsule is built to
    /// host a variable number of items, so shipping them is an assignment here
    /// rather than a re-layout of the bar's whole right side.
    var extensionActions: [TopBarActionItem] = [] { didSet { rebuildCapsule() } }

    /// Where agent H's download popover points.
    var downloadsAnchor: NSView? { capsule.view(for: Self.downloadsItem) }

    // MARK: - Views

    private static let newTabItem = "luna.topBar.newTab"
    private static let downloadsItem = "luna.topBar.downloads"
    private static let profileItem = "luna.topBar.profile"

    private let session: BrowserSession
    /// **The capsule item's circle**, so back is the same size as the new-tab,
    /// downloads and profile buttons at the other end of the bar. The bar has
    /// one button size and this is it.
    private let backButton = TopBarButton(metric: TopBarMetrics.capsuleItem, glass: true)
    private let strip: TopBarTabStrip
    private let separator = TopBarSeparator()
    private let capsule = TopBarActionCapsule()
    private var leadingInset: NSLayoutConstraint?

    init(session: BrowserSession) {
        self.session = session
        strip = TopBarTabStrip(session: session)
        super.init(frame: .zero)

        wantsLayer = true
        // The bar's height animates 0 → 52 during the §4.1 switch; without this
        // its contents spill over the page on the way up.
        clipsToBounds = true
        Glass.apply(.topBar, to: self)

        buildControls()
        buildLayout()
        rebuildCapsule()
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

    /// Back sends its action to `nil`, so it travels the responder chain to the
    /// same `AppDelegate` method the menu item calls — §22.5's "declared once,
    /// implemented once".
    private func buildControls() {
        backButton.icon = TopBarButton.symbol("chevron.backward")
        backButton.setAccessibilityLabel(String(localized: "Back"))
        backButton.target = nil
        backButton.action = #selector(AppDelegate.goBack(_:))
    }

    /// `ChromeHostView` keeps **both** layouts alive and cross-fades them, and
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
        // `⌘L` belongs to whichever layout is on screen (§3.2, §4); when the
        // sidebar is showing, the bar hands the command straight back.
        let previousFocus = session.focusURLField
        session.focusURLField = { [weak self] in
            guard let self, isOnScreenLayout else {
                previousFocus?()
                return
            }
            beginURLEditing()
        }
    }

    /// True only for the layout the user can actually see: `ChromeHostView`
    /// hides the faded-out one and holds the other at full alpha.
    private var isOnScreenLayout: Bool {
        window != nil && !isHiddenOrHasHiddenAncestor && alphaValue > 0
    }

    private func buildLayout() {
        let views: [NSView] = [backButton, strip, separator, capsule]
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            view.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        }
        // Measured from the real window buttons in `updateTrafficLightReserve`;
        // this is only the floor until there is a window to measure.
        let leading = backButton.leadingAnchor.constraint(
            equalTo: leadingAnchor,
            constant: Tokens.Metric.rowInset
        )
        leadingInset = leading

        NSLayoutConstraint.activate([
            leading,
            strip.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: TopBarMetrics.clusterGap),
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
            guard let self else { return }
            _ = session.newTab(url: nil, kind: .today)
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
            label: String(localized: "Profile")
        ) { [weak self] in
            guard let self, let anchor = capsule.view(for: Self.profileItem) else { return }
            onProfile?(anchor)
        }
        capsule.items = extensionActions + [newTab, downloads, profile]
    }

    // MARK: - State

    /// Re-reads everything from the session. Safe to call from the coordinator
    /// as well as from `onChange`.
    func refresh() {
        backButton.isEnabled = activeState?.canGoBack ?? false
        strip.reload()
    }

    /// One tab's live state (§4.3): title, progress, `themeColor`.
    func apply(_ state: TabState, for id: UUID) {
        if id == session.activeTabID { backButton.isEnabled = state.canGoBack }
        strip.apply(state, for: id)
    }

    /// `⌘L` (§20.1): the pill expands to the full URL, selected. `Esc` reverts.
    func beginURLEditing() {
        strip.beginURLEditing()
    }

    private var activeState: TabState? {
        session.activeTabID.flatMap { session.controller(for: $0)?.state }
    }

    // MARK: - §4.1 layout switch

    /// `ChromeHostView` un-hides this layout at the start of the switch and
    /// fades it in from there, which is exactly the moment §4.1's stagger
    /// belongs to — so the bar plays it itself and the coordinator does not
    /// have to remember to.
    override func viewDidUnhide() {
        super.viewDidUnhide()
        // **Only when this really is the layout coming on screen.** AppKit
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
        let views: [NSView] = [backButton, strip, separator, capsule]
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

    /// The bar starts after the traffic lights, and it *measures* them rather
    /// than assuming a width: `TrafficLightLayoutManager` owns their placement
    /// and a second copy of that arithmetic here would be the §7.7 bug.
    private func updateTrafficLightReserve() {
        guard let window else { return }
        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let edge = types
            .compactMap { window.standardWindowButton($0) }
            .map { convert($0.bounds, from: $0).maxX }
            .max()
        guard let edge else { return }
        let reserve = edge + TopBarMetrics.clusterGap
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

// MARK: - Separator

/// §4's vertical hairline, dividing the tab strip from the action capsule.
@MainActor
final class TopBarSeparator: NSView, TopBarThemed {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: Tokens.Metric.hairline,
            height: Tokens.Metric.topBarHeight - TopBarMetrics.clusterGap * 2
        )
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Tokens.Line.hairline.cgColor
    }

    func applyTokens() { needsDisplay = true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
