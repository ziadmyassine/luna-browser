//
//  ControlSkyView.swift
//  Luna
//
//  The top of Luna Control's settings pane (docs/LUNA-CONTROL.md, "The
//  Settings pane"): a night sky with the moon in it, dark while apps cannot
//  reach Luna and full while they can. Every connected app is a light on one
//  of two orbits; the one in use trails a ring, and each call it makes runs a
//  beam to the moon. The switch that turns Luna Control on sits in the sky.
//
//  State and timing are here; the painting is in `+Drawing`.
//

import AppKit

@MainActor
final class ControlSkyView: NSView {

    /// An app in the sky.
    struct Satellite: Equatable {
        let id: String
        let name: String
        let colour: NSColor
        /// 0 is the inner orbit, 1 the outer.
        let orbit: Int
        let startAngle: CGFloat
        let isLive: Bool
    }

    struct Body {
        var satellite: Satellite
        var angle: CGFloat
        var alpha: CGFloat = 0
        /// Kept dark while its light is still flying up from the list.
        var isHeld = false
        var appearsAt: CFTimeInterval = 0
        var isLeaving = false
    }

    struct Beam {
        let id: String
        let start: CFTimeInterval
    }

    struct Star {
        let x: CGFloat
        let y: CGFloat
        let radius: CGFloat
        let alpha: CGFloat
        let speed: CGFloat
        let offset: CGFloat
        let depth: CGFloat
    }

    /// The user moved the switch.
    var onToggle: ((Bool) -> Void)?

    // Read by the drawing half.
    var phase: CGFloat = 0
    var orbitAlpha: CGFloat = 0
    var bodies: [String: Body] = [:]
    var beams: [Beam] = []
    var stars: [Star] = []
    var parallax = CGPoint.zero
    /// What the twinkles and pulses are timed against. Stands still under
    /// Reduce Motion, which is what stops them.
    var clock: CFTimeInterval = 0
    var caughtAt: CFTimeInterval = -.infinity

    private(set) var isOn = false
    private struct Tween {
        let from: CGFloat
        let to: CGFloat
        let start: CFTimeInterval
        let spec: MotionSpec
    }

    private var tween: Tween?
    private var parallaxTarget = CGPoint.zero
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0

    private let toggle = SystemSwitch(isOn: false)
    private let chip = ControlSkyChip()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")

