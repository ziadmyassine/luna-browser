import Foundation
import GRDB

/// The per-site answers, in the same `siteSettings` row the per-site zoom and the
/// blocking exemption already live in: §3.2's two from the site menu, plus §14.4's
/// "never offer to save a password here".
///
/// The columns are added the way `BrowserStore+Blocking.swift` adds its two: an idempotent
/// `ALTER TABLE` rather than a migration, because `Store/Schema.swift` belongs to the
/// milestone that wrote it and one statement that runs once per process is cheaper than a
/// schema version everybody has to reason about.
/// ponytail: fold all five columns into a `v2` migration next time `Schema.swift` is opened.
extension BrowserStore {

    /// Which permission a row is carrying. The raw value is the column name, so the
    /// two cannot drift apart — and it is a literal from this file, never user input,
    /// which is why interpolating it into SQL is not an injection path.
    public enum SitePermission: String, CaseIterable, Sendable {
        /// A video keeps playing in a floating window when you leave its tab.
        case automaticPictureInPicture
        /// The page may reach addresses on this Mac's own network.
        case localNetwork
        /// Luna may offer to save a password for this site (§14.4).
        ///
        /// Written only by "Never for this site" on the save chip, so a row
        /// here is always an explicit refusal — which is why the default is
        /// yes and absence means "has not said no".
        case savePasswords

        /// What the permission is when nobody has answered for this site.
        ///
        /// Picture-in-Picture is on because it is a convenience the user notices only
        /// when it is missing; the local network is off because it is the one that
        /// reaches off the page and onto the hardware in the room.
        public var defaultsToAllowed: Bool {
            switch self {
            case .automaticPictureInPicture: true
            case .localNetwork: false
            // §14.4: offering is the default; the chip's "Never for this
            // site" is the only thing that ever writes a `false` here.
            case .savePasswords: true
            }
        }
    }

    /// Every host that has been answered for, per permission, with the answer — the
    /// whole table, because it is read once at launch and then answered from memory (see
    /// `SitePermissions`).
    ///
    /// A host is absent when nobody has answered for it, which is not the same as a `no`:
    /// Picture-in-Picture defaults to yes, so "not in the map" and "mapped to false" have
    /// to stay tellable apart.
    public func sitePermissions() async throws -> [SitePermission: [String: Bool]] {
        try await ensurePermissionColumns()
        let columns = SitePermission.allCases
        return try await pool.read { db in
            var result: [SitePermission: [String: Bool]] = [:]
            let names = columns.map(\.rawValue)
            let test = names.map { "\($0) IS NOT NULL" }.joined(separator: " OR ")
            for row in try Row.fetchAll(
                db,
                sql: "SELECT host, \(names.joined(separator: ", ")) FROM siteSettings WHERE \(test)"
            ) {
                let host: String = row["host"]
                for permission in columns {
                    guard let answer = row[permission.rawValue] as Bool? else { continue }
                    result[permission, default: [:]][host] = answer
                }
            }
            return result
        }
    }

    public func setSitePermission(_ permission: SitePermission, allowed: Bool, host: String) async throws {
        try await ensurePermissionColumns()
        let column = permission.rawValue
        // `zoom` carries a NOT NULL default, so the upsert can create the row without
        // knowing anything about zoom.
        try await pool.write { db in
            try db.execute(
                sql: """
                INSERT INTO siteSettings (host, updatedAt, \(column)) VALUES (?, ?, ?)
                ON CONFLICT(host) DO UPDATE SET \(column) = excluded.\(column), updatedAt = excluded.updatedAt
                """,
                arguments: [host, Date(), allowed]
            )
        }
    }

    /// Nullable, unlike the blocking flags. "Nobody has answered" and "answered no"
    /// are different states here: the default is the permission's, not the column's, and
    /// a `NOT NULL DEFAULT 0` would silently record a refusal for every site that has a
    /// zoom level set.
    private func ensurePermissionColumns() async throws {
        try await pool.write { db in
            let existing = Set(try db.columns(in: "siteSettings").map(\.name))
            for permission in SitePermission.allCases where !existing.contains(permission.rawValue) {
                try db.execute(sql: "ALTER TABLE siteSettings ADD COLUMN \(permission.rawValue) BOOLEAN")
            }
        }
    }
}
