//
//  OnboardingMetrics.swift
//  Luna — §30.17
//
//  Where first run's two panes are, derived rather than invented: `Design/`
//  has no onboarding entry, and contract rule 2 forbids inlining one.
//

import Foundation

enum OnboardingMetrics {

    /// A column of prose the width Luna already sets prose in (§9.1's floor),
    /// beside a pane as wide as Settings' detail side, at Settings' height.
    static var leftPane: CGFloat { Tokens.Metric.commandBarMinWidth }

    static var rightPane: CGFloat { Tokens.Metric.settingsDefaultWidth - Tokens.Metric.settingsSidebarWidth }

    static var size: CGSize {
        CGSize(width: leftPane + rightPane, height: Tokens.Metric.settingsDefaultHeight)
    }

    /// The page's own margin. Wider than the chrome's, because this is the one
    /// surface in Luna with nothing else on it.
    static var margin: CGFloat { Tokens.Metric.chromeGapWide * 2 }

    /// Two chrome capsules tall. A browser you are choosing between five of
    /// is a card, not a row in a list: at §3.4's height the icons were stamps
    /// and the page read as a settings pane.
    static var rowHeight: CGFloat { Tokens.Metric.capsuleHeight * 2 }

    /// The app's own icon, at the size the Dock would show it standing next
    /// to its name rather than in a column of them.
    static var rowIcon: CGFloat { Tokens.Metric.capsuleHeight + Tokens.Metric.rowInset }

    /// The tick, a `chromeGapWide` inside the icon it answers.
    static var rowMark: CGFloat { rowIcon - Tokens.Metric.chromeGapWide }

    /// A card that tall needs the chrome's corner plus its own inset, or the
    /// plate reads as a rectangle with the corners filed off.
    static var rowRadius: CGFloat { Tokens.Metric.rowCornerRadius + Tokens.Metric.rowInset }

    static var rowGap: CGFloat { Tokens.Metric.chromeGap }

    /// How far a card stands in from the edges of the pane it is on. Three
    /// margins, which is a fifth of the pane each side: a card that runs the
    /// full width of its half is a table row, and this is a thing you pick.
    /// It is also the slack `pressSwell` needs — a plate flush to the scroll
    /// view's clip grew into it and came back with its corner sliced off.
    static var cardInset: CGFloat { margin * 3 }

    /// The app's own mark on the first and last page. Seven window corners:
    /// it is alone on half a window, and at five it read as an icon someone
    /// had left on the page rather than as the subject of it.
    static var badge: CGFloat { Tokens.Metric.windowCornerRadius * 7 }
}
