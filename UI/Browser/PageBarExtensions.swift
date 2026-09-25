//
//  PageBarExtensions.swift
//  Luna
//
//  §16.4 on §3.2b's page bar: a glass cylinder in the bar's trailing corner,
//  on the pill's line but not on the pill, holding the extensions button and,
//  to its left, the pinned extensions.
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

    /// Places the cylinder against the bar's trailing inset and returns where
    /// the pill's room ends. Without extensions that is the inset itself.
    func placeShelf(centreY: CGFloat, after left: CGFloat) -> CGFloat {
        let end = bounds.maxX - Tokens.Metric.pageBarInset
        guard showsExtensions else { return end }
        let spare = end - left - Tokens.Metric.pageBarPillWidth * Tokens.Metric.pinnedExtensionsAddressShare
            - Tokens.Metric.chromeGapWide - PageBarExtensionShelf.width(pins: 0)
        let count = ExtensionShelfFit.count(extensionPins.count, room: spare, pitch: PageBarExtensionShelf.pitch)
        shelf.show(pins: Array(extensionPins.prefix(count)))
        let width = PageBarExtensionShelf.width(pins: count)
        let height = PageBarExtensionShelf.button.height
        shelf.frame = NSRect(x: end - width, y: centreY - height / 2, width: width, height: height).pixelAligned
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

    static func width(pins: Int) -> CGFloat { CGFloat(pins + 1) * pitch }

    var onPin: ((String, NSView) -> Void)?
    var onExtensions: ((NSView) -> Void)?

    let extensionsButton = PageBarExtensionShelf.makeButton(
        symbol: ExtensionsSymbol.name,
        label: ExtensionsSymbol.label
    )
    private(set) var pinButtons: [(id: String, button: GlassButton)] = []
    /// Between the pins and the button that lists them all, as `NavCluster`
    /// divides back from forward.
    private let divider = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = Self.button.cornerCurve
        Glass.apply(.control, to: self, cornerRadius: Self.button.cornerRadius, cornerCurve: Self.button.cornerCurve)
        divider.wantsLayer = true
        extensionsButton.onActivate = { [weak self] in
            guard let self else { return }
            onExtensions?(extensionsButton)
        }
        extensionsButton.onPressChange = { [weak self] pressed in self?.setPressed(pressed) }
        for view in [divider, extensionsButton] { addSubview(view) }
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
            divider.isHidden = pins.isEmpty
            needsLayout = true
        }
        for (pin, entry) in zip(pins, pinButtons) {
            entry.button.setImage(ExtensionBadge.composite(pin.icon ?? ExtensionsSymbol.image, badge: pin.badge))
            entry.button.setAccessibilityLabel(pin.badge.isEmpty ? pin.name : "\(pin.name), \(pin.badge)")
            entry.button.toolTip = pin.name
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
            let buttonX = CGFloat(pinButtons.count) * side
            extensionsButton.frame = NSRect(x: buttonX, y: 0, width: side, height: bounds.height).pixelAligned
            // Short of the ends, as `NavCluster`'s rule is.
            let inset = bounds.height / 4
            divider.frame = NSRect(
                x: buttonX - Tokens.Metric.hairline / 2,
                y: inset,
                width: Tokens.Metric.hairline,
                height: bounds.height - 2 * inset
            ).pixelAligned
        }
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        divider.layer?.backgroundColor = Tokens.Line.hairline.cgColor
    }

    /// A press between two buttons is the cylinder's, not the page's.
    override var mouseDownCanMoveWindow: Bool { false }
}
