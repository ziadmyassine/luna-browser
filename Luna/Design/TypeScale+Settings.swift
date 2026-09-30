//
//  TypeScale+Settings.swift
//  Luna
//
//  The name at the head of a Settings page (`SettingsPageHeader`) and the
//  user's name on the account row. Its own file because TypeScale.swift is
//  the browser's type and these are what Settings adds to it.
//

import AppKit

extension Tokens.TypeScale {

    /// Between `settingsHeading` (15) and `pageTitle` (26): large enough to
    /// name the page beside its 44 pt tile, small enough that the first card
    /// under it still reads as the start of the page rather than a footnote.
    static var settingsPageTitle: NSFont { .systemFont(ofSize: 22, weight: .semibold) }

    /// The account row's name: the list's own 13 pt, set heavier so the one
    /// row that is a person rather than a place reads first.
    static var settingsAccountName: NSFont { .systemFont(ofSize: 13, weight: .semibold) }
}
