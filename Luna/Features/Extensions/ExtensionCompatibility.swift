//
//  ExtensionCompatibility.swift
//  Luna
//
//  Extensions known not to work in Luna, and why, in the words Settings shows
//  on their cards. Only what has been established goes here; an extension
//  that merely misbehaves is §16.5's list, not this one.
//

import Foundation
import Security

enum ExtensionCompatibility {

    /// Apple's iCloud Passwords, for Chrome and for Edge. Every request goes
    /// over native messaging to Apple's `PasswordManagerBrowserExtensionHelper`,
    /// whose parent launch constraint (read from its signature, 2026-09-30)
    /// lets it run only under a browser holding `webBrowserEntitlement` or one
    /// of about forty it names; under any other it is killed at launch. Search
    /// runs it because Apple granted Search the entitlement.
    static let iCloudPasswords: Set<String> = [
        "pejdijmoenmkgeppbflobdenhhabjlaj",
        "mfbcdcnpokpoajjciilocoachedjkima"
    ]

    static let webBrowserEntitlement = "com.apple.developer.web-browser.public-key-credential"

    /// Read from this build's own signature, so the card stops saying so the
    /// day a build signed with the entitlement runs.
    static let hasWebBrowserEntitlement: Bool = {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, webBrowserEntitlement as CFString, nil) as? Bool == true
    }()

    private static func isBlocked(_ id: String) -> Bool {
        iCloudPasswords.contains(id) && !hasWebBrowserEntitlement
    }

    /// The reason in a few words, for a line that has one line: a card.
    static func shortBlocker(for id: String) -> String? {
        guard isBlocked(id) else { return nil }
        return String(localized: "Needs Apple’s approval for Luna")
    }

    static func blocker(for id: String) -> String? {
        guard isBlocked(id) else { return nil }
        return String(localized: """
        Can’t work in Luna yet. It needs Apple’s passwords helper, and macOS only lets browsers that Apple \
        has approved start it. Luna has everything else it needs, so it will work once Apple approves Luna. \
        Until then, Luna’s own password manager is the way to fill passwords here.
        """)
    }
}
