//
//  PopoutPanelView.swift
//  Luna
//
//  The shape §6.4's History panel arrived at, with the second surface that
//  wants it — Downloads — lifted out of it.
//
//  A pop-out is a glass panel **standing on the control that opened it**, over
//  a transparent sheet that catches the click that dismisses it. That is what
//  an `NSMenu` puts up and for the same reason: a glance opened from a button
//  belongs on that button, it must not cost the page behind it, and the click
//  that closes it must not also land on whatever it was over.
//
//  The one thing that differs between the two callers is **which way it
//  grows**. The sidebar's History button is at the foot of §3.5, so its pop-out
//  goes up; the top bar's capsule is at the window's head, so its pop-outs go
//  down. Everything else — the material, the shadow, the clamps, the corner the
//  spring unfolds from — is the same, so it is written once here.
//
//  Why a shadow and no scrim: with a backdrop behind it the panel was separated
//  from the page by the veil; standing on the page directly, its own edge is
//  all it has, and §2's popover material has no heavier weight to ask for
//  (`Tokens.Shadow.popover`). Same token the §6.6 drag lift carries.
//

import AppKit

/// Which way a pop-out grows out of the control that opened it.
enum PopoutEdge: Sendable {
    /// Upward, out of the button's top edge — §3.5's foot of the sidebar.
    case above
    /// Downward, out of the button's bottom edge — §4's action capsule.
    case below
}

enum PopoutMetrics {
    static var cornerRadius: CGFloat { Tokens.Metric.contentCardRadius }
    /// A header row, at the same height as the chrome rows the panel covers.
    static var headerHeight: CGFloat { Tokens.Metric.topBarHeight }
    static var padding: CGFloat { Tokens.Metric.panelInset }
    static var inset: CGFloat { Tokens.Metric.chromeGapWide }
    /// How far the pop-out stands off the button it came from.
    static var gap: CGFloat { Tokens.Metric.historyPopoutGap }
}

/// The full-window sheet and the panel standing on it. Subclasses fill `body`.
@MainActor
class PopoutPanelView: NSView {

    /// A click that landed on the sheet rather than on the panel.
    var onBackgroundClick: (() -> Void)?

    /// The button the pop-out stands on, in this view's coordinates.
    ///
    /// Read live rather than captured: the sidebar can be resized and the
    /// window moved while the pop-out is open, and the button goes with them.
    /// An empty rect falls back to the corner the edge implies, which is where
    /// that button is anyway.
    var anchorRect: (() -> NSRect)?

    /// The rounded panel. Subclasses add their header and list to it.
    let body = PopoutBodyView()

    private let preferredSize: CGSize
    private let edge: PopoutEdge

    /// The floor the height clamp will not go below — a pop-out with no room
    /// for a single row still has to be a pop-out. A header by default.
    var minimumHeight: CGFloat { PopoutMetrics.headerHeight }

    init(frame frameRect: NSRect, size: CGSize, edge: PopoutEdge) {
        self.preferredSize = size
        self.edge = edge
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        body.wantsLayer = true
        // **Positioned by frame, and its children by Auto Layout.** The panel's
        // own geometry is two clamps against a button that moves with a sidebar
        // drag — see `layout()` — and a constant assigned from inside `layout()`
        // lands one pass too late to be solved, which put the pop-out at the
        // window's corner with the right size and the wrong place.
        Glass.apply(.popover, to: body, cornerRadius: PopoutMetrics.cornerRadius)
        body.layer.map { Tokens.Shadow.popover.apply(to: $0, in: effectiveAppearance) }
        addSubview(body)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Geometry

    /// **Standing on the button, and never off the window.**
    ///
    /// It grows away from the button along the edge it was given and rightward
    /// from the button's leading edge, which is the only direction there is
    /// room in. Both are then clamped, because the sidebar can be dragged to
    /// 420 and the window can be short.
    override func layout() {
        super.layout()
        let anchor = anchorRect?() ?? .zero
        let button = anchor.isEmpty ? fallbackAnchor : anchor
        let gap = PopoutMetrics.gap
        let inset = PopoutMetrics.inset

        let available: CGFloat = switch edge {
        case .above: bounds.maxY - (button.maxY + gap) - inset
        case .below: (button.minY - gap) - bounds.minY - inset
        }
        let height = min(preferredSize.height, max(available, minimumHeight))
        let originY: CGFloat = switch edge {
        case .above: button.maxY + gap
        case .below: button.minY - gap - height
        }
        let originX = min(
            max(button.minX, inset),
            max(bounds.maxX - preferredSize.width - inset, inset)
        )
        body.frame = NSRect(x: originX, y: originY, width: preferredSize.width, height: height).integral
        body.layoutSubtreeIfNeeded()
    }

    /// Where the button would be if nobody said: the corner the edge implies.
    private var fallbackAnchor: NSRect {
        switch edge {
        case .above: NSRect(origin: bounds.origin, size: .zero)
        case .below: NSRect(x: bounds.minX, y: bounds.maxY, width: 0, height: 0)
        }
    }

    // MARK: - Dismissal

    override func mouseDown(with event: NSEvent) {
        onBackgroundClick?()
    }

    // MARK: - Motion

    /// §6's `commandBarIn`, **grown from the button** rather than from its own
    /// centre. The anchor point is the corner standing on the control that
    /// opened it, so the pop-out unfolds out of the button instead of appearing
    /// around it.
    func animateIn() {
        layoutSubtreeIfNeeded()
        guard let layer = body.layer,
              let scale = Tokens.Motion.commandBarIn.springAnimation(keyPath: "transform.scale")
        else {
            alphaValue = 1
            return
        }
        let frame = layer.frame
        let corner = CGPoint(x: 0, y: edge == .above ? 0 : 1)
        layer.anchorPoint = corner
        layer.position = CGPoint(
            x: frame.minX + frame.width * corner.x,
            y: frame.minY + frame.height * corner.y
        )
        scale.fromValue = 0.96
        scale.toValue = 1.0
        layer.add(scale, forKey: "popoutIn")
        alphaValue = 0
        Tokens.Motion.animate(Tokens.Motion.commandBarIn) { _ in
            self.animator().alphaValue = 1
        }
    }
}

/// The rounded panel itself. Swallows clicks so they do not reach the sheet.
@MainActor
final class PopoutBodyView: NSView {
    override func mouseDown(with event: NSEvent) {}
}
