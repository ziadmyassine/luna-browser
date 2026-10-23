//
//  CommentNoteViewTests.swift
//  LunaTests
//
//  The note field as it is drawn over a white and a black page in a dark
//  Luna: the appearance it settles on, its words against its plate, and the
//  edge that keeps the plate from vanishing into a page of its own colour.
//
//  The plate is popover glass, which AppKit will not render off screen, so
//  its fill is read as `Surface.raised` in the field's appearance: the solid
//  the same plate becomes under Reduce Transparency. Over a white page the
//  owner's screen measured the glass at #FDFDFD, a step lighter than that.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class CommentNoteViewTests: XCTestCase {

    func testTheFieldReadsOverAWhiteAndABlackPage() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 200), styleMask: [], backing: .buffered, defer: false)
        defer { window.close() }
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        let field = CommentNoteView(undoManager: UndoManager())
        window.contentView?.addSubview(field)

        for (page, wanted) in [(NSColor.white, NSAppearance.Name.aqua), (.black, .darkAqua)] {
            field.setPageColour(page)
            // The window is never on screen, so nothing draws it unless asked.
            field.subviews.forEach { $0.displayIfNeeded() }
            let appearance = field.effectiveAppearance
            XCTAssertEqual(appearance.name, wanted, "\(page)")
            let plate = Tokens.Surface.raised
            let text = try XCTUnwrap(field.textView.textColor)
            let placeholder = try XCTUnwrap(field.subviews.compactMap { $0 as? NSTextField }.first?.textColor)
            XCTAssertGreaterThanOrEqual(text.contrastRatio(over: plate, in: appearance), 4.5, "text over \(page)")
            XCTAssertGreaterThanOrEqual(placeholder.contrastRatio(over: plate, in: appearance), 3, "placeholder over \(page)")

            let backing = try XCTUnwrap(field.subviews.first { $0 is GlassBackingView }?.layer)
            XCTAssertGreaterThanOrEqual(backing.borderWidth, Tokens.Metric.hairline, "no edge over \(page)")
            XCTAssertGreaterThan(backing.borderColor?.alpha ?? 0, 0, "no edge over \(page)")
            let layer = try XCTUnwrap(field.layer)
            XCTAssertGreaterThan(layer.shadowOpacity, 0, "no depth over \(page)")
            XCTAssertGreaterThan(layer.shadowColor?.alpha ?? 0, 0, "no depth over \(page)")
        }
    }
}
