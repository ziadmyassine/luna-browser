//
//  TopBarRunMarks.swift
//  Luna
//
//  The two marks §4's run draws that are not tabs: the dashed slot a kept tab
//  is about to land in, and the spine that says which tabs are in a folder.
//
//  Both are the column's, turned on their side. The dash is §3.3's — what Luna
//  draws where a thing goes, in the grid's empty slot and round a folder taking
//  a drop. The spine is §3.4b's hairline down the leading edge of a folder's
//  tabs; a bar has no leading edge to run down, so it runs along under them.
//
//  Neither takes a click: they are marks, and the bar under them moves the
//  window (§4).
//

import AppKit

/// §3.3's empty slot: a dashed outline in a tile's shape.
@MainActor
final class TopBarSlotOutline: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Redrawn at every size rather than stretched: the dash is a fixed
        // length, and a scaled copy of it comes out at a different pitch.
        layerContentsRedrawPolicy = .duringViewResize
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code")
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = TopBarMetrics.keptTile.cornerRadius
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: Tokens.Metric.hairline / 2, dy: Tokens.Metric.hairline / 2),
            xRadius: radius,
            yRadius: radius
        )
        path.lineWidth = Tokens.Metric.hairline
        let dash = Tokens.Metric.pinHintDash
        path.setLineDash(dash, count: dash.count, phase: 0)
        Tokens.Line.border.setStroke()
        path.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// §3.4b's spine, along the foot of a folder's open tabs.
@MainActor
final class TopBarFolderSpine: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func applyTokens() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = Tokens.Line.hairline.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }
}
