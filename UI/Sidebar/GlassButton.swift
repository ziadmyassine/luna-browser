//
//  GlassButton.swift
//  Luna
//
//  Every round or squircular glass control in the sidebar: the §3.1 toggle /
//  back / reload cluster, the §3.3 Essentials tiles, the §3.5 avatar and
//  archive circles. One class, because they differ only in shape and glyph —
//  a second implementation would be a second set of hover, focus-ring and
//  VoiceOver bugs.
//
//  **Hover lifts the fill, not the border** (§3.1). Luna has no translucent
//  "hover fill" token — `Surface.raised`/`glassFallback` are opaque and the
//  `Line.*` tokens are line colours — so the lift is expressed on the glyph
//  (`Text.secondary` → `Text.primary`) and the border is left alone, which is
//  the half of the rule that matters most. See the milestone report:
//  `Tokens.Surface.hover` is the missing token.
//

import AppKit

@MainActor
final class GlassButton: NSView {

    /// Fired on click, Space or Return.
    var onActivate: (() -> Void)?
    /// Makes the button a drag source (§6.6 — an Essentials tile moves between
    /// sections). Return the pasteboard item for this button's content, or nil
    /// for a button that is not draggable.
    var dragItem: (() -> NSPasteboardItem?)?
    /// The right-click menu, built on demand so it always reflects the
    /// button's current tab rather than the one it was created with.
    var menuBuilder: (() -> NSMenu?)?
    /// §3.3: the active Essential carries a 1 pt accent ring.
    var isAccented = false { didSet { refresh() } }
    /// §3.1: back dims when `canGoBack` is false.
    var isEnabled = true { didSet { refresh() } }

    private let shape: RoundedMetric
    private let pointSize: CGFloat
    private let glyph = NSImageView()
    private var isHovering = false
    private var isPressed = false

    init(shape: RoundedMetric, symbolName: String, pointSize: CGFloat, label: String) {
        self.shape = shape
        self.pointSize = pointSize
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: shape.width, height: shape.height)))
        wantsLayer = true
        layer?.cornerCurve = .continuous
        Glass.apply(.control, to: self, cornerRadius: shape.cornerRadius)

        glyph.imageScaling = .scaleProportionallyUpOrDown
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        addSubview(glyph)
        setSymbol(symbolName)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Content

    /// Swaps the glyph — reload → stop while loading (§3.1), speaker → speaker
    /// slash when muted (§3.4).
    func setSymbol(_ name: String) {
        glyph.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        glyph.contentTintColor = nil
        refresh()
    }

    /// A favicon instead of a symbol (§3.3). Template is off: a site's icon is
    /// its own colours, not chrome ink.
    func setImage(_ image: NSImage?) {
        glyph.image = image
        image?.isTemplate = false
        glyph.contentTintColor = nil
        refresh()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: shape.width, height: shape.height)
    }

    override func layout() {
        super.layout()
        let side = min(pointSize, min(bounds.width, bounds.height))
        glyph.frame = NSRect(
            x: (bounds.width - side) / 2,
            y: (bounds.height - side) / 2,
            width: side,
            height: side
        ).integral
    }

    // MARK: - State

    private func refresh() {
        // §21.4 has no "disabled" ink; `tertiary` is the dimmest tier that still
        // clears the floor, and is used in place of §3.1's unreadable 35 %.
        let ink: NSColor
        if !isEnabled {
            ink = Tokens.Text.tertiary
        } else {
            ink = (isHovering || isPressed) ? Tokens.Text.primary : Tokens.Text.secondary
        }
        if glyph.image?.isTemplate ?? true { glyph.contentTintColor = ink }
        needsDisplay = true
        setAccessibilityEnabled(isEnabled)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = shape.cornerRadius
        let ringed = isAccented || (window?.firstResponder === self)
        layer.borderWidth = ringed ? Tokens.Metric.hairline : 0
        layer.borderColor = ringed ? Tokens.Accent.tint.cgColor : nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    // MARK: - Hover (§6, 0.10 s)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        setHovering(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovering(false)
    }

    private func setHovering(_ hovering: Bool) {
        guard hovering != isHovering, isEnabled else { return }
        isHovering = hovering
        Tokens.Motion.animate(Tokens.Motion.controlHover) { context in
            context.allowsImplicitAnimation = true
            refresh()
        }
    }

    // MARK: - Activation

    override func menu(for event: NSEvent) -> NSMenu? {
        menuBuilder?() ?? super.menu(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        refresh()
        if isEnabled, inside { onActivate?() }
    }

    /// Drag starts once the pointer leaves the button, which is AppKit's own
    /// threshold and avoids the hand-rolled 4 pt test the SwiftUI browsers need.
    override func mouseDragged(with event: NSEvent) {
        guard let item = dragItem?(), !bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        isPressed = false
        refresh()
        let dragged = NSDraggingItem(pasteboardWriter: item)
        dragged.setDraggingFrame(bounds, contents: glyph.image)
        beginDraggingSession(with: [dragged], event: event, source: self)
    }

    // MARK: - Keyboard (§20.2 — every chrome control is reachable)

    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { isEnabled }
    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: shape.cornerRadius, yRadius: shape.cornerRadius).fill()
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        let pressed = event.charactersIgnoringModifiers ?? ""
        guard isEnabled, pressed == " " || pressed == "\r" || pressed == "\u{3}" else {
            super.keyDown(with: event)
            return
        }
        onActivate?()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onActivate?()
        return true
    }
}

extension GlassButton: NSDraggingSource {

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }
}
