//
//  TopBarActionCapsule.swift
//  Luna
//
//  §4 / §30.14: the bar's right-hand cluster — `[+ new tab] [downloads]
//  [profile]` — in its own rounded glass capsule, divided from the tab strip by
//  a hairline.
//
//  **Variable item count is the whole design.** Extension action buttons dock
//  here in v2 (§16.4), and retrofitting that means re-laying out the entire
//  right side of the bar, so the capsule takes an array today: assign `items`
//  and the capsule re-sizes itself. That is the one piece of future-proofing
//  M1 asks for, and it costs an array instead of three outlets.
//
//  The capsule shape is not drawn. Each item carries its own `.control` glass
//  and `Glass.merging` unions them: Liquid Glass merges neighbours within
//  `spacing`, so N round items become one capsule with correctly rounded ends
//  for any N — which is exactly why the items are circles and not squircles.
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

    private let row = NSView()
    private let merged: NSView
    private var buttons: [TopBarButton] = []

    override init(frame frameRect: NSRect) {
        merged = Glass.merging(row, spacing: TopBarMetrics.gap)
        super.init(frame: frameRect)
        addSubview(merged)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Actions"))
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

    // MARK: - Items

    private func rebuild() {
        for button in buttons { button.removeFromSuperview() }
        buttons = items.enumerated().map { index, item in
            let button = TopBarButton(metric: TopBarMetrics.capsuleItem, glass: true)
            button.icon = TopBarButton.symbol(item.symbolName)
            button.setAccessibilityLabel(item.label)
            button.toolTip = item.label
            button.tag = index
            button.target = self
            button.action = #selector(itemPressed)
            row.addSubview(button)
            return button
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    @objc private func itemPressed(_ sender: NSButton) {
        guard items.indices.contains(sender.tag) else { return }
        items[sender.tag].action()
    }

    // MARK: - Geometry

    override var intrinsicContentSize: NSSize {
        let item = TopBarMetrics.capsuleItem
        let inset = TopBarMetrics.capsuleInset
        guard !buttons.isEmpty else { return NSSize(width: 0, height: item.height + inset * 2) }
        let count = CGFloat(buttons.count)
        return NSSize(
            width: count * item.width + (count - 1) * TopBarMetrics.gap + inset * 2,
            height: item.height + inset * 2
        )
    }

    override func layout() {
        super.layout()
        // The container is documented to host `contentView`; `row` is sized
        // here as well so the item frames below are valid either way.
        merged.frame = bounds
        row.frame = bounds

        let item = TopBarMetrics.capsuleItem
        let originY = ((bounds.height - item.height) / 2).rounded()
        var originX = TopBarMetrics.capsuleInset
        for button in buttons {
            button.frame = NSRect(x: originX, y: originY, width: item.width, height: item.height)
            originX += item.width + TopBarMetrics.gap
        }
    }
}
