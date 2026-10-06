//
//  AgentPanelHost.swift
//  Luna
//
//  Where a window keeps the agent panel (`AgentPanelView`): a column on the
//  window's glass on the side the sidebar is not on — trailing, unless the
//  sidebar is — under §4's bar in the top-bar layout, and gone in page
//  fullscreen. The page's pane makes room for it, and rounds its corners on
//  that side as it does against the sidebar. Its own type rather than more
//  constraints on `BrowserWindowController`, which is at its length limit.
//

import AppKit

@MainActor
final class AgentPanelHost {

    private(set) var panel: NSView?
    var isShown = false
    private var leading: NSLayoutConstraint?
    private var trailing: NSLayoutConstraint?
    private var top: NSLayoutConstraint?
    /// The panel's light, under the page and a corner wider than the panel.
    private var aura: NSView?
    private var auraLeading: NSLayoutConstraint?
    private var auraTrailing: NSLayoutConstraint?

    private var width: CGFloat { Tokens.Metric.agentPanelWidth }

    /// Adds the panel the first time it is shown, parked off the window's
    /// edge and laid out there at once — so the first show slides it in from
    /// the edge like every later one, rather than growing it out of the
    /// window's corner from a zero frame. Returns whether it was added.
    @discardableResult
    func install(_ view: NSView, in root: NSView, above card: NSView, for state: ChromeState) -> Bool {
        guard panel == nil else { return false }
        panel = view
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        root.addSubview(view, positioned: .above, relativeTo: card)
        leading = view.leadingAnchor.constraint(equalTo: root.leadingAnchor)
        trailing = root.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        top = view.topAnchor.constraint(equalTo: root.topAnchor)
        NSLayoutConstraint.activate([
            top, view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            view.widthAnchor.constraint(equalToConstant: width)
        ].compactMap { $0 })
        trailing?.constant = -width
        trailing?.isActive = true
        if let light = (view as? AgentPanelView)?.aura { installAura(light, in: root, below: card, beside: view) }
        if let card = card as? ContentCardView {
            // WebKit sets a docked inspector's frame after adding it.
            card.onSubviewsChange = { [weak self, weak card] in
                DispatchQueue.main.async { if let card { self?.shade(beside: card) } }
            }
        }
        Tokens.Motion.immediately {
            place(for: state)
            root.layoutSubtreeIfNeeded()
        }
        return true
    }

    /// Under the page, the panel's height and a window corner wider than it on
    /// the page's side: the page covers the overlap but for the notches its
    /// rounded corners leave, which the light fills instead of the window.
    private func installAura(_ light: NSView, in root: NSView, below card: NSView, beside panel: NSView) {
        aura = light
        light.isHidden = true
        root.addSubview(light, positioned: .below, relativeTo: card)
        auraLeading = light.leadingAnchor.constraint(equalTo: panel.leadingAnchor)
        auraTrailing = light.trailingAnchor.constraint(equalTo: panel.trailingAnchor)
        NSLayoutConstraint.activate([
            light.topAnchor.constraint(equalTo: panel.topAnchor),
            light.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            light.widthAnchor.constraint(equalTo: panel.widthAnchor, constant: WindowCorner.radius)
        ])
        auraTrailing?.isActive = true
    }

    /// The pane's edge the panel stands against, or nil when it is not shown.
    func edge(for state: ChromeState) -> CardEdge? {
        guard isShown, panel != nil else { return nil }
        switch state {
        case .fullscreen: return nil
        case .sidebar, .sidebarCollapsed, .topBar: return side(for: state)
        }
    }

    /// The pane's insets with the panel's column taken out of them.
    func adjusting(_ insets: NSEdgeInsets, for state: ChromeState) -> NSEdgeInsets {
        var insets = insets
        switch edge(for: state) {
        case .leading?: insets.left += width
        case .trailing?: insets.right += width
        case .top?, nil: break
        }
        return insets
    }

    /// The pane's edges, corners and insets for `state`, and the panel
    /// beside it, in one step of the layout transaction.
    func lay(_ card: ContentCardView, out insets: NSEdgeInsets, for state: ChromeState) {
        card.insetEdge = state.cardInsetEdge
        card.agentEdge = edge(for: state)
        card.setInsets(insets)
        place(for: state)
        shade(beside: card)
    }

