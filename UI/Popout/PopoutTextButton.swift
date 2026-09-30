//
//  PopoutTextButton.swift
//  Luna
//
//  A word in a pop-out's header that can be pressed, such as §15.3's "Clear".
//  It answers the pointer and the finger like every button Luna draws.
//
//  Flat at rest, which is not an exemption from §3.4's washes but where they
//  start from. `SettingsPushButton` wears the 6 % at rest because it stands
//  among other plates; this stands in a glass header beside a heading, where a
//  permanent plate would read as a second title in a box. So the pointer
//  brings the 6 %, and the press takes it to 12 % and swells.
//
//  Full radius rather than `rowCornerRadius`: at the height a word sets this is
//  a capsule the size of §3.2's, and a 12 pt corner on a 23 pt chip is a
//  rounded rectangle pretending to be one.
//

import AppKit

/// A text button for a pop-out header. Presses like everything else.
@MainActor
final class PopoutTextButton: NSButton {

    var onActivate: (() -> Void)?

    private var isHovering = false {
        didSet {
            guard isHovering != oldValue else { return }
            redraw()
        }
    }
    private var isPressed = false {
        didSet {
            guard isPressed != oldValue else { return }
            redraw()
            Tokens.Motion.swell(self, to: isPressed ? Tokens.Motion.pressSwell : 1)
        }
    }

    /// A header word rests at secondary ink beside its heading. On a chip the
    /// button is the message's other half, and at secondary ink over a busy
    /// page it read as disabled, so a chip passes the heading's own ink and font.
    private let restingInk: NSColor
    private let titleFont: NSFont

    init(
        title: String,
        label: String,
        restingInk: NSColor = Tokens.Text.secondary,
        font: NSFont = Tokens.TypeScale.settingsCaption
    ) {
        self.restingInk = restingInk
        self.titleFont = font
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        // A borderless text button rather than a bezelled one: a push button's
        // system bezel is the one piece of stock AppKit chrome that cannot be
        // made to sit on glass.
        isBordered = false
        self.title = title
        target = self
        action = #selector(fire)
        setAccessibilityLabel(label)
        translatesAutoresizingMaskIntoConstraints = false
        applyTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    @objc private func fire() { onActivate?() }

    /// The title is attributed, so it has to be re-made whenever the colour it
    /// is drawn in could have changed — AppKit only re-inks the ones it drew
    /// itself. `title` is overridden for the same reason: `attributedTitle`
    /// wins once it is set, so assigning the plain string alone would change
    /// nothing on screen.
    /// Re-applied even when the words are the same: `NSButton`'s setter has
    /// already reset the attributes to `controlTextColor` by then.
    override var title: String {
        didSet { applyTitle() }
    }

    private func applyTitle() {
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: titleFont,
            // Brighter under the pointer, for the same reason the wash arrives:
            // a word is mostly ink, so the ink is most of the answer.
            .foregroundColor: isHovering || isPressed ? Tokens.Text.primary : restingInk
        ])
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    /// The word, with a chip's worth of room around it. `panelInset` is the
    /// pop-out's own gap, so the chip is inset from the panel edge by exactly
    /// as much as it is padded inside.
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 2 * Tokens.Metric.panelInset
        size.height += Tokens.Metric.panelInset
        return size
    }

    private func redraw() {
        applyTitle()
        Tokens.Motion.animate(Tokens.Motion.controlHover) { context in
            context.allowsImplicitAnimation = true
            self.needsDisplay = true
            self.displayIfNeeded()
        }
    }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = bounds.height / 2
        let wash: NSColor? = if isPressed {
            Tokens.Surface.selected
        } else if isHovering {
            Tokens.Surface.hover
        } else {
            nil
        }
        layer.backgroundColor = wash?.cgColor
    }

    /// `wantsUpdateLayer` is false on a control that draws a title, so the chip
    /// is refreshed on the way into `super.draw`.
    override func draw(_ dirtyRect: NSRect) {
        updateLayer()
        super.draw(dirtyRect)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTitle()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        // Active in the app, not the key window: §17's chip is a non-activating
        // panel that never becomes key, and its buttons still answer the pointer.
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }

    override func mouseExited(with event: NSEvent) { isHovering = false }

    /// The press is taken around `NSControl`'s own tracking loop, which does
    /// not return until the mouse comes back up — see `TopBarButton.mouseDown`.
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        super.mouseDown(with: event)
        isPressed = false
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        isPressed = flag && isEnabled
    }
}
