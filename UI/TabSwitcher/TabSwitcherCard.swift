//
//  TabSwitcherCard.swift
//  Luna
//
//  One tab in the `⌃⇥` switcher: a picture of the page with its icon and
//  title under it, on a plate that lights for the highlighted card.
//
//  A button rather than a list row. The cards are a handful of separate
//  targets side by side, each with a plate of its own, so a press swells the
//  plate the way it swells every other control that owns its material.
//

import AppKit

/// What a card shows. Built by the controller from the session.
struct TabSwitcherItem {
    let id: UUID
    let title: String
    let favicon: NSImage?
}

@MainActor
final class TabSwitcherCard: NSView {

    /// A click that went down and came up on the card.
    var onActivate: (() -> Void)?

    /// The card the switcher will go to. Lit like a pressed control, because
    /// it is the one that will be chosen when `⌃` comes up.
    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            setAccessibilitySelected(isSelected)
            refresh()
        }
    }

    private var isHovering = false { didSet { if isHovering != oldValue { refresh() } } }
    private var isPressed = false {
        didSet {
            guard isPressed != oldValue else { return }
            refresh()
            Tokens.Motion.swell(self, to: isPressed ? Tokens.Motion.pressSwell : 1)
        }
    }

    /// The page. Its layer carries the picture, so the corner clips it and
    /// `resizeAspectFill` crops rather than squashes a page of another shape.
    private let picture = NSView()
    /// The site's icon at twice size in the middle of the picture, until
    /// there is a picture — a tab that has never been captured has none.
    private let placeholder = NSImageView()
    private let icon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    init(item: TabSwitcherItem) {
        super.init(frame: NSRect(origin: .zero, size: TabSwitcherMetrics.cardSize))
        wantsLayer = true
        layer?.cornerCurve = .continuous

        picture.wantsLayer = true
        picture.layer?.cornerCurve = .continuous
        picture.layer?.masksToBounds = true
        picture.layer?.contentsGravity = .resizeAspectFill
        addSubview(picture)

        let mark = item.favicon ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        placeholder.image = mark
        placeholder.imageScaling = .scaleProportionallyUpOrDown
        picture.addSubview(placeholder)
        icon.image = mark
        icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)

        titleLabel.stringValue = item.title
        titleLabel.font = Tokens.TypeScale.sidebarRow
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.title)
        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// The page's picture, replacing the placeholder.
    func setPicture(_ image: NSImage) {
        guard let layer = picture.layer else { return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer.contentsScale = scale
        layer.contents = image.layerContents(forContentsScale: scale)
        placeholder.isHidden = true
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            let metrics = TabSwitcherMetrics.self
            let inset = metrics.cardInset
            let side = Tokens.Metric.faviconSize
            let rowY = inset
            picture.frame = NSRect(
                x: inset,
                y: rowY + side + inset,
                width: metrics.pictureSize.width,
                height: metrics.pictureSize.height
            )
            let mark = 2 * side
            placeholder.frame = NSRect(
                x: ((picture.bounds.width - mark) / 2).rounded(),
                y: ((picture.bounds.height - mark) / 2).rounded(),
                width: mark,
                height: mark
            )
            icon.frame = NSRect(x: inset, y: rowY, width: side, height: side)
            let titleX = icon.frame.maxX + inset
            let titleHeight = ceil(titleLabel.fittingSize.height)
            titleLabel.frame = NSRect(
                x: titleX,
                y: (icon.frame.midY - titleHeight / 2).rounded(),
                width: max(bounds.width - titleX - inset, 0),
                height: titleHeight
            )
        }
    }

    // MARK: - The plate

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        applyTokens()
    }

    private func applyTokens() {
        guard let layer else { return }
        layer.cornerRadius = TabSwitcherMetrics.cardRadius
        layer.backgroundColor = fill.cgColor
        picture.layer?.cornerRadius = TabSwitcherMetrics.pictureRadius
        picture.layer?.backgroundColor = Tokens.Surface.hover.cgColor
        titleLabel.textColor = Tokens.Text.primary
        // A template glyph is ink, and ink follows the text. A favicon is the
        // site's own colours and is left alone.
        let tint = placeholder.image?.isTemplate == true ? Tokens.Text.secondary : nil
        placeholder.contentTintColor = tint
        icon.contentTintColor = tint
    }

    /// 12 % for the highlighted card and under a press, 6 % under the pointer,
    /// nothing at rest — the two washes every control in Luna answers with.
    private var fill: NSColor {
        if isSelected || isPressed { return Tokens.Surface.selected }
        return isHovering ? Tokens.Surface.hover : .clear
    }

    private func refresh() {
        Tokens.Motion.animate(Tokens.Motion.controlHover) { context in
            context.allowsImplicitAnimation = true
            self.needsDisplay = true
            self.displayIfNeeded()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: - Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }

    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseUp(with event: NSEvent) {
        let landed = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        if landed { onActivate?() }
    }

    /// The card, not the window, answers a drag that starts on it.
    override var mouseDownCanMoveWindow: Bool { false }

    /// The panel never becomes key, so every click on a card is a first one.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }
}
