//
//  TopBarActionCapsule.swift
//  Luna
//
//  §4 / §30.14: the bar's right-hand cluster — `[+ new tab] [downloads]
//  [profile]` — in its own rounded glass capsule, divided from the tab strip by
//  a hairline.
//
//  Variable item count is the design. Extension action buttons dock here in v2
//  (§16.4), and retrofitting that means re-laying out the whole right side of
//  the bar, so the capsule takes an array: assign `items` and it re-sizes
//  itself.
//
//  One glass surface, not N merged ones. Every item used to carry its own
//  `.control` backing, handed to `Glass.merging` on the theory that Liquid
//  Glass unions neighbours within `spacing`. On screen it did not union them:
//  three separate bright circles, each with its own specular rim, and white
//  glyphs washed out against them. The glass is applied once, to the capsule,
//  at full radius.
//

import AppKit

/// One button in the capsule. `@MainActor` because `action` closes over view
/// state and is only ever called from the capsule.
@MainActor
struct TopBarActionItem {
    /// Stable identity, so a caller can find a button again — agent H's
    /// download popover anchors to `downloads` (§5).
    var id: String
    var symbolName: String
    /// VoiceOver label and tooltip. These buttons are icon-only (§8, §21.1).
    var label: String
    var action: () -> Void

    init(id: String, symbolName: String, label: String, action: @escaping () -> Void) {
        self.id = id
        self.symbolName = symbolName
        self.label = label
        self.action = action
    }
}

@MainActor
final class TopBarActionCapsule: NSView {

    var items: [TopBarActionItem] = [] {
        didSet { rebuild() }
    }

    private var buttons: [TopBarButton] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        Glass.apply(.control, to: self, cornerRadius: Self.height / 2)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Actions"))
    }

    /// The cylinder's height: one item plus its padding, top and bottom.
    private static var height: CGFloat {
        TopBarMetrics.capsuleItem.height + TopBarMetrics.capsuleInset * 2
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code")
    }

    /// The button for an item id, or nil if there is no such item. The seam a
    /// popover anchors to.
    func view(for id: String) -> NSView? {
        guard let index = items.firstIndex(where: { $0.id == id }),
              buttons.indices.contains(index)
        else { return nil }
        return buttons[index]
    }

    /// Dims one item without rebuilding the capsule.
    ///
    /// The enabled flag is not part of `TopBarActionItem` on purpose: Back
    /// changes it on every navigation, and an item list that carried it would
    /// have to be reassigned — and therefore rebuilt — several times a minute.
    func setEnabled(_ enabled: Bool, for id: String) {
        (view(for: id) as? NSButton)?.isEnabled = enabled
    }

    // MARK: - Items

    private func rebuild() {
        for button in buttons { button.removeFromSuperview() }
        buttons = items.enumerated().map { index, item in
            // `glass: false`: the cylinder around them is the glass. A second
            // material per item is what made the three read as three.
            let button = TopBarButton(metric: TopBarMetrics.capsuleItem, glass: .none)
            // The cylinder is the material, so the cylinder is what swells —
            // see `TopBarButton.ownsItsMaterial`.
            button.ownsItsMaterial = false
            button.onPressChange = { [weak self] pressed in self?.setPressed(pressed) }
            button.icon = TopBarButton.symbol(item.symbolName)
            button.setAccessibilityLabel(item.label)
            button.toolTip = item.label
            button.tag = index
            button.target = self
            button.action = #selector(itemPressed)
            addSubview(button)
            return button
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    /// §6 `controlPress`, on behalf of whichever item is down.
    private func setPressed(_ pressed: Bool) {
        Tokens.Motion.swell(self, to: pressed ? Tokens.Motion.pressSwell : 1)
    }

    @objc private func itemPressed(_ sender: NSButton) {
        guard items.indices.contains(sender.tag) else { return }
        items[sender.tag].action()
    }

    // MARK: - Geometry

    override var intrinsicContentSize: NSSize {
        let item = TopBarMetrics.capsuleItem
        let inset = TopBarMetrics.capsuleInset
        guard !buttons.isEmpty else { return NSSize(width: 0, height: Self.height) }
        let count = CGFloat(buttons.count)
        return NSSize(
            width: count * item.width + (count - 1) * TopBarMetrics.gap + inset * 2,
            height: Self.height
        )
    }

    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately { placeContents() }
    }

    private func placeContents() {
        let item = TopBarMetrics.capsuleItem
        let originY = ((bounds.height - item.height) / 2).rounded()
        var originX = TopBarMetrics.capsuleInset
        for button in buttons {
            button.frame = NSRect(x: originX, y: originY, width: item.width, height: item.height)
            originX += item.width + TopBarMetrics.gap
        }
    }
}
