//
//  TopBarRunPlates.swift
//  Luna
//
//  The two surfaces §4's chips stand on: the glass cylinder around the kept
//  run, and the recessed plate under a folder.
//
//  One file because they are the same idea twice. A bar has one line and no
//  indentation, so what groups chips together on it is the surface underneath
//  them — and which surface says which grouping it is. Glass is the chrome's
//  own material, so the kept run reads as part of the bar; a well is ink cut
//  into it, so a folder reads as a place things are inside.
//
//  Neither takes a click. A surface that swallowed them would leave a dead
//  border around every chip standing on it, and dragging the bar's background
//  moves the window (§4) — which is as true of the gap between two tabs as of
//  anywhere else on it.
//

import AppKit

/// The glass cylinder around §3.3's tiles and §3.4b's kept tier — "the tabs
/// you keep", said once, around all of them.
@MainActor
final class TopBarKeptCylinder: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        Glass.apply(.control, to: self, cornerRadius: TopBarMetrics.plate.cornerRadius)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var mouseDownCanMoveWindow: Bool { true }
}

/// The recess a folder's header and its open tabs stand on (§3.4b).
@MainActor
final class TopBarGroupPlate: NSView, TopBarThemed {

    /// §6.6: a lift is over this folder and would land in it. The plate is the
    /// folder, so the plate is what lights up — a ring round the header alone
    /// would be saying "this name", and what is being offered is the inside.
    var isDropTarget = false {
        didSet {
            guard isDropTarget != oldValue else { return }
            applyTokens()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .circular
        layer?.cornerRadius = TopBarMetrics.plate.cornerRadius
        setAccessibilityElement(false)
        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var mouseDownCanMoveWindow: Bool { true }

    func applyTokens() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            // §3.1's recess, the same ink a well is drawn in: a folder is a
            // place things are inside, and the bar's own glass is what it is
            // inside of.
            self.layer?.backgroundColor = Tokens.Surface.well.cgColor
            // Lit, the same hairline §3.4's group drop draws round the rows it
            // is offering. It is a border rather than a brighter fill because
            // the fill is a recess and a recess that lightens stops reading as
            // one.
            self.layer?.borderWidth = self.isDropTarget ? Tokens.Metric.hairline : 0
            self.layer?.borderColor = self.isDropTarget ? Tokens.Line.border.cgColor : nil
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }
}
