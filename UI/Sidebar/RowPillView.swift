//
//  RowPillView.swift
//  Luna
//
//  §3.4's two row fills. Split out of `TabListController.swift` to keep that
//  file inside SwiftLint's length limit; nothing changed on the way across.
//

import AppKit

/// §3.4's two row fills: the selected pill and the hover lift.
///
/// **Clear glass alone was not visible.** The pill was `Glass.control` plus a
/// hairline and nothing else, and `.clear` glass over the sidebar's own glass
/// is very nearly the sidebar — a selected row read as unselected. `Tokens`
/// has carried `Surface.selected` and `Surface.hover` for exactly this since
/// M1; they were simply never asked for. Both are translucent washes, so the
/// glass under them is still glass.
@MainActor
final class RowPillView: NSView {

    enum Role { case selected, hover }

    /// Kept for the callers that track the table's focus. **It no longer
    /// changes what is drawn**: a selected row used to take an accent-coloured
    /// border while the list had focus, and a blue ring around the current tab
    /// is a system list, not this one. The selection reads as glass — the
    /// material plus §3.4's wash — in every focus state.
    var isFocused = false

    private let role: Role

    init(role: Role) {
        self.role = role
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        Glass.apply(.control, to: self, cornerRadius: Tokens.Metric.rowCornerRadius)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = Tokens.Metric.rowCornerRadius
        layer.backgroundColor = (role == .selected ? Tokens.Surface.selected : Tokens.Surface.hover).cgColor
        // §3.4 gives the selected row a visible border and the hover lift none:
        // a border that appeared under the pointer would read as a second
        // selection. The border is the glass's own edge — `Line.border`, never
        // the accent: **no blue anywhere on a selected tab.**
        let bordered = role == .selected
        layer.borderWidth = bordered ? Tokens.Metric.hairline : 0
        layer.borderColor = bordered ? Tokens.Line.border.cgColor : nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Moving one pill between rows

/// **One pill travels; it is never re-created per row.** Both lists that wear
/// §3.4's fills — the sidebar's tabs and §2's section list — keep exactly two
/// of these and move them, which is what makes the selection *slide* from one
/// row to the next instead of blinking out of one and into another. It lives
/// here rather than in either list so the two cannot drift apart: a settings
/// row and a tab row answer the pointer on the same spring.
extension RowPillView {

    /// Move to `target`, springing on `spec` — or land there with no animation
    /// when the pill was parked, which is a pill arriving rather than moving.
    func move(to target: NSRect, spec: MotionSpec?) {
        let wasParked = alphaValue == 0 || frame == .zero
        if !wasParked, let spring = spec?.springAnimation(keyPath: "position") {
            let from = layer?.position ?? .zero
            frame = target
            spring.fromValue = NSValue(point: from)
            spring.toValue = NSValue(point: layer?.position ?? .zero)
            layer?.add(spring, forKey: "position")
        } else {
            // Layer-backed frames animate themselves; `SidebarRowView.layout`
            // takes the same precaution for the same reason.
            Tokens.Motion.immediately {
                layer?.removeAnimation(forKey: "position")
                frame = target
            }
        }
        fade(to: 1)
    }

    /// Park the pill, or bring it back. A row with nothing selected and nothing
    /// hovered has no fill at all (§30.7).
    func fade(to alpha: CGFloat) {
        guard alphaValue != alpha else { return }
        Tokens.Motion.animate(Tokens.Motion.rowHover) { context in
            context.allowsImplicitAnimation = true
            animator().alphaValue = alpha
        }
    }
}
