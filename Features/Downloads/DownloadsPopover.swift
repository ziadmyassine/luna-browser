//
//  DownloadsPopover.swift
//  Luna
//
//  `docs/UI-SPEC.md` §5 / TODO.md §30.15 — the download-complete popover. It
//  renders outside the window bounds, floating above the top edge with a
//  pointer tail down into the downloads button in the §4 action capsule, so it
//  is an `NSPanel` and not a view in the window.
//
//  Two things §5 says that are easy to read past:
//
//  · Middle truncation is required, not stylistic. A statement called
//    `97103328759-2026-01-01-2026-08-31.pdf` has to keep both ends: head
//    truncation destroys the account number, tail truncation destroys the
//    extension, and either leaves the user unable to tell which file landed.
//
//  · There is no heavy glass style on macOS 26 (see `Glass.swift`). The
//    popover is `.regular` like the bar, and its extra weight comes from the
//    panel shadow. `Tokens.Shadow.popover` does not exist yet, so what ships
//    here is the system panel shadow — see the report.
//
//  Accessibility (§21.1): completion is announced to VoiceOver, the row carries
//  a real label with the filename and its state rather than existing only as
//  an animation, and Escape dismisses the panel from anywhere in the app
//  without it having to steal key focus from the page the user is reading.
//

import AppKit

@MainActor
final class DownloadsPopover {

    private var panel: NSPanel?
    private var content: PopoverContentView?
    private var dismissTimer: Timer?
    private var escapeMonitor: Any?

    // MARK: - Geometry

    /// §5 draws a pointer tail but gives it no metric. A square of the
    /// popover's own corner radius, rotated 45°, sits half inside the body and
    /// half below it — proportioned to the surface it belongs to instead of
    /// to a number nobody measured.
    private static var tailSide: CGFloat { Tokens.Metric.downloadsPopover.cornerRadius }
    /// Half the diagonal of that square: how far the tip reaches below the body.
    private static var tailRise: CGFloat { tailSide * CGFloat(2).squareRoot() / 2 }

    private static var panelSize: CGSize {
        CGSize(
            width: Tokens.Metric.downloadsPopover.width,
            height: Tokens.Metric.downloadsPopover.height + tailRise
        )
    }

    // MARK: - Showing it

    /// Floats the popover above `anchor` — the downloads button in the top
    /// bar's action capsule. Only the button's screen frame is used; nothing
    /// else about agent F's view is touched.
    func present(_ item: DownloadItem, anchoredTo anchor: NSView) {
        guard let host = anchor.window else { return }
        dismiss(animated: false)

        let panel = makePanel()
        let content = PopoverContentView(
            item: item,
            tailRise: Self.tailRise,
            onConfirm: { [weak self] in self?.dismiss(animated: true) },
            onHoverChanged: { [weak self] hovering in
                hovering ? self?.cancelTimer() : self?.startTimer()
            }
        )

        let anchorScreen = anchor.window?.convertToScreen(anchor.convert(anchor.bounds, to: nil)) ?? .zero
        let frame = Self.frame(anchoredTo: anchorScreen, over: host)
        panel.setFrame(frame, display: false)
        content.frame = CGRect(origin: .zero, size: frame.size)
        content.tailCentreX = anchorScreen.midX - frame.minX
        panel.contentView = content

        // A child window follows the browser window when it moves and goes
        // away with it — the popover can never be orphaned over the desktop.
        host.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)

        self.panel = panel
        self.content = content

