//
//  CommentSetTests.swift
//  LunaTests
//
//  The comments not yet exported: kept in `draft.json` so a relaunch loses
//  none, and undoable step by step. Every folder is a temporary one.
//

@testable import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class CommentSetTests: XCTestCase {

    private var base: URL!
    private var draft: URL { base.appending(path: "Comment Draft") }
    private var undo: UndoManager!

    override func setUpWithError() throws {
        base = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: draft, withIntermediateDirectories: true)
        undo = UndoManager()
        // One step per change, as a menu command would make it, without a run loop to close the groups.
        undo.groupsByEvent = false
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func set() -> CommentSet { CommentSet(folder: draft, undoManager: undo) }

    /// A comment whose pictures are already in the draft, as capture leaves them.
    private func captured(_ note: String = "Make it taller") throws -> Comment {
        let comment = Comment.fixture(note: note)
        for name in [comment.image, comment.context].compactMap(\.self) {
            try Data("png".utf8).write(to: draft.appending(path: name))
        }
        return comment
    }

    private func onDisk() throws -> [Comment] {
        try JSONDecoder().decode([Comment].self, from: Data(contentsOf: draft.appending(path: "draft.json")))
    }

    func testAddingWritesTheDraft() throws {
        let comments = set()
        let comment = try captured()
        comments.add(comment)

        XCTAssertEqual(comments.comments, [comment])
        XCTAssertEqual(try onDisk(), [comment])
    }

    func testAFreshSetRestoresTheDraftAndSweepsPicturesNothingNames() throws {
        let first = set()
        let comment = try captured()
        first.add(comment)
        try Data("png".utf8).write(to: draft.appending(path: "orphan.png"))

        let restored = set()

        XCTAssertEqual(restored.comments, [comment])
        XCTAssertFalse(FileManager.default.fileExists(atPath: draft.appending(path: "orphan.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: draft.appending(path: comment.image).path))
    }

    func testDeleteThenUndoBringsBackTheNoteAndItsPictures() throws {
        let comments = set()
        let comment = try captured("Drop the shadow")
        comments.add(comment)
        comments.delete(comment.id)
        XCTAssertEqual(comments.comments, [])
        XCTAssertEqual(try onDisk(), [])

        undo.undo()

        XCTAssertEqual(comments.comments.map(\.note), ["Drop the shadow"])
        XCTAssertEqual(try onDisk(), [comment])
        for name in [comment.image, comment.context].compactMap(\.self) {
            XCTAssertTrue(FileManager.default.fileExists(atPath: draft.appending(path: name).path), name)
        }

        undo.redo()
        XCTAssertEqual(comments.comments, [])
    }

    func testEditingTheNoteIsOneStepAndAnEmptyNoteDeletes() throws {
        let comments = set()
        let comment = try captured("Taller")
        comments.add(comment)
        comments.setNote("Shorter", of: comment.id)
        XCTAssertEqual(try onDisk().map(\.note), ["Shorter"])

        undo.undo()
        XCTAssertEqual(comments.comments.map(\.note), ["Taller"])

        comments.setNote("", of: comment.id)
        XCTAssertEqual(comments.comments, [])
    }

    /// `draft.json` in the shape comment mode wrote before regions.
    func testADraftFromBeforeRegionsStillLoads() throws {
        let id = UUID().uuidString
        let old = """
        [{"id":"\(id)","note":"Drop the shadow","created":800000000,"origin":"localhost-3002",
          "page":{"url":"http://localhost:3002/orders","viewportWidth":1440,"dark":true,"scrollX":0,"scrollY":312},
          "element":{"selector":"button.btn","matches":1,"tag":"button","text":"New order",
            "html":"<button class=\\"btn\\">New order</button>","heading":"Orders","landmark":"header",
            "siblings":["Search orders"],"box":{"x":10,"y":20,"width":132,"height":36}},
          "image":"\(id).png","context":null}]
        """
        try Data(old.utf8).write(to: draft.appending(path: "draft.json"))

        let restored = set().comments
        XCTAssertEqual(restored.map(\.note), ["Drop the shadow"])
        XCTAssertEqual(restored.first?.kind, .element)
        XCTAssertNil(restored.first?.region)
    }

    func testARegionCommentRoundTripsThroughTheDraft() throws {
        var comment = try captured("Line the cards up")
        comment.region = PageRegion(
            box: .init(x: 60, y: 30, width: 430, height: 100),
            contents: [.init(tag: "article", text: "Plan 2 Start", html: #"<article class="card">"#, selector: "article.card",
                             box: .init(x: 140, y: 40, width: 100, height: 80))],
            more: 3
        )
        set().add(comment)

        let restored = set().comments
        XCTAssertEqual(restored, [comment])
        XCTAssertEqual(restored.first?.kind, .region)
    }

    func testClearingAfterExportIsOneUndoStep() throws {
        let comments = set()
        let first = try captured("One"), second = try captured("Two")
        comments.add(first)
        comments.add(second)

        let written = try comments.export(to: base.appending(path: "Comments"))

        XCTAssertEqual(Array(written.keys), ["localhost-3002"])
        XCTAssertEqual(comments.comments, [])
        XCTAssertEqual(try onDisk(), [])

        undo.undo()
        XCTAssertEqual(comments.comments, [first, second])
        XCTAssertEqual(try onDisk(), [first, second])
    }
}
