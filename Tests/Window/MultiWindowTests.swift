//
//  MultiWindowTests.swift
//  LunaTests
//
//  §22.6: one session, several windows, and the one thing each window owns —
//  where it is standing.
//
//  These are the cases that are silent when they break. Two windows sharing a
//  selection looks like a window "jumping to the wrong tab" and reads as a
//  drawing bug; a window that keeps a closed tab selected shows the page again
//  the next time it comes forward, which reads as the tab not having closed.
//  Neither is visible in the window the user is looking at, which is exactly
//  why they are asserted here.
//
//  Nothing here wakes a tab, so nothing here builds a web view.
//

import BrowserKit
import WebKit
import XCTest
@testable import Luna

@MainActor
final class MultiWindowTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Two windows, one tab list

    /// The whole of what `⌘N` buys: the same rows in both columns, and a
    /// different one lit in each.
    func testEachWindowKeepsItsOwnSelection() async throws {
        let session = try await session()
        let (first, second) = try twoWindows(on: session)
        let tabs = try twoTabs(in: session)

        session.activateTab(tabs.0, inWindow: first)
        session.activateTab(tabs.1, inWindow: second)

        XCTAssertEqual(session.activeTabID(inWindow: first), tabs.0)
        XCTAssertEqual(session.activeTabID(inWindow: second), tabs.1)
        XCTAssertEqual(
            session.tabs(inWindow: first).map(\.id),
            session.tabs(inWindow: second).map(\.id),
            "the two windows are looking at one tab list"
        )
    }

    /// An unqualified question is about the window the user is in, which is
    /// what makes every command in `BrowserCommands` correct without being
    /// told which window it is running in.
    func testTheUnqualifiedAnswerIsTheFrontWindows() async throws {
        let session = try await session()
        let (first, second) = try twoWindows(on: session)
        let tabs = try twoTabs(in: session)
        session.activateTab(tabs.0, inWindow: first)
        session.activateTab(tabs.1, inWindow: second)

        session.setKeyWindow(first)
        XCTAssertEqual(session.activeTabID, tabs.0)
        session.setKeyWindow(second)
        XCTAssertEqual(session.activeTabID, tabs.1)
    }

    /// A new window opens where the one it came out of is standing, with
    /// nothing selected — the same state a cold launch leaves (§19.4).
    func testANewWindowOpensOnTheFrontWindowsSpaceShowingNothing() async throws {
        let session = try await session()
        let first = try window(on: session)
        let tabs = try twoTabs(in: session)
        session.activateTab(tabs.0, inWindow: first)
        session.setKeyWindow(first)

        let second = UUID()
        session.openWindow(second)
        XCTAssertEqual(session.activeSpaceID(inWindow: second), session.activeSpaceID(inWindow: first))
        XCTAssertNil(session.activeTabID(inWindow: second), "a new window selects nothing")
    }

    /// Two windows in two Spaces draw two columns.
    func testAWindowFollowsItsOwnSpace() async throws {
        let session = try await session()
        let (first, second) = try twoWindows(on: session)
        _ = try twoTabs(in: session)
        let other = try await session.createSpace(name: "Work").id

        session.switchSpace(other, inWindow: second)

        XCTAssertNotEqual(session.activeSpaceID(inWindow: first), session.activeSpaceID(inWindow: second))
        XCTAssertFalse(session.tabs(inWindow: first).isEmpty)
        XCTAssertTrue(session.tabs(inWindow: second).isEmpty, "the new Space has no tabs in it")
    }

    // MARK: - A tab going away

    /// The one that is invisible from the front: a tab closed in one window
    /// must stop being selected in the other, or that window puts the page
    /// back on screen the moment it comes forward.
    func testClosingATabReleasesItInEveryWindow() async throws {
        let session = try await session()
        let (first, second) = try twoWindows(on: session)
        let tabs = try twoTabs(in: session)
        session.activateTab(tabs.0, inWindow: first)
        session.activateTab(tabs.0, inWindow: second)

        session.setKeyWindow(first)
        session.closeTab(tabs.0)

        XCTAssertNotEqual(session.activeTabID(inWindow: second), tabs.0)
        XCTAssertNotEqual(session.activeTabID(inWindow: first), tabs.0)
    }

    /// A window that has gone takes its place with it, and hands the front on
    /// rather than leaving the session pointing at nothing.
    func testAClosedWindowIsForgotten() async throws {
        let session = try await session()
        let (first, second) = try twoWindows(on: session)
        let tabs = try twoTabs(in: session)
        session.activateTab(tabs.1, inWindow: second)
        session.setKeyWindow(second)

        session.closeWindow(second)

        XCTAssertEqual(session.keyWindowID, first)
        XCTAssertNil(session.commandBar(inWindow: second), "the closed window's bar is still wired in")
    }

    // MARK: - §5.6

    /// Every Space in a private session shares one jar, and it is not one that
    /// exists on disk.
    func testAPrivateSessionNeverAsksForAJarOnDisk() async throws {
        let session = try await session(isPrivate: true)
        let first = try XCTUnwrap(session.spaces.first)
        let other = try await session.createSpace(name: "Second").id

        let jar = session.dataStore(forSpace: first.id)
        XCTAssertFalse(jar.isPersistent)
        XCTAssertTrue(jar === session.dataStore(forSpace: other), "two jars where the window has one")
    }

    /// An ordinary session still gets a jar per Space (§5.1) — the branch above
    /// is the exception and must not have become the rule.
    func testAnOrdinarySessionStillGetsAJarPerSpace() async throws {
        let session = try await session()
        let first = try XCTUnwrap(session.spaces.first)
        XCTAssertTrue(session.dataStore(forSpace: first.id).isPersistent)
    }

    /// A window that leaves a note of which Space it was in is not private,
    /// however little the note says.
    func testAPrivateSessionWritesNoNoteOfWhereItWas() async throws {
        let key = "luna.activeSpaceID"
        let before = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(before, forKey: key) }

        let session = try await session(isPrivate: true)
        let other = try await session.createSpace(name: "Second").id
        session.switchSpace(other)

        XCTAssertEqual(UserDefaults.standard.string(forKey: key), before)
    }

    // MARK: - Fixtures

    private func session(isPrivate: Bool = false) async throws -> BrowserSession {
        let store = try BrowserStore(path: directory.appending(path: "\(UUID().uuidString).sqlite"))
        return try await BrowserSession.restored(store: store, isPrivate: isPrivate)
    }

    private func window(on session: BrowserSession) throws -> UUID {
        let id = UUID()
        session.openWindow(id)
        return id
    }

    private func twoWindows(on session: BrowserSession) throws -> (UUID, UUID) {
        (try window(on: session), try window(on: session))
    }

    /// Two loose tabs in the seeded Space, made without waking either.
    private func twoTabs(in session: BrowserSession) throws -> (UUID, UUID) {
        let space = try XCTUnwrap(session.spaces.first).id
        let tabs = (0 ..< 2).map { index in
            Tab(
                spaceID: space,
                kind: .today,
                url: URL(string: "https://example.com/\(index)")!,
                title: "Tab \(index)",
                order: index
            )
        }
        for tab in tabs { session.persistAll(session.list.insert(tab)) }
        return (tabs[0].id, tabs[1].id)
    }
}
