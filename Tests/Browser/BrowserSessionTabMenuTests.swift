//
//  BrowserSessionTabMenuTests.swift
//  LunaTests
//
//  §3.4a's four verbs, and the menu that spells them.
//
//  The two worth asserting hardest are the ones where nil and the empty string are
//  different answers. A rename to `""` means "give the name back to the page" and must not
//  be stored, or the row would override the page's title with nothing forever; a rename to
//  a name must survive the page changing its own title, which is the entire point of it.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class BrowserSessionTabMenuTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Duplicate

    func testDuplicateOpensASecondTabOnTheSamePage() async throws {
        let session = try await makeSession()
        let original = try tab(in: session, at: url("one"))

        let copy = try XCTUnwrap(session.duplicateTab(original))

        XCTAssertNotEqual(copy, original)
        XCTAssertEqual(session.tab(copy)?.url, url("one"))
        XCTAssertEqual(session.tab(copy)?.parentTabID, original, "a duplicate came from somewhere")
        XCTAssertEqual(session.activeTabID, copy, "the copy is the tab you are now on")
    }

    /// The whole reason to duplicate rather than open the address again: the trail you are
    /// on comes with you.
    func testDuplicateCarriesTheBackForwardHistory() async throws {
        let session = try await makeSession()
        let original = try tab(in: session, at: url("one"))
        var walked = try XCTUnwrap(session.tab(original))
        walked.interactionState = Data([4, 5, 6])
        session.write(walked)

        let copy = try XCTUnwrap(session.duplicateTab(original))

        XCTAssertEqual(session.tab(copy)?.interactionState, Data([4, 5, 6]))
    }

    func testDuplicateLandsDirectlyBelowTheTabItCameFrom() async throws {
        let session = try await makeSession()
        let first = try tab(in: session, at: url("one"))
        let second = try tab(in: session, at: url("two"))

        let copy = try XCTUnwrap(session.duplicateTab(second))

        let today = session.tabs.filter { $0.kind == .today }.map(\.id)
        let position = try XCTUnwrap(today.firstIndex(of: second))
        XCTAssertEqual(today[position + 1], copy)
        XCTAssertTrue(today.contains(first))
    }

    /// A tile is a place the user put something, capped at twelve per Profile. A second
    /// copy of one is a page you want open now.
    func testDuplicatingATileGivesAnOrdinaryTab() async throws {
        let session = try await makeSession()
        let tile = try tab(in: session, at: url("tile"))
        XCTAssertTrue(session.pinTab(tile))

        let copy = try XCTUnwrap(session.duplicateTab(tile))

        XCTAssertEqual(session.tab(copy)?.kind, .today)
        XCTAssertEqual(session.tab(tile)?.kind, .essential, "the tile itself is untouched")
    }

    // MARK: - Rename

    func testRenameSurvivesThePageChangingItsOwnTitle() async throws {
        let session = try await makeSession()
        let id = try tab(in: session, at: url("one"))
        session.renameTab(id, to: "Invoices")

        var navigated = try XCTUnwrap(session.tab(id))
        navigated.title = "Untitled — example.com"
        session.write(navigated)

        XCTAssertEqual(session.tab(id)?.listTitle, "Invoices")
    }

    func testRenamingToNothingGivesTheNameBackToThePage() async throws {
        let session = try await makeSession()
        let id = try tab(in: session, at: url("one"))
        var titled = try XCTUnwrap(session.tab(id))
        titled.title = "Example"
        session.write(titled)
        session.renameTab(id, to: "Invoices")

        session.renameTab(id, to: "   ")

        XCTAssertNil(session.tab(id)?.customTitle, "blank is nil, never a stored empty string")
        XCTAssertEqual(session.tab(id)?.listTitle, "Example")
    }

    func testRenameIsUndoable() async throws {
        let session = try await makeSession()
        let id = try tab(in: session, at: url("one"))
        session.renameTab(id, to: "Invoices")

        session.undoManager.undo()

        XCTAssertNil(session.tab(id)?.customTitle)
    }

    // MARK: - Change Icon

    func testIconIsStoredAndCanBeGivenBack() async throws {
        let session = try await makeSession()
        let id = try tab(in: session, at: url("one"))

        session.setIcon("star", forTab: id)
        XCTAssertEqual(session.tab(id)?.customSymbolName, "star")

        session.setIcon(nil, forTab: id)
        XCTAssertNil(session.tab(id)?.customSymbolName, "nil is the way back to the favicon")
    }

    /// Every name the picker can produce has to resolve, or the tile and the row draw
    /// nothing at all and the user has no way to tell which of the six thousand it was.
    func testEveryOfferedSymbolExists() {
        for symbol in TabMenu.symbols {
            XCTAssertNotNil(
                NSImage(systemSymbolName: symbol.name, accessibilityDescription: nil),
                "\(symbol.label) — \(symbol.name)"
            )
        }
    }

    // MARK: - Mute

    func testMuteSurvivesTheTabGoingCold() async throws {
        let session = try await makeSession()
        let id = try tab(in: session, at: url("one"))
        session.setMuted(true, tab: id)

        // §19.2 reclaiming the page, which throws the controller away entirely.
        session.discardController(id)
        session.activateTab(id)

        XCTAssertTrue(session.isMuted(id))
        XCTAssertEqual(session.controller(for: id)?.isMuted, true, "the new controller was told")
    }

    /// A mute is a fact about a page that is making a noise. A reopened tab is a new page.
    func testClosingATabForgetsItsMute() async throws {
        let session = try await makeSession()
        let id = try tab(in: session, at: url("one"))
        session.setMuted(true, tab: id)

        session.closeTab(id)
        session.unarchiveTab(id)

        XCTAssertFalse(session.isMuted(id))
    }

    // MARK: - The menu itself

    /// The reference's order and the reference's five groups, which is what "the same UI"
    /// meant. Asserted as a list because it is the one thing about this surface a reader
    /// can check against the screenshot without running the app.
    func testMenuIsTheReferenceOrder() async throws {
        let session = try await makeSession()
        let id = try tab(in: session, at: url("one"))
        let menu = TabMenu.build(for: try XCTUnwrap(session.tab(id)), isMuted: false, actions: noActions)

        XCTAssertEqual(menu.items.map(Self.word), [
            "Pin", "Save Tab", "", "Add to Folder", "", "Duplicate", "",
            "Copy Link", "", "Rename…", "Change Icon…", "Mute Site", "", "Close"
        ])
        XCTAssertEqual(menu.items.filter(\.isSeparatorItem).count, 5)
    }

    /// §3.4b's two items are not on a §3.3 tile: a tile is already kept by a tier that
    /// keeps it harder, and a folder may not be pinned at all, so both would be offers to
    /// demote it.
    func testATileIsNotOfferedSavingOrGrouping() async throws {
        let session = try await makeSession()
        let id = try tab(in: session, at: url("one"))
        XCTAssertTrue(session.pinTab(id))
        let menu = TabMenu.build(for: try XCTUnwrap(session.tab(id)), isMuted: false, actions: noActions)

        XCTAssertFalse(menu.items.contains { Self.word($0) == "Save Tab" })
        XCTAssertFalse(menu.items.contains { Self.word($0) == "Add to Folder" })
    }

    /// A saved tab is offered the way back out, and one already in a folder is offered a
    /// move rather than an add — the item says which act it is.
    func testTheWordingFollowsWhereTheTabAlreadyIs() async throws {
        let session = try await makeSession()
        let id = try tab(in: session, at: url("one"))
        session.setTabSaved(true, tab: id)
        let saved = try XCTUnwrap(session.tab(id))
        XCTAssertTrue(TabMenu.build(for: saved, isMuted: false, actions: noActions).items
            .contains { Self.word($0) == "Remove from Saved" })

        let group = TabGroup(spaceID: saved.spaceID, name: "Work")
        let moving = TabMenu.build(for: saved, isMuted: false, group: group, actions: noActions)
        XCTAssertTrue(moving.items.contains { Self.word($0) == "Move to Folder" })
    }

    func testMenuSaysUnpinOnATileAndUnmuteOnAMutedTab() async throws {
        let session = try await makeSession()
        let id = try tab(in: session, at: url("one"))
        XCTAssertTrue(session.pinTab(id))
        let menu = TabMenu.build(for: try XCTUnwrap(session.tab(id)), isMuted: true, actions: noActions)

        XCTAssertEqual(menu.items.first.map(Self.word), "Unpin")
        XCTAssertTrue(menu.items.contains { Self.word($0) == "Unmute Site" })
    }

    // MARK: - Helpers

    /// An item's word, without the glyph in front of it.
    ///
    /// `NSMenuItem.title` reports the `attributedTitle`'s string once one is set, and
    /// §3.4a's glyph rides in there as an attachment character followed by the tab that
    /// lines the words up — so the title comes back as `"\u{FFFC}\tPin"`. Everything
    /// before the tab is the icon.
    private static func word(_ item: NSMenuItem) -> String {
        item.title.split(separator: "\t", maxSplits: 1).last.map(String.init) ?? item.title
    }

    private var noActions: TabMenu.Actions {
        TabMenu.Actions(
            pin: {}, unpin: {}, setSaved: { _ in }, setGroup: { _ in }, newGroup: {},
            duplicate: {}, rename: { _ in }, setIcon: { _ in }, setMuted: { _ in }, close: {}
        )
    }

    @discardableResult
    private func tab(in session: BrowserSession, at address: URL) throws -> UUID {
        let space = try XCTUnwrap(session.spaces.first)
        let tab = Tab(spaceID: space.id, kind: .today, url: address)
        session.persistAll(session.list.insert(tab, at: TabList.openIndex(for: .today)))
        return tab.id
    }

    private func makeSession() async throws -> BrowserSession {
        try await BrowserSession.restored(store: BrowserStore(path: directory.appending(path: "luna.sqlite")))
    }

    private func url(_ path: String) -> URL {
        URL(string: "https://example.com/\(path)")!
    }
}
