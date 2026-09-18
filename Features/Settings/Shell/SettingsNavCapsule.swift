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

import AppKit

@MainActor
final class SettingsNavCapsule: NSView {

    var onBack: (() -> Void)?
    var onForward: (() -> Void)?

    private let back = GlassButton(
        shape: Tokens.Metric.controlCircle,
        symbolName: "chevron.backward",
        pointSize: Tokens.Metric.glyphSize,
        label: String(localized: "Back"),
        // Bare on the capsule's own glass: two materials stacked read as a
        // button inside a button. The chevron takes its material on hover.
        glassMode: .dormant
    )
    private let forward = GlassButton(
        shape: Tokens.Metric.controlCircle,
        symbolName: "chevron.forward",
        pointSize: Tokens.Metric.glyphSize,
        label: String(localized: "Forward"),
        glassMode: .dormant
    )
    private let divider = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        // One capsule of glass with two bare glyphs on it, which is §4's action
        // capsule exactly: the material is the button, the chevrons are only
        // what it says.
        Glass.apply(.control, to: self, cornerRadius: SettingsMetrics.controlRowHeight / 2)
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
        let circle = Tokens.Metric.controlCircle
        return NSSize(
            width: 2 * circle.width + Tokens.Metric.hairline + 2 * Tokens.Metric.chromeGap,
            height: SettingsMetrics.controlRowHeight
        )
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            let circle = Tokens.Metric.controlCircle
            let originY = (bounds.height - circle.height) / 2
            let inset = Tokens.Metric.chromeGap / 2
            back.frame = NSRect(x: inset, y: originY, width: circle.width, height: circle.height).pixelAligned
            divider.frame = NSRect(
                x: back.frame.maxX + Tokens.Metric.chromeGap / 2,
                y: originY + circle.height / 4,
                width: Tokens.Metric.hairline,
                height: circle.height / 2
            ).pixelAligned
            forward.frame = NSRect(
                x: divider.frame.maxX + Tokens.Metric.chromeGap / 2,
                y: originY,
                width: circle.width,
                height: circle.height
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
