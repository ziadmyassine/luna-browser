//
//  FolderEmojiTests.swift
//  LunaTests
//
//  §3.4b: a folder named and never given an icon takes the emoji its name
//  suggests, and one the user chose is never replaced.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class FolderEmojiTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-folder-emoji-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Reading a name

    func testTheThingANameIsAboutPicksItsEmoji() {
        XCTAssertEqual(FolderEmoji.suggestion(for: "Running shoes"), "👟")
        XCTAssertEqual(FolderEmoji.suggestion(for: "Gaming"), "🎮")
        XCTAssertEqual(FolderEmoji.suggestion(for: "Work"), "💼")
        XCTAssertEqual(FolderEmoji.suggestion(for: "Recipes"), "🍳")
        XCTAssertEqual(FolderEmoji.suggestion(for: "Trip to Rome"), "✈️")
    }

    /// Word forms find the topic: "running" files under "run".
    func testWordFormsAreReadAsTheirTopic() {
        XCTAssertEqual(FolderEmoji.suggestion(for: "Running"), "🏃")
        XCTAssertEqual(FolderEmoji.suggestion(for: "Cats"), "🐱")
    }

    func testDanishNamesAreRead() {
        XCTAssertEqual(FolderEmoji.suggestion(for: "Skole"), "🏫")
        XCTAssertEqual(FolderEmoji.suggestion(for: "Opskrifter"), "🍳")
    }

    /// A word the short list does not know still finds an emoji named for it.
    func testUnicodeNamesFillTheGaps() {
        XCTAssertEqual(FolderEmoji.suggestion(for: "Volcano"), "🌋")
    }

    func testAnEmojiInTheNameIsTakenAsItIs() {
        XCTAssertEqual(FolderEmoji.suggestion(for: "🦊 Foxes"), "🦊")
    }

    /// A name that says nothing about a topic keeps the folder symbol.
    func testANameWithNoTopicGetsNoGuess() {
        XCTAssertNil(FolderEmoji.suggestion(for: "What is up my g"))
        XCTAssertNil(FolderEmoji.suggestion(for: BrowserSession.untitledGroupName))
        XCTAssertNil(FolderEmoji.suggestion(for: "Qwzx"))
    }

    // MARK: - Naming a folder

    private func session() async throws -> BrowserSession {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        try await store.seedIfEmpty()
        return try await BrowserSession.restored(store: store)
    }

    func testNamingANewFolderGivesItAnEmoji() async throws {
        let session = try await session()
        let id = try XCTUnwrap(session.createGroup(name: BrowserSession.untitledGroupName))
        XCTAssertEqual(session.list.group(id)?.symbolName, TabGroup.defaultSymbolName)
        session.renameGroup(id, to: "Gaming")
        XCTAssertEqual(session.list.group(id)?.symbolName, "🎮")
    }

    /// Luna's guess follows the name; the user's own icon stays.
    func testAGuessFollowsARenameAndAChoiceDoesNot() async throws {
        let session = try await session()
        let id = try XCTUnwrap(session.createGroup(name: "Gaming"))
        session.renameGroup(id, to: "Gaming nights")
        session.renameGroup(id, to: "Recipes")
        XCTAssertEqual(session.list.group(id)?.symbolName, "🍳")

        session.setIcon("star", forGroup: id)
        session.renameGroup(id, to: "Work")
        XCTAssertEqual(session.list.group(id)?.symbolName, "star", "the user's icon was replaced")
    }
}
