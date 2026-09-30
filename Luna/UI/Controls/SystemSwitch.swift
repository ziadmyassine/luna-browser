//
//  SystemSwitch.swift
//  Luna
//
//  The on/off switch, everywhere Luna has one: Settings' rows and the site
//  settings pop-out.
//
//  AppKit's own, which on macOS 26 is the Liquid Glass switch. Luna drew its
//  own for a while, at 36 × 20, because `NSSwitch` is 54 × 24 at every
//  `controlSize` (measured again on macOS 26: `.mini` through `.large` all fit
//  to 54 × 24). The drawn one was a flat copy of the system's with none of
//  its glass, and read as the one control in the app that was not the Mac's.
//  The size is the system's and the rows are built around it.
//
//  Being AppKit's, it brings its own hover, press, key loop, focus ring and
//  VoiceOver role; nothing here re-earns them. What it adds is the closure every
//  other Luna control takes and a Bool to say where it stands.
//

import AppKit

@MainActor
final class SystemSwitch: NSSwitch {

    /// The user moved it. Not called when `isOn` is set in code.
    var onChange: ((Bool) -> Void)?

    var isOn: Bool {
        get { state == .on }
        set { state = newValue ? .on : .off }
    }

    init(isOn: Bool) {
        super.init(frame: .zero)
        state = isOn ? .on : .off
        target = self
        action = #selector(changed)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    @objc private func changed() { onChange?(isOn) }

    /// A disabled switch leaves the key-view loop to the row around it, which
    /// then carries the reason it is off (`SettingsRowView`).
    override var acceptsFirstResponder: Bool { isEnabled && super.acceptsFirstResponder }
}
