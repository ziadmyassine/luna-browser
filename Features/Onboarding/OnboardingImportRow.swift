//
//  OnboardingImportRow.swift
//  Luna — §30.17, §30.18
//
//  One browser on the transfer screen: its own app icon, its name, and a mark
//  that fills when it is picked.
//
//  A control, not a list row (CLAUDE.md): it is a thing you aim at and choose,
//  so it answers the pointer with a wash and the finger with a swell. The
//  greyed state is §30.18's — a browser that is installed but unreadable is
//  listed with its reason rather than hidden, because a user looking for
//  Safari and not finding it concludes Luna cannot do it at all.
//

import AppKit

@MainActor
final class OnboardingImportRow: NSView {

    let source: DetectedSource

    var onToggle: (() -> Void)?

    var isChosen = false {
        didSet {
            guard isChosen != oldValue else { return }
            refresh()
            markCheck()
        }
    }

    /// Set while the import is running, and again when it lands. The row is
    /// the only progress there is: a bar under a list of six browsers says
    /// less than the six of them ticking off one at a time.
    var state: State = .idle { didSet { refresh() } }

    enum State { case idle, running, done, failed }

    /// The chosen card's material. §2's clear glass, the finish the URL pill
    /// wears, faded in over the plate the other cards keep: a tick alone is a
    /// mark you have to look for, and the pointer's own wash was already
    /// `Surface.selected` — so hovering an unpicked card and picking one
    /// looked identical.
    private let glass = Glass.backing(.control, cornerRadius: OnboardingMetrics.rowRadius)
    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let reason = NSTextField(labelWithString: "")
    private let mark = NSView()
    private let check = NSImageView()
    private let spinner = NSProgressIndicator()
    private var isHovering = false { didSet { if isHovering != oldValue { refresh() } } }
    private var isPressed = false {
        didSet {
            guard isPressed != oldValue, source.isAvailable else { return }
            refresh()
            Tokens.Motion.swell(self, to: isPressed ? Tokens.Motion.pressSwell : 1)
        }
    }

