//
//  CommentFlowTests+Region.swift
//  LunaTests
//
//  A press and drag in comment mode: the region comment it makes, its crop
//  and context picture, and the note beside it. A file of its own only for
//  SwiftLint's length limits; the fixture is `CommentFlowTests`'s.
//

import AppKit
@testable import BrowserKit
import XCTest
@testable import Luna

extension CommentFlowTests {

    /// Round `#near`, which sits at 40,60 and is 100 × 40.
    private static let nearDrag = ((20.0, 40.0), (160.0, 120.0))

    func testADragBecomesARegionComment() async throws {
        delegate.toggleCommenting(nil)
        try await region(from: Self.nearDrag.0, to: Self.nearDrag.1)
        let comment = try XCTUnwrap(set.comments.first)

        XCTAssertEqual(comment.kind, .region)
        let region = try XCTUnwrap(comment.region)
        XCTAssertEqual(region.box, PageElement.Box(x: 20, y: 40, width: 140, height: 80))
        XCTAssertEqual(region.contents.map(\.selector), ["#near"])
        XCTAssertEqual(region.contents.map(\.text), ["Save"])
        XCTAssertEqual(comment.element.tag, "body", "the container is not what holds the area")
    }

    func testTheRegionCropIsExactlyTheRectangle() async throws {
        delegate.toggleCommenting(nil)
        try await region(from: Self.nearDrag.0, to: Self.nearDrag.1)
        let comment = try XCTUnwrap(set.comments.first)
        let scale = try XCTUnwrap(controller.window?.backingScaleFactor)
        let size = try pixels(of: comment.image)

        XCTAssertEqual(size.width, Int((140 * scale).rounded()))
        XCTAssertEqual(size.height, Int((80 * scale).rounded()))
    }

    func testALargeRegionKeepsTheLongSideCap() async throws {
        controller.window?.setContentSize(NSSize(width: 2200, height: 1000))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let read = try await tab.webView?.evaluateJavaScript("[innerWidth, innerHeight]") as? [Double]
        let viewport = try XCTUnwrap(read)
        XCTAssertGreaterThan(
            viewport[0] - 2, 1600, "the viewport is too small to reach the cap at any scale: window "
                + "\(String(describing: controller.window?.frame)), screens \(NSScreen.screens.map(\.frame))"
        )
        delegate.toggleCommenting(nil)
        try await region(from: (1, 1), to: (viewport[0] - 1, viewport[1] - 1))
        let comment = try XCTUnwrap(set.comments.first)
        let box = try XCTUnwrap(comment.region?.box)
        let size = try pixels(of: comment.image)

        XCTAssertEqual(max(size.width, size.height), 1600)
        XCTAssertEqual(Double(size.height), (box.height * 1600 / box.width).rounded(), accuracy: 1)
    }

    func testTheRegionContextPictureFollowsTheLocalRule() async throws {
        delegate.toggleCommenting(nil)
        try await region(from: Self.nearDrag.0, to: Self.nearDrag.1)
        let context = try XCTUnwrap(set.comments.first?.context, "a file: page is local")
        XCTAssertGreaterThan(try pixels(of: context).width, 0)

        // An empty note's comment goes as the next one is made.
        try XCTUnwrap(window.comments?.note).textView.string = "Line them up"
        window.comments?.isLocal = { _ in false }
        try await region(from: (20, 180), to: (360, 320))
        XCTAssertEqual(set.comments.count, 2)
        XCTAssertNil(set.comments.last?.context, "a live site's region got the viewport picture")
    }

    func testTheNoteOpensBesideTheRegion() async throws {
        delegate.toggleCommenting(nil)
        try await region(from: Self.nearDrag.0, to: Self.nearDrag.1)
        let field = try XCTUnwrap(window.comments?.note)
        let webView = try XCTUnwrap(tab.webView)
        let y = webView.isFlipped ? 40 : webView.bounds.height - 40 - 80
        let rect = controller.controlSurface.convert(CGRect(x: 20, y: y, width: 140, height: 80), from: webView)

        XCTAssertEqual(field.frame.minX, rect.maxX + Tokens.Metric.chromeGap, accuracy: 0.5)
        XCTAssertEqual(field.frame.minY, rect.minY, accuracy: 0.5)
    }

    func testAFailedRegionCaptureSaysArea() async throws {
        delegate.toggleCommenting(nil)
        window.comments?.frame = { _, _ in throw CocoaError(.fileWriteUnknown) }
        try await drag(from: Self.nearDrag.0, to: Self.nearDrag.1)
        let surface = controller.controlSurface
        try await waitFor { surface.toast?.text == PageToast.areaNotCaptured.text }
        XCTAssertTrue(set.comments.isEmpty)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: set.folder.path)) ?? []
        XCTAssertEqual(files.filter { $0.hasSuffix(".png") }, [])
    }

    // MARK: - Support

    /// A drag as the picker hears one, then the comment and field it makes.
    private func region(from start: (Double, Double), to end: (Double, Double)) async throws {
        let before = set.comments.count
        try await drag(from: start, to: end)
        try await waitFor { self.set.comments.count > before && self.window.comments?.note != nil }
    }

    private func drag(from start: (Double, Double), to end: (Double, Double)) async throws {
        let steps = [("pointerdown", start), ("pointermove", end), ("pointerup", end)]
        let events = steps.map { kind, point in
            "document.dispatchEvent(new PointerEvent('\(kind)', { bubbles: true, cancelable: true, "
                + "clientX: \(point.0), clientY: \(point.1), button: 0, buttons: \(kind == "pointerup" ? 0 : 1) }));"
        }
        _ = try await tab.webView?.evaluateJavaScript(events.joined(separator: "\n") + " 1")
    }
}
