import Foundation
import GRDB

/// The per-site answers, in the same `siteSettings` row the per-site zoom and the
/// blocking exemption already live in: §3.2's two from the site menu, plus §14.4's
/// "never offer to save a password here".
///
/// The columns are created by migrations (`v12`, `Schema.prepareForSync`), because sync's
/// triggers name them. A new case needs its column in a new migration and in the synced
/// columns of `SyncSQL`'s `siteSettings` triggers.
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
        /// absent, the site is asked. Local to this Mac (`Schema.rememberDeviceAnswers`).
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
    }

    /// Every host that has been answered for, per permission, with the answer — the
    /// whole table, because it is read once at launch and then answered from memory (see
    /// `SitePermissions`).
    ///
    /// A host is absent when nobody has answered for it, which is not the same as a `no`:
    /// Picture-in-Picture defaults to yes, so "not in the map" and "mapped to false" have
    /// to stay tellable apart.
    public func sitePermissions() async throws -> [SitePermission: [String: Bool]] {
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
}
