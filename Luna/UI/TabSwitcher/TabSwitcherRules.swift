//
//  TabSwitcherRules.swift
//  Luna
//
//  The decisions behind `⌃⇥` that need no window: which tabs the switcher
//  offers and in what order, how many rows they take, and what a keystroke
//  means while it is up. Kept apart from the view and the controller so all
//  three can be tested with values.
//

import AppKit
import BrowserKit

/// Which tabs the switcher shows, most recently used first.
enum TabSwitcherOrder {

    /// The tabs a person has actually been using in this Space: the one on
    /// screen, then every tab opened since launch in the order they were last
    /// looked at, then any other tab that still has a page loaded — the first
    /// `TabSwitcherGrid.capacity` of them.
    ///
    /// Never a tab that is only a place in the sidebar. A pinned tab nobody
    /// has opened, a Favorite that was never clicked and a dimmed row that was
    /// closed are all in `open`, and a switcher full of them buries the three
    /// tabs the keystroke is for under a list of bookmarks. The archive is not
    /// in `open` at all.
    ///
    /// - Parameters:
    ///   - open: the window's tabs in sidebar order, every tier.
    ///   - recent: `BrowserSession.recentTabs`, most recent first. It spans
    ///     every Space and window, which is why it is filtered against `open`.
    ///   - live: tabs with a page loaded right now.
    ///   - active: the tab the window is showing.
    static func tabs(_ open: [Tab], recent: [UUID], live: Set<UUID>, active: UUID?) -> [UUID] {
        let offered = Set(open.lazy.filter { !$0.isDormant }.map(\.id))
        var result: [UUID] = []
        func take(_ id: UUID) {
            guard offered.contains(id), !result.contains(id) else { return }
            result.append(id)
        }
        // First even when another window used a tab more recently: the card
        // under the highlight's starting point has to be the page you are on.
        if let active { take(active) }
        recent.forEach(take)
        open.lazy.map(\.id).filter(live.contains).forEach(take)
        return Array(result.prefix(TabSwitcherGrid.capacity))
    }

    /// `index` moved `offset` places, wrapping at both ends.
    static func step(from index: Int, by offset: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index + offset) % count + count) % count
    }
}

/// How the cards are laid out: five across, and a second row of five once
/// there are more than five. Ten is the most the switcher ever shows.
///
/// The same in every window. The switcher is its own panel and stands past
/// the edges of a window too small for it, so the number of cards is not
/// something the window's width decides — the grid neither shrinks nor
/// scrolls. Two rows is the ceiling because three rows of cards stand taller
/// than the smallest window Luna allows (`Tokens.Metric.windowMinHeight`), and
/// the tabs past the tenth are ones you last looked at long enough ago that the
/// sidebar is the better way back to them.
struct TabSwitcherGrid: Equatable {
    static let perRow = 5
    static let capacity = 2 * perRow

    let rows: Int
    let columns: Int

    init(count: Int) {
        let count = min(max(count, 0), Self.capacity)
        rows = count > Self.perRow ? 2 : 1
        columns = min(count, Self.perRow)
    }

    /// Row by row, left to right: the most recent tabs along the top, in the
    /// order `⌃⇥` moves through them.
    func place(_ index: Int) -> (row: Int, column: Int) {
        guard columns > 0 else { return (0, 0) }
        return (index / columns, index % columns)
    }

    /// The card straight above or below `index`, or `index` itself when there
    /// is none — on one row, or under the last card of a short second row.
    func vertical(from index: Int, down: Bool, count: Int) -> Int {
        guard rows == 2 else { return index }
        let next = down ? index + columns : index - columns
        return (0..<count).contains(next) ? next : index
    }
}

/// What a keystroke means to the switcher.
enum TabSwitcherKey: Equatable {
    /// `⌃⇥`, or → while it is up.
    case forward
    /// `⌃⇧⇥`, or ← while it is up.
    case backward
    /// ↑ and ↓ while it is up: the card above or below, on two rows.
    case up
    case down
    /// `⌃` let go, or Return: go to the highlighted tab.
    case commit
    /// Escape: stay where you were.
    case cancel
    /// Any other key while the switcher is up. It is eaten rather than passed
    /// to the page, which cannot see the switcher and would take a letter
    /// typed at it as typing.
    case swallow

    /// - Parameter isEngaged: whether a `⌃⇥` has started a switch that has not
    ///   ended. Outside one, only `⌃⇥` itself means anything.
    static func reading(
        _ type: NSEvent.EventType,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        isEngaged: Bool
    ) -> TabSwitcherKey? {
        let held = modifiers.intersection([.command, .option, .control])
        switch type {
        // ⌃ alone, so ⌃⌥⇥ and ⌃⌘⇥ stay free for whatever else wants them.
        case .keyDown where keyCode == KeyCode.tab && held == .control:
            return modifiers.contains(.shift) ? .backward : .forward
        case .keyDown where isEngaged:
            return whileEngaged[keyCode] ?? .swallow
        case .flagsChanged where isEngaged && !modifiers.contains(.control):
            return .commit
        default:
            return nil
        }
    }

    /// The keys that mean something while the switcher is up.
    private static let whileEngaged: [UInt16: TabSwitcherKey] = [
        KeyCode.escape: .cancel,
        KeyCode.returnKey: .commit, KeyCode.enter: .commit,
        KeyCode.leftArrow: .backward, KeyCode.rightArrow: .forward,
        KeyCode.upArrow: .up, KeyCode.downArrow: .down
    ]

    /// Virtual key codes, which name keys where they sit rather than what they
    /// type — a Tab is 48 on every layout.
    private enum KeyCode {
        static let tab: UInt16 = 48
        static let returnKey: UInt16 = 36
        static let enter: UInt16 = 76
        static let escape: UInt16 = 53
        static let leftArrow: UInt16 = 123
        static let rightArrow: UInt16 = 124
        static let downArrow: UInt16 = 125
        static let upArrow: UInt16 = 126
    }
}
