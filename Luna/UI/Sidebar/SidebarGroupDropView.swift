//
//  SidebarGroupDropView.swift
//  Luna
//
//  §6.6's answer to "it is going in there": the box that closes round a §3.4b
//  folder while a lift is aimed inside it.
//
//  The folder's whole extent, not its header — the name, the tabs already in
//  it, and the gap the list has opened for the one arriving. A folded folder's
//  extent is its header alone, so one view answers both states. One for the
//  list rather than one per folder, because a lift is in one place.
//
//  The dash is §3.3's: a dashed line is what Luna draws where a thing goes. The
//  fill is `Surface.selected` rather than `Surface.hover`, §3.4's distinction:
//  hover says the pointer is over this, and a folder taking a drop is the
//  chosen destination.
//

import AppKit

@MainActor
final class SidebarGroupDropView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // The box is redrawn at every size it is given rather than stretched
        // from the last one: the dash is a fixed length, so a scaled copy of it
        // would come out at a different pitch on every folder.
        layerContentsRedrawPolicy = .duringViewResize
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Tokens.Metric.groupPlateCornerRadius
        alphaValue = 0
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// Puts the box round `box`, or takes it away. The frame is placed at once
    /// and only the fade is animated: a box that flew from one folder to the
    /// next would be a mark travelling through the rows between them, which is
    /// two folders' worth of answer to one question.
    func show(_ box: NSRect?) {
        Tokens.Motion.immediately {
            if let box, box != frame {
                frame = box
                needsDisplay = true
            }
        }
        let wanted = box != nil
        guard !Tokens.Motion.reduceMotion else {
            isHidden = !wanted
            // The same end state the fade lands on: a box left at full
            // opacity while hidden flashes the moment anything unhides it.
            alphaValue = wanted ? 1 : 0
            layer?.backgroundColor = wanted ? Tokens.Surface.selected.cgColor : nil
            return
        }
        if wanted { isHidden = false }
        Tokens.Motion.wash(layer, to: wanted ? Tokens.Surface.selected : nil)
        Tokens.Motion.animate(Tokens.Motion.tabInsert) { context in
            context.allowsImplicitAnimation = true
            self.animator().alphaValue = wanted ? 1 : 0
        } completion: { [self] in
            MainActor.assumeIsolated { isHidden = !wanted }
        }
    }

    /// The box lies under the rows it encloses and answers nothing: the tab
    /// under the pointer is still the one that takes the press.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let hairline = Tokens.Metric.hairline
        let radius = Tokens.Metric.rowCornerRadius
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: hairline / 2, dy: hairline / 2),
            xRadius: radius,
            yRadius: radius
        )
        path.lineWidth = hairline
        let dash = Tokens.Metric.pinHintDash
        path.setLineDash(dash, count: dash.count, phase: 0)
        Tokens.Line.border.setStroke()
        path.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Both were resolved into the appearance they were set in.
        if !isHidden { layer?.backgroundColor = Tokens.Surface.selected.cgColor }
        needsDisplay = true
    }
}
