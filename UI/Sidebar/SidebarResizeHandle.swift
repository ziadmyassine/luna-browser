//
//  SidebarResizeHandle.swift
//  Luna
//
//  §3.7: a `◁|▷` handle on the sidebar/content divider, appearing on hover
//  after 0.1 s, dragging within 180–420 pt, double-clicking back to 280.
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

    private var isRevealed = false
    private var revealTask: Task<Void, Never>?
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
        alphaValue = 0
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

    /// The 20 × 32 drawn handle, centred on the divider.
    private var handle: NSRect {
        let size = Tokens.Metric.resizeHandle
        return NSRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Clicks land on the strip, plus the drawn handle once it is showing —
    /// everything else belongs to the row underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let live = strip.contains(local) || (isRevealed && handle.contains(local))
        return live ? self : nil
    }

    override func resetCursorRects() {
        addCursorRect(strip, cursor: .resizeLeftRight)
        if isRevealed { addCursorRect(handle, cursor: .resizeLeftRight) }
    }

    // MARK: - Reveal (§3.7: after a 0.1 s intent delay)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        revealTask?.cancel()
        // The class is `@MainActor`, so the task body is too — no hop, and no
        // `@Sendable` closure reaching back into main-actor state.
        revealTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Tokens.Motion.hoverPeekDelay))
            guard !Task.isCancelled else { return }
            self?.setRevealed(true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        revealTask?.cancel()
        guard !isDragging else { return }
        setRevealed(false)
    }

    private func setRevealed(_ revealed: Bool) {
        guard revealed != isRevealed else { return }
        isRevealed = revealed
        window?.invalidateCursorRects(for: self)
        Tokens.Motion.animate(Tokens.Motion.hoverPeek) { context in
            context.allowsImplicitAnimation = true
            animator().alphaValue = revealed ? 1 : 0
        }
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
        setRevealed(true)
        isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        onWidthChange?(width(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        let final = width(for: event)
        Self.storedWidth = final
        onWidthCommitted?(final)
        if let point = window?.mouseLocationOutsideOfEventStream,
           !bounds.contains(convert(point, from: nil)) {
            setRevealed(false)
        }
    }

    /// Sidebar width the pointer implies, clamped to §1's 180–420 pt.
    private func width(for event: NSEvent) -> CGFloat {
        // The sidebar's own leading edge is the window's, so the pointer's x in
        // sidebar coordinates *is* the width the user is asking for.
        guard let sidebar = superview else { return Tokens.Metric.sidebarWidth.default }
        return Tokens.Metric.sidebarWidth.clamp(sidebar.convert(event.locationInWindow, from: nil).x)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        Tokens.Text.secondary.setFill()
        let box = handle
        let bar = NSRect(
            x: box.midX - Tokens.Metric.hairline,
            y: box.midY - Tokens.Metric.spaceDot,
            width: 2 * Tokens.Metric.hairline,
            height: 2 * Tokens.Metric.spaceDot
        )
        NSBezierPath(roundedRect: bar, xRadius: Tokens.Metric.hairline, yRadius: Tokens.Metric.hairline).fill()
        arrow(pointingLeft: true, in: box).fill()
        arrow(pointingLeft: false, in: box).fill()
    }

    /// One half of `◁|▷`: a triangle the height of a dot pair, set a hairline
    /// pair clear of the bar.
    private func arrow(pointingLeft: Bool, in box: NSRect) -> NSBezierPath {
        let reach = Tokens.Metric.spaceDot
        let gap = 2 * Tokens.Metric.hairline
        let tipX = pointingLeft ? box.midX - gap - reach : box.midX + gap + reach
        let baseX = pointingLeft ? box.midX - gap : box.midX + gap
        let path = NSBezierPath()
        path.move(to: NSPoint(x: tipX, y: box.midY))
        path.line(to: NSPoint(x: baseX, y: box.midY + reach))
        path.line(to: NSPoint(x: baseX, y: box.midY - reach))
        path.close()
        return path
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
