//
//  WindowDropTests.swift
//  LunaTests
//
//  A file or a link dropped on the window anywhere but the page: what is taken,
//  and that the two views that take it hand it on.
//

import AppKit
import XCTest
@testable import Luna

/// Only the pasteboard and the source's operations are read by a drop, so
/// the rest answers with nothing.
@MainActor
private final class Drag: NSObject, @MainActor NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingSourceOperationMask: NSDragOperation

    init(_ urls: [URL], offering mask: NSDragOperation = [.copy, .link, .generic]) {
        draggingPasteboard = NSPasteboard(name: NSPasteboard.Name("WindowDropTests-\(UUID().uuidString)"))
        draggingPasteboard.clearContents()
        draggingPasteboard.writeObjects(urls.map { $0 as NSURL })
        draggingSourceOperationMask = mask
    }

    init(text: String) {
        draggingPasteboard = NSPasteboard(name: NSPasteboard.Name("WindowDropTests-\(UUID().uuidString)"))
        draggingPasteboard.clearContents()
        draggingPasteboard.setString(text, forType: .string)
        draggingSourceOperationMask = [.copy, .link, .generic]
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions = [],
        for view: NSView?,
        classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}

@MainActor
final class WindowDropTests: XCTestCase {

    private let page = URL(fileURLWithPath: "/Users/someone/page.html")
    private let photo = URL(fileURLWithPath: "/Users/someone/photo.png")
    private let archive = URL(fileURLWithPath: "/Users/someone/stuff.zip")
    private let link = URL(string: "https://example.com/")!

    /// What Finder's Open With takes, in the order it was dragged.
    func testTakesWhatOpenWithTakesInOrder() {
        let mail = URL(string: "mailto:someone@example.com")!
        let drag = Drag([photo, archive, mail, link, page])
        XCTAssertEqual(WindowDrop.pages(on: drag.draggingPasteboard), [photo, link, page])
    }

    /// A list of links selected in a note: each line is a page.
    func testTextWithOneLinkPerLineDropsAsThoseLinks() {
        XCTAssertTrue(WindowDrop.types.contains(.string))
        let drag = Drag(text: "https://a.example/\nexample.org")
        XCTAssertEqual(
            WindowDrop.pages(on: drag.draggingPasteboard),
            [URL(string: "https://a.example/")!, URL(string: "https://example.org")!]
        )
        XCTAssertEqual(WindowDrop.operation(for: drag), .copy)
    }

    func testTextWithNoLinksIsRefused() {
        XCTAssertEqual(WindowDrop.operation(for: Drag(text: "just some words")), [])
    }

    /// No badge for a drag holding nothing Luna opens; otherwise the first
    /// operation the source offers of copy, link and generic.
    func testOperation() {
        XCTAssertEqual(WindowDrop.operation(for: Drag([archive])), [])
        XCTAssertEqual(WindowDrop.operation(for: Drag([page])), .copy)
        XCTAssertEqual(WindowDrop.operation(for: Drag([page], offering: [.link, .move])), .link)
        XCTAssertEqual(WindowDrop.operation(for: Drag([page], offering: .move)), [])
    }

    func testTheChromeTakesADropOnceItHasSomewhereToOpenIt() {
        let chrome = ChromeHostView()
        XCTAssertTrue(chrome.registeredDraggedTypes.isEmpty)
        XCTAssertFalse(chrome.performDragOperation(Drag([page])))

        var opened: [URL] = []
        chrome.onDropPages = { opened += $0 }
        XCTAssertEqual(Set(chrome.registeredDraggedTypes), Set(WindowDrop.types))
        XCTAssertEqual(chrome.draggingEntered(Drag([page, link])), .copy)
        XCTAssertTrue(chrome.performDragOperation(Drag([page, link])))
        XCTAssertFalse(chrome.performDragOperation(Drag([archive])))
        XCTAssertEqual(opened, [page, link])

        chrome.onDropPages = nil
        XCTAssertTrue(chrome.registeredDraggedTypes.isEmpty)
    }

    func testTheCardTakesADropOnceItHasSomewhereToOpenIt() {
        let card = ContentCardView()
        XCTAssertTrue(card.registeredDraggedTypes.isEmpty)

        var opened: [URL] = []
        card.onDropPages = { opened += $0 }
        XCTAssertEqual(Set(card.registeredDraggedTypes), Set(WindowDrop.types))
        XCTAssertEqual(card.draggingEntered(Drag([photo])), .copy)
        XCTAssertTrue(card.performDragOperation(Drag([photo])))
        XCTAssertEqual(opened, [photo])
    }
}
