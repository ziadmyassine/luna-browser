//
//  ProfileNamingTests.swift
//  LunaTests
//
//  §9's Profiles as things the user owns: named, made and unmade.
//
//  A Profile's name was written once, by `createSpace`, and nothing anywhere
//  could change it afterwards. §6.1 makes the Space before the form that names
//  it opens, so a Space made by §30.9's swipe sat on a Profile called `Space 2`
//  for good — which is how this was reported.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class ProfileNamingTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() throws -> BrowserStore {
        try BrowserStore(path: directory.appending(path: "luna.sqlite"))
    }

    private func makeSession(_ store: BrowserStore) async throws -> BrowserSession {
        try await BrowserSession.restored(store: store)
    }

    // MARK: - Renaming

    func testAProfileCanBeRenamed() async throws {
        let store = try makeStore()
        let session = try await makeSession(store)
        let id = try XCTUnwrap(session.profilesByName.first?.id)

        try await session.renameProfile(id, to: "  Personal  ")

        XCTAssertEqual(session.profiles[id]?.name, "Personal", "trimmed, like a Space's")
        let persisted = try await store.profiles().first { $0.id == id }
        XCTAssertEqual(persisted?.name, "Personal", "…and it survives a relaunch")
    }

    func testAProfileNameTakesTheSameCapASpacesDoes() async throws {
        let session = try await makeSession(try makeStore())
        let id = try XCTUnwrap(session.profilesByName.first?.id)

        try await session.renameProfile(id, to: String(repeating: "a", count: BrowserSession.spaceNameCap * 2))

        XCTAssertEqual(session.profiles[id]?.name.count, BrowserSession.spaceNameCap)
    }

    func testAnEmptyProfileNameIsRefused() async throws {
        let session = try await makeSession(try makeStore())
        let id = try XCTUnwrap(session.profilesByName.first?.id)
        let before = session.profiles[id]?.name

        do {
            try await session.renameProfile(id, to: "   ")
            XCTFail("a profile with no name is an unreadable row in every picker")
        } catch {
            XCTAssertEqual(session.profiles[id]?.name, before)
        }
    }

    // MARK: - Following the Space, and letting go of it

    /// The reported case: the Space made by the swipe is `Space 2` before the
    /// form that names it opens, so the Profile it minted is too.
    func testAPrivateProfileFollowsItsSpacesName() async throws {
        let session = try await makeSession(try makeStore())
        let space = try XCTUnwrap(session.spaces.first)

        try await session.renameSpace(space.id, to: "Reading")

        XCTAssertEqual(session.profiles[space.profileID]?.name, "Reading")
    }

    /// And stops following the moment the user names it themselves: from then
    /// on the two have diverged on purpose.
    ///
    /// The Profile is given a name the Space never had, which is what makes it
    /// a divergence — renaming it to what it already said would be no answer
    /// at all, and is how this test failed first time out.
    func testAProfileNamedByHandStopsFollowing() async throws {
        let session = try await makeSession(try makeStore())
        let space = try XCTUnwrap(session.spaces.first)
        XCTAssertNotEqual(space.name, "Shared Jar")

        try await session.renameProfile(space.profileID, to: "Shared Jar")
        try await session.renameSpace(space.id, to: "Reading")

        XCTAssertEqual(
            session.profiles[space.profileID]?.name, "Shared Jar",
            "a Space rename undid a Profile rename"
        )
        XCTAssertEqual(session.space(space.id)?.name, "Reading")
    }

    /// What it follows with is the stored name, not what was typed: a Profile
    /// is drawn in the same places a Space is and takes the same cap.
    func testItFollowsWithTheCappedNameRatherThanTheTypedOne() async throws {
        let session = try await makeSession(try makeStore())
        let space = try XCTUnwrap(session.spaces.first)

        try await session.renameSpace(space.id, to: String(repeating: "a", count: BrowserSession.spaceNameCap * 2))

        XCTAssertEqual(session.profiles[space.profileID]?.name, session.space(space.id)?.name)
        XCTAssertEqual(session.profiles[space.profileID]?.name.count, BrowserSession.spaceNameCap)
    }

    /// A shared Profile is the group's, and the other Spaces did not ask (§9).
    func testASharedProfileNeverFollows() async throws {
        let session = try await makeSession(try makeStore())
        let first = try XCTUnwrap(session.spaces.first)
        _ = try await session.createSpace(name: "Work Admin", profileID: first.profileID)

        try await session.renameSpace(first.id, to: "Reading")

        XCTAssertEqual(session.profiles[first.profileID]?.name, first.name)
    }

    // MARK: - Making and unmaking

    /// An empty Profile is a row and an identifier, and the row is what keeps
    /// it: `liveDataStoreIdentifiers` reads from the rows, so the orphan sweep
    /// has no reason to touch one nothing is on yet.
    func testAProfileCanBeMadeWithNoSpaceOnIt() async throws {
        let store = try makeStore()
        let session = try await makeSession(store)

        let made = try await session.createProfile(named: "Work")

        XCTAssertEqual(session.profiles[made.id]?.name, "Work")
        XCTAssertFalse(session.isProfileInUse(made.id))
        let live = try await store.liveDataStoreIdentifiers()
        XCTAssertTrue(live.contains(made.dataStoreIdentifier), "the sweep would take its store")
    }

    func testAnUnusedProfileCanBeDeleted() async throws {
        let store = try makeStore()
        let session = try await makeSession(store)
        let made = try await session.createProfile(named: "Work")

        try await session.deleteProfile(made.id)

        XCTAssertNil(session.profiles[made.id])
        let persisted = try await store.profiles().first { $0.id == made.id }
        XCTAssertNil(persisted)
    }

    /// Refused by the store rather than by a check in the session: many Spaces
    /// may share one, so only the database can answer "is anything still on it".
    func testAProfileInUseCannotBeDeleted() async throws {
        let session = try await makeSession(try makeStore())
        let space = try XCTUnwrap(session.spaces.first)

        do {
            try await session.deleteProfile(space.profileID)
            XCTFail("that would sign a live Space out of everything, with no undo")
        } catch {
            XCTAssertNotNil(session.profiles[space.profileID])
        }
    }
}
