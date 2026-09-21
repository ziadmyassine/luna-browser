import Foundation

/// §6.3's two sweeps, as pure functions over `Tab` values.
///
/// Both are one-liners with an exemption list, which is exactly why they are
/// here and not inlined: the exemptions are the part that silently rots. A
/// pinned tab that auto-archives is a user's bookmark bar emptying itself
/// overnight.
public enum AutoArchive {

    /// How long Luna keeps an archived tab's row, title, URL, favicon and
    /// snapshot before deleting it (§6.3).
    public static let retention: TimeInterval = 30 * 24 * 60 * 60

    /// The user-settable thresholds. `never` is 0 hours.
    public static let choices: [Double] = [6, 12, 24, 0]
    public static let defaultHours: Double = 12

    /// Today tabs untouched for longer than `hours`.
    ///
    /// Exempt: pinned and Essentials (`.pinned`, `.essential` — §6.3 calls
    /// the latter Favorites), anything already archived, and the tab the user is
    /// looking at, however long ago it was last marked active.
    public static func idleTabs(
        _ tabs: [Tab],
        now: Date,
        hours: Double,
        excluding activeID: UUID? = nil
    ) -> [UUID] {
        guard hours > 0 else { return [] }  // "never"
        let cutoff = now.addingTimeInterval(-hours * 60 * 60)
        return tabs
            .filter { $0.kind == .today && $0.archivedAt == nil }
            .filter { $0.id != activeID && $0.lastActiveAt <= cutoff }
            .map(\.id)
    }

    /// Archived tabs past their 30 days. Their snapshots go with them.
    public static func expired(_ archived: [Tab], now: Date, retention: TimeInterval = retention) -> [UUID] {
        let cutoff = now.addingTimeInterval(-retention)
        return archived.compactMap { tab in
            guard let archivedAt = tab.archivedAt, archivedAt <= cutoff else { return nil }
            return tab.id
        }
    }
}
