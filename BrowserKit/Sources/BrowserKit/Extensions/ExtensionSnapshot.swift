import Foundation

/// What one Space's extensions can see of the browser at a moment: its
/// windows and its tabs. Two of them, old and new, say what to tell WebKit.
///
/// Pure so the rules can be tested without a controller: a hibernated tab is
/// still in `tabs` (docs/EXTENSIONS.md §3.6), so going cold is not a close.
struct ExtensionSnapshot: Equatable {

    /// Browser windows standing in this Space, in the browser's stable order.
    /// Not focus order: the first holds the tabs, and focus moving between
    /// two windows in one Space must not move every tab with it.
    var windows: [UUID] = []
    /// The window with keyboard focus, if it stands in this Space.
    var focused: UUID?
    /// The Space's tabs in list order. They all belong to `windows.first`:
    /// two windows in one Space draw the same column, and a tab can only be
    /// in one extension window.
    var tabs: [UUID] = []
    /// The selected tab of `windows.first`.
    var activeTab: UUID?

    var primaryWindow: UUID? { windows.first }

    enum Event: Equatable {
        case openWindow(UUID)
        case openTab(UUID)
        case moveTab(UUID, from: Int, oldWindow: UUID?)
        case activateTab(UUID, previous: UUID?)
        case focusWindow(UUID?)
        case closeTab(UUID)
        case closeWindow(UUID)
    }

    /// Opens first and closes last, so no event names a window WebKit has
    /// already been told is gone.
    static func events(from old: Self, to new: Self) -> [Event] {
        var events: [Event] = []
        let oldWindows = Set(old.windows), newWindows = Set(new.windows)
        let oldTabs = Set(old.tabs), newTabs = Set(new.tabs)

        events += new.windows.filter { !oldWindows.contains($0) }.map(Event.openWindow)
        events += new.tabs.filter { !oldTabs.contains($0) }.map(Event.openTab)
        events += moves(from: old, to: new)
        if new.activeTab != old.activeTab, let active = new.activeTab {
            events.append(.activateTab(active, previous: old.activeTab.flatMap { newTabs.contains($0) ? $0 : nil }))
        }
        if new.focused != old.focused { events.append(.focusWindow(new.focused)) }
        events += old.tabs.filter { !newTabs.contains($0) }.map(Event.closeTab)
        events += old.windows.filter { !newWindows.contains($0) }.map(Event.closeWindow)
        return events
    }

    /// A tab moved when its place among the tabs that stayed has changed, or
    /// when the window holding the Space's tabs is a different one. Opening or
    /// closing a neighbour shifts indices without moving anything.
    private static func moves(from old: Self, to new: Self) -> [Event] {
        let kept = Set(old.tabs).intersection(new.tabs)
        let before = old.tabs.filter(kept.contains), after = new.tabs.filter(kept.contains)
        let rehomed = new.primaryWindow != nil && old.primaryWindow != new.primaryWindow
        return after.enumerated().compactMap { index, id in
            guard rehomed || before[index] != id, let from = old.tabs.firstIndex(of: id) else { return nil }
            return .moveTab(id, from: from, oldWindow: old.primaryWindow)
        }
    }
}
