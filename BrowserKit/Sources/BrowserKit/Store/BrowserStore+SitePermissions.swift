import Foundation
import GRDB

/// The per-site answers, in two tables. The ones that hold in every Space live in the
/// `siteSettings` row beside the per-site zoom and the blocking exemption: Picture in
/// Picture, and §14.4's "never offer to save a password here". The ones that belong to
/// one Space's cookie jar live in `spaceSitePermissions`, one row per Space and site
/// (`v14`, `Schema.keepSiteAnswersPerSpace`).
///
/// The columns are created by migrations, because sync's triggers name the shared ones.
/// A new case needs its column in a new migration, in the table `isPerSpace` puts it in,
/// and, if it is shared and should sync, in the synced columns of `SyncSQL`'s
/// `siteSettings` triggers.
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
        /// §17: pop-ups open here whatever the blocking mode says. Written by the
        /// pop-up chip's Always Allow and the site menu's switch.
        case popups
        /// §17.8: the page may turn on the camera, the microphone, or ask where this
        /// Mac is. Written by the toast's Allow and Don't Allow and by the site menu;
        /// absent, the site is asked.
        case camera
        case microphone
        case location

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
            // Absent means the mode decides, which is what "not allowed" does.
            case .popups: false
            // Absent means ask, and nothing is handed over before the answer.
            case .camera, .microphone, .location: false
            }
        }

        /// Whether an answer holds in one Space only. A Space is a separate identity
        /// with its own logins (§5), so letting a site reach the camera, the room's
        /// network or a new window is said to that identity: a yes to a call site in
        /// Work is not a yes in Personal. Picture in Picture and the password offer are
        /// about how Luna behaves, not about what the site may do, and hold everywhere.
        public var isPerSpace: Bool {
            switch self {
            case .camera, .microphone, .location, .localNetwork, .popups: true
            case .automaticPictureInPicture, .savePasswords: false
            }
        }
    }

    /// The answers that hold in every Space, per permission, with the answer — the whole
    /// table, because it is read once at launch and then answered from memory (see
    /// `SitePermissions`).
    ///
    /// A host is absent when nobody has answered for it, which is not the same as a `no`:
    /// Picture-in-Picture defaults to yes, so "not in the map" and "mapped to false" have
    /// to stay tellable apart.
    public func sitePermissions() async throws -> [SitePermission: [String: Bool]] {
        try await pool.read { db in
            var result: [SitePermission: [String: Bool]] = [:]
            for answer in try Self.answers(perSpace: false, db) {
                result[answer.permission, default: [:]][answer.host] = answer.allowed
            }
            return result
        }
    }

    /// Every Space's answers to the `isPerSpace` permissions, read the same way and for
    /// the same reason as ``sitePermissions()``.
    public func spaceSitePermissions() async throws -> [UUID: [SitePermission: [String: Bool]]] {
        try await pool.read { db in
            var result: [UUID: [SitePermission: [String: Bool]]] = [:]
            for answer in try Self.answers(perSpace: true, db) {
                guard let space = answer.spaceID else { continue }
                result[space, default: [:]][answer.permission, default: [:]][answer.host] = answer.allowed
            }
            return result
        }
    }

    /// An answer that holds in every Space.
    public func setSitePermission(_ permission: SitePermission, allowed: Bool, host: String) async throws {
        precondition(!permission.isPerSpace, "\(permission) belongs to a Space; pass inSpace:")
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

    /// An answer that holds in `spaceID` only. Throws when the Space has gone, which
    /// is the foreign key refusing a row nothing would ever delete.
    public func setSitePermission(_ permission: SitePermission, allowed: Bool, host: String, inSpace spaceID: UUID) async throws {
        precondition(permission.isPerSpace, "\(permission) holds in every Space; leave out inSpace:")
        let column = permission.rawValue
        try await pool.write { db in
            try db.execute(
                sql: """
                INSERT INTO spaceSitePermissions (spaceID, host, \(column)) VALUES (?, ?, ?)
                ON CONFLICT(spaceID, host) DO UPDATE SET \(column) = excluded.\(column)
                """,
                arguments: [spaceID, host, allowed]
            )
        }
    }

    private struct Answer {
        var spaceID: UUID?
        var host: String
        var permission: SitePermission
        var allowed: Bool
    }

    /// Every answer in one of the two tables, one per answered column of each row.
    private static func answers(perSpace: Bool, _ db: Database) throws -> [Answer] {
        let columns = SitePermission.allCases.filter { $0.isPerSpace == perSpace }
        let names = columns.map(\.rawValue)
        let test = names.map { "\($0) IS NOT NULL" }.joined(separator: " OR ")
        let (space, table) = perSpace ? ("spaceID, ", "spaceSitePermissions") : ("", "siteSettings")
        return try Row.fetchAll(db, sql: "SELECT \(space)host, \(names.joined(separator: ", ")) FROM \(table) WHERE \(test)")
            .flatMap { row in
                columns.compactMap { permission in
                    (row[permission.rawValue] as Bool?).map {
                        Answer(spaceID: perSpace ? row["spaceID"] : nil, host: row["host"], permission: permission, allowed: $0)
                    }
                }
            }
    }
}
