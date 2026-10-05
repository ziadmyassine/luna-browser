//
//  ControlAgentPointer.swift
//  Luna
//
//  The pointer Luna Control draws for an agent on the page it is working on.
//  Its own file because `ControlSurface.swift` had reached SwiftLint's length
//  limit; the surface places it and nothing else does.
//

import AppKit

/// The agent's pointer: Astro itself, in its own colours, with a ring in its
/// app's colour spreading from it on a click, and a pill beside it saying the
/// agent is working, where
/// it last clicked, hovered, typed or dragged. A picture only: it takes no
/// events, and the page never sees it.
@MainActor
final class ControlAgentPointer: NSView {

    /// The puck's diameter: big enough for the face to read on a busy page,
    /// small enough to sit on a button without hiding its label.
    private static let puckSize: CGFloat = 26
    /// Where in the view the puck's centre is, which is what stands on the
    /// point: the puck, clear of its ring and shadow.
    static let tip = NSPoint(x: puckSize / 2 + 3, y: puckSize / 2 + 3)
    /// The pill stands beside the puck, centred on it.
    private static let pillGap: CGFloat = 6

    private let puck = CALayer()
    private let face = CALayer()
    private let ripple = CAShapeLayer()
    private let badge = NSView()
    private let nameTag = NSTextField(labelWithString: "")

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 48))
        wantsLayer = true
        layer?.masksToBounds = false
        buildPuck()
        badge.wantsLayer = true
        badge.layer?.cornerCurve = .continuous
        badge.layer.map { Tokens.Shadow.popover.apply(to: $0, in: effectiveAppearance) }
        nameTag.font = .systemFont(ofSize: Tokens.TypeScale.settingsRow.pointSize, weight: .medium)
        badge.addSubview(nameTag)
        addSubview(badge)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// Not its name tag either: the pointer stands on the page at alpha 0
    /// between actions, and an ignored view's children are still read — as an
    /// empty line of text at the page's corner. The working capsule says who
    /// is acting.
    override func accessibilityChildren() -> [Any]? { [] }

    private func buildPuck() {
        let side = Self.puckSize
        puck.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        puck.position = CGPoint(x: Self.tip.x, y: Self.tip.y)
        puck.cornerRadius = side / 2
        puck.shadowColor = NSColor.black.cgColor
        puck.shadowOpacity = 0.35
        puck.shadowRadius = 3
        puck.shadowOffset = CGSize(width: 0, height: 1)
        face.frame = puck.bounds
        face.contents = AgentGlyph.image(pointSize: side)
        face.contentsGravity = .resizeAspect
        puck.addSublayer(face)
        ripple.fillColor = nil
        ripple.lineWidth = 2
        ripple.opacity = 0
        let radius: CGFloat = 14
        ripple.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
        ripple.position = CGPoint(x: Self.tip.x, y: Self.tip.y)
        layer?.addSublayer(ripple)
        layer?.addSublayer(puck)
    }

    /// - Parameter agent: the app's name, which the pill puts in a sentence.
    func configure(agent: String, tint: NSColor) {
        ripple.strokeColor = tint.cgColor
        let ink: NSColor = tint.luminance > 0.6 ? .black : .white
        nameTag.textColor = ink
        nameTag.stringValue = String(localized: "\(agent) is working…")
        nameTag.sizeToFit()
        // A pill, as the capsule and the activity pill are: the same agent's
        // colour in the same shape wherever it shows.
        let height = nameTag.frame.height + 12
        let width = nameTag.frame.width + height
        badge.frame = NSRect(
            x: Self.tip.x + Self.puckSize / 2 + Self.pillGap, y: Self.tip.y - height / 2, width: width, height: height
        )
        badge.layer?.cornerRadius = height / 2
        badge.layer?.backgroundColor = tint.cgColor
        // A hairline of white rather than the outline the arrow wears: enough
        // to hold the pill's edge on a page of its own colour.
        badge.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        badge.layer?.borderWidth = Tokens.Metric.hairline
        nameTag.setFrameOrigin(NSPoint(x: height / 2, y: 6))
        setFrameSize(NSSize(width: badge.frame.maxX, height: max(badge.frame.maxY, Self.tip.y * 2)))
    }

    /// A ring spreading from the puck and fading, where the agent clicked, and
    /// the puck pressed in and springing back, so the click is seen landing
    /// and not only the pointer arriving.
    func pulse() {
        guard !Tokens.Motion.reduceMotion else { return }
        let press = CAKeyframeAnimation(keyPath: "transform.scale")
        press.values = [1, 0.78, 1.12, 1]
        press.keyTimes = [0, 0.3, 0.7, 1]
        press.duration = Tokens.Motion.agentSheet.duration
        puck.add(press, forKey: "press")
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.3
        grow.toValue = 1.3
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = Tokens.Motion.agentSheet.duration
        group.timingFunction = Tokens.Motion.agentSheet.timingFunction
        ripple.add(group, forKey: "pulse")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private extension NSColor {
    /// Relative luminance, 0...1. Brightness was the test once and put black
    /// on Claude's orange, which is bright but not light; only a tint as light
    /// as white or the label colour on a dark sidebar wants dark ink.
    var luminance: CGFloat {
        guard let rgb = usingColorSpace(.sRGB) else { return 0 }
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
    }
}
