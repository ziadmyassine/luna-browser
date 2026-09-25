//
//  TypeScale+Settings.swift
//  Luna
//
//  The name at the head of a Settings page (`SettingsPageHeader`). Its own
//  file because TypeScale.swift is the browser's type and this is the one
//  size Settings adds to it.
//

import AppKit

extension Tokens.TypeScale {

    /// Between `settingsHeading` (15) and `pageTitle` (26): large enough to
    /// name the page beside its 44 pt tile, small enough that the first card
    /// under it still reads as the start of the page rather than a footnote.
    static var settingsPageTitle: NSFont { .systemFont(ofSize: 22, weight: .semibold) }
}
