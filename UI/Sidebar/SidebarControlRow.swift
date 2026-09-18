//
//  SidebarControlRow.swift
//  Luna
//
//  §3.1, 52 pt: `[traffic lights] · [toggle 28] ··· [back 28] [reload 28]`.
//
//  **The traffic lights are not laid out here.** `TrafficLightLayoutManager`
//  owns their frames for all six window states (§7.7); this row only has to
//  leave their space clear. It does that by measuring what AppKit owns and
//  never moves — the buttons' size, and the spacing between them — and deriving
//  the rest from `trafficLightInset`, the one number the manager places them
//  with. Reading their live origins instead is a race this row loses on every
//  resize; see `trafficLights`.
//
//  Two deliberate departures from §3.1's written order, both measured off
//  `inspiration/main-tab-bar-and-ui.png`:
//
//  · the reference puts the toggle beside the traffic lights and pins
//    back/reload to the **trailing** edge, not 16 pt after the toggle. §3.1's
//    gap figure describes a cluster the reference does not have.
//  · **the toggle is the same circle as its two neighbours**, not the squircle
//    §3.1 quotes, and its glyph sits on the same centre line as the traffic
//    lights — which is why this row asks the window for that line rather than
//    centring in its own 52 pt.
//
//  The circle is `Metric.sidebarCircle` — the URL pill's own height — so the
//  sidebar's head is one stack of equal-height controls instead of three small
//  buttons above a bigger one. All three carry their glass at rest: the toggle
//  is how you get the sidebar back, and a control you cannot see until you
//  happen to sweep the pointer over it is not one.
//

import AppKit

@MainActor
final class SidebarControlRow: NSView {

    var onToggleSidebar: (() -> Void)?
    var onBack: (() -> Void)?
    /// Reload, or stop while the page is loading.
    var onReloadOrStop: ((_ isLoading: Bool) -> Void)?

    /// **Always glass.** It briefly carried its material on hover only; that
    /// made the one control that brings a hidden sidebar back invisible until
    /// the pointer found it, which is the wrong trade for the one button on
    /// this row that is not reachable any other way.
    private let toggle = GlassButton(
        shape: Tokens.Metric.sidebarCircle,
        symbolName: "sidebar.leading",
        pointSize: Tokens.Metric.glyphSize,
        label: "Hide Sidebar"
    )
    private let back = GlassButton(
        shape: Tokens.Metric.sidebarCircle,
        symbolName: "chevron.backward",
        pointSize: Tokens.Metric.glyphSize,
        label: "Back"
    )
    private let reload = GlassButton(
        shape: Tokens.Metric.sidebarCircle,
        symbolName: "arrow.clockwise",
        pointSize: Tokens.Metric.glyphSize,
        label: "Reload"
    )
    private var isLoading = false

    /// **False when §3.2b has moved these three onto the page.** The row itself
    /// stays — it is what keeps the traffic lights' corner clear, and the lights
    /// do not move when the pill does (`TrafficLightLayout` places them the same
    /// way in every layout). Only its buttons go.
    var showsButtons = true {
        didSet {
            guard showsButtons != oldValue else { return }
            for view in [toggle, back, reload] { view.isHidden = !showsButtons }
        }
    }
    /// Whether the last pass found the traffic lights. See `placeButtons`.
    private var hadLights = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toggle.onActivate = { [weak self] in self?.onToggleSidebar?() }
        back.onActivate = { [weak self] in self?.onBack?() }
        reload.onActivate = { [weak self] in
            guard let self else { return }
            onReloadOrStop?(isLoading)
        }
        for view in [toggle, back, reload] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Tokens.Metric.topBarHeight)
    }

    // MARK: - State

    /// §3.1: back dims when there is nowhere to go, and reload becomes a stop
    /// glyph for as long as the page is loading.
    func update(canGoBack: Bool, isLoading: Bool) {
        back.isEnabled = canGoBack
        guard isLoading != self.isLoading else { return }
        self.isLoading = isLoading
        reload.setSymbol(isLoading ? "xmark" : "arrow.clockwise")
        reload.setAccessibilityLabel(isLoading ? "Stop" : "Reload")
    }

    // MARK: - Layout

    /// The space the three traffic lights occupy, in this row's coordinates —
    /// or nil when there are none to clear. See `TrafficLightSpace` for why the
    /// read is derived rather than taken from the buttons' live origins, and
    /// for the second caller it is shared with.
    ///
    /// **And nil when they are not on this row at all.** macOS keeps the lights
    /// at the window's top-left and offers no way to move them, so a sidebar
    /// standing on the *trailing* edge does not contain them — they float over
    /// the page instead, which is what every browser that offers a right-hand
    /// sidebar does. Reserving their space anyway would push the toggle off the
    /// column entirely; that is what a rect starting left of this row is saying.
    private var trafficLights: NSRect? {
        guard let rect = TrafficLightSpace.rect(in: self), rect.minX >= bounds.minX else { return nil }
        return rect
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately { placeButtons() }
    }

    private func placeButtons() {
        let inset = Tokens.Metric.rowInset
        let circle = Tokens.Metric.sidebarCircle
        let lights = trafficLights
        // **A nil that was not nil a moment ago is worth asking about twice.**
        // The buttons are legitimately gone in fullscreen and while the sidebar
        // is hidden, and then this row closes up around the space they left.
        // But AppKit also rebuilds the titlebar from time to time, and a pass
        // that lands inside that rebuild measures nothing and lays the toggle
        // out over the lights it could not see. One more pass on the next tick
        // settles it, and costs nothing when they really are gone: the second
        // pass finds nil as well and stops asking.
        if lights == nil, hadLights {
            DispatchQueue.main.async { [weak self] in self?.needsLayout = true }
        }
        hadLights = lights != nil
        // §3.1: the three buttons share the traffic lights' centre line. The
        // lights sit `trafficLightInset` from the window's top, which is not
        // the centre of a 52 pt row — centring here instead would leave them a
        // point apart, which is exactly the misalignment this row is fixing.
        let centreY = lights?.midY ?? bounds.midY
        let originY = centreY - circle.height / 2
        // With no lights to clear, the toggle starts where any other row does.
        let toggleX = lights.map { $0.maxX + Tokens.Metric.chromeGapWide } ?? inset
        toggle.frame = NSRect(
            x: toggleX,
            y: originY,
            width: circle.width,
            height: circle.height
        ).pixelAligned
        reload.frame = NSRect(
            x: bounds.maxX - inset - circle.width,
            y: originY,
            width: circle.width,
            height: circle.height
        ).pixelAligned
        back.frame = NSRect(
            x: reload.frame.minX - Tokens.Metric.controlPairGap - circle.width,
            y: originY,
            width: circle.width,
            height: circle.height
        ).pixelAligned
    }
}
