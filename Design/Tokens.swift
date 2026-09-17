//
//  Tokens.swift
//  Luna
//
//  THE ONLY FILE IN LUNA PERMITTED TO CONTAIN A COLOUR VALUE (§0.3, §8.1).
//  Everything visual references a semantic token from here. No hex, no
//  `NSColor.white`, no `.systemBlue` anywhere else. If a view needs a colour
//  that isn't here yet, add a named token here first.
//
//  Two rules for anything added below:
//    1. Semantic names only. `Surface.base`, never `gray900`.
//    2. Every colour resolves for light *and* dark (§8.1), live. Prefer a
//       semantic system colour — it already handles Increase Contrast and
//       Reduce Transparency (§21.2), which a hex value silently does not.
//       Only go custom where the system has no right answer, and say why.
//       Never sample `NSApp.effectiveAppearance` once at startup; a browser
//       window changes appearance while running and a stale colour is a bug.
//
//  Concurrency: `NSColor` is `NS_SWIFT_SENDABLE`, its semantic class
//  properties are nonisolated, and every token here is a *computed* static
//  with no storage — so there is no shared mutable state and no isolation is
//  required. Do not "fix" this file with `@MainActor` or `nonisolated(unsafe)`.
//

import AppKit

enum Tokens {

    /// Background planes, back to front (§8.1 `surface/0..3`).
    enum Surface {
        /// surface/0 — the window plane, behind all chrome. System-backed.
        static var base: NSColor { .windowBackgroundColor }

        /// surface/1 — one visible step above `base`: sidebar wash, popovers.
        ///
        /// Custom, because on macOS 26 every candidate system colour
        /// (`controlBackgroundColor`, `textBackgroundColor`) resolves to
        /// *exactly* `windowBackgroundColor` — #FFFFFF light / #1E1E1E dark —
        /// so a system-backed `raised` would be indistinguishable from `base`.
        /// These give a 1.14:1 (light) / 1.18:1 (dark) step: visible, not loud.
        static var raised: NSColor {
            dynamicColor(light: 0xF0_F0_F0, dark: 0x2B_2B_2B)
        }
    }

    /// Foreground text (§8.1 `textPrimary/Secondary/Tertiary`).
    ///
    /// §21.4 contrast, measured against both surfaces in both themes:
    /// primary 14.9 / 13.5 (light, base / raised), 12.2 / 10.6 (dark);
    /// secondary 5.7 / 5.5 (light), 6.8 / 6.1 (dark). Worst pair 5.5:1.
    enum Text {
        /// System-backed. Increase Contrast drives it to full opacity for free.
        static var primary: NSColor { .labelColor }

        /// Custom, because `.secondaryLabelColor` **fails §21.4**: it is
        /// black at 50 % , which measures 3.95:1 on a white window — under the
        /// 4.5:1 floor. 60 % is the smallest round alpha that clears it.
        static var secondary: NSColor {
            NSColor(name: "luna.text.secondary") { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    ? NSColor(white: 1, alpha: 0.60)   // 6.8:1 on base
                    : NSColor(white: 0, alpha: 0.60)   // 5.7:1 on base
            }
        }
    }

    /// Rules and dividers (§8.1 `separator`).
    enum Line {
        /// System-backed: `.separatorColor` already resolves to 10 % black /
        /// 10 % white, which is §8.4's hairline spec, and it tracks Increase
        /// Contrast. Do not hand-roll this one.
        static var hairline: NSColor { .separatorColor }
    }

    /// Non-colour constants. Sendable values, no isolation needed.
    enum Metric {
        static let windowMinWidth: CGFloat = 640
        static let windowMinHeight: CGFloat = 480
        static let windowDefaultWidth: CGFloat = 1200
        static let windowDefaultHeight: CGFloat = 800
    }
}

/// Builds a token that re-resolves every time the appearance changes.
///
/// This is where the rest of §8.1 lands (`surface/2..3`, `textTertiary`,
/// `accent`, `dangerous`, `overlayScrim`, `focusRing`) — none of those has a
/// correct system equivalent, so each becomes one line here. A token that also
/// needs to react to Increase Contrast writes its own `bestMatch` over
/// `.accessibilityHighContrast*` instead, as `Text.secondary` shows.
private func dynamicColor(light: UInt32, dark: UInt32) -> NSColor {
    NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgb: dark) : NSColor(srgb: light)
    }
}

private extension NSColor {
    /// 0xRRGGBB, sRGB, opaque. The only hex entry point in the codebase.
    convenience init(srgb hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
