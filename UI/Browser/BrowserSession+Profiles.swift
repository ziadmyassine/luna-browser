//
//  BrowserSession+Profiles.swift
//  Luna
//
//  Profiles as things the user has, rather than as a side effect of making a
//  Space (§9).
//
//  A Profile's name used to be set once and never again: `createSpace` names a
//  new one after the Space being made, and nothing anywhere could change it
//  afterwards. §6.1 creates the Space before the form that names it opens — the
//  swipe ends with the fingers coming off the trackpad — so every Space made
//  that way left a Profile called `Space 2` for good.
//
//  None of this touches the cookie jar. The store on disk is WebKit's (§3.1):
//  a rename is a label, and a new Profile is a row plus an identifier that no
//  `WKWebsiteDataStore` exists under until a Space is moved onto it. The row is
//  also what keeps it — `liveDataStoreIdentifiers` is read from the profile
//  rows, so a Profile with no Space on it is not an orphan and
//  `sweepOrphanedProfileStores` leaves it where it is.
//

import BrowserKit
import Foundation

extension BrowserSession {

    // MARK: - Reading

    /// Every Profile, in the order Settings lists them.
    var profilesByName: [Profile] { profiles.values.sorted { $0.name < $1.name } }

    /// Whether any Space is on it, which is the only thing standing between a
    /// Profile and deletion.
    func isProfileInUse(_ id: UUID) -> Bool { spaces.contains { $0.profileID == id } }

    // MARK: - Naming

    /// Capped and trimmed exactly as a Space's name is: a Profile's name starts
    /// life as a copy of one, and is drawn in the same places.
    static func profileName(from typed: String) throws -> String {
        try spaceName(from: typed)
    }

    func renameProfile(_ id: UUID, to name: String) async throws {
        let name = try Self.profileName(from: name)
        guard var profile = profiles[id] else { throw SessionError.unknownProfile }
        guard profile.name != name else { return }
        profile.name = name
        profiles[id] = profile
        try await store.upsert(profile)
        notifyChange()
    }

    /// The picture on §3.5's avatar, or nil to take it off again.
    ///
    /// The bytes are already cropped and downsampled by the time they arrive —
    /// see `ProfilePicture`, which is where a chosen file becomes something
    /// worth persisting. This is the write, not the policy.
    func setImage(_ data: Data?, forProfile id: UUID) async throws {
        guard var profile = profiles[id] else { throw SessionError.unknownProfile }
        guard profile.imageData != data else { return }
        profile.imageData = data
        profiles[id] = profile
        try await store.upsert(profile)
        notifyChange()
    }

    /// A Profile still wearing the name of the one Space on it goes on wearing
    /// it — so the Space made by §30.9's swipe stops being `Space 2` the moment
    /// the form that opens after it is given a name.
    ///
    /// Two guards, and they are different refusals. A shared Profile keeps its
    /// own name: it belongs to the group, and the other Spaces on it did not
    /// ask (§9). A Profile whose name has already been changed by hand keeps
    /// that too — the two have diverged on purpose from then on, and a Space
    /// rename must not quietly undo it.
    func followSpaceRename(of spaceID: UUID, from was: String, to name: String) async throws {
        guard let space = space(spaceID),
              let profile = profiles[space.profileID],
              profile.name == was,
              spaces(onProfile: space.profileID).count == 1
        else { return }
        try await renameProfile(profile.id, to: name)
    }

    // MARK: - Making and unmaking

    /// An empty Profile, waiting for a Space to be moved onto it (`setProfile`).
    ///
    /// It has no cookie jar yet and will not have one until it is used, which
    /// is the whole difference between this and the Profile `createSpace`
    /// mints: that one arrives already spoken for.
    @discardableResult
    func createProfile(named name: String) async throws -> Profile {
        let profile = Profile(name: try Self.profileName(from: name))
        try await store.upsert(profile)
        profiles[profile.id] = profile
        notifyChange()
        return profile
    }

    /// A Profile nothing is on.
    ///
    /// Refused while any Space names it, by the store rather than by a check
    /// here (`BrowserStoreError.profileInUse`): many Spaces may share one, so
    /// "the Space that made it is gone" and "anything still needs it" are
    /// different questions and only the database answers the second.
    func deleteProfile(_ id: UUID) async throws {
        guard profiles[id] != nil else { throw SessionError.unknownProfile }
        try await store.delete(profileID: id)
        profiles[id] = nil
        notifyChange()
    }
}