    init(source: DetectedSource) {
        self.source = source
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous

        icon.image = Self.appIcon(for: source.source)
        icon.imageScaling = .scaleProportionallyUpOrDown
        name.stringValue = source.source.displayName
        name.font = Tokens.TypeScale.pageBody
        reason.stringValue = source.unavailableReason ?? ""
        reason.font = Tokens.TypeScale.settingsCaption
        reason.lineBreakMode = .byWordWrapping
        // Three, because the card is narrower than it was: Safari's reason —
        // the only one a user can act on — stopped mid-sentence at two.
        reason.maximumNumberOfLines = 3
        reason.isHidden = source.isAvailable

        mark.wantsLayer = true
        check.image = NSImage(
            systemSymbolName: "checkmark",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(
            pointSize: Tokens.Metric.pillGlyphSize,
            weight: Tokens.TypeScale.glyphWeight(for: "checkmark")
        ))
        check.contentTintColor = Tokens.Accent.onTint
        check.wantsLayer = true
        check.alphaValue = 0

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        glass.alphaValue = 0
        for view in [glass, icon, name, reason, mark, check, spinner] as [NSView] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel(source.source.displayName)
        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// The browser's own icon, from the copy installed on this Mac. A source
    /// with no icon is one the detector should not have called available, but
    /// the placeholder keeps the row the same shape either way.
    private static func appIcon(for source: ImportSource) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) else {
            return NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            glass.frame = bounds
            let inset = Tokens.Metric.chromeGapWide
            let side = OnboardingMetrics.rowIcon
            icon.frame = NSRect(
                x: inset,
                y: ((bounds.height - side) / 2).rounded(),
                width: side,
                height: side
            )
            let markSide = OnboardingMetrics.rowMark
            mark.frame = NSRect(
                x: bounds.maxX - inset - markSide,
                y: ((bounds.height - markSide) / 2).rounded(),
                width: markSide,
                height: markSide
            )
            mark.layer?.cornerRadius = markSide / 2
            check.frame = mark.frame
            spinner.frame = mark.frame.insetBy(dx: 2, dy: 2)
            layOutText(
                from: icon.frame.maxX + Tokens.Metric.chromeGapWide,
                to: mark.frame.minX - Tokens.Metric.chromeGapWide
            )
        }
    }

    private func layOutText(from left: CGFloat, to right: CGFloat) {
        let width = max(right - left, 0)
        let nameHeight = ceil(name.fittingSize.height)
        guard !reason.isHidden else {
            name.frame = NSRect(x: left, y: ((bounds.height - nameHeight) / 2).rounded(), width: width, height: nameHeight)
            return
        }
        let reasonHeight = ceil(reason.sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude)).height)
        let block = nameHeight + reasonHeight
        let top = ((bounds.height + block) / 2).rounded()
        name.frame = NSRect(x: left, y: top - nameHeight, width: width, height: nameHeight)
        reason.frame = NSRect(x: left, y: top - block, width: width, height: reasonHeight)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() { applyTokens() }

    private func applyTokens() {
        guard let layer else { return }
        layer.cornerRadius = OnboardingMetrics.rowRadius
        layer.backgroundColor = fill.cgColor
        mark.layer?.backgroundColor = (isChosen ? Tokens.Accent.tint : .clear).cgColor
        mark.layer?.borderWidth = isChosen ? 0 : Tokens.Metric.hairline
        mark.layer?.borderColor = Tokens.Line.border.cgColor
        name.textColor = source.isAvailable ? Tokens.Text.primary : Tokens.Text.secondary
        reason.textColor = Tokens.Text.tertiary
        icon.alphaValue = source.isAvailable ? 1 : 0.35
        mark.isHidden = !source.isAvailable || state == .running
        // The tick is a second view over the circle, so hiding the circle for
        // the spinner left the two drawn on top of each other.
        check.isHidden = mark.isHidden
        spinner.isHidden = state != .running
        if state == .running { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    private var fill: NSColor {
        // A browser that cannot be imported carries no plate at all: with
        // three installed and eight not, a list where every row is a card is a
        // wall with the answer hidden in it.
        guard source.isAvailable, !isChosen else { return .clear }
        return isPressed || isHovering ? Tokens.Surface.selected : Tokens.Surface.hover
    }

    private func refresh() {
        Tokens.Motion.animate(Tokens.Motion.controlHover) { context in
            context.allowsImplicitAnimation = true
            glass.animator().alphaValue = isChosen ? 1 : 0
            self.needsDisplay = true
            self.displayIfNeeded()
        }
    }

    /// The tick lands rather than fades in: it is the answer to a press, so it
    /// arrives over size and settles on §6's press spring.
    private func markCheck() {
        Tokens.Motion.animate(Tokens.Motion.controlHover) { context in
            context.allowsImplicitAnimation = true
            check.animator().alphaValue = isChosen ? 1 : 0
        }
        guard isChosen, let layer = check.layer,
              let spring = Tokens.Motion.controlPress.springAnimation(keyPath: "transform.scale")
        else { return }
        spring.fromValue = Tokens.Motion.pressSwell
        spring.toValue = 1
        layer.add(spring, forKey: "tick")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// §30.1: the window's background moves the window; a control on it does
    /// not. Without this the page's own buttons are a drag handle — AppKit
    /// takes the press for `isMovableByWindowBackground` before the control
    /// ever sees it.
    override var mouseDownCanMoveWindow: Bool { false }

    /// The whole card is the target. Its name and its reason are
    /// `NSTextField`s, and a label answers `hitTest` for its own rectangle —
    /// so the pointer aimed at "Arc", which is the middle of the card and the
    /// obvious place to aim, landed on a control that is not one and the tick
    /// did not move. Everything inside is decoration.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = source.isAvailable }

    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseDragged(with event: NSEvent) {
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        guard inside, source.isAvailable, state == .idle else { return }
        onToggle?()
    }

    override func accessibilityPerformPress() -> Bool {
        guard source.isAvailable, state == .idle else { return false }
        onToggle?()
        return true
    }
}
