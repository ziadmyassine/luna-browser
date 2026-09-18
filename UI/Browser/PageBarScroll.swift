//
//  PageBarScroll.swift
//  Luna
//
//  §3.2b's one rule: when the page bar is open and when it is out of the way.
//
//  A value, with no view and no session in it, for the reason
//  `TrafficLightLayout` is one — the rule is the part that can be wrong in ways
//  that are invisible until someone scrolls a particular page a particular way,
//  and a rule that can be asserted is a rule that stays right.
//
//  **The comparison is against an anchor, not against the last frame.** A page
//  reports its offset on every animation frame of a drag, so a rule comparing
//  consecutive frames would answer a two-pixel momentum wobble. The anchor is
//  the offset the bar last answered at: it takes `pageBarScrollSlack` of travel
//  away from it to change state, and the anchor then trails the page in
//  whichever direction it is already going, so the *next* reversal is measured
//  from where the user stopped rather than from where they started.
//

import Foundation

struct PageBarScroll {

    /// Whether the bar should currently be out of the way.
    private(set) var isCollapsed = false

    /// The offset the last decision was taken at.
    private var anchor: Double = 0

    /// How far the page has to travel to change the bar's mind.
    static var slack: Double { Double(Tokens.Metric.pageBarScrollSlack) }

    /// A new page, or a new tab: open, and forget where the last one was.
    mutating func reset() {
        isCollapsed = false
        anchor = 0
    }

    /// Feeds in the page's vertical offset.
    ///
    /// - Returns: `true` when `isCollapsed` changed, so the caller animates
    ///   once per state change rather than once per frame.
    @discardableResult
    mutating func page(movedTo offset: Double) -> Bool {
        let travelled = offset - anchor
        let was = isCollapsed
        // **The top of the page always shows the bar.** Without this a page left
        // a slack's worth down — a short flick, a restored scroll position —
        // would sit there collapsed with a clear gap above its content.
        if offset <= Self.slack {
            isCollapsed = false
            anchor = offset
        } else if travelled > Self.slack {
            isCollapsed = true
            anchor = offset
        } else if travelled < -Self.slack {
            isCollapsed = false
            anchor = offset
        } else if (isCollapsed && travelled > 0) || (!isCollapsed && travelled < 0) {
            // Still going the way we already answered. Let the anchor follow, so
            // the reversal that matters is measured from here.
            anchor = offset
        }
        return isCollapsed != was
    }
}
