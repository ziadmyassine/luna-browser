//
//  PageBarExtensions.swift
//  Luna
//
//  §16.4 on §3.2b's page bar: a glass cylinder in the bar's trailing corner,
//  on the pill's line but not on the pill, holding the extensions button and,
//  to its left, the pinned extensions; and at its end, beside the agent panel
//  it opens on that side, the agent's button.
//
//  The pill keeps half its width however many are pinned
//  (`pinnedExtensionsAddressShare`); pins past that are in the pop-out.
//
//  An extension of `PageChromeBar` in a file of its own, as `PageBarLights`
//  is, for the bar's length limit.
//

import AppKit

extension PageChromeBar {

    /// The view the pop-out opens on.
    var extensionsAnchor: NSView? { showsExtensions ? shelf.extensionsButton : nil }

    /// Whether the cylinder is on the bar at all: for extensions, the agent, or both.
    var showsShelf: Bool { showsExtensions || shelf.showsAgent }

    /// Places the cylinder against the bar's trailing inset and returns where
    /// the pill's room ends. Without extensions that is the inset itself.
    func placeShelf(centreY: CGFloat, after left: CGFloat) -> CGFloat {
        let end = bounds.maxX - Tokens.Metric.pageBarInset
        guard showsShelf else { return end }
        shelf.showsExtensions = showsExtensions
        let fixed = PageBarExtensionShelf.width(pins: 0, extensions: showsExtensions, agent: shelf.showsAgent)
        let spare = end - left - Tokens.Metric.pageBarPillWidth * Tokens.Metric.pinnedExtensionsAddressShare
            - Tokens.Metric.chromeGapWide - fixed
        let pins = showsExtensions ? extensionPins : []
        let count = ExtensionShelfFit.count(pins.count, room: spare, pitch: PageBarExtensionShelf.pitch)
        shelf.show(pins: Array(pins.prefix(count)))
        let width = fixed + CGFloat(count) * PageBarExtensionShelf.pitch
        let height = PageBarExtensionShelf.button.height
        shelf.frame = NSRect(x: end - width, y: centreY - height / 2, width: width, height: height).pixelAligned
        // Moved, maybe from under the pointer, by the agent panel coming or going.
        for case let button as GlassButton in shelf.subviews { button.settleHover() }
        return shelf.frame.minX - Tokens.Metric.chromeGapWide
    }
}

/// The cylinder itself, built the way `NavCluster` is at the bar's other end:
/// one piece of glass, and `GlassButton`s with none of their own that fill it
/// edge to edge. So the extensions button alone is the sidebar toggle's circle
/// to the point — the same wash across the whole circle under the pointer,
/// the same ink lifting from secondary to primary, the same swell under a
/// press — and with pins the cylinder is one control the pointer moves along.
@MainActor
final class PageBarExtensionShelf: NSView {

    /// One button's circle: the toggle's and the history cluster's.
    static let button = Tokens.Metric.sidebarCircle
    /// Buttons touch, as `NavCluster`'s halves do; a gap in one piece of glass
    /// is a dead strip between two controls.
    static var pitch: CGFloat { button.width }

    static func width(pins: Int, extensions: Bool = true, agent: Bool = false) -> CGFloat {
        CGFloat(pins + (extensions ? 1 : 0) + (agent ? 1 : 0)) * pitch
    }

    var onPin: ((String, NSView) -> Void)?
    var onExtensions: ((NSView) -> Void)?
    /// The agent's button, at the cylinder's end. Nil leaves it off.
    var onAgent: (() -> Void)? {
        didSet {
            agentButton.isHidden = onAgent == nil
            needsLayout = true
        }
    }
    var showsAgent: Bool { onAgent != nil }
    var showsExtensions = true {
        didSet {
            extensionsButton.isHidden = !showsExtensions
            if showsExtensions != oldValue { needsLayout = true }
        }
    }

    let extensionsButton = PageBarExtensionShelf.makeButton(
        symbol: ExtensionsSymbol.name,
        label: ExtensionsSymbol.label
    )
    let agentButton = PageBarExtensionShelf.makeButton(symbol: ExtensionsSymbol.name, label: String(localized: "Agent"))
    private(set) var pinButtons: [(id: String, button: GlassButton)] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = Self.button.cornerCurve
        Glass.apply(.control, to: self, cornerRadius: Self.button.cornerRadius, cornerCurve: Self.button.cornerCurve)
        extensionsButton.onActivate = { [weak self] in
            guard let self else { return }
            onExtensions?(extensionsButton)
        }
        extensionsButton.onPressChange = { [weak self] pressed in self?.setPressed(pressed) }
        addSubview(extensionsButton)
        agentButton.setImage(AgentGlyph.image(pointSize: Tokens.Metric.glyphSize))
        agentButton.toolTip = String(localized: "Agent")
        agentButton.isHidden = true
        agentButton.onActivate = { [weak self] in self?.onAgent?() }
        agentButton.onPressChange = { [weak self] pressed in self?.setPressed(pressed) }
        addSubview(agentButton)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(ExtensionsSymbol.label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private static func makeButton(symbol: String, label: String) -> GlassButton {
        GlassButton(shape: button, symbolName: symbol, pointSize: Tokens.Metric.glyphSize, label: label, glassMode: .none)
    }

    /// The pins in order. The same ids keep their buttons, re-dressed: a badge
    /// changes on every page load, and a rebuilt button under the pointer loses
    /// its hover and its press.
    func show(pins: [ExtensionShelfItem]) {
        if pins.map(\.id) != pinButtons.map(\.id) {
            for pin in pinButtons { pin.button.removeFromSuperview() }
            pinButtons = pins.map { pin in
                let button = Self.makeButton(symbol: ExtensionsSymbol.name, label: pin.name)
                button.onPressChange = { [weak self] pressed in self?.setPressed(pressed) }
                button.onActivate = { [weak self, weak button] in
                    guard let self, let button else { return }
                    onPin?(pin.id, button)
                }
                addSubview(button)
                return (id: pin.id, button: button)
            }
            needsLayout = true
        }
        for (pin, entry) in zip(pins, pinButtons) {
            entry.button.setImage(ExtensionBadge.composite(pin.icon ?? ExtensionsSymbol.image, badge: pin.badge))
            entry.button.setAccessibilityLabel(pin.badge.isEmpty ? pin.name : "\(pin.name), \(pin.badge)")
            entry.button.toolTip = pin.name
            entry.button.menuBuilder = { ExtensionMenu.make(for: pin) }
        }
    }

    func pinButton(_ id: String) -> NSView? { pinButtons.first { $0.id == id }?.button }

    /// §6 `controlPress`, on behalf of whichever button is down: the glass is
    /// the material, so the glass is what swells.
    private func setPressed(_ pressed: Bool) {
        Tokens.Motion.swell(self, to: pressed ? Tokens.Motion.pressSwell : 1)
    }

    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately {
            let side = Self.pitch
            for (index, entry) in pinButtons.enumerated() {
                entry.button.frame = NSRect(x: CGFloat(index) * side, y: 0, width: side, height: bounds.height).pixelAligned
            }
            var x = CGFloat(pinButtons.count) * side
            for button in [extensionsButton, agentButton] where !button.isHidden {
                button.frame = NSRect(x: x, y: 0, width: side, height: bounds.height).pixelAligned
                x += side
            }
        }
    }

    /// A press between two buttons is the cylinder's, not the page's.
    override var mouseDownCanMoveWindow: Bool { false }
}