    init(title: String, subtitle: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Tokens.Metric.rowCornerRadius
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        // Always night, so the switch and the chip take the dark appearance
        // whatever the window has: a light switch on this sky all but vanished.
        appearance = NSAppearance(named: .darkAqua)

        titleLabel.stringValue = title
        titleLabel.font = Tokens.TypeScale.pageTitle
        titleLabel.textColor = Tokens.Moon.ink
        subtitleLabel.stringValue = subtitle
        subtitleLabel.font = Tokens.TypeScale.settingsRow
        subtitleLabel.textColor = Tokens.Moon.inkSecondary
        toggle.setAccessibilityLabel(title)
        toggle.setAccessibilityHelp(subtitle)
        toggle.onChange = { [weak self] on in self?.onToggle?(on) }
        layOut()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(accessibilityChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var isFlipped: Bool { true }

    private func layOut() {
        for view in [chip, titleLabel, subtitleLabel, toggle] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let inset = Tokens.Metric.controlSkyInset
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Tokens.Metric.controlSkyHeight),
            chip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            chip.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            chip.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -inset),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -inset),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Tokens.Metric.chromeGap / 2),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            toggle.bottomAnchor.constraint(equalTo: subtitleLabel.bottomAnchor)
        ])
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { makeStars() }
    }

    private func makeStars() {
        var random = SeededRandom(seed: 5)
        let count = Int(bounds.width * bounds.height / Tokens.Metric.controlStarSpacing)
        stars = (0..<max(count, 0)).map { _ in
            Star(
                x: random.next(), y: random.next(),
                radius: 0.35 + random.next() * random.next() * 1.1,
                alpha: 0.25 + random.next() * 0.7,
                speed: 0.6 + random.next() * 2.2,
                offset: random.next() * .pi * 2,
                depth: 0.25 + random.next() * 0.75
            )
        }
    }

    // MARK: - Frames

    static func speed(orbit: Int) -> CGFloat {
        let lap = orbit == 0 ? Tokens.Motion.innerOrbitLap : Tokens.Motion.outerOrbitLap
        return .pi * 2 / CGFloat(lap)
    }

    private func wax(to target: CGFloat, spec: MotionSpec, animated: Bool) {
        guard animated, !Tokens.Motion.reduceMotion else {
            tween = nil
            phase = target
            return
        }
        tween = Tween(from: phase, to: target, start: CACurrentMediaTime(), spec: spec)
    }

    private func stagger(after delay: TimeInterval) {
        let now = CACurrentMediaTime()
        for (index, id) in bodies.keys.sorted().enumerated() {
            bodies[id]?.appearsAt = now + delay + Double(index) * Tokens.Motion.satelliteStagger
        }
    }

    private func kick() {
        link?.isPaused = false
        needsDisplay = true
    }

    @objc private func accessibilityChanged() { kick() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            link?.invalidate()
            link = nil
            return
        }
        guard link == nil else { return }
        let made = displayLink(target: self, selector: #selector(tick(_:)))
        made.add(to: .main, forMode: .common)
        link = made
        lastTick = CACurrentMediaTime()
    }

    @objc private func tick(_ sender: CADisplayLink) {
        let now = CACurrentMediaTime()
        let step = CGFloat(min(now - lastTick, 0.05))
        lastTick = now
        if Tokens.Motion.reduceMotion {
            settle()
            sender.isPaused = true
        } else {
            advance(now: now, step: step)
        }
        guard !isHiddenOrHasHiddenAncestor, window?.occlusionState.contains(.visible) == true else { return }
        needsDisplay = true
    }

    private func advance(now: CFTimeInterval, step: CGFloat) {
        clock = now
        if let tween {
            let progress = tween.spec.progress(at: now - tween.start)
            phase = tween.from + (tween.to - tween.from) * progress
            if progress >= 1 { self.tween = nil }
        }
        let fade = step / CGFloat(Tokens.Motion.satelliteFade.duration)
        orbitAlpha = approach(orbitAlpha, isOn ? 1 : 0, by: fade)
        for (id, body) in bodies {
            var next = body
            let shown = isOn && !body.isHeld && !body.isLeaving && now >= body.appearsAt
            next.alpha = approach(body.alpha, shown ? 1 : 0, by: fade)
            next.angle += Self.speed(orbit: body.satellite.orbit) * step
            if body.isLeaving, next.alpha <= 0 { bodies[id] = nil } else { bodies[id] = next }
        }
        beams.removeAll { beam in
            let done = now - beam.start >= Tokens.Motion.moonBeam.duration
            if done { caughtAt = now }
            return done
        }
        // Eased toward the pointer rather than stuck to it, so the sky drifts.
        let ease = min(1, step / CGFloat(Tokens.Motion.satelliteFade.duration) * 1.5)
        parallax.x += (parallaxTarget.x - parallax.x) * ease
        parallax.y += (parallaxTarget.y - parallax.y) * ease
    }

    /// Reduce Motion: every tween at its end, nothing drifting.
    private func settle() {
        tween = nil
        phase = isOn ? 1 : 0
        orbitAlpha = isOn ? 1 : 0
        for (id, body) in bodies {
            if body.isLeaving { bodies[id] = nil } else { bodies[id]?.alpha = isOn && !body.isHeld ? 1 : 0 }
        }
        beams.removeAll()
        parallax = .zero
        parallaxTarget = .zero
        needsDisplay = true
    }

    private func approach(_ value: CGFloat, _ target: CGFloat, by amount: CGFloat) -> CGFloat {
        value < target ? min(value + amount, target) : max(value - amount, target)
    }

}

// MARK: - What the section tells it

extension ControlSkyView {

