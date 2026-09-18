//
//  SettingsNavCapsule.swift
//  Luna
//
//  The back/forward pair at the head of §1's detail pane.
//
//  **It replaces the pane's title**, which repeated in semibold the word the
//  user had just clicked two inches to the left. This spends that space on the
//  one thing the list cannot do: retracing the order the sections were actually
//  visited in.
//
//  One plate, two bare glyphs — not two buttons inside a capsule, which is
//  three rounded shapes where there should be one.
//

import AppKit

@MainActor
final class SettingsNavCapsule: NSView {

    var onBack: (() -> Void)?
    var onForward: (() -> Void)?

    private let back = SettingsNavChevron(symbolName: "chevron.backward", label: String(localized: "Back"))
    private let forward = SettingsNavChevron(symbolName: "chevron.forward", label: String(localized: "Forward"))
    private let divider = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        divider.wantsLayer = true
        back.onActivate = { [weak self] in self?.onBack?() }
        forward.onActivate = { [weak self] in self?.onForward?() }
        for view in [back, divider, forward] { addSubview(view) }
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "History"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// §4: a direction you cannot go is dimmed, not hidden — a capsule that
    /// changed width as you moved would be a moving target.
    func update(canGoBack: Bool, canGoForward: Bool) {
        back.isEnabled = canGoBack
        forward.isEnabled = canGoForward
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: Tokens.Metric.settingsNavCapsule.width,
            height: Tokens.Metric.settingsNavCapsule.height
        )
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            let half = bounds.width / 2
            back.frame = NSRect(x: 0, y: 0, width: half, height: bounds.height).pixelAligned
            forward.frame = NSRect(x: half, y: 0, width: half, height: bounds.height).pixelAligned
            // Short of the plate's edges: a rule that runs the full height cuts
            // the capsule in two rather than separating the glyphs.
            let inset = bounds.height / 4
            divider.frame = NSRect(
                x: half,
                y: inset,
                width: Tokens.Metric.hairline,
                height: bounds.height - 2 * inset
            ).pixelAligned
        }
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = Tokens.Metric.settingsNavCapsule.cornerRadius
        layer.backgroundColor = Tokens.Surface.raised.cgColor
        layer.borderWidth = Tokens.Metric.hairline
        layer.borderColor = Tokens.Line.border.cgColor
        divider.layer?.backgroundColor = Tokens.Line.hairline.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// One chevron on the capsule's plate. It carries no plate of its own — hover
/// lifts the glyph's ink, because there is no room for a second surface in here.
@MainActor
final class SettingsNavChevron: NSView {

    var onActivate: (() -> Void)?

    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            applyTint(animated: true)
        }
    }

    private let icon = NSImageView()
    private var isHovering = false {
        didSet {
            guard isHovering != oldValue else { return }
            applyTint(animated: true)
        }
    }

    init(symbolName: String, label: String) {
        super.init(frame: .zero)
        icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: Tokens.Metric.glyphSize - 3,
            weight: .semibold
        )
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
        applyTint(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func applyTint(animated: Bool) {
        let ink: NSColor = if !isEnabled {
            Tokens.Text.disabled
        } else if isHovering {
            Tokens.Text.primary
        } else {
            Tokens.Text.secondary
        }
        setAccessibilityEnabled(isEnabled)
        guard animated else {
            icon.contentTintColor = ink
            return
        }
        Tokens.Motion.animate(Tokens.Motion.controlHover) { context in
            context.allowsImplicitAnimation = true
            self.icon.contentTintColor = ink
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTint(animated: false)
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

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onActivate?()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onActivate?()
        return true
    }
}
