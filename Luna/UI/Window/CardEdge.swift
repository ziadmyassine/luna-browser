//
//  CardEdge.swift
//  Luna
//
//  Which edge of the page's pane meets the chrome, and the pane's insets for
//  each layout. Split out of `ContentCardView.swift` for length; neither needs
//  anything the card keeps.
//

import AppKit

/// The one edge of the page's pane that meets the chrome rather than the
/// window, and so the pair of corners that is rounded.
enum CardEdge: Equatable {
    case leading, trailing, top

    init(_ edge: SidebarEdge) {
        self = edge == .leading ? .leading : .trailing
    }

    /// The pane's two corners along this edge.
    var corners: CACornerMask {
        switch self {
        case .trailing: [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        case .top: [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        case .leading: [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        }
    }
}

extension ChromeState {

    /// Which of the pane's edges is not a window edge, and therefore which pair
    /// of corners is rounded: the side the sidebar is on, or the top under §4's
    /// bar. Collapsed or in fullscreen the pane meets the window on every side
    /// and the window's own mask is the only corner there is.
    var cardInsetEdge: CardEdge? {
        switch self {
        case let .sidebar(_, edge): CardEdge(edge)
        case .topBar: .top
        case .sidebarCollapsed, .fullscreen: nil
        }
    }

    var cardIsInset: Bool { cardInsetEdge != nil }

    /// The card's inset from the window's content view, per layout.
    ///
    /// Pure, and unit-tested alongside the traffic lights: this and
    /// `TrafficLightLayout` are the only two places window geometry is decided.
    var cardInsets: NSEdgeInsets {
        switch self {
        case let .sidebar(width, edge):
            // Flush to the window's top and bottom and to the edge the sidebar
            // is not on; the sidebar is the only thing that insets it.
            return switch edge {
            case .leading: NSEdgeInsets(top: 0, left: width, bottom: 0, right: 0)
            case .trailing: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: width)
            }
        case .sidebarCollapsed:
            // Flush, lights and all. Hiding the sidebar means the page
            // fills the window; reserving a 52 pt strip for the traffic lights
            // would leave a band of empty glass across the top, which is not
            // "hidden". The lights keep their own place in the titlebar and
            // float over the page, which is what every browser that has this
            // mode does.
            return NSEdgeInsets()
        case .topBar:
            // §4: flush full-bleed below the bar.
            return NSEdgeInsets(top: TopBarMetrics.barHeight, left: 0, bottom: 0, right: 0)
        case .fullscreen:
            return NSEdgeInsets()
        }
    }
}
