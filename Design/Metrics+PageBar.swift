//
//  Metrics+PageBar.swift
//  Luna
//
//  §3.2b's page bar: the sidebar's address pill and its three controls, moved
//  onto the page. Separate from Metrics.swift because that file is at the
//  400-line limit.
//
//  Almost nothing here is a new number — the bar is the sidebar's head
//  floating over the page, so it borrows the sidebar's band height, gaps and
//  pill. Only the collapsed band, the expanded pill's width and the scroll
//  slack are genuinely new.
//

import Foundation

extension Tokens.Metric {

    /// The band the bar's controls sit in, at rest. §3.1's row height, because
    /// the bar is §3.1's row: same circles, same pill, on the page instead of
    /// in the column.
    static let pageBar: CGFloat = topBarHeight

    /// The band it shrinks to once the page scrolls. Tall enough for the domain
    /// at `TypeScale.urlPill` plus the capsule's padding, and no taller: the
    /// collapsed state exists to give the page back its top edge.
    static let pageBarCollapsed: CGFloat = 30

    /// The collapsed capsule's height, inside `pageBarCollapsed`.
    static let pageBarCollapsedPillHeight: CGFloat = 22

    /// Leading and trailing inset. §3.1's "gap 16", the same distance the
    /// sidebar's toggle keeps from the traffic lights.
    static let pageBarInset: CGFloat = chromeGapWide

    /// The expanded pill's width.
    ///
    /// Wider than `urlPill`'s 266, which is a column's pill: the page bar has a
    /// whole window to sit in and the reference's pill spans half of it. A
    /// ceiling rather than a width — `PageChromeBar` takes the lesser of this
    /// and what the row has room for, so a narrow window shrinks the pill
    /// instead of overlapping the buttons.
    static let pageBarPillWidth: CGFloat = 420

    /// The sidebar's top row once §3.2b has taken its buttons away.
    ///
    /// With only the traffic lights in it, 52 pt leaves 20 pt of nothing above
    /// the Essentials grid. The lights are 14 pt tall at `trafficLightInset`
    /// from the window's top, so they end at 32, and `rowInset` on top of that
    /// is the breathing room every other edge in the column gets. The row
    /// cannot go lower: that is what keeps the lights' corner clear, and
    /// `TrafficLightLayout` places them identically in every layout.
    static let sidebarHeadlessRow: CGFloat = trafficLightInset + trafficLightHeight + rowInset

    /// AppKit's own, measured on macOS 26 by the probe `TrafficLightLayoutTests`
    /// carries its fixtures from: three 14 × 14 buttons in a 32 pt titlebar.
    /// Read at runtime wherever there is a window to read it from; this is the
    /// constant for the one place that reserves the space before there is one.
    static let trafficLightHeight: CGFloat = 14

    /// How far the page has to move before the bar changes state. Not zero: a
    /// page that answers a scroll by nudging itself two points — an anchor
    /// jump, a sticky header settling, momentum unwinding — would otherwise
    /// flip the bar open and shut while the user is holding still.
    static let pageBarScrollSlack: CGFloat = 24
}