        content.animateIn(from: content.tailCentreX / max(frame.width, 1))
        content.runSweep()
        announce(item)
        startEscapeMonitor()
        startTimer()
    }

    /// §5: the tail's tip meets the window's top edge and points down into the
    /// button, the body floats clear of the window, and the whole thing is
    /// nudged back onto the screen if the button sits near a corner.
    private static func frame(anchoredTo anchor: NSRect, over host: NSWindow) -> NSRect {
        let size = panelSize
        var origin = CGPoint(x: anchor.midX - size.width / 2, y: host.frame.maxY)
        if let visible = host.screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = min(origin.y, visible.maxY - size.height)
        }
        return NSRect(origin: origin, size: size)
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // §5's "heavier shadow". The system panel shadow is the heaviest weight
        // available without a shadow token to draw our own.
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.setAccessibilityLabel(String(localized: "Download complete"))
        return panel
    }

    // MARK: - Dismissal

    func dismiss(animated: Bool = true) {
        cancelTimer()
        stopEscapeMonitor()
        guard let panel else { return }
        self.panel = nil
        content = nil

        guard animated, !Tokens.Motion.reduceMotion else {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            return
        }
        Tokens.Motion.animate(Tokens.Motion.popoverIn) { _ in panel.animator().alphaValue = 0 }
        // The window has to survive the fade, so the close is a main-actor
        // continuation rather than the `@Sendable` completion handler — an
        // `NSPanel` cannot be captured by one.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Tokens.Motion.popoverIn.duration))
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    /// §5: auto-dismisses after 4 s; hovering cancels the timer.
    private func startTimer() {
        cancelTimer()
        let timer = Timer(timeInterval: Tokens.Motion.downloadsAutoDismiss, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(animated: true) }
        }
        // `.common`, not `.default`: a popover that quietly stops counting down
        // because the user is scrolling would sit there until it was clicked.
        RunLoop.main.add(timer, forMode: .common)
        dismissTimer = timer
    }

    private func cancelTimer() {
        dismissTimer?.invalidate()
        dismissTimer = nil
    }

    /// Escape has to work while the user is still typing in the page, so the
    /// popover must not become key just to be dismissible. A local monitor
    /// gives it the key without taking the focus.
    private func startEscapeMonitor() {
        stopEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.charactersIgnoringModifiers == "\u{1b}" else { return event }
            MainActor.assumeIsolated { self?.dismiss(animated: true) }
            return nil
        }
    }

    private func stopEscapeMonitor() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }

    /// §21.1 — a download that only exists as an animation is invisible to a
    /// screen reader.
    private func announce(_ item: DownloadItem) {
        guard let panel else { return }
        NSAccessibility.post(
            element: panel,
            notification: .announcementRequested,
            userInfo: [
                .announcement: item.accessibilityLabel,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}

// MARK: - The panel

/// Borderless windows refuse key by default, which would put the confirm button
/// out of reach of the keyboard. It becomes key only if something in it is
/// focused — never on its own.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - The content

/// Body + tail + row. Non-flipped, so the tail is at the bottom in both the
/// maths and the drawing.
@MainActor
private final class PopoverContentView: NSView {

    private let row: DownloadsPopoverRowView
    private let body: NSView
    private let tail: NSView
    private let tailRise: CGFloat
    /// Width and height of the diamond's bounding box.
    private var tailDiagonal: CGFloat { tailRise * 2 }
    private let onHoverChanged: (Bool) -> Void

    /// Where in this view's width the tail points. Set by the controller once
    /// the panel has been clamped onto the screen.
    var tailCentreX: CGFloat = 0 { didSet { needsLayout = true } }

    init(
        item: DownloadItem,
        tailRise: CGFloat,
        onConfirm: @escaping () -> Void,
        onHoverChanged: @escaping (Bool) -> Void
    ) {
        self.tailRise = tailRise
        self.onHoverChanged = onHoverChanged
        self.row = DownloadsPopoverRowView(item: item, onConfirm: onConfirm)
        // §5's popover is `.regular` glass like the bar — there is no heavier
        // style on macOS 26 (`Glass.swift`); the weight is the panel shadow.
        self.tail = Glass.backing(.popover, cornerRadius: Tokens.Metric.hairline)
        self.body = Glass.backing(.popover, cornerRadius: Tokens.Metric.downloadsPopover.cornerRadius)
        super.init(frame: .zero)
        wantsLayer = true

        // Sized before they are in the tree, for the reason
        // `DownloadsPopoverRowView` already records about `confirmBacking`: a
        // glass backing that first lays out at zero has nothing to scale from.
        tail.setFrameSize(CGSize(width: tailDiagonal, height: tailDiagonal))
        body.setFrameSize(Tokens.Metric.downloadsPopover.size)

        // Behind the body, so the body's glass composites over the half of the
        // diamond that is inside it and the two read as one surface.
        addSubview(tail)

        addSubview(body)
        body.addSubview(row)

        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Download complete"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func layout() {
        super.layout()
        body.frame = CGRect(x: 0, y: tailRise, width: bounds.width, height: bounds.height - tailRise)
        row.frame = body.bounds
        // The square's corners sit `tailRise` from its centre along both axes,
        // so this is exactly the box the rotated square occupied: the tip meets
        // y = 0 and the opposite corner sits inside the body.
        tail.frame = CGRect(x: tailCentreX - tailRise, y: 0, width: tailDiagonal, height: tailDiagonal)
        maskTail()
    }

    /// A square turned on its point — masked, not rotated.
    ///
    /// Measured at runtime (M1 integration): with
    /// `tail.frameCenterRotation = 45` the app died the instant the panel was
    /// ordered in, `EXC_BREAKPOINT` / "Invalid view geometry: y is NaN" raised
    /// from `NSViewActuallyUpdateFrameFromLayoutEngine`. Auto Layout cannot
    /// express a rotation, and `Glass.backing` puts an `NSGlassEffectView` in
    /// here that lays its own `contentView` out with constraints — solved
    /// inside a rotated frame, the engine hands back NaN and AppKit traps on
    /// the next layout pass. A mask draws the same diamond with no rotation.
    private func maskTail() {
        let box = tail.bounds
        let diamond = CGMutablePath()
        diamond.move(to: CGPoint(x: box.midX, y: box.minY))
        diamond.addLine(to: CGPoint(x: box.maxX, y: box.midY))
        diamond.addLine(to: CGPoint(x: box.midX, y: box.maxY))
        diamond.addLine(to: CGPoint(x: box.minX, y: box.midY))
        diamond.closeSubpath()
        let mask = tail.layer?.mask as? CAShapeLayer ?? CAShapeLayer()
        mask.frame = box
        mask.path = diamond
        tail.layer?.mask = mask
    }

    // MARK: Hover cancels the auto-dismiss (§5)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged(false) }

    // MARK: Motion

    /// §6: 0.20 s spring, scale 0.94 → 1.0, from the tail anchor — it grows
    /// out of the button it points at rather than out of its own centre.
    func animateIn(from anchorFraction: CGFloat) {
        guard let layer else { return }
        layer.anchorPoint = CGPoint(x: min(max(anchorFraction, 0), 1), y: 0)
        layer.position = CGPoint(x: bounds.width * layer.anchorPoint.x, y: 0)
        guard let spring = Tokens.Motion.popoverIn.springAnimation(keyPath: "transform.scale") else { return }
        spring.fromValue = 0.94
        spring.toValue = 1
        layer.add(spring, forKey: "popoverIn")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.duration = Tokens.Motion.popoverIn.duration
        layer.add(fade, forKey: "popoverFade")
    }

    func runSweep() {
        layoutSubtreeIfNeeded()
        row.runSweep()
    }
}
