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

        /// How far a working folder's glow spreads past its outline: enough to
        /// read as light at the sidebar's size, less than the gap between one
        /// folder and the row below it.
        static let glowRadius: CGFloat = 6

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
