//
//  ContentCardView+Corners.swift
//  Luna
//
//  Which of the page's corners round while a Web Inspector is docked beside
//  it, and how a view's layer is told. Split out of `ContentCardView.swift`
//  for length; neither needs anything the card keeps.
//

import AppKit

extension ContentCardView {

    /// The corners of `page` to round, in the card's coordinates (top is
    /// `maxY`): all of them but those where two window edges meet, which the
    /// window's own mask already rounds — and which in fullscreen are square.
    /// An edge is the window's when it lies on the card's edge and that edge
    /// is not one of the `chrome` edges, where the sidebar, the top bar or the
    /// agent's panel is.
    static func roundedCorners(of page: NSRect, in card: NSRect, chrome: Set<CardEdge>) -> CACornerMask {
        let left = page.minX <= card.minX + 0.5 && !chrome.contains(.leading)
        let right = page.maxX >= card.maxX - 0.5 && !chrome.contains(.trailing)
        let top = page.maxY >= card.maxY - 0.5 && !chrome.contains(.top)
        let bottom = page.minY <= card.minY + 0.5
        var corners: CACornerMask = []
        if !(left && top) { corners.insert(.layerMinXMaxYCorner) }
        if !(right && top) { corners.insert(.layerMaxXMaxYCorner) }
        if !(left && bottom) { corners.insert(.layerMinXMinYCorner) }
        if !(right && bottom) { corners.insert(.layerMaxXMinYCorner) }
        return corners
    }

    /// `corners` are in the card's terms, top at `maxY`; a flipped view's
    /// layer has its top at `minY`, and a web view is flipped.
    static func round(_ view: NSView, corners: CACornerMask, edged: Bool) {
        guard let layer = view.layer else { return }
        layer.cornerCurve = .continuous
        layer.maskedCorners = layerCorners(corners, of: view)
        layer.cornerRadius = corners.isEmpty ? 0 : WindowCorner.radius
        layer.masksToBounds = !corners.isEmpty
        layer.borderWidth = edged ? Tokens.Metric.hairline : 0
    }

    /// `corners`, in the card's terms, as `view`'s layer and anything masking
    /// it read them.
    static func layerCorners(_ corners: CACornerMask, of view: NSView) -> CACornerMask {
        guard view.isFlipped else { return corners }
        var flipped: CACornerMask = []
        if corners.contains(.layerMinXMaxYCorner) { flipped.insert(.layerMinXMinYCorner) }
        if corners.contains(.layerMaxXMaxYCorner) { flipped.insert(.layerMaxXMinYCorner) }
        if corners.contains(.layerMinXMinYCorner) { flipped.insert(.layerMinXMaxYCorner) }
        if corners.contains(.layerMaxXMinYCorner) { flipped.insert(.layerMaxXMaxYCorner) }
        return flipped
    }
}
