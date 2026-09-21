//
//  SettingsShortcutRecorder.swift
//  Luna
//
//  §3.6's editable key chip: it prints a shortcut, and when you click it, it
//  listens for the next one.
//
//  **This is the one place in Luna that installs an `NSEvent` monitor**, and the
//  ban it is stepping around is worth restating rather than quietly breaking.
//  `BrowserCommands` forbids monitors because a *command* driven by one is
//  invisible — not in a menu, not in the accessibility tree, impossible to
//  discover (§22.5). None of that applies here: nothing is being commanded. The
//  monitor exists so the keystroke can be **read instead of obeyed**, which is
//  exactly what the menu bar would otherwise do with it. Without one, pressing
//  ⇧⌘T over this control opens a tab.
//
//  It is local (this process), it matches only `.keyDown`, and it lives only
//  between the click that starts recording and the keystroke, Escape, or lost
//  focus that ends it. `stop()` is idempotent and is called from every exit,
//  including the view leaving its window.
//
//  Escape cancels and ⌫ clears, which is the convention every other shortcut
//  recorder on the platform uses. They are not recordable as shortcuts
//  themselves — neither carries ⌘, ⌃ or ⌥, so `KeyBinding(event:)` would refuse
//  them anyway.
//

import AppKit

@MainActor
final class SettingsShortcutRecorder: NSView {

    /// The captured keystroke, or nil for "clear this shortcut". Not called for
    /// a cancel — a cancelled recording is not a change.
    var onRecord: ((KeyBinding?) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var binding: KeyBinding?
    private var monitor: Any?
    private var isRecording = false
    private var isHovering = false { didSet { if isHovering != oldValue { refresh() } } }

    init(binding: KeyBinding?) {
        self.binding = binding
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous

        label.font = Tokens.TypeScale.settingsRow
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: SettingsMetrics.controlHeight),
            widthAnchor.constraint(greaterThanOrEqualToConstant: SettingsMetrics.controlHeight * 2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Tokens.Metric.chromeGap),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Tokens.Metric.chromeGap),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// Re-prints the chip — after a commit, and after a Reset that the row did
    /// not perform itself.
    func show(_ binding: KeyBinding?) {
        self.binding = binding
        refresh()
    }

    // MARK: - Recording

    override func mouseDown(with event: NSEvent) {
        // §6's swell, which here says "taken" rather than "held": the chip
        // changes mode on the way down, so the spring back on `mouseUp` is the
        // whole of the press. Without it the only thing a click changed was a
        // word, and a word is not a control answering a finger.
        Tokens.Motion.swell(self, to: Tokens.Motion.pressSwell)
        isRecording ? stop() : beginRecording()
    }

    override func mouseUp(with event: NSEvent) {
        Tokens.Motion.swell(self, to: 1)
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

    /// The keyboard's way in: §20.2 wants every chrome control operable without
    /// the pointer, and a recorder that can only be started by clicking is a
    /// shortcuts editor you need a mouse to use.
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers ?? ""
        guard !isRecording, key == " " || key == "\r" else {
            super.keyDown(with: event)
            return
        }
        beginRecording()
    }

    /// Test seam: internal so a test can drive a recording without a key window
    /// to click in.
    var isListening: Bool { isRecording }

    /// Internal for the same reason — see `isListening`.
    func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        window?.makeFirstResponder(self)
        // **Returning nil swallows the event.** That is the point: while this
        // control is listening, ⌘W must not close the tab behind the Settings
        // window on its way to being recorded.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, isRecording else { return event }
            record(event)
            return nil
        }
        refresh()
    }

    /// What the monitor hands over. Internal so the tests can measure Escape,
    /// Delete and the modifier floor without synthesising a click first.
    func record(_ event: NSEvent) {
        let key = event.charactersIgnoringModifiers ?? ""
        // 0x1B and 0x7F: Escape and Delete, neither of which can be a shortcut.
        if key == "\u{1B}" {
            stop()
            return
        }
        if key == "\u{7F}" {
            stop()
            onRecord?(nil)
            return
        }
        // Nil means "not a shortcut" — a bare letter, or shift and a letter,
        // which would be eaten out of every text field in the browser. Keep
        // listening rather than committing something unusable.
        guard let recorded = KeyBinding(event: event) else { return }
        stop()
        onRecord?(recorded)
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        refresh()
    }

    /// The view leaving its window — the Settings window closing, or the
    /// section being filtered away mid-recording. `deinit` is too late and, on
    /// a `@MainActor` type, not somewhere `removeMonitor` can be called from.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() }
    }

    override func resignFirstResponder() -> Bool {
        stop()
        return super.resignFirstResponder()
    }

    // MARK: - Drawing

    private func refresh() {
        label.stringValue = isRecording
            ? String(localized: "Press keys…")
            : (binding?.display ?? String(localized: "—"))
        // **The ink answers the pointer, not the fill.** This chip is drawn as
        // a well — `Surface.well` is black ink in both themes — and §3.4's
        // hover wash is white, so lifting the fill here would flip a recess
        // into a plate on the way past it. §3.1's other half is the one that
        // applies: the glyph, or here the keystroke, brightens instead.
        label.textColor = if isRecording {
            Tokens.Accent.tint
        } else {
            isHovering ? Tokens.Text.primary : Tokens.Text.secondary
        }
        setAccessibilityLabel(
            isRecording
                ? String(localized: "Recording. Press the new shortcut, or Escape to cancel.")
                : (binding.map { String(localized: "Shortcut \($0.display). Click to change.") }
                    ?? String(localized: "No shortcut. Click to set one."))
        )
        toolTip = isRecording
            ? String(localized: "Press the new shortcut, or Escape to cancel.")
            : String(localized: "Click, then press the new shortcut. Delete clears it.")
        needsDisplay = true
    }

    /// The pointer says what the border implies. A box you can click and a box
    /// you cannot are one hairline apart at a glance; the cursor changing as it
    /// crosses the edge settles it without the user having to click to find out.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = SettingsMetrics.controlCorner
        layer?.backgroundColor = Tokens.Surface.well.cgColor
        layer?.borderWidth = Tokens.Metric.hairline
        layer?.borderColor = (isRecording ? Tokens.Accent.tint : Tokens.Line.border).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    // MARK: - Focus ring (§20.2)

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(
            roundedRect: bounds,
            xRadius: SettingsMetrics.controlCorner,
            yRadius: SettingsMetrics.controlCorner
        ).fill()
    }
}
