//
//  ControlRows.swift
//  Luna
//
//  The rows under Luna Control's sky: an app with its planet and its status,
//  a line of the activity log on its rail, and the dot both of them carry.
//  Plus the layer a newly connected app's light flies across on its way from
//  its row into orbit.
//

import AppKit

/// Grey for off, green for connected, and green with a widening ring while
/// the app is in use.
@MainActor
final class ControlStatusDot: NSView {

    enum State { case off, on, live }

    var state: State = .off {
        didSet {
            guard state != oldValue else { return }
            needsDisplay = true
            pulse()
        }
    }

    private let onSky: Bool
    private let ring = CALayer()

    /// `onSky` for the dot in the sky's chip, whose off colour has to read on
    /// night rather than on the pane.
    init(onSky: Bool = false) {
        self.onSky = onSky
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        let side = Tokens.Metric.controlStatusDot
        widthAnchor.constraint(equalToConstant: side).isActive = true
        heightAnchor.constraint(equalToConstant: side).isActive = true
        ring.frame = CGRect(x: 0, y: 0, width: side, height: side)
        ring.cornerRadius = side / 2
        ring.borderWidth = 1.5
        ring.opacity = 0
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = bounds.width / 2
        layer.masksToBounds = false
        let off = onSky ? Tokens.Moon.dotOff : Tokens.Text.disabled
        layer.backgroundColor = (state == .off ? off : Tokens.Accent.secure).cgColor
        ring.borderColor = Tokens.Accent.secure.cgColor
        if ring.superlayer == nil { layer.addSublayer(ring) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        pulse()
    }

    /// `livePulse` repeats for as long as the app is in use: a rate, not a
    /// transition, and never run under Reduce Motion.
    private func pulse() {
        ring.removeAllAnimations()
        guard state == .live, window != nil, !Tokens.Motion.reduceMotion else { return }
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.8
        grow.toValue = 2.4
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = Tokens.Motion.livePulse.duration
        group.timingFunction = Tokens.Motion.livePulse.timingFunction
        group.repeatCount = .infinity
        ring.add(group, forKey: "livePulse")
    }
}

/// An app's own icon, or — for one with nothing installed to take an icon
/// from — a small planet in its colour with its initials on it. A dashed ring
/// round it once it is connected, the orbit it now has.
@MainActor
final class ControlPlanetView: NSView {

    private let colour: NSColor
    private let initials: String
    private let icon: NSImage?
    private let isConnected: Bool
    private let isInstalled: Bool

    init(name: String, colour: NSColor, icon: NSImage? = nil, isConnected: Bool, isInstalled: Bool) {
        self.colour = colour
        self.initials = Self.initials(of: name)
        self.icon = icon
        self.isConnected = isConnected
        self.isInstalled = isInstalled
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let side = Tokens.Metric.controlPlanet
        widthAnchor.constraint(equalToConstant: side).isActive = true
        heightAnchor.constraint(equalToConstant: side).isActive = true
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var isFlipped: Bool { true }

    /// Two capitals where the name has them ("VS Code", "Claude Code"),
    /// otherwise its first two letters ("Codex" is "Co").
    static func initials(of name: String) -> String {
        let capitals = name.filter(\.isUppercase)
        if capitals.count >= 2 { return String(capitals.prefix(2)) }
        return String(name.prefix(2))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let disc = bounds.insetBy(dx: 3, dy: 3)
        if let icon {
            // An app icon carries its own clear margin, so it takes the whole
            // square where the planet keeps three points clear for the ring.
            icon.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: isInstalled ? 1 : 0.5,
                      respectFlipped: true, hints: nil)
            drawRing(context)
            return
        }
        let tone = isInstalled ? colour : colour.blended(withFraction: 1, of: .gray) ?? colour
        let deep = tone.blended(withFraction: 0.45, of: Tokens.Moon.skyBottom) ?? tone
        context.saveGState()
        context.setAlpha(isInstalled ? 1 : 0.5)
        context.addEllipse(in: disc)
        context.clip()
        let light = CGPoint(x: disc.minX + disc.width * 0.34, y: disc.minY + disc.height * 0.30)
        if let gradient = CGGradient(
            colorsSpace: nil, colors: [NSColor.white.cgColor, tone.cgColor, deep.cgColor] as CFArray, locations: [0, 0.48, 1]
        ) {
            context.drawRadialGradient(gradient, startCenter: light, startRadius: 0,
                                       endCenter: CGPoint(x: disc.midX, y: disc.midY), endRadius: disc.width * 0.62,
                                       options: [.drawsAfterEndLocation])
        }
        context.restoreGState()

        let text = NSAttributedString(string: initials, attributes: [
            .font: NSFont.systemFont(ofSize: Tokens.TypeScale.settingsCaption.pointSize - 1, weight: .semibold),
            .foregroundColor: Tokens.Moon.skyTop.withAlphaComponent(isInstalled ? 0.72 : 0.4)
        ])
        let size = text.size()
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
        drawRing(context)
    }

