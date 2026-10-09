//
//  AgentComposerView.swift
//  Luna
//
//  Where the user writes to the agent: a capsule with a field and one round
//  button at its end — send while there is something to send, Stop while the
//  agent works and the field is empty. Return sends; Shift- or Option-Return
//  starts a new line. The field grows a line at a time as the words wrap, up
//  to `agentComposerLines`, and scrolls past that. Round it runs a ring of
//  Astro's light, lavender to ice, which turns while Astro works.
//

import AppKit

@MainActor
final class AgentComposerView: NSView, NSTextViewDelegate {

    var onSend: ((String) -> Void)?
    /// How far the field stands above its one-line height, said inside the
    /// animation that grows it, so the conversation can make room in step.
    var onGrow: ((CGFloat) -> Void)?
    var onStop: (() -> Void)?

    var isRunning = false { didSet { if isRunning != oldValue { refresh() } } }
    var isEnabled = true { didSet { if isEnabled != oldValue { refresh() } } }

    private let scroll = NSScrollView()
    /// Fades the text out across the field's top and bottom inset, where no
    /// line stands at rest, so one scrolled part out of sight fades rather
    /// than being cut in half.
    private let fade = CAGradientLayer()
    private let field = AgentComposerTextView()
    private var height: NSLayoutConstraint?
    private let ring = CAGradientLayer()
    private let ringShape = CAShapeLayer()
    private let button = GlassButton(
        shape: Tokens.Metric.controlCircle, symbolName: "arrow.up",
        pointSize: Tokens.Metric.agentStepGlyph + 1, label: String(localized: "Send")
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        Glass.apply(.control, to: self, cornerRadius: Self.radius)
        ring.type = .conic
        ring.startPoint = CGPoint(x: 0.5, y: 0.5)
        ring.endPoint = CGPoint(x: 0.5, y: 0)
        ringShape.fillColor = nil
        ringShape.strokeColor = NSColor.black.cgColor
        ringShape.lineWidth = 1.5
        ring.mask = ringShape
        ring.shadowColor = Tokens.Astro.from.cgColor
        ring.shadowRadius = 6
        ring.shadowOffset = .zero
        layer?.addSublayer(ring)
        buildField()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.onActivate = { [weak self] in self?.press() }
        addSubview(scroll)
        addSubview(button)
        let circle = Tokens.Metric.controlCircle
        let end = (Tokens.Metric.agentComposerHeight - circle.height) / 2
        let height = heightAnchor.constraint(equalToConstant: Tokens.Metric.agentComposerHeight)
        self.height = height
        NSLayoutConstraint.activate([
            height,
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Tokens.Metric.pillTextInset + 4),
            scroll.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -Tokens.Metric.chromeGap),
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: Self.rim),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.rim),
            // At the foot as the field grows, where the last line is.
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -end),
            button.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -end),
            button.widthAnchor.constraint(equalToConstant: circle.width),
            button.heightAnchor.constraint(equalToConstant: circle.height)
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// A capsule at one line, and the same corners as it grows: a radius of
    /// half the height made a tall field a lozenge.
    private static let radius = Tokens.Metric.agentComposerHeight / 2
    /// The text stops this far inside the capsule's top and bottom, so a
    /// line scrolled half out of sight is cut short of the ring, not under it.
    private static let rim: CGFloat = 6

    private func buildField() {
        field.font = Tokens.TypeScale.agentBody
        field.textColor = Tokens.Text.primary
        field.drawsBackground = false
        field.isRichText = false
        field.allowsUndo = true
        field.isAutomaticQuoteSubstitutionEnabled = false
        field.delegate = self
        field.isVerticallyResizable = true
        field.isHorizontallyResizable = false
        field.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        field.autoresizingMask = .width
        field.textContainer?.widthTracksTextView = true
        field.textContainer?.lineFragmentPadding = 0
        // One line sits in the middle of the capsule, as the old field's did.
        let line = field.layoutManager?.defaultLineHeight(for: Tokens.TypeScale.agentBody) ?? 16
        field.textContainerInset = NSSize(width: 0, height: ((Tokens.Metric.agentComposerHeight - line) / 2 - Self.rim).rounded(.down))
        scroll.documentView = field
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.wantsLayer = true
        fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        scroll.layer?.mask = fade
    }

    /// The height the words need: one line's capsule at least, and
    /// `agentComposerLines` of them at most.
    var fittingHeight: CGFloat {
        guard let layout = field.layoutManager, let container = field.textContainer else { return Tokens.Metric.agentComposerHeight }
        layout.ensureLayout(for: container)
        let line = layout.defaultLineHeight(for: Tokens.TypeScale.agentBody)
        let used = max(layout.usedRect(for: container).height, line)
        let cap = Tokens.Metric.agentComposerHeight + CGFloat(Tokens.Metric.agentComposerLines - 1) * line
        let needed = used + 2 * (field.textContainerInset.height + Self.rim)
        return min(max(needed, Tokens.Metric.agentComposerHeight), cap).rounded(.up)
    }

    /// Grows or shrinks to the words, the conversation above giving way in the
    /// same movement.
    private func fit(animated: Bool = true) {
        let target = fittingHeight
        guard let height, abs(height.constant - target) > 0.5 else { return }
        let rise = target - Tokens.Metric.agentComposerHeight
        guard animated, window != nil, let container = superview else {
            height.constant = target
            onGrow?(rise)
            return
        }
        // The field grows over the foot of the conversation rather than
        // pushing it: re-laying out the conversation, its blurred edges and
        // its fade on every new line was what made this stutter.
        Tokens.Motion.animate(Tokens.Motion.composerGrow) { context in
            context.allowsImplicitAnimation = true
            height.constant = target
            onGrow?(rise)
            container.layoutSubtreeIfNeeded()
        }
        field.scrollRangeToVisible(field.selectedRange())
    }

    override func layout() {
        super.layout()
        // The text runs the scroll view's width and fills its height, so a
        // click anywhere in the field lands in it. Words set before there was
        // a width (Ask Astro's) are measured again once there is one.
        let room = scroll.contentSize
        if field.frame.width != room.width {
            Tokens.Motion.immediately { field.frame.size.width = room.width }
            DispatchQueue.main.async { [weak self] in self?.fit(animated: false) }
        }
        field.minSize = NSSize(width: 0, height: room.height)
        // Inside the growing animation the ring keeps pace with the glass;
        // anything else lands at once.
        let context = NSAnimationContext.current
        CATransaction.begin()
        if context.allowsImplicitAnimation, context.duration > 0 {
            CATransaction.setAnimationDuration(context.duration)
            CATransaction.setAnimationTimingFunction(context.timingFunction)
        } else {
            CATransaction.setDisableActions(true)
        }
        ring.frame = bounds
        ringShape.frame = bounds
        fade.frame = scroll.bounds
        let edge = Double(field.textContainerInset.height / max(scroll.bounds.height, 1))
        fade.locations = [0, NSNumber(value: edge), NSNumber(value: 1 - edge), 1]
        let radius = Self.radius - 0.75
        ringShape.path = CGPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), cornerWidth: radius, cornerHeight: radius, transform: nil)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paintRing()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        spinRing()
    }

    private func paintRing() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let alpha = Tokens.Astro.ringAlpha(dark: dark) * (isRunning ? 1 : 0.55)
        let from = Tokens.Astro.from.withAlphaComponent(alpha).cgColor
        let to = Tokens.Astro.to.withAlphaComponent(alpha).cgColor
        ring.colors = [from, to, from]
        ring.shadowOpacity = isRunning ? 0.7 : 0
    }

    /// The light runs round the ring while Astro works.
    private func spinRing() {
        guard isRunning, window != nil, !Tokens.Motion.reduceMotion else { return ring.removeAnimation(forKey: "spin") }
        // Left running: restarting it on every keystroke made it stutter.
        guard ring.animation(forKey: "spin") == nil else { return }
        let spin = CAKeyframeAnimation(keyPath: "endPoint")
        spin.values = (0...8).map { step in
            let angle = Double(step) / 8 * 2 * .pi
            return NSValue(point: NSPoint(x: 0.5 + 0.5 * sin(angle), y: 0.5 - 0.5 * cos(angle)))
        }
        spin.duration = 3
        spin.repeatCount = .infinity
        ring.add(spin, forKey: "spin")
    }

    func focus() {
        window?.makeFirstResponder(field)
    }

    /// What the field holds — for the Command Bar's "Ask Astro", which
    /// arrives with its text already written.
    var text: String {
        get { field.string }
        set {
            field.string = newValue
            refresh()
            fit(animated: false)
        }
    }

    private var hasText: Bool { !field.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func refresh() {
        paintRing()
        spinRing()
        field.isEditable = isEnabled
        field.isSelectable = isEnabled
        field.placeholder = isRunning
            ? String(localized: "Tell it more while it works…") : String(localized: "Ask Astro to do something…")
        let stops = isRunning && !hasText
        button.setSymbol(stops ? "stop.fill" : "arrow.up")
        button.setAccessibilityLabel(stops ? String(localized: "Stop") : String(localized: "Send"))
        button.isEnabled = isEnabled && (stops || hasText)
    }

    private func press() {
        guard hasText else {
            if isRunning { onStop?() }
            return
        }
        let text = field.string
        field.string = ""
        onSend?(text)
        refresh()
        fit()
    }

    func textDidChange(_ notification: Notification) {
        refresh()
        fit()
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        // Shift-Return is a new line, as Option-Return already is: that one
        // arrives as `insertNewlineIgnoringFieldEditor` and is left to the view.
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            textView.insertNewlineIgnoringFieldEditor(nil)
        } else {
            press()
        }
        return true
    }
}

/// The composer's text, with its placeholder drawn where the first line
/// would be while there is nothing written.
@MainActor
final class AgentComposerTextView: NSTextView {

    var placeholder = "" {
        didSet { if placeholder != oldValue { needsDisplay = true } }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? Tokens.TypeScale.agentBody, .foregroundColor: Tokens.Text.tertiary
        ]
        NSAttributedString(string: placeholder, attributes: attributes).draw(at: textContainerOrigin)
    }

    override func didChangeText() {
        super.didChangeText()
        // The placeholder goes the moment the first letter arrives, and comes
        // back when the last one goes.
        needsDisplay = true
    }
}
