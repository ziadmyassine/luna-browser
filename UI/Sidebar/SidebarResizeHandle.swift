//
//  SidebarResizeHandle.swift
//  Luna
//
//  §3.7: an invisible 8 pt grab strip on the sidebar/content divider, dragging
//  within 180–420 pt, double-clicking back to 280.
//
//  **Nothing is drawn.** §3.7 asked for a `◁|▷` glyph to fade in on hover, and
//  on screen it read as a piece of UI that had come loose: a small floating
//  mark over the page, unattached to either surface, appearing for no reason
//  the user had asked for. The resize cursor already says the divider is
//  draggable, which is what every native split view relies on, so the glyph is
//  gone and the strip is the whole affordance.
//
//  The width is reported out rather than applied here: the sidebar's width is a
//  constraint on the *window controller's* chrome view (§4.1 animates it in the
//  same transaction as the traffic lights), and a view reaching up to mutate
//  that is how the two ends end up disagreeing.
//

import AppKit

@MainActor
final class SidebarResizeHandle: NSView {

    /// Live during a drag, so the divider tracks the pointer.
    var onWidthChange: ((CGFloat) -> Void)?
    /// Fired once at the end of a drag or on a double-click reset.
    var onWidthCommitted: ((CGFloat) -> Void)?

    private static let defaultsKey = "dk.novapps.luna.sidebar.width"

    private var isDragging = false

    /// The remembered width, clamped into §1's range. Collapsing the sidebar
    /// never overwrites it — §3.7's double-click has to have something to
    /// restore, and so does `⌘S`.
    static var storedWidth: CGFloat {
        get {
            let stored = UserDefaults.standard.double(forKey: defaultsKey)
            return stored > 0 ? Tokens.Metric.sidebarWidth.clamp(stored) : Tokens.Metric.sidebarWidth.default
        }
        set { UserDefaults.standard.set(Double(newValue), forKey: defaultsKey) }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel("Sidebar width")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Geometry

    /// The 8 pt hit strip, centred on the divider (§3.7).
    private var strip: NSRect {
        let width = Tokens.Metric.resizeHandleHitWidth
        return NSRect(x: (bounds.width - width) / 2, y: 0, width: width, height: bounds.height)
    }

    /// Clicks land on the strip; everything else belongs to the row underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        strip.contains(convert(point, from: superview)) ? self : nil
    }

    override func resetCursorRects() {
        addCursorRect(strip, cursor: .resizeLeftRight)
    }

    // MARK: - Drag

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            // §3.7: double-click resets to the 280 pt default.
            let reset = Tokens.Metric.sidebarWidth.default
            Self.storedWidth = reset
            onWidthChange?(reset)
            onWidthCommitted?(reset)
            return
        }
        isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        onWidthChange?(width(for: event))
    }

    /// §30.1: the sidebar's plane moves the window; a control on it does not.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        let final = width(for: event)
        Self.storedWidth = final
        onWidthCommitted?(final)
    }

    /// Sidebar width the pointer implies, clamped to §1's 180–420 pt.
    private func width(for event: NSEvent) -> CGFloat {
        // The sidebar's own leading edge is the window's, so the pointer's x in
        // sidebar coordinates *is* the width the user is asking for.
        guard let sidebar = superview else { return Tokens.Metric.sidebarWidth.default }
        return Tokens.Metric.sidebarWidth.clamp(sidebar.convert(event.locationInWindow, from: nil).x)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
