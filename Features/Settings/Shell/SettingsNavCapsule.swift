//
//  SettingsNavCapsule.swift
//  Luna
//
//  The back/forward pair at the head of §1's detail pane.
//
//  **It replaces the pane's title.** The pane used to open with the section's
//  name and a hairline under it — which repeats, in 12 pt semibold, the word
//  the user has just clicked in the list two inches to the left. The reference
//  spends that space on the one thing the list cannot do: retracing the order
//  the sections were actually visited in. `⌘,` → General → Privacy → back is a
//  gesture; "Privacy" written above Privacy is not.
//
//  **One plate, two bare chevrons.** The first build of this made each chevron
//  a `GlassButton`, so the capsule showed two circles inside a pill — three
//  rounded shapes stacked where the reference has one. The reference's capsule
//  is a single rounded rectangle with the glyphs drawn straight onto it, and
//  the only thing that ever moves is the glyph's ink: full strength when you
//  can go that way, `Text.disabled` when you cannot.
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
        Glass.apply(.control, to: self, cornerRadius: Tokens.Metric.settingsNavCapsule.cornerRadius)
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
    /// changed width as you moved through the sections would be a moving target.
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
            // The rule is short of the plate's edges on purpose: a divider that
            // runs the full height cuts the capsule in two, and the reference
            // draws one that only separates the glyphs.
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
        divider.layer?.backgroundColor = Tokens.Line.hairline.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// One chevron on the capsule's plate. Not a `GlassButton`: it carries no
/// material of its own, because the capsule under it already is one.
@MainActor
final class SettingsNavChevron: NSView {

    var onActivate: (() -> Void)?

    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            applyTint()
        }
    }

    private let icon = NSImageView()
    private var isHovering = false {
        didSet {
            guard isHovering != oldValue else { return }
            applyTint()
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
        applyTint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// The only thing that changes. Hover lifts the glyph rather than lighting
    /// a plate under it — there is no room for a second material in here.
    private func applyTint() {
        icon.contentTintColor = if !isEnabled {
            Tokens.Text.disabled
        } else if isHovering {
            Tokens.Text.primary
        } else {
            Tokens.Text.secondary
        }
        setAccessibilityEnabled(isEnabled)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTint()
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
