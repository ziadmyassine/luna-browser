import Foundation

/// What the account row's subtitle and the account page say about sync (docs/SYNC-PLAN.md §4).
/// Every state is a quiet line, never a modal.
public enum SyncStatus: Sendable, Equatable {
    case needsSignedBuild
    case off
    /// On, before the first fetch has finished.
    case syncing
    case synced(Date)
    case noAccount
    case unavailable
    case switchedAccount
    case storageFull
    case offline
    case removedElsewhere

    public func line(now: Date = Date(), locale: Locale = .current) -> String {
        switch self {
        case .needsSignedBuild: "iCloud sync needs the signed build."
        case .off: "iCloud sync off"
        case .syncing: "Syncing…"
        case .synced(let date): Self.synced(date, now: now, locale: locale)
        case .noAccount: "Sign in to iCloud to sync."
        case .unavailable: "iCloud is unavailable right now."
        case .switchedAccount: "Signed into a different iCloud account."
        case .storageFull: "iCloud storage is full."
        case .offline: "Offline — will sync when connected."
        case .removedElsewhere: "Luna's iCloud data was removed from another Mac."
        }
    }

    private static func synced(_ date: Date, now: Date, locale: Locale) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return "Synced just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = locale
        return "Synced " + formatter.localizedString(for: date, relativeTo: now)
    }
}
