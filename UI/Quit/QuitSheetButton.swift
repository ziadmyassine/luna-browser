//
//  QuitSheetButton.swift
//  Luna
//
//  The three answers on §3.1's quit sheet: a capsule with a word in it and,
//  on the two that have one, the key that does the same thing.
//
//  **Its own control rather than `GlassButton` or `SettingsPushButton`.**
//  `GlassButton` is a shape with a symbol in it — every one in the chrome is
//  square or round and none of them carries a title. `SettingsPushButton` is
//  the Settings shell's, sized by `SettingsMetrics`, and a modal in the browser
//  window is not a settings row. What both of them lack is the thing this is
//  for: **the key hint**. The sheet takes the keyboard while it is up, so what
//  Return and Escape do is not a shortcut the user might discover, it is part
//  of the answer — and a control that says so is why nobody has to read the
//  sentence twice.
//
//  The fill is §3.4's, which is the same pair the rest of the chrome answers
//  the pointer with: `Surface.hover` under it, `Surface.selected` under a
//  press. The one that is already `selected` — the recommended answer — has
//  nothing above it to lift to, so it holds still and lets its glyph carry the
//  press instead. There is no accent here and no blue: §3.4 settled that.
//

import AppKit

@MainActor
final class QuitSheetButton: NSView {

    var onActivate: (() -> Void)?

    /// The answer the sheet is recommending. Exactly one button per sheet may
    /// be one, and it is the one Return is bound to.
    let isKey: Bool

    private let label = NSTextField(labelWithString: "")
    /// The key that does the same thing, in a well of its own — or nil for the
    /// answer no key is bound to.
    private let hint: NSTextField?
    private let hintWell = NSView()

    private var isHovering = false { didSet { guard isHovering != oldValue else { return }; applyState() } }
    private var isPressed = false { didSet { guard isPressed != oldValue else { return }; applyState() } }

