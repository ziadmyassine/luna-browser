//
//  CommentFlowTests+Marker.swift
//  LunaTests
//
//  The selection marker that stays on what was picked while its note is
//  open, and never reaches a picture. A file of its own only for SwiftLint's
//  length limits; the fixture is `CommentFlowTests`'s.
//

import AppKit
@testable import BrowserKit
import ImageIO
import XCTest
@testable import Luna

extension CommentFlowTests {

    /// Round `#near`, which sits at 40,60; its top edge runs over the white page.
    private static let around = ((20.0, 40.0), (160.0, 120.0))

    /// After a drag and after a pick, the marker is on the comment's box; the second moves it.
    func testTheMarkerOpensWithTheNoteAndMovesToTheNextPick() async throws {
        try await enterCommenting()
        try await dragOut(from: Self.around.0, to: Self.around.1)
        try await assertMarked([20, 40, 140, 80], "no marker on the dragged area")
        try XCTUnwrap(window.comments?.note).textView.string = "Line them up"

        try await clickOut(x: "innerWidth - 58", y: "80")
        let box = try XCTUnwrap(set.comments.last?.element.box)
        try await assertMarked([box.x, box.y, box.width, box.height], "the marker did not move to the picked element")
    }

    /// The same area twice: the first area's marker is up when the second is cropped.
    func testTheCropNeverHoldsTheMarker() async throws {
        try await enterCommenting()
        try await dragOut(from: Self.around.0, to: Self.around.1)
        try await assertMarked([20, 40, 140, 80], "no marker to keep out of the crop")
        try XCTUnwrap(window.comments?.note).textView.string = "Line them up"
        try await dragOut(from: Self.around.0, to: Self.around.1)
        let crop = try XCTUnwrap(set.comments.last?.image)

        let row = try topRow(of: crop)
        XCTAssertFalse(row.isEmpty)
        XCTAssertTrue(row.allSatisfy { $0 == [255, 255, 255] }, "the crop's top edge is not the white page: \(Set(row))")
    }

    func testReturnAndEscapeInTheNoteTakeTheMarkerAway() async throws {
        try await enterCommenting()
        for command in [#selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:))] {
            try await clickOut(x: "90", y: "80")
            try await assertMarked([40, 60, 100, 40], "no marker before \(command)")
            try XCTUnwrap(window.comments?.note).textView.string = "Make it blue"
            XCTAssertTrue(try XCTUnwrap(window.comments?.note).handle(command, shift: false))
            try await assertMarked([], "\(command) left the marker up")
        }
    }

    // MARK: - Support

    /// The picker's script is put in asynchronously; a press before it lands goes to the page.
    private func enterCommenting() async throws {
        delegate.toggleCommenting(nil)
        for _ in 0 ..< 50 {
            let ready = try await tab.webView?.evaluateJavaScript(
                "!!window.__lunaPicker", in: nil, contentWorld: .defaultClient
            ) as? Bool
            if ready == true { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("the picker never started")
    }

    private func clickOut(x: String, y: String) async throws {
        let before = set.comments.count
        try await click(x: x, y: y)
        try await waitFor { self.set.comments.count > before && self.window.comments?.note != nil }
    }

    private func dragOut(from start: (Double, Double), to end: (Double, Double)) async throws {
        let before = set.comments.count
        let steps = [("pointerdown", start), ("pointermove", end), ("pointerup", end)]
        let events = steps.map { kind, point in
            "document.dispatchEvent(new PointerEvent('\(kind)', { bubbles: true, cancelable: true, "
                + "clientX: \(point.0), clientY: \(point.1), button: 0, buttons: \(kind == "pointerup" ? 0 : 1) }));"
        }
        _ = try await tab.webView?.evaluateJavaScript(events.joined(separator: "\n") + " 1")
        try await waitFor { self.set.comments.count > before && self.window.comments?.note != nil }
    }

    /// The marker is set asynchronously once the note opens, so this waits for it.
    private func assertMarked(_ wanted: [Double], _ message: String, line: UInt = #line) async throws {
        var marked: [Double]?
        for _ in 0 ..< 50 {
            marked = try await tab.webView?.evaluateJavaScript(
                "window.__lunaPicker.marked()", in: nil, contentWorld: .defaultClient
            ) as? [Double]
            if marked == wanted { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(marked, wanted, message, line: line)
    }

    /// The first row of a PNG in the draft, as 8-bit sRGB.
    private func topRow(of name: String) throws -> [[UInt8]] {
        let url = set.folder.appending(path: name)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var bytes = [UInt8](repeating: 0, count: image.width * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: image.width, height: 1, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 1 - image.height, width: image.width, height: image.height))
        }
        return stride(from: 0, to: bytes.count, by: 4).map { Array(bytes[$0 ..< $0 + 3]) }
    }
}
