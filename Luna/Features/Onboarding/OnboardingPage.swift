//
//  OnboardingPage.swift
//  Luna — §30.17
//
//  The four screens of first run, as copy rather than as views. There is no
//  page for Spaces — a new Luna starts with one, Personal, in no colour — and
//  none for the default browser: finishing asks macOS, which shows its own
//  question (`OnboardingWindowController.finish`).
//
//  Kept apart from the window so the words can be read in one place and tested
//  without one: §30.18's copy warning is that Luna must never promise to bring
//  extensions across, and a promise is easiest to break in a string literal
//  nobody is looking at.
//

import Foundation

enum OnboardingPage: Int, CaseIterable, Sendable {
    case welcome
    case theme
    case transfer
    case finish

    var title: String {
        switch self {
        case .welcome: String(localized: "Welcome to Luna")
        case .theme: String(localized: "Light or dark")
        case .transfer: String(localized: "Bring it all with you")
        case .finish: String(localized: "You're set")
        }
    }

    /// One sentence. The left pane is a column, not a page.
    var body: String {
        switch self {
        case .welcome:
            String(localized: "Your tabs down the side, your Spaces kept apart, and nothing in the way of the page.")
        case .theme:
            String(localized: "Luna can follow your Mac or stay one way, and Settings can change it later.")
        case .transfer:
            String(localized: "Luna can copy your bookmarks and history from the browsers on this Mac. Nothing in them changes.")
        case .finish:
            String(localized: "Press ⌘T for the Command Bar — a site, a search, or a tab you already have open.")
        }
    }

    var continueTitle: String {
        switch self {
        case .welcome: String(localized: "Get started")
        case .theme: String(localized: "Continue")
        case .transfer: String(localized: "Continue")
        case .finish: String(localized: "Start browsing")
        }
    }

    var next: OnboardingPage? { OnboardingPage(rawValue: rawValue + 1) }
    var previous: OnboardingPage? { OnboardingPage(rawValue: rawValue - 1) }
}
