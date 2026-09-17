//
//  SidebarControlRow.swift
//  Luna
//
//  §3.1, 52 pt: `[traffic lights] · [toggle squircle 28] ··· [back 35] [reload 35]`.
//
//  **The traffic lights are not laid out here.** `TrafficLightLayoutManager`
//  owns their frames for all six window states (§7.7); this row only has to
//  leave their space clear, and it does that by *measuring* them — converting
//  the zoom button's frame out of the titlebar and into this row — rather than
//  hard-coding a width that AppKit is free to change.
//
//  Two deliberate departures from §3.1's written order, both measured off
//  `inspiration/main-tab-bar-and-ui.png`:
//
//  · the reference puts the toggle beside the traffic lights and pins
//    back/reload to the **trailing** edge, not 16 pt after the toggle. §3.1's
//    gap figure describes a cluster the reference does not have.
//  · **the toggle is the same 35 pt circle as its two neighbours**, not the
//    28 pt squircle §3.1 quotes. All three measure 100 px across in the
//    reference, and the toggle's glyph sits on the same centre line as the
//    traffic lights — which is why this row asks the window for that line
//    rather than centring in its own 52 pt.
//

import AppKit

@MainActor
final class SidebarControlRow: NSView {

    var onToggleSidebar: (() -> Void)?
    var onBack: (() -> Void)?
    /// Reload, or stop while the page is loading.
    var onReloadOrStop: ((_ isLoading: Bool) -> Void)?

    private let toggle = GlassButton(
        shape: Tokens.Metric.controlCircle,
        symbolName: "sidebar.leading",
        pointSize: Tokens.Metric.glyphSize,
        label: "Hide Sidebar"
    )
    private let back = GlassButton(
        shape: Tokens.Metric.controlCircle,
        symbolName: "chevron.backward",
        pointSize: Tokens.Metric.glyphSize,
        label: "Back"
    )
    private let reload = GlassButton(
        shape: Tokens.Metric.controlCircle,
        symbolName: "arrow.clockwise",
        pointSize: Tokens.Metric.glyphSize,
        label: "Reload"
    )
    private var isLoading = false

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

    /// The last traffic light's frame, in this row's coordinates. Measured,
    /// because `TrafficLightLayoutManager` owns the placement and AppKit owns
    /// the button sizes — and nil before the row is in a window, when there is
    /// nothing to measure and the fallbacks below apply.
    private var trafficLights: NSRect? {
        guard let button = window?.standardWindowButton(.zoomButton),
              let titlebar = button.superview
        else { return nil }
        return convert(titlebar.convert(button.frame, to: nil), from: nil)
    }

    override func layout() {
        super.layout()
        let inset = Tokens.Metric.rowInset
        let circle = Tokens.Metric.controlCircle
        let lights = trafficLights
        // §3.1: the three buttons share the traffic lights' centre line. The
        // lights sit `trafficLightInset` from the window's top, which is not
        // the centre of a 52 pt row — centring here instead would leave them a
        // point apart, which is exactly the misalignment this row is fixing.
        let centreY = lights?.midY ?? bounds.midY
        let y = centreY - circle.height / 2
        let lightsTrailing = lights?.maxX ?? Tokens.Metric.trafficLightInset
        toggle.frame = NSRect(
            x: lightsTrailing + Tokens.Metric.chromeGapWide,
            y: y,
            width: circle.width,
            height: circle.height
        ).integral
        reload.frame = NSRect(
            x: bounds.maxX - inset - circle.width,
            y: y,
            width: circle.width,
            height: circle.height
        ).integral
        back.frame = NSRect(
            x: reload.frame.minX - Tokens.Metric.controlPairGap - circle.width,
            y: y,
            width: circle.width,
            height: circle.height
        ).integral
    }
}
