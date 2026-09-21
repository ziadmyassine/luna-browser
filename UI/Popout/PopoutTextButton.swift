//
//  PopoutTextButton.swift
//  Luna
//
//  A word in a pop-out's header that can be pressed. §15.3's "Clear" is the
//  only one, and it was a bare `NSButton` with an attributed title on it —
//  which meant it was the one control in the app that answered neither the
//  pointer nor the finger. CLAUDE.md's first rule is that every button Luna
//  draws does both.
//
//  **It is flat at rest, and that is not an exemption from §3.4's washes — it
//  is where they start from.** `SettingsPushButton` wears the 6 % at rest and
//  goes to 12 % under the pointer because it stands in a pane of plates, among
//  other plates; this stands in a glass header next to a heading, and a
//  permanent plate beside "Downloads" would read as a second title in a box.
//  So the resting state is the header's own material, the pointer brings the
//  6 %, and the press takes it to 12 % and swells — the same two washes in the
//  same order, with the chip appearing rather than brightening.
//
//  Full radius rather than `rowCornerRadius`: at the height a word sets this
//  is a capsule the size of §3.2's, and a 12 pt corner on a 23 pt chip is a
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

    init(title: String, label: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        // A borderless text button rather than a bezelled one: a push button's
        // system bezel is the one piece of stock AppKit chrome that cannot be
        // made to sit on glass, which is half of what was wrong with the panel
        // this replaces.
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
    override var title: String {
        didSet {
            guard title != oldValue else { return }
            applyTitle()
        }
    }

    private func applyTitle() {
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: Tokens.TypeScale.settingsCaption,
            // Brighter under the pointer, for the same reason the wash arrives:
            // a word is mostly ink, so the ink is most of the answer.
            .foregroundColor: isHovering || isPressed ? Tokens.Text.primary : Tokens.Text.secondary
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
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
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
