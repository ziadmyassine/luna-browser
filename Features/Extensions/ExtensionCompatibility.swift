//
//  ExtensionCompatibility.swift
//  Luna
//
//  Extensions known not to work in Luna, and why, in the words Settings shows
//  on their cards. Only what has been established goes here; an extension
//  that merely misbehaves is §16.5's list, not this one.
//

import Foundation

enum ExtensionCompatibility {

    /// Apple's iCloud Passwords, for Chrome and for Edge. It does nothing on its
    /// own: every request goes over native messaging to Apple's
    /// `PasswordManagerBrowserExtensionHelper`. Luna has no native messaging yet
    /// (TODO §14.7), and it would not help: macOS kills that helper at launch
    /// unless a browser Apple allows started it. Checked 2026-09-25 by starting
    /// it from a shell — SIGKILL before it read a byte (TODO §14 has the rest).
    static let iCloudPasswords: Set<String> = [
        "pejdijmoenmkgeppbflobdenhhabjlaj",
        "mfbcdcnpokpoajjciilocoachedjkima"
    ]

    /// The reason in a few words, for a line that has one line: a card.
    static func shortBlocker(for id: String) -> String? {
        guard iCloudPasswords.contains(id) else { return nil }
        return String(localized: "Can’t work in Luna")
    }

    static func blocker(for id: String) -> String? {
        guard iCloudPasswords.contains(id) else { return nil }
        return String(localized: """
        Can’t work in Luna. It needs Apple’s passwords helper, which macOS only lets Safari, Chrome, \
        Edge and Firefox use. Luna’s own password manager is the way to fill iCloud passwords here.
        """)
    }
}
