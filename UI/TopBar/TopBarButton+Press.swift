//
//  TopBarButton+Press.swift
//  Luna
//
//  The two halves of `TopBarButton` that do not need its stored state: the SF
//  Symbol it is handed, and the press loop a draggable chip runs instead of
//  `NSControl`'s. Split out when the class crossed SwiftLint's type body limit.
//

import AppKit

extension TopBarButton {

    /// An SF Symbol sized to the bar's glyph size, and weighted so it draws the
    /// same line as the rest of them — see `TypeScale.glyphWeight(for:)`, for
    /// why one nominal weight is not one apparent weight. Nil only for a name
    /// the installed SF Symbols set does not have.
    static func symbol(_ name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: TopBarMetrics.glyph,
            weight: Tokens.TypeScale.glyphWeight(for: name)
        )
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    /// Waits for the press to declare itself: a drag past §6.6's threshold
    /// hands the original event on and takes no further part, and a mouse-up
    /// before that is a click.
    func trackPress(from press: NSEvent) {
        guard let window else { return }
        let start = convert(press.locationInWindow, from: nil)
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let point = convert(next.locationInWindow, from: nil)
            guard next.type == .leftMouseDragged else {
                if bounds.contains(point) { sendAction(action, to: target) }
                return
            }
            guard abs(point.x - start.x) >= Tokens.Metric.dragThreshold
                || abs(point.y - start.y) >= Tokens.Metric.dragThreshold
            else { continue }
            setPressed(false)
            onDragOut?(press)
            return
        }
    }
}
