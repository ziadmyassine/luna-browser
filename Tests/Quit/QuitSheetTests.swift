//
//  QuitSheetTests.swift
//  LunaTests
//
//  §3.1's quit sheet. These are the four ways it can be wrong in a way nobody
//  notices until the day it matters: an answer that has lost a word, two
//  answers that both look like the recommendation, an accidental gesture that
//  quits, and an answer that arrives twice.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class QuitSheetTests: XCTestCase {

    private func laidOutSheet() -> QuitSheetView {
        let sheet = QuitSheetView(caption: "5 tabs open across 2 Spaces. Luna will put them all back next time.")
        sheet.frame = NSRect(x: 0, y: 0, width: Tokens.Metric.windowMinWidth * 1.5, height: 700)
        sheet.layoutSubtreeIfNeeded()
        return sheet
    }

    private func answers(in view: NSView) -> [QuitSheetButton] {
        view.subviews.flatMap { child -> [QuitSheetButton] in
            (child as? QuitSheetButton).map { [$0] } ?? answers(in: child)
        }
    }

    /// The panel is as wide as its answers, so **no answer may be narrower
    /// than the words in it**. A fixed width shipped twice and was short both
    /// times — "Cancel" rendered as "Can" and then "Quit" as "Qu" — because a
    /// row that does not fit does not fail, it shaves the lowest-priority
    /// thing in it, and that is always a word. The titles are localised, so
    /// this is the check rather than any particular number.
    func testNoAnswerIsNarrowerThanItsOwnWords() {
        let sheet = laidOutSheet()
        let row = answers(in: sheet)
        XCTAssertEqual(row.count, 3, "three answers: quit, quit for good, and stay")
        for button in row {
            XCTAssertGreaterThanOrEqual(
                button.frame.width,
                button.fittingSize.width - 0.5,
                "\(button.accessibilityLabel() ?? "?") is narrower than its title"
            )
        }
    }

    /// The panel takes the row's width, and never goes under §3.1's floor.
    func testThePanelIsAtLeastItsMinimumAndFitsItsRow() {
        let sheet = laidOutSheet()
        guard let panel = sheet.subviews.first(where: { !answers(in: $0).isEmpty }) else {
            return XCTFail("no panel")
        }
        XCTAssertGreaterThanOrEqual(panel.frame.width, QuitSheetMetrics.minimumWidth)
        let row = answers(in: sheet)
        let widest = row.map(\.frame.maxX).max() ?? 0
        XCTAssertLessThanOrEqual(widest, panel.frame.width, "an answer hangs off the panel")
    }

    /// Exactly one recommendation. Two would be the sheet failing at the
    /// only job it has, which is to make the default answer unmistakable —
    /// and it is the one Return is bound to, so two would also be ambiguous
    /// about what the keyboard does.
    func testExactlyOneAnswerIsTheRecommendedOne() {
        XCTAssertEqual(answers(in: laidOutSheet()).filter(\.isKey).count, 1)
    }

    /// Every accidental gesture means stay. Escape, and a click that
    /// missed the panel: the sheet exists because ⌘Q is next to ⌘W, and a
    /// guard that can be dismissed into the thing it guards is not one.
    func testEscapeAndAMissedClickBothMeanStay() {
        for gesture in ["escape", "click"] {
            let sheet = laidOutSheet()
            var given: QuitAnswer?
            sheet.onAnswer = { given = $0 }
            if gesture == "escape" {
                sheet.cancelOperation(nil)
            } else {
                sheet.mouseDown(with: click(at: NSPoint(x: 4, y: 4), in: sheet))
            }
            XCTAssertEqual(given, .stay, "\(gesture) did not mean stay")
        }
    }

    /// A click racing the keyboard must not quit twice — the second answer
    /// would reach `NSApp.terminate` after the first had already started
    /// tearing the session down.
    func testAnAnswerArrivesOnlyOnce() {
        let sheet = laidOutSheet()
        var count = 0
        sheet.onAnswer = { _ in count += 1 }
        sheet.cancelOperation(nil)
        sheet.cancelOperation(nil)
        sheet.mouseDown(with: click(at: NSPoint(x: 4, y: 4), in: sheet))
        XCTAssertEqual(count, 1)
    }

    private func click(at point: NSPoint, in view: NSView) -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: view.convert(point, to: nil),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }
}
