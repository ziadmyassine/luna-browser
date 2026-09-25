import Foundation

/// The capture tools' rules that need no web view: the sizes `viewport`
/// takes, what a recording draws a frame after, and points from a scaled
/// screenshot put back into the CSS pixels input lands in.
extension ControlCommand {

    /// A small phone to a 4K screen.
    public static let viewportRange = 320 ... 3840

    /// Whether a recording takes a frame after this call: whatever can change
    /// what the page shows. Reads, pictures and the recording itself do not.
    public var recordsFrame: Bool {
        switch self {
        case .scroll, .hover, .viewport: true
        default: acts
        }
    }

    /// The call with every point divided by `scale`: after a screenshot at
    /// half size the model reads coordinates off the half-size picture.
    public func fromScreenshot(scale: Double) -> ControlCommand {
        func map(_ target: Target) -> Target {
            guard case let .point(x, y) = target else { return target }
            return .point(x: x / scale, y: y / scale)
        }
        switch self {
        case let .click(target, count, button, modifiers, trusted):
            return .click(map(target), clickCount: count, button: button, modifiers: modifiers, trusted: trusted)
        case let .hover(target): return .hover(map(target))
        case let .drag(from, to, trusted): return .drag(from: map(from), to: map(to), trusted: trusted)
        case let .scroll(direction, amount, target): return .scroll(direction, amount: amount, target: target.map(map))
        default: return self
        }
    }
}
