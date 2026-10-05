//
//  AstroHero.swift
//  Luna
//
//  The head of the Astro page: Astro itself, live, floating in the night sky
//  Luna Control's page is drawn on (`Tokens.Moon`), with its name, a line on
//  what it does, and a chip that says whether it is ready. It stands in for
//  `SettingsPageHeader`, as the sky does on Luna Control's page.
//

import AppKit

@MainActor
final class AstroHeroView: NSView {

    private let rover = AgentRoverView()
    private let glow = CAGradientLayer()
    private let sky = CAGradientLayer()
    private let stars = CAShapeLayer()
    private let chip = NSView()
    private let dot = NSView()
    private let status = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = Tokens.Metric.rowCornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        sky.colors = [Tokens.Moon.skyTop.cgColor, Tokens.Moon.skyBottom.cgColor]
        sky.startPoint = CGPoint(x: 0.5, y: 1)
        sky.endPoint = CGPoint(x: 0.5, y: 0)
        stars.fillColor = Tokens.Moon.star.cgColor
        // A halo behind Astro in the bloom's lavender, fading to nothing.
        glow.type = .radial
        glow.colors = [Tokens.Moon.glowInner.withAlphaComponent(0.32).cgColor, Tokens.Moon.glowInner.withAlphaComponent(0).cgColor]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        for sublayer in [sky, stars, glow] { layer?.addSublayer(sublayer) }
        build()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Astro"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func build() {
        let name = NSTextField(labelWithString: String(localized: "Astro"))
        name.font = Tokens.TypeScale.settingsPageTitle
        name.textColor = Tokens.Moon.ink
        let line = NSTextField(wrappingLabelWithString: String(
            localized: "Your agent in Luna. Give it a task and it works in tabs of its own while you watch."
        ))
        line.font = Tokens.TypeScale.settingsRow
        line.textColor = Tokens.Moon.inkSecondary
        line.alignment = .center
        buildChip()
        for view in [rover, name, line, chip] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let inset = SettingsMetrics.cardInset
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Tokens.Metric.controlSkyHeight),
            rover.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            rover.centerXAnchor.constraint(equalTo: centerXAnchor),
            rover.widthAnchor.constraint(equalToConstant: Tokens.Metric.agentRoverHero),
            rover.heightAnchor.constraint(equalToConstant: Tokens.Metric.agentRoverHero),
            name.topAnchor.constraint(equalTo: rover.bottomAnchor, constant: 2),
            name.centerXAnchor.constraint(equalTo: centerXAnchor),
            line.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 2),
            line.centerXAnchor.constraint(equalTo: centerXAnchor),
            line.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            line.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: inset),
            chip.topAnchor.constraint(equalTo: line.bottomAnchor, constant: SettingsMetrics.controlRowGap + 4),
            chip.centerXAnchor.constraint(equalTo: centerXAnchor),
            chip.heightAnchor.constraint(equalToConstant: Tokens.Metric.controlChipHeight),
            chip.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -inset)
        ])
    }

    /// The status chip, drawn as Luna Control's sky draws its own.
    private func buildChip() {
        chip.wantsLayer = true
        chip.layer?.backgroundColor = Tokens.Moon.chipFill.cgColor
        chip.layer?.borderColor = Tokens.Moon.chipRing.cgColor
        chip.layer?.borderWidth = Tokens.Metric.hairline
        chip.layer?.cornerRadius = Tokens.Metric.controlChipHeight / 2
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3.5
        status.font = Tokens.TypeScale.settingsCaption
        status.textColor = Tokens.Moon.ink
        for view in [dot, status] {
            view.translatesAutoresizingMaskIntoConstraints = false
            chip.addSubview(view)
        }
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 12),
            dot.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 7),
            dot.heightAnchor.constraint(equalToConstant: 7),
            status.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 7),
            status.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -12),
            status.centerYAnchor.constraint(equalTo: chip.centerYAnchor)
        ])
    }

    /// The chip: ready and on which model, or what stands in the way.
    func show(ready: Bool, text: String) {
        status.stringValue = text
        dot.layer?.backgroundColor = (ready ? Tokens.Moon.glowOuter : Tokens.Moon.dotOff).cgColor
        rover.mood = ready ? .idle : .stopped
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            sky.frame = bounds
            stars.frame = bounds
            stars.path = Self.stars(in: bounds)
            let side: CGFloat = 220
            let centre = bounds.maxY - Tokens.Metric.agentRoverHero / 2 - SettingsMetrics.cardInset
            glow.frame = CGRect(x: bounds.midX - side / 2, y: centre - side / 2, width: side, height: side)
        }
    }

    /// The same stars every time, scattered by a fixed sequence rather than
    /// at random, so the sky does not reshuffle when the page is rebuilt.
    static func stars(in bounds: CGRect) -> CGPath {
        let path = CGMutablePath()
        var seed: UInt64 = 0x5EED_A57C
        func next() -> CGFloat {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
        }
        // Clear of the words, which a star on a letter reads as a typo in.
        let words = CGRect(
            x: bounds.width * 0.16, y: bounds.height * 0.06, width: bounds.width * 0.68, height: bounds.height * 0.48
        )
        for _ in 0..<56 {
            let point = CGPoint(x: next() * bounds.width, y: next() * bounds.height)
            let radius = 0.4 + next() * 0.9
            guard !words.contains(point) else { continue }
            path.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius))
        }
        return path
    }
}