    private func drawRing(_ context: CGContext) {
        guard isConnected else { return }
        context.setStrokeColor(colour.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(Tokens.Metric.hairline)
        context.setLineDash(phase: 0, lengths: [2, 2.5])
        context.strokeEllipse(in: bounds.insetBy(dx: 0.5, dy: 0.5))
    }
}

/// One app under "Connect an app": its planet, its name, what state it is in,
/// and the button that changes that.
@MainActor
final class ControlAppRowView: NSView {

    let planet: ControlPlanetView

    init(name: String, colour: NSColor, icon: NSImage?, status: String, dot: ControlStatusDot.State,
         isInstalled: Bool, isConnected: Bool, accessory: NSView?) {
        planet = ControlPlanetView(
            name: name, colour: colour, icon: icon, isConnected: isConnected, isInstalled: isInstalled
        )
        super.init(frame: .zero)
        let title = NSTextField(labelWithString: name)
        title.font = Tokens.TypeScale.settingsRow
        title.textColor = isInstalled ? Tokens.Text.primary : Tokens.Text.tertiary
        let caption = NSTextField(labelWithString: status)
        caption.font = Tokens.TypeScale.settingsCaption
        caption.textColor = Tokens.Text.secondary
        caption.lineBreakMode = .byTruncatingTail
        caption.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let dotView = ControlStatusDot()
        dotView.state = dot

        let line = NSStackView(views: [dotView, caption])
        line.spacing = Tokens.Metric.chromeGap * 0.75
        let text = NSStackView(views: [title, line])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        for view in [planet, text] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let inset = SettingsMetrics.cardInset, gap = SettingsMetrics.controlInset
        var layout = [
            heightAnchor.constraint(greaterThanOrEqualToConstant: Tokens.Metric.controlAppRow),
            planet.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            planet.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.leadingAnchor.constraint(equalTo: planet.trailingAnchor, constant: gap),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: Tokens.Metric.chromeGap)
        ]
        if let accessory {
            accessory.translatesAutoresizingMaskIntoConstraints = false
            accessory.setContentHuggingPriority(.required, for: .horizontal)
            accessory.setContentCompressionResistancePriority(.required, for: .horizontal)
            addSubview(accessory)
            layout += [
                accessory.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
                accessory.centerYAnchor.constraint(equalTo: centerYAnchor),
                text.trailingAnchor.constraint(lessThanOrEqualTo: accessory.leadingAnchor, constant: -gap)
            ]
        } else {
            layout.append(text.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset))
        }
        NSLayoutConstraint.activate(layout)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("\(name), \(status)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }
}

/// A line of the activity log: its time, its place on the rail in the
/// colour of the app that made the call, and what happened.
@MainActor
final class ControlActivityRowView: NSView {

    enum Place { case only, first, middle, last }

    private let colour: NSColor
    private let place: Place

