//
//  MediaCommandsTests.swift
//  LunaTests
//
//  §18.4a: Mute All Tabs and Unmute All Tabs, and which tab holds the Mac's
//  play/pause keys.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class MediaCommandsTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Mute All

    /// Every awake tab, and not the cold one: it makes no sound, and a mute
    /// answers the noise happening now.
    func testMuteAllMutesEveryAwakeTab() async throws {
        let session = try await makeSession()
        let first = try tab(in: session), second = try tab(in: session), cold = try tab(in: session)
        session.activateTab(first)
        session.activateTab(second)
        XCTAssertTrue(session.canMuteAllTabs)

        session.muteAllTabs()

        XCTAssertTrue(session.isMuted(first))
        XCTAssertTrue(session.isMuted(second))
        XCTAssertEqual(session.controller(for: second)?.isMuted, true, "the page was not told")
        XCTAssertFalse(session.isMuted(cold))
        XCTAssertFalse(session.canMuteAllTabs)
    }

    func testUnmuteAllLetsEveryMutedTabSpeak() async throws {
        let session = try await makeSession()
        let first = try tab(in: session), second = try tab(in: session)
        session.activateTab(first)
        session.activateTab(second)
        session.setMuted(true, tab: first)
        session.muteAllTabs()

        session.unmuteAllTabs()

        XCTAssertTrue(session.mutedTabIDs.isEmpty)
        XCTAssertEqual(session.controller(for: first)?.isMuted, false)
    }

    func testBothCommandsAreInTheViewMenuAndTheBar() throws {
        let view = try XCTUnwrap(NSApp.mainMenu?.items.first { $0.submenu?.title == "View" }?.submenu)
        let titles = view.items.map(\.title)
        XCTAssertTrue(titles.contains("Mute All Tabs"))
        XCTAssertTrue(titles.contains("Unmute All Tabs"))
        XCTAssertNotNil(BrowserCommand.muteAllTabs.symbolName)
        XCTAssertNotNil(BrowserCommand.unmuteAllTabs.symbolName)
    }

    func testTheToastSaysWhichWayItWent() {
        XCTAssertEqual(PageToast.allTabs(muted: true).text, "All tabs muted")
        XCTAssertEqual(PageToast.allTabs(muted: false).text, "All tabs unmuted")
    }

    // MARK: - Now Playing

    /// The tab that played last holds the keys through its pause, gives them
    /// up to the next tab that plays, and lets go when its page changes.
    func testTheLastTabToPlayHoldsTheKeys() async throws {
        let session = try await makeSession()
        let first = try tab(in: session), second = try tab(in: session)

        session.noteNowPlaying(first, TabState(isPlayingAudio: true, hasPlayedAudio: true))
        XCTAssertEqual(session.nowPlayingTabID, first)
        session.noteNowPlaying(first, TabState(isPlayingAudio: false, hasPlayedAudio: true))
        XCTAssertEqual(session.nowPlayingTabID, first, "a pause gave the keys away")

        session.noteNowPlaying(second, TabState(isPlayingAudio: true, hasPlayedAudio: true))
        XCTAssertEqual(session.nowPlayingTabID, second)
        session.noteNowPlaying(first, TabState(isPlayingAudio: false, hasPlayedAudio: false))
        XCTAssertEqual(session.nowPlayingTabID, second, "another tab's new page took the keys back")

        session.noteNowPlaying(second, TabState(isPlayingAudio: false, hasPlayedAudio: false))
        XCTAssertNil(session.nowPlayingTabID)
    }

    // MARK: - Helpers

    private func tab(in session: BrowserSession) throws -> UUID {
        let space = try XCTUnwrap(session.spaces.first)
        let tab = Tab(spaceID: space.id, kind: .today, url: URL(string: "https://example.invalid/\(UUID())")!)
        session.persistAll(session.list.insert(tab, at: TabList.openIndex(for: .today)))
        return tab.id
    }

    private func makeSession() async throws -> BrowserSession {
        try await BrowserSession.restored(store: BrowserStore(path: directory.appending(path: "luna.sqlite")))
    }
}
