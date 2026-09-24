//
//  SettingsControls.swift
//  Luna
//
//  The controls §4's rows are filled with: the pushbutton, the text field and
//  its cell, and §3.6's key chip. The switch is AppKit's (`SystemSwitch`).
//
//  Split out of `SettingsRowView.swift` for that file's length limit, along the
//  seam it already had — above are the row and the containers it sits in, here
//  are the things that go inside one.
//
//  Each of these replaces an AppKit control rather than restyling it, and each
//  says why at its own declaration. The common thread is that AppKit's bezels
//  are the only bright plates in an otherwise dark pane.
//

import AppKit

/// §4's pushbutton, drawn flat.
///
/// AppKit's `.push` bezel is a near-white plate with a shadow: next to a bare
/// popup and a switch it read as the one control dropped in from another app.
/// Still an `NSButton`, so `isEnabled`, the key loop, `performClick` and the
/// `AXButton` role are AppKit's — only the bezel is ours.
@MainActor
final class SettingsPushButton: NSButton {

    var onActivate: (() -> Void)?

    private let isDestructive: Bool
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

    init(title: String, isDestructive: Bool) {
        self.isDestructive = isDestructive
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        isBordered = false
        self.title = title
        target = self
        action = #selector(fire)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: SettingsMetrics.controlHeight).isActive = true
        applyTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    @objc private func fire() { onActivate?() }

    /// The title is attributed, so `isEnabled` has to dim it by hand — AppKit
    /// only dims the ones it drew itself. `title` is overridden for the same
    /// reason: `attributedTitle` wins once it is set, so assigning the plain
    /// string alone would change nothing on screen.
    override var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            applyTitle()
        }
    }

    override var title: String {
        didSet {
            guard title != oldValue else { return }
            applyTitle()
        }
    }

    private func applyTitle() {
        let ink: NSColor = if !isEnabled {
            Tokens.Text.disabled
        } else if isDestructive {
            Tokens.Accent.danger
        } else {
            Tokens.Text.primary
        }
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: Tokens.TypeScale.settingsRow,
            .foregroundColor: ink
        ])
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 2 * SettingsMetrics.controlInset
        size.height = SettingsMetrics.controlHeight
        return size
    }

    private func redraw() {
        Tokens.Motion.animate(Tokens.Motion.controlHover) { context in
            context.allowsImplicitAnimation = true
            self.needsDisplay = true
            self.displayIfNeeded()
        }
    }

    /// §3.4's two washes, the way round every other control in the app has
    /// them: the resting plate is the 6 %, the pointer takes it to 12 %, and
    /// the press holds it there while the button swells. It used to be
    /// inverted — `selected` at rest and `hover` under the pointer — so the
    /// one button in Settings with a word on it was also the one that got
    /// fainter when you went for it.
    override func updateLayer() {
        guard let layer else { return }
        let lifted = isEnabled && (isHovering || isPressed)
        layer.cornerRadius = SettingsMetrics.controlCorner
        layer.backgroundColor = (lifted ? Tokens.Surface.selected : Tokens.Surface.hover).cgColor
        layer.borderWidth = Tokens.Metric.hairline
        layer.borderColor = Tokens.Line.border.cgColor
    }

    /// `wantsUpdateLayer` is false on a control that draws a title, so the plate
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

/// §4's text field, drawn as the well the browser's own two search fields are:
/// `Surface.well`, a hairline, and the same corner. AppKit's bezel is a white
/// box, which in a dark pane is the brightest thing in the window.
@MainActor
final class SettingsTextField: NSTextField {