    /// Tells the light where a docked Web Inspector stands against the
    /// panel, if one does: on the panel's side of the card, the whole height
    /// docked there, or its foot docked along the bottom.
    func shade(beside card: ContentCardView) {
        guard let light = aura as? AgentAura else { return }
        guard let edge = card.agentEdge, let frame = card.dockedInspectorFrame else {
            guard light.inspector != nil else { return }
            // Not until the page has grown back over the inspector's place
            // (`ContentCardView.revealPage`): the card is clear until then.
            DispatchQueue.main.asyncAfter(deadline: .now() + Tokens.Motion.sidebarCollapse.duration) { [weak card] in
                MainActor.assumeIsolated {
                    if card?.dockedInspectorFrame == nil { light.inspector = nil }
                }
            }
            return
        }
        let touches = edge == .leading ? frame.minX <= card.bounds.minX + 0.5 : frame.maxX >= card.bounds.maxX - 0.5
        let run = light.convert(frame, from: card)
        light.inspector = touches ? run.minY...run.maxY : nil
    }

    /// The side the panel belongs on, shown or not: away from the sidebar.
    private func side(for state: ChromeState) -> CardEdge {
        switch state {
        case .sidebar(_, .trailing), .sidebarCollapsed(.trailing): .leading
        default: .trailing
        }
    }

    /// Puts the panel where `state` has it: beside the pane, or parked a
    /// width off the window's edge. Called inside the layout transaction, so
    /// it slides with the pane — a slide alone, at full strength: fading it
    /// as well left it a ghost of itself for most of the move.
    func place(for state: ChromeState) {
        guard let panel else { return }
        let edge = edge(for: state)
        let side = side(for: state)
        leading?.isActive = side == .leading
        trailing?.isActive = side == .trailing
        // Pinned by the panel's outer edge, so its extra width lies under the page.
        auraTrailing?.isActive = side == .trailing
        auraLeading?.isActive = side == .leading
        // The strip lies on the page's side: leading when the panel trails.
        (aura as? AgentAura)?.notches = (WindowCorner.radius, side == .trailing)
        let offset = edge == nil ? -width : 0
        leading?.constant = offset
        trailing?.constant = offset
        // Under §4's bar; and on the leading side, under the traffic lights.
        switch (state, side) {
        case (.topBar, _): top?.constant = TopBarMetrics.barHeight
        case (_, .leading): top?.constant = Tokens.Metric.pageBar
        default: top?.constant = 0
        }
        if edge != nil {
            panel.isHidden = false
            aura?.isHidden = false
        }
    }

    /// Takes a parked panel out of the drawing once it has slid away, so its
    /// rover stops animating where nobody can see it.
    func settle() {
        guard let panel, !isShown else { return }
        panel.isHidden = true
        aura?.isHidden = true
    }
}

extension BrowserWindowController {

    /// Shows or hides the agent panel, sliding the page aside for it.
    func setAgentPanel(_ view: NSView, shown: Bool) {
        if let root = window?.contentView, let card = root.subviews.first(where: { $0 is ContentCardView }) {
            agentHost.install(view, in: root, above: card, for: chromeState)
        }
        guard agentHost.isShown != shown else { return }
        agentHost.isShown = shown
        apply(chromeState, animated: true)
        guard !shown else { return }
        let duration = Tokens.Motion.sidebarCollapse.duration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { [weak self] in
            MainActor.assumeIsolated { self?.agentHost.settle() }
        }
    }

    var isAgentPanelShown: Bool { agentHost.isShown }

    /// How long a chrome change takes. Here rather than in the controller,
    /// which is at its length limit.
    static func motion(from old: ChromeState, to new: ChromeState) -> MotionSpec {
        switch (old, new) {
        case (.fullscreen, _), (_, .fullscreen):
            Tokens.Motion.cardFullscreen
        case (.sidebar, .sidebarCollapsed), (.sidebarCollapsed, .sidebar):
            Tokens.Motion.sidebarCollapse
        // The agent panel coming or going: the state stays, and the pane
        // makes room the way it does for the sidebar.
        case let (old, new) where old == new:
            Tokens.Motion.sidebarCollapse
        default:
            Tokens.Motion.layoutSwitch
        }
    }
}