    func setOn(_ on: Bool, animated: Bool) {
        toggle.isOn = on
        guard on != isOn else { return }
        isOn = on
        wax(to: on ? 1 : 0, spec: on ? Tokens.Motion.moonrise : Tokens.Motion.moonset, animated: animated)
        if on { stagger(after: animated ? Tokens.Motion.moonrise.duration / 2 : 0) }
        kick()
    }

    /// The moon rises again from dark: the pane's entrance, each time
    /// Settings shows it.
    func rise() {
        guard isOn, !Tokens.Motion.reduceMotion else { return }
        phase = 0
        orbitAlpha = 0
        for id in bodies.keys { bodies[id]?.alpha = 0 }
        wax(to: 1, spec: Tokens.Motion.moonrise, animated: true)
        stagger(after: Tokens.Motion.moonrise.duration / 2)
        kick()
    }

    /// The connected apps. A new one fades in, a missing one fades out, and
    /// one already there keeps its place on its orbit.
    func setSatellites(_ satellites: [Satellite]) {
        let ids = Set(satellites.map(\.id))
        for satellite in satellites {
            if var body = bodies[satellite.id] {
                body.satellite = satellite
                body.isLeaving = false
                bodies[satellite.id] = body
            } else {
                bodies[satellite.id] = Body(satellite: satellite, angle: satellite.startAngle)
            }
        }
        for id in bodies.keys where !ids.contains(id) { bodies[id]?.isLeaving = true }
        kick()
    }

    func setStatus(_ text: String, dot: ControlStatusDot.State) {
        chip.set(text, dot: dot)
    }

    /// The app with this light did something.
    func beam(from id: String) {
        guard !Tokens.Motion.reduceMotion, let body = bodies[id], body.alpha > 0.5 else { return }
        beams.append(Beam(id: id, start: CACurrentMediaTime()))
        kick()
    }

    /// Keeps an app's light dark while its flight from the list is under way,
    /// then lights it where the flight lands.
    func hold(_ id: String) { bodies[id]?.isHeld = true }

    func release(_ id: String) {
        bodies[id]?.isHeld = false
        bodies[id]?.alpha = 1
        caughtAt = CACurrentMediaTime()
        kick()
    }

    /// Where an app's light will be `delay` seconds from now, in this view's
    /// coordinates, so a flight can aim at where it is going to be.
    func predictedPoint(of id: String, after delay: TimeInterval) -> CGPoint? {
        guard let body = bodies[id] else { return nil }
        let angle = body.angle + Self.speed(orbit: body.satellite.orbit) * CGFloat(delay)
        return point(orbit: body.satellite.orbit, angle: angle).point
    }
}

// MARK: - The pointer

extension ControlSkyView {

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let point = convert(event.locationInWindow, from: nil)
        parallaxTarget = CGPoint(x: (point.x / bounds.width - 0.5) * 2, y: (point.y / bounds.height - 0.5) * 2)
    }

    override func mouseExited(with event: NSEvent) { parallaxTarget = .zero }
}

/// The label in the sky's top corner: whether apps can reach Luna, and which
/// are connected and in use.
@MainActor
final class ControlSkyChip: NSView {

    private let dot = ControlStatusDot(onSky: true)
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Tokens.Metric.controlChipHeight / 2
        label.font = Tokens.TypeScale.settingsCaption
        label.textColor = Tokens.Moon.ink.withAlphaComponent(0.86)
        label.lineBreakMode = .byTruncatingTail
        for view in [dot, label] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let pad = Tokens.Metric.chromeGap
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Tokens.Metric.controlChipHeight),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad + 1),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: pad - 1),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(pad + 2)),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    func set(_ text: String, dot state: ControlStatusDot.State) {
        label.stringValue = text
        dot.state = state
        setAccessibilityLabel(text)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Tokens.Moon.chipFill.cgColor
        layer?.borderWidth = Tokens.Metric.hairline / 2
        layer?.borderColor = Tokens.Moon.chipRing.cgColor
    }
}