    init(time: String, title: String, subtitle: String, colour: NSColor, place: Place) {
        self.colour = colour
        self.place = place
        super.init(frame: .zero)
        let clock = NSTextField(labelWithString: time)
        clock.font = Tokens.TypeScale.rowTimestamp
        clock.textColor = Tokens.Text.tertiary
        clock.alignment = .right
        let head = NSTextField(labelWithString: title)
        head.font = Tokens.TypeScale.settingsRow
        head.lineBreakMode = .byTruncatingTail
        head.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let sub = NSTextField(labelWithString: subtitle)
        sub.font = Tokens.TypeScale.settingsCaption
        sub.textColor = Tokens.Text.secondary
        sub.lineBreakMode = .byTruncatingTail
        sub.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for view in [clock, head, sub] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let inset = SettingsMetrics.cardInset, gap = Tokens.Metric.chromeGap
        let textStart = inset + Tokens.Metric.controlTimeColumn + gap + Tokens.Metric.controlRailWidth + gap
        NSLayoutConstraint.activate([
            clock.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            clock.widthAnchor.constraint(equalToConstant: Tokens.Metric.controlTimeColumn),
            clock.firstBaselineAnchor.constraint(equalTo: head.firstBaselineAnchor),
            head.leadingAnchor.constraint(equalTo: leadingAnchor, constant: textStart),
            head.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset),
            head.topAnchor.constraint(equalTo: topAnchor, constant: gap),
            sub.leadingAnchor.constraint(equalTo: head.leadingAnchor),
            sub.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset),
            sub.topAnchor.constraint(equalTo: head.bottomAnchor, constant: 1),
            sub.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -gap)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("\(time), \(title), \(subtitle)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var isFlipped: Bool { true }

    /// The rail runs the row's full height, except that it starts at the
    /// first dot and stops at the last, so the line is only ever between
    /// two calls.
    override func draw(_ dirtyRect: NSRect) {
        let gap = Tokens.Metric.chromeGap, dot = Tokens.Metric.controlRailDot
        let railX = SettingsMetrics.cardInset + Tokens.Metric.controlTimeColumn + gap + Tokens.Metric.controlRailWidth / 2
        let dotY = gap + Tokens.TypeScale.settingsRow.pointSize / 2 + 1
        let top = place == .first || place == .only ? dotY : 0
        let bottom = place == .last || place == .only ? dotY : bounds.height
        if bottom > top {
            Tokens.Line.hairline.setFill()
            NSRect(x: railX - Tokens.Metric.hairline / 2, y: top, width: Tokens.Metric.hairline, height: bottom - top).fill()
        }
        let disc = NSRect(x: railX - dot / 2, y: dotY - dot / 2, width: dot, height: dot)
        Tokens.Surface.raised.setFill()
        NSBezierPath(ovalIn: disc.insetBy(dx: -2.5, dy: -2.5)).fill()
        colour.setFill()
        NSBezierPath(ovalIn: disc).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// A transparent layer over the whole pane that a connected app's light
/// flies across, from its planet in the list to its place in the sky. It
/// takes no clicks.
@MainActor
final class ControlFlightView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// A curve that rises above both ends, the way a download's flight to its
    /// button arcs, and shrinks the light to its size in orbit on the way.
    func fly(from start: CGPoint, to end: CGPoint, colour: NSColor, landed: @escaping @MainActor () -> Void) {
        guard let host = layer else { return landed() }
        let side = Tokens.Metric.controlSatellite * 3
        let light = CALayer()
        light.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        light.cornerRadius = side / 2
        light.backgroundColor = colour.cgColor
        light.shadowColor = colour.cgColor
        light.shadowOpacity = 1
        light.shadowRadius = Tokens.Metric.controlSatelliteGlow / 2
        light.shadowOffset = .zero
        light.position = end
        light.transform = CATransform3DMakeScale(0.55, 0.55, 1)

        let path = CGMutablePath()
        path.move(to: start)
        let lift = Tokens.Metric.controlSkyHeight / 3
        path.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2 - lift / 2, y: max(start.y, end.y) + lift))
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1
        shrink.toValue = 0.55
        let group = CAAnimationGroup()
        group.animations = [move, shrink]
        group.duration = Tokens.Motion.satelliteLaunch.duration
        group.timingFunction = Tokens.Motion.satelliteLaunch.timingFunction

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated {
                light.removeFromSuperlayer()
                landed()
            }
        }
        host.addSublayer(light)
        light.add(group, forKey: "satelliteLaunch")
        CATransaction.commit()
    }
}

/// The icon of the app a Luna Control client belongs to, from Luna's own
/// `ControlApps.xcassets` rather than from the app on disk: a row for an app
/// that is not installed yet still shows its face, and every row shows the
/// same rendition whatever version is installed. Claude Code has no app of
/// its own and takes Claude's.
@MainActor
enum ControlAppIcon {

    static let assets: [String: String] = [
        "claude-code": "ControlClaude",
        "claude-desktop": "ControlClaude",
        "codex": "ControlCodex",
        "cursor": "ControlCursor",
        "vscode": "ControlVSCode"
    ]

    /// Nil only for an app Luna ships no icon for.
    static func image(for appID: String) -> NSImage? {
        assets[appID].flatMap { NSImage(named: $0) }
    }
}
