import Foundation

/// The failures `BrowserStore` raises on its own behalf, as opposed to the ones GRDB raises.
///
/// Both cases are refusals, not accidents: each one names something the caller asked for
/// that would leave the database describing a world that cannot exist.
public enum BrowserStoreError: Error, Equatable, LocalizedError {

    /// `delete(profileID:)` while at least one Space still names that profile.
    ///
    /// Deleting it anyway would leave `spaces.profileID` pointing at nothing, and those
    /// Spaces would resolve to no data store at all — a window of tabs with no cookie jar.
    /// The `spaceIDs` are carried so the caller can say which Spaces, which is the one
    /// clause §6.4's deletion dialog has no prior art to copy.
    case profileInUse(profileID: UUID, spaceIDs: [UUID])

    /// A profile was written with the all-zero `dataStoreIdentifier` (§3.1).
    case invalidDataStoreIdentifier(profileID: UUID)

    public var errorDescription: String? {
        switch self {
        case let .profileInUse(profileID, spaceIDs):
            "Profile \(profileID) is still used by \(spaceIDs.count) Space(s) and cannot be deleted."
        case let .invalidDataStoreIdentifier(profileID):
            "Profile \(profileID) has an unusable website data store identifier."
        }
    }
}
