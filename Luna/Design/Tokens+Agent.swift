//
//  Tokens+Agent.swift
//  Luna
//
//  The colour a Luna Control folder is outlined in: each app's own, so the
//  folder says whose it is at a glance. Keyed by `ControlApp.id`.
//

import AppKit

extension Tokens {

    /// Astro's light: the lavender-to-ice of Luna Control's tile, which is the
    /// moon's glow at the saturation of the colours beside it. Its strengths
    /// were set by eye against the sidebar's bloom: strong enough to read as
    /// colour on the dark window, faint enough that the panel's type stays
    /// the brightest thing in it; light mode needs less to read as much.
    enum Astro {
        static var from: NSColor { Tile.controlFrom }
        static var to: NSColor { Tile.controlTo }
        static func auraAlpha(dark: Bool) -> CGFloat { dark ? 0.26 : 0.16 }
        static func bubbleAlpha(dark: Bool) -> CGFloat { dark ? 0.30 : 0.20 }
        static func ringAlpha(dark: Bool) -> CGFloat { dark ? 0.85 : 0.7 }
    }

    enum Agent {
        /// Claude's clay orange, from its own icon.
        static var claude: NSColor { NSColor(srgbRed: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1) }
        /// VS Code's blue, from its own icon.
        static var vscode: NSColor { NSColor(srgbRed: 0x00, green: 0x7A / 255, blue: 0xCC / 255, alpha: 1) }

        /// A Luna Control folder's plate: its app's colour as a wash under the
        /// folder and a stronger line round it, as Dia tints a folder. The
        /// wash is the strength at which the orange reads as a colour on the
        /// dark sidebar and the tab rows on it still read as rows.
        static let fillAlpha: CGFloat = 0.16
        static let rimAlpha: CGFloat = 0.55
        /// The spark that runs round a working folder's rim: a little wider
        /// than the rim so the light reads over it, and the app's colour
        /// lifted toward white so it reads as light rather than paint.
        static let sparkWidth: CGFloat = 1.5
        static let sparkLift: CGFloat = 0.35
        /// The capsule at the foot of a page an agent is working on: a
        /// push button's height with room round it.
        static let capsuleHeight: CGFloat = 36

        /// ChatGPT's and Cursor's icons are black and white, so theirs is the
        /// label colour: white on a dark sidebar, black on a light one, where
        /// white would not show.
        static func tint(forApp id: String?) -> NSColor {
            switch id {
            case "claude-code", "claude-desktop": claude
            case "vscode": vscode
            case "codex", "cursor": .labelColor
            case "astro": Astro.from
            default: Tokens.Text.secondary
            }
        }
    }
}
