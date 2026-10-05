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

    private var width: CGFloat { Tokens.Metric.agentPanelWidth }

    func install(_ view: NSView, in root: NSView, above card: NSView) {
        guard panel == nil else { return }
        panel = view
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alphaValue = 0
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
    /// it slides with the pane.
    func place(for state: ChromeState) {
        guard let panel else { return }
        let edge = edge(for: state)
        let side = side(for: state)
        leading?.isActive = side == .leading
        trailing?.isActive = side == .trailing
        let offset = edge == nil ? -width : 0
        leading?.constant = offset
        trailing?.constant = offset
        // Under §4's bar; and on the leading side, under the traffic lights.
        switch (state, side) {
        case (.topBar, _): top?.constant = TopBarMetrics.barHeight
        case (_, .leading): top?.constant = Tokens.Metric.pageBar
        default: top?.constant = 0
        }
        panel.animator().alphaValue = edge == nil ? 0 : 1
    }
}

extension BrowserWindowController {

    /// Shows or hides the agent panel, sliding the page aside for it.
    func setAgentPanel(_ view: NSView, shown: Bool) {
        if let root = window?.contentView, let card = root.subviews.first(where: { $0 is ContentCardView }) {
            agentHost.install(view, in: root, above: card)
        }
        guard agentHost.isShown != shown else { return }
        agentHost.isShown = shown
        apply(chromeState, animated: true)
    }

    var isAgentPanelShown: Bool { agentHost.isShown }
}
