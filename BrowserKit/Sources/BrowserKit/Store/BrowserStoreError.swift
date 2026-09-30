import Foundation

/// The failures `BrowserStore` raises on its own behalf, as opposed to the ones GRDB raises.
///
/// Both are refusals, not accidents: each names something the caller asked for that would
/// leave the database describing a world that cannot exist.
public enum BrowserStoreError: Error, Equatable, LocalizedError {

    /// A Space was written with the all-zero `dataStoreIdentifier` (§3.1).
    case invalidDataStoreIdentifier(spaceID: UUID)

    /// A Space was written with a `dataStoreIdentifier` another Space already holds (§9).
    ///
    /// The column is `UNIQUE`, but GRDB's upsert carries no conflict target, so SQLite
    /// resolves a uniqueness conflict on any index by updating the row it collided with.
    /// A duplicate jar would not fail: it would quietly overwrite the other Space, and a
    /// Space would disappear. Hence an explicit refusal.
    case dataStoreIdentifierTaken(spaceID: UUID, by: UUID)

    public var errorDescription: String? {
        switch self {
        case let .invalidDataStoreIdentifier(spaceID):
            "Space \(spaceID) has an unusable website data store identifier."
        case let .dataStoreIdentifierTaken(spaceID, owner):
            "Space \(spaceID) was given the website data store Space \(owner) already uses."
        }
    }
}
