import Foundation
import GRDB

/// An installed extension, as the database remembers it. Its name, version and
/// permissions are the manifest's, read from disk when it loads.
public struct ExtensionRecord: Sendable, Hashable, Codable {
    public var id: String
    public var source: ExtensionSource
    public var installedAt: Date

    public init(id: String, source: ExtensionSource, installedAt: Date = Date()) {
        self.id = id
        self.source = source
        self.installedAt = installedAt
    }
}

/// One extension in one Space: whether it runs there and what it may do there.
public struct ExtensionSpaceRecord: Sendable, Hashable, Codable {
    public var extensionID: String
    public var spaceID: UUID
    public var isEnabled: Bool
    public var grants: ExtensionGrants

    public init(extensionID: String, spaceID: UUID, isEnabled: Bool, grants: ExtensionGrants) {
        self.extensionID = extensionID
        self.spaceID = spaceID
        self.isEnabled = isEnabled
        self.grants = grants
    }
}

/// The user's answers for one extension in one Space, as WebKit's own strings:
/// permission names (`"storage"`, `"tabs"`) and match patterns (`"<all_urls>"`).
///
/// Denials are kept as well as grants. A refusal is an answer, and forgetting it
/// would let the extension ask again as though it never had.
public struct ExtensionGrants: Sendable, Hashable, Codable {
    public var grantedPermissions: Set<String>
    public var deniedPermissions: Set<String>
    public var grantedPatterns: Set<String>
    public var deniedPatterns: Set<String>

    public init(
        grantedPermissions: Set<String> = [],
        deniedPermissions: Set<String> = [],
        grantedPatterns: Set<String> = [],
        deniedPatterns: Set<String> = []
    ) {
        self.grantedPermissions = grantedPermissions
        self.deniedPermissions = deniedPermissions
        self.grantedPatterns = grantedPatterns
        self.deniedPatterns = deniedPatterns
    }
}

extension BrowserStore {

    /// Every installed extension with its per-Space rows. Read once at launch.
    public func installedExtensions() async throws -> [(ExtensionRecord, [ExtensionSpaceRecord])] {
        try await pool.read { db in
            let spaces = try ExtensionSpaceRecord.fetchAll(db)
            return try ExtensionRecord.fetchAll(db, sql: "SELECT * FROM extensions ORDER BY installedAt").map { record in
                (record, spaces.filter { $0.extensionID == record.id })
            }
        }
    }

    /// Records an install or an update: the extension, and its row in the Space
    /// it was installed from. Other Spaces' rows are left as they were.
    public func saveExtension(_ record: ExtensionRecord, in space: ExtensionSpaceRecord) async throws {
        try await pool.write { db in
            try record.upsert(db)
            try space.upsert(db)
        }
    }

    public func saveExtensionSpace(_ space: ExtensionSpaceRecord) async throws {
        try await pool.write { db in try space.upsert(db) }
    }

    /// Uninstall. The per-Space rows cascade.
    public func deleteExtension(id: String) async throws {
        _ = try await pool.write { db in try ExtensionRecord.deleteOne(db, key: id) }
    }
}