    init(title: String, keyHint: String?, isKey: Bool) {
        self.isKey = isKey
        hint = keyHint.map(NSTextField.init(labelWithString:))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous

        label.stringValue = title
        // One step above a chrome row: this is the sentence you are answering
        // with, not a label beside something else.
        label.font = Tokens.TypeScale.commandBarRow
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        translatesAutoresizingMaskIntoConstraints = false
        var constraints = [
            heightAnchor.constraint(equalToConstant: Tokens.Metric.urlPill.height),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Tokens.Metric.chromeGapWide),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ]
        if let hint {
            hint.font = Tokens.TypeScale.sectionLabel
            hint.alignment = .center
            hint.translatesAutoresizingMaskIntoConstraints = false
            hintWell.wantsLayer = true
            hintWell.layer?.cornerCurve = .continuous
            hintWell.translatesAutoresizingMaskIntoConstraints = false
            hintWell.addSubview(hint)
            addSubview(hintWell)
            // **The key is the button's end, not a chip floating inside it.**
            // Inset from the trailing edge, the capsule's own fill came back
            // in the sliver between the chip and the edge — a second
            // background in the last four points of the control, which at a
            // glance reads as the chip having come loose. Pinned to all three
            // edges it is the cap instead: the button is a title and a key,
            // and the two of them are the whole capsule.
            constraints += [
                hintWell.leadingAnchor.constraint(
                    equalTo: label.trailingAnchor,
                    constant: Tokens.Metric.chromeGap
                ),
                hintWell.trailingAnchor.constraint(equalTo: trailingAnchor),
                hintWell.topAnchor.constraint(equalTo: topAnchor),
                hintWell.bottomAnchor.constraint(equalTo: bottomAnchor),
                // Dead centre of the cap, both ways. An optical nudge toward
                // the leading edge was tried first, on the theory that the
                // trailing half of the cap is curve rather than field — and
                // what it actually looks like is a key that has slipped.
                // `esc` and the return arrow are both marks in a capsule, and
                // a mark in a capsule sits in the middle of it.
                hint.centerXAnchor.constraint(equalTo: hintWell.centerXAnchor),
                hint.centerYAnchor.constraint(equalTo: hintWell.centerYAnchor),
                // Which leaves the inset to say how narrow the cap may get.
                hint.leadingAnchor.constraint(
                    greaterThanOrEqualTo: hintWell.leadingAnchor,
                    constant: Tokens.Metric.chromeGap
                ),
                hint.trailingAnchor.constraint(
                    lessThanOrEqualTo: hintWell.trailingAnchor,
                    constant: -Tokens.Metric.chromeGap
                )
            ]
        } else {
            constraints.append(
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Tokens.Metric.chromeGapWide)
            )
        }
        NSLayoutConstraint.activate(constraints)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - State

    private func applyState() {
        Tokens.Motion.wash(layer, to: fill)
        label.textColor = ink
    }

    /// **The recommended answer is filled with the accent, and it is the only
    /// control in Luna that is.** See `Tokens.Accent.onTint` for why the rule
    /// it breaks is still a rule. Its two other states are AppKit's own
    /// variants of that colour rather than a second and third blue chosen
    /// here: `withSystemEffect` is what every stock control uses, so the
    /// hovered and pressed accent match the rest of the system exactly, in
    /// whichever accent the user picked and whichever theme they are in.
    ///
    /// The other two answers are §3.4's pair, unchanged: `Surface.well` at
    /// rest, `hover` under the pointer, `selected` under a press.
    private var fill: NSColor? {
        if isKey {
            if isPressed { return Tokens.Accent.tint.withSystemEffect(.pressed) }
            return isHovering ? Tokens.Accent.tint.withSystemEffect(.rollover) : Tokens.Accent.tint
        }
        if isPressed { return Tokens.Surface.selected }
        return isHovering ? Tokens.Surface.hover : Tokens.Surface.well
    }

    private var ink: NSColor {
        if isKey { return Tokens.Accent.onTint }
        return isHovering || isPressed ? Tokens.Text.primary : Tokens.Text.secondary
    }

    private func applyTokens() {
        Tokens.Motion.wash(layer, to: fill, animated: false)
        label.textColor = ink
        hint?.textColor = isKey ? Tokens.Accent.onTint : Tokens.Text.tertiary
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = Tokens.Metric.urlPill.cornerRadius
        // **The filled one carries no hairline.** §2's edge is what stops a
        // translucent surface reading as a smudge; a solid colour has an edge
        // already, and a grey line round it only muddies the one it has.
        layer.borderWidth = isKey ? 0 : Tokens.Metric.hairline
        layer.borderColor = isKey ? nil : Tokens.Line.border.cgColor
        // The button's own radius, because the well's trailing half *is* the
        // button's trailing cap and the two curves have to be one curve.
        hintWell.layer?.cornerRadius = Tokens.Metric.urlPill.cornerRadius
        // On the accent the well is a hole punched in it rather than a recess
        // cut into the chrome, so it is the accent's own ink at a wash — which
        // is what `Surface.well` already is over everything else.
        hintWell.layer?.backgroundColor = (isKey ? Tokens.Surface.selected : Tokens.Surface.well).cgColor
        hintWell.layer?.borderWidth = isKey ? 0 : Tokens.Metric.hairline
        hintWell.layer?.borderColor = isKey ? nil : Tokens.Line.border.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }

    // MARK: - The pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        Tokens.Motion.swell(self, to: Tokens.Motion.pressSwell)
    }

    /// The whole gesture, the way every other control in Luna reads one: the
    /// button fires only if the mouse comes back up inside it.
    override func mouseUp(with event: NSEvent) {
        isPressed = false
        Tokens.Motion.swell(self, to: 1)
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        onActivate?()
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }

    /// §30.1: a press on the sheet is an answer, never a window drag.
    override var mouseDownCanMoveWindow: Bool { false }
}
