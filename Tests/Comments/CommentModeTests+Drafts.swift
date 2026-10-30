//
//  CommentModeTests+Drafts.swift
//  LunaTests
//
//  One draft per page and an export folder per export: two pages of one
//  site keep their notes apart, across a relaunch, and no export replaces
//  another. Apart from `CommentModeTests.swift` for its length limit.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
extension CommentModeTests {

    /// Each export's prompt names its own folder, and the first is still whole after the second.
    func testASecondExportOfTheSamePageKeepsTheFirst() async throws {
        try await open(page())
        let set = try comments(2)
        _ = delegate.exportComments(to: bundles, pasteboard: pasteboard)
        let first = try XCTUnwrap(pasteboard.string(forType: .string))
        try add(to: set)

        _ = delegate.exportComments(to: bundles, pasteboard: pasteboard)

        let written = try exported()
        XCTAssertEqual(written.count, 2)
        XCTAssertNotEqual(pasteboard.string(forType: .string), first)
        XCTAssertEqual(try files(in: written[0]).filter { $0.hasSuffix(".png") }.count, 4)
        XCTAssertEqual(try files(in: written[1]).filter { $0.hasSuffix(".png") }.count, 2)
    }

    /// Two tabs on two pages of one site: two drafts, each still there after a relaunch.
    func testTwoPagesKeepTwoDraftsAcrossARelaunch() throws {
        let one = try page(), two = try page("other.html")
        try add("Taller", to: XCTUnwrap(delegate.commentSet(for: one)))
        try add("Wider", to: XCTUnwrap(delegate.commentSet(for: two)))
        XCTAssertFalse(try XCTUnwrap(delegate.commentSet(for: one)) === delegate.commentSet(for: two))

        let relaunched = AppDelegate()
        relaunched.commentDrafts = drafts

        XCTAssertEqual(try XCTUnwrap(relaunched.commentSet(for: one)).comments.map(\.note), ["Taller"])
        XCTAssertEqual(try XCTUnwrap(relaunched.commentSet(for: two)).comments.map(\.note), ["Wider"])
    }

    /// A fragment scrolls the page it is on, so it is the same draft.
    func testAFragmentIsTheSamePage() throws {
        let url = try page()
        let anchored = try XCTUnwrap(URL(string: url.absoluteString + "#notes"))
        XCTAssertTrue(try XCTUnwrap(delegate.commentSet(for: url)) === delegate.commentSet(for: anchored))
    }

    /// The draft every page shared before is the draft of the page its comments were made on.
    func testTheSharedDraftFromBeforeBecomesThePagesDraft() async throws {
        let url = try page()
        let legacy = directory.appending(path: "Comment Draft")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let comment = Comment.fixture(origin: "file", url: url.absoluteString, note: "Kept")
        for name in [comment.image, comment.context].compactMap(\.self) {
            try Data("png".utf8).write(to: legacy.appending(path: name))
        }
        try JSONEncoder().encode([comment]).write(to: legacy.appending(path: "draft.json"))
        try await open(url)

        XCTAssertEqual(offered(), [true, true])
        XCTAssertEqual(delegate.commentSet(for: url)?.comments, [comment])
    }

    /// Every export folder under the `file` site, oldest first.
    func exported() throws -> [URL] {
        let site = bundles.appending(path: "file")
        return try FileManager.default.contentsOfDirectory(atPath: site.path).sorted().map { site.appending(path: $0) }
    }

    func files(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path)
    }
}
