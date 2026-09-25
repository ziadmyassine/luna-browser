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

    /// The bar's frame is the open band, whatever state it is in: nothing
    /// here resizes, so the plane and the controls can travel inside a frame
    /// that is standing still. `hitTest` is what keeps the part of it the plane
    /// does not cover from taking the page's clicks.
    override func layout() {
        super.layout()
        Tokens.Motion.immediately { applyState() }
    }

    /// The surface before the frames: the pill's own contents are laid out
    /// against the margins its surface keeps, and the collapsed one keeps
    /// narrower ones.
    func applyState() {
        pill.surface = isCollapsed ? .bare : .glass
        placeControls()
        for view in buttons { view.alphaValue = isCollapsed ? 0 : 1 }
    }

    /// The room the bar is taking right now, for the page below it.
    var bandHeight: CGFloat {
        isCollapsed ? Tokens.Metric.pageBarCollapsed : Tokens.Metric.pageBar
    }

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
        let centreY = isCollapsed ? strip.midY : (lights?.midY ?? strip.midY)

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
        //
        // The open layout places the pill and the collapsed one keeps that
        // place exactly — same x, same width. They were worked out separately
        // before, and even once they shared a centre the capsule still
        // travelled, because its two edges did: it drew in from 420 pt to the
        // width of `apple.com` while its material faded.
        //
        // It can keep the width because collapsed it has no surface. A `.bare`
        // pill draws nothing but its centred domain, so 420 pt of it is 420 pt
        // of nothing with a word in the middle, already on the centre line the
        // open pill put it on. Nothing moves sideways; the height and the
        // material are all of it. It also puts truncation beyond reach: a
        // domain that fits the open pill fits the collapsed one.
        let right = bounds.maxX - Tokens.Metric.pageBarInset
        let left = buttonsEnd + Tokens.Metric.chromeGapWide
        let width = min(Tokens.Metric.pageBarPillWidth, max(right - left, 0))
        let height = isCollapsed ? Tokens.Metric.pageBarCollapsedPillHeight : circle.height
        pill.frame = NSRect(
            x: min(max(bounds.midX - width / 2, left), max(right - width, left)),
            y: centreY - height / 2,
            width: width,
            height: height
        ).pixelAligned
    }

    // MARK: - Events

    /// Only the band takes events. The bar's frame is the open band's
    /// height whichever state it is in, so while it is collapsed the lower
    /// 22 pt of it is over live page and must behave like page: a link there
    /// has to stay clickable.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        // A control or the pill: theirs.
        guard hit === self || hit === plane else { return hit }
        return band.contains(convert(point, from: superview)) ? self : nil
    }

    /// The window has one handle at a time, and it is the chrome that is on
    /// screen. In this layout that is §3's column: the sidebar's plane moves
    /// the window, and this bar — which is over the page, inside the card,
    /// clipped to the page's own corners — does not.
    ///
    /// It used to move it too, on the reasoning that a chrome bar is a chrome
    /// bar. Two handles on one window is one too many: with the sidebar out the
    /// window could be dragged from a band that belongs to the page, which is
    /// also the band §3.2b asks the pointer to aim at for the pill,
    /// the toggle and the history cluster.
    ///
    /// The exception is the state where there is no column to drag by. With
    /// the sidebar hidden this bar is the only chrome above the page, and a
    /// window whose only handle has been put away is one the user cannot move
    /// at all. Computed rather than stored: AppKit asks at mouse-down, so the
    /// answer is never a copy of a state that has since changed.
    /// The lights this bar's buttons stand clear of, or nil.
    ///
    /// Behind a sidebar hidden off the leading edge there are none. The lights
    /// only show there on §7.2's peek, and then they are on the sidebar that
    /// has slid out over this bar, not beside its buttons: cleared anyway, the
    /// toggle and the history cluster stepped right under the sidebar every
    /// time it came out, and back when it went. A trailing sidebar's peek
    /// leaves the lights over the page, so those are still cleared.
    private var lightsBesideTheBar: NSRect? {
        let state = (window?.windowController as? BrowserWindowController)?.chromeState
        guard state != .sidebarCollapsed(edge: .leading) else { return nil }
        return TrafficLightSpace.rect(in: self)
    }

    override var mouseDownCanMoveWindow: Bool {
        (window?.windowController as? BrowserWindowController)?.chromeState.isSidebarCollapsed ?? false
    }
}
