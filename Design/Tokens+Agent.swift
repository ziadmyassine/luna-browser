//
//  Tokens+Agent.swift
//  Luna
//
//  The colour a Luna Control folder is outlined in: each app's own, so the
//  folder says whose it is at a glance. Keyed by `ControlApp.id`.
//

import AppKit

extension Tokens {

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

        /// ChatGPT's and Cursor's icons are black and white, so theirs is the
        /// label colour: white on a dark sidebar, black on a light one, where
        /// white would not show.
        static func tint(forApp id: String?) -> NSColor {
            switch id {
            case "claude-code", "claude-desktop": claude
            case "vscode": vscode
            case "codex", "cursor": .labelColor
            default: Tokens.Text.secondary
            }
        }
    }
}
