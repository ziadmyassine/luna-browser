//
//  PageChromeBarLayout.swift
//  Luna
//
//  Where §3.2b's bar puts its controls and its pill, and which part of it takes
//  a click.
//
//  Split out of `PageChromeBar.swift` for that file's length limit.
//
//  The handful of members this reaches are `internal` rather than `private`,
//  like the pill's `field` and `sliders`: still the bar's, and nothing outside
//  these two files touches them.
//

import AppKit

extension PageChromeBar {

    // MARK: - Layout

    override func layout() {
        super.layout()
        // Through a chrome transition the bar's frame slides, and its controls
        // slide with it in the same animation. Placed at their end at once,
        // the pill and the extensions jumped there on the first frame while
        // the page's edge was still on its way. Anything else, the bar's
        // first layout above all, lands at once.
        let sliding = NSAnimationContext.current.allowsImplicitAnimation && placedWidth > 0 && placedWidth != bounds.width
        placedWidth = bounds.width
        if sliding { placeControls() } else { Tokens.Motion.immediately { placeControls() } }
    }

    /// The room the bar takes, for the page below it.
    var bandHeight: CGFloat { Tokens.Metric.pageBar }

    /// The band the plane fills, in this view's coordinates.
    var band: NSRect {
        NSRect(x: bounds.minX, y: bounds.maxY - bandHeight, width: bounds.width, height: bandHeight)
    }

    func placeControls() {
        let circle = Tokens.Metric.sidebarCircle
        let strip = band
        // Only lights standing beside the band. Under §4's top bar they are on
        // the bar above it, and a bar that lined its controls up with them
        // put its buttons half out of its own band.
        let lights = lightsBesideTheBar.flatMap { lights in
            (strip.minY...strip.maxY).contains(lights.midY) ? lights : nil
        }
        plane.frame = strip

        // The traffic lights are the centre line whenever they are on
        // screen. The pane is flush to the window's top in every state this
        // bar appears in, so the lights' centre is a line this view shares with
        // §3.1's control row — and the two must agree, because with the sidebar
        // showing they are 280 pt apart on the same row of pixels.
        let centreY = lights?.midY ?? strip.midY

        // With the sidebar showing, the lights are 280 pt to the left of this
        // view and `maxX` comes back negative — which is exactly right, and why
        // this is a `max` rather than a branch on the chrome state.
        let start = max(
            lights.map { $0.maxX + Tokens.Metric.chromeGapWide } ?? 0,
            Tokens.Metric.pageBarInset
        )
        var x = start
        for view in buttons {
            // Each asks how wide it is, because one of them changes: the
            // history cluster is a circle until there is a forward to go to and
            // a capsule after that (`NavCluster`).
            let width = view.intrinsicContentSize.width
            view.frame = NSRect(
                x: x,
                y: centreY - circle.height / 2,
                width: width,
                height: circle.height
            ).pixelAligned
            x += width + Tokens.Metric.controlPairGap
        }
        let buttonsEnd = x - Tokens.Metric.controlPairGap

        // The buttons' own diameter, not the pill's own height token. The
        // two are the same 34 pt today — `sidebarCircle` is defined as a circle
        // of `urlPill.height` — and on this bar they have to stay the same:
        // four controls on one line, one of them a different height, is the
        // thing the eye finds first.
        //
        // Centred on the pane when there is room, and pushed off centre when
        // there is not. A 640 pt window with a sidebar open leaves about
        // 230 pt beside the buttons; a pill centred in that overlaps them, and
        // an overlapping pill is worse than an off-centre one.
        let left = buttonsEnd + Tokens.Metric.chromeGapWide
        let right = placeShelf(centreY: centreY, after: left)
        let width = min(Tokens.Metric.pageBarPillWidth, max(right - left, 0))
        pill.frame = NSRect(
            x: min(max(bounds.midX - width / 2, left), max(right - width, left)),
            y: centreY - circle.height / 2,
            width: width,
            height: circle.height
        ).pixelAligned
    }

    // MARK: - Events

    /// Only the band takes events: anything the bar's frame covers past it is
    /// live page, and a link there has to stay clickable.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        // A control or the pill: theirs.
        guard hit === self || hit === plane else { return hit }
        return band.contains(convert(point, from: superview)) ? self : nil
    }

    /// The lights this bar's buttons stand clear of, or nil.
    ///
    /// None behind a sidebar hidden off the leading edge: the lights only show
    /// there on §7.2's peek, on the sidebar that has slid out over this bar.
    /// Cleared anyway, the toggle and the history cluster stepped under the
    /// sidebar every time it came out, and back when it went. A trailing
    /// sidebar's peek leaves the lights over the page, so those are cleared.
    private var lightsBesideTheBar: NSRect? {
        let state = (window?.windowController as? BrowserWindowController)?.chromeState
        guard state != .sidebarCollapsed(edge: .leading) else { return nil }
        return TrafficLightSpace.rect(in: self)
    }

    /// The window has one handle at a time: the chrome on screen. In this
    /// layout that is §3's column, and this bar — over the page, inside the
    /// card — does not move the window. Not both: with the sidebar out, the
    /// window could be dragged from a band that belongs to the page, the band
    /// §3.2b asks the pointer to aim at for the pill, the toggle and the
    /// history cluster.
    ///
    /// Except with the sidebar hidden, when this bar is the only chrome above
    /// the page and the window's only handle. Computed rather than stored:
    /// AppKit asks at mouse-down, so the answer is never a stale copy.
    override var mouseDownCanMoveWindow: Bool {
        (window?.windowController as? BrowserWindowController)?.chromeState.isSidebarCollapsed ?? false
    }
}
