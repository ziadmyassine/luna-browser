//
//  TopBarSpaceCapsule.swift
//  Luna
//
//  §4's Space switcher, in a cylinder of its own at the bar's trailing end,
//  after the action capsule. It used to head the plate of kept tabs on the
//  left; the switcher is about where the window is rather than what is in it,
//  so it stands with the controls instead of with the tabs.
//
//  The glass is the capsule's, applied once at full radius, as
//  `TopBarActionCapsule` does it: the name inside carries no material.
//

import AppKit

@MainActor
final class TopBarSpaceCapsule: NSView {

    let spaceName: TopBarSpaceName

    /// The action capsule's cylinder, which is the bar's line.
    static var height: CGFloat { TopBarMetrics.lineHeight }

    init(spaceName: TopBarSpaceName) {
        self.spaceName = spaceName
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        Glass.apply(.control, to: self, cornerRadius: Self.height / 2)
        spaceName.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spaceName)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            // The name pads itself (`TopBarSpaceName.intrinsicContentSize`).
            spaceName.leadingAnchor.constraint(equalTo: leadingAnchor),
            trailingAnchor.constraint(equalTo: spaceName.trailingAnchor),
            spaceName.topAnchor.constraint(equalTo: topAnchor),
            spaceName.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Space"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code")
    }

    /// Kept, not passed on up to the window — `TopBarSpaceName.mouseDown`.
    override var mouseDownCanMoveWindow: Bool { false }
}