    init(string: String) {
        super.init(frame: .zero)
        stringValue = string
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        usesSingleLineMode = true
        cell?.wraps = false
        cell?.isScrollable = true
        wantsLayer = true
        layer?.cornerCurve = .continuous
        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// Set when what is typed here is not being used — a custom search
    /// template with no `%s` in it. The ink carries it, because the alternative
    /// was a sentence under the row saying the same thing in thirty words.
    var warns = false {
        didSet {
            guard warns != oldValue else { return }
            Tokens.Motion.animate(Tokens.Motion.controlHover) { context in
                context.allowsImplicitAnimation = true
                self.applyTokens()
            }
        }
    }

    private func applyTokens() {
        font = Tokens.TypeScale.settingsRow
        textColor = if !isEnabled {
            Tokens.Text.disabled
        } else if warns {
            Tokens.Accent.danger
        } else {
            Tokens.Text.primary
        }
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.height = SettingsMetrics.controlHeight
        return size
    }

    override var isEnabled: Bool {
        didSet { applyTokens() }
    }

    override func drawFocusRingMask() {}

    override func draw(_ dirtyRect: NSRect) {
        guard let layer else {
            super.draw(dirtyRect)
            return
        }
        layer.cornerRadius = SettingsMetrics.controlCorner
        layer.backgroundColor = Tokens.Surface.well.cgColor
        layer.borderWidth = Tokens.Metric.hairline
        layer.borderColor = Tokens.Line.border.cgColor
        super.draw(dirtyRect)
    }

    override static var cellClass: AnyClass? {
        get { SettingsTextFieldCell.self }
        set { super.cellClass = newValue }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }
}

/// `NSTextFieldCell` draws from the top of whatever rect it is handed and never
/// centres, so a field standing at the pane's control height had its text
/// against the well's top edge. The inset is therefore horizontal and
/// vertical, measured from the line height of the font it was given.
@MainActor
final class SettingsTextFieldCell: NSTextFieldCell {

    private func centred(_ rect: NSRect) -> NSRect {
        let line = (font ?? Tokens.TypeScale.settingsRow).boundingRectForFont.height
        let inset = max((rect.height - line) / 2, 0)
        return rect.insetBy(dx: Tokens.Metric.pillTextInset, dy: inset)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        super.drawingRect(forBounds: centred(rect))
    }

    override func edit(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(withFrame: centred(rect), in: controlView, editor: editor, delegate: delegate, event: event)
    }

    override func select(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor: NSText,
        delegate: Any?,
        start: Int,
        length: Int
    ) {
        super.select(
            withFrame: centred(rect),
            in: controlView,
            editor: editor,
            delegate: delegate,
            start: start,
            length: length
        )
    }
}

/// A key equivalent, on the same well every other read-only value sits in.
///
/// `isFixed` is the whole of §3.6's "which of these can I change?". A
/// shortcut the user can move is drawn by `SettingsShortcutRecorder`, which is
/// this chip plus a click target: same well, same border, same corner. Drawn
/// identically, a shortcut that is nobody's to move looked exactly like one
/// that is, and the only way to find out was to click it. A fixed chip
/// therefore drops the well and the border and prints flat, so the boxes down
/// the right-hand side of the table are precisely the rows that are yours.
@MainActor
final class SettingsKeyChip: NSView {

    private let label: NSTextField
    private let isFixed: Bool

    init(key: String, isFixed: Bool = false) {
        label = NSTextField(labelWithString: key)
        self.isFixed = isFixed
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        label.font = Tokens.TypeScale.settingsRow
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: SettingsMetrics.controlHeight),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Tokens.Metric.chromeGap),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Tokens.Metric.chromeGap),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(isFixed ? String(localized: "Shortcut \(key). This one cannot be changed.") : key)
        applyTint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func applyTint() {
        label.textColor = isFixed ? Tokens.Text.tertiary : Tokens.Text.secondary
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = SettingsMetrics.controlCorner
        // Nothing drawn at all, rather than a paler well: a faint box is still a
        // box, and at a glance it would read as a control that happens to be
        // dimmed — which is the one thing this must not say.
        guard !isFixed else {
            layer?.backgroundColor = nil
            layer?.borderWidth = 0
            return
        }
        layer?.backgroundColor = Tokens.Surface.well.cgColor
        layer?.borderWidth = Tokens.Metric.hairline
        layer?.borderColor = Tokens.Line.border.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTint()
    }
}
