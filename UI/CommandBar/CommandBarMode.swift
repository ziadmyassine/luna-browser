//
//  CommandBarMode.swift
//  Luna
//
//  What the bar was opened *for*: `⌘T`, `⌘L`, or a pill handing over what has
//  already been typed into it.
//
//  Its own file rather than the controller's, for the reason
//  `CommandBarPanelLayout.swift` is: that file crosses SwiftLint's 400-line
//  limit otherwise. It has earned the move anyway — the mode is §9.1's
//  vocabulary, spoken by the app menu, the sidebar and the page bar, and the
//  controller is only one of the places that reads it.
//

import Foundation

/// `⌘T` and `⌘L` (§9.1, §20.1), plus the pills that hand off to the bar.
///
/// The mode carries two separate things, and conflating them is what made the
/// New Tab page open a *second* empty tab: what the field starts with, and
/// which tab a chosen result lands in.
enum CommandBarMode: Equatable {
    /// `⌘T`: empty. Choosing a result opens a new tab.
    case newTab
    /// `⌘L`: prefilled with the current URL and selected. Choosing a result
    /// navigates the tab you are already on.
    case editCurrentURL
    /// A pill handing off to the bar — the top bar's (§4) or the New Tab page's
    /// (§30.19). Starts from whatever was typed into it, and navigates the tab
    /// you are already standing on, because that is the tab you meant to fill.
    case search(String)
}

extension CommandBarMode {

    /// Whether a chosen result opens a **new** tab or navigates the current one.
    /// This is the half of the mode that was wrong: the New Tab page's pill ran
    /// as `.newTab`, so committing left the empty page behind and opened a
    /// second tab next to it.
    var opensNewTab: Bool { self == .newTab }

    /// What the field starts with. `currentURL` is only read when the mode
    /// actually wants it.
    func prefill(currentURL: () -> String) -> String {
        switch self {
        case .newTab: ""
        case .editCurrentURL: currentURL()
        case let .search(text): text
        }
    }
}
