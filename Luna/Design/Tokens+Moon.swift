//
//  Tokens+Moon.swift
//  Luna
//
//  The night sky Luna Control's settings pane is drawn on, and the moon in it
//  (docs/LUNA-CONTROL.md, "The Settings pane"). The sky is night in both
//  appearances: it is a picture, not a surface, so none of these follow the
//  appearance and none of them is a tint over the glass.
//

import AppKit

extension Tokens {

    enum Moon {

        static var skyTop: NSColor { rgb(0x08_0A_15) }
        static var skyBottom: NSColor { rgb(0x14_1A_2F) }
        /// The haze in the lower corner, under the title. Lifted a little as the
        /// moon fills, so the whole sky brightens with it.
        static var haze: NSColor { rgb(0xA0_78_D2) }
        static var star: NSColor { rgb(0xEB_EB_FF) }
        /// Darkens the sky behind the title and the switch, so white type
        /// reads over any star or orbit that happens to pass under it.
        static var scrim: NSColor { rgb(0x08_0A_14) }

        /// The two glows round the moon are `Bloom.lavender` and `Bloom.mint`
        /// at full strength — the same two hues the sidebar's bloom mixes.
        static var glowInner: NSColor { rgb(0xD3_AD_F0) }
        static var glowOuter: NSColor { rgb(0xBB_E9_F5) }
        static var orbit: NSColor { rgb(0xD3_BE_F5) }

        /// The surface, lit side to limb, and the marks on it.
        static var surfaceLit: NSColor { rgb(0xFF_FD_F7) }
        static var surfaceMid: NSColor { rgb(0xE6_E1_EF) }
        static var surfaceLimb: NSColor { rgb(0xAB_A5_C4) }
        static var maria: NSColor { rgb(0x62_5C_88) }
        static var crater: NSColor { rgb(0x58_52_78) }
        static var limbShade: NSColor { rgb(0x28_22_48) }

        /// Type on the sky. Always white: the sky is always night.
        static var ink: NSColor { .white }
        static var inkSecondary: NSColor { NSColor.white.withAlphaComponent(0.72) }
        static var chipFill: NSColor { NSColor.white.withAlphaComponent(0.10) }
        static var chipRing: NSColor { NSColor.white.withAlphaComponent(0.14) }
        static var dotOff: NSColor { NSColor.white.withAlphaComponent(0.35) }

        /// One colour per connected app: its light in the sky, its planet in
        /// the list and its dot in the activity log. Assigned by the app's
        /// place in `ControlApp.all`, so an app keeps its colour for good. The
        /// middle three are the bloom's own hues; peach and blue fill it out to
        /// the five apps Luna knows by name.
        static var satellites: [NSColor] {
            [rgb(0xF2_C6_A0), rgb(0xBB_E9_F5), rgb(0xD3_AD_F0), rgb(0xF7_F0_A8), rgb(0xA9_C8_FF)]
        }

        static func satellite(_ index: Int) -> NSColor {
            let palette = satellites
            return palette[((index % palette.count) + palette.count) % palette.count]
        }

        private static func rgb(_ hex: UInt32) -> NSColor {
            NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    }
}
