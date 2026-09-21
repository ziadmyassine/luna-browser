//
//  OnboardingTests.swift
//  LunaTests
//
//  §30.17's first run: the words, the two panes, and what a tick means.
//
//  The copy is the half with a promise in it. §30.18's warning is that the
//  reference screen offers "bookmarks, history, and extensions" and Luna
//  cannot import extensions — so the assertion is on every string the screen
//  can show, not on the one that happened to be written last.
//

import XCTest
@testable import Luna

final class OnboardingCopyTests: XCTestCase {

    private var everyString: [String] {
        OnboardingPage.allCases.flatMap { [$0.title, $0.body, $0.continueTitle] }
    }

    /// Nothing on this screen may offer to bring extensions or passwords
    /// across. The engine cannot do either (§23.2), and a promise made here is
    /// broken in the first five minutes.
    func testNothingPromisesWhatTheImporterCannotDo() {
        for text in everyString {
            let lowered = text.lowercased()
            for forbidden in ["extension", "password", "everything"] {
                XCTAssertFalse(lowered.contains(forbidden), "\(text) promises \(forbidden)")
            }
        }
    }

    /// Three pages, each with something to say and a way on.
    func testEveryPageIsWrittenAndLeadsSomewhere() {
        for page in OnboardingPage.allCases {
            XCTAssertFalse(page.title.isEmpty)
            XCTAssertFalse(page.body.isEmpty)
            XCTAssertFalse(page.continueTitle.isEmpty)
        }
        XCTAssertEqual(OnboardingPage.welcome.next, .transfer)
        XCTAssertEqual(OnboardingPage.transfer.next, .finish)
        XCTAssertNil(OnboardingPage.finish.next)
        XCTAssertNil(OnboardingPage.welcome.previous, "there is nothing behind the first page")
        XCTAssertEqual(OnboardingPage.finish.previous, .transfer)
    }
}

@MainActor
final class OnboardingScreenTests: XCTestCase {

    private func sources() -> [DetectedSource] {
        [
            DetectedSource(source: .arc, profiles: [ChromiumProfile(directoryName: "Default")], isAvailable: true),
            DetectedSource(source: .chrome, profiles: [ChromiumProfile(directoryName: "Default")], isAvailable: true),
            DetectedSource(
                source: .safari,
                profiles: [],
                isAvailable: false,
                unavailableReason: "Safari needs Full Disk Access."
            )
        ]
    }

    private func laidOutScreen() -> OnboardingView {
        let view = OnboardingView(sources: sources())
        view.frame = NSRect(origin: .zero, size: OnboardingMetrics.size)
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func descendants<T: NSView>(of root: NSView, ofType type: T.Type) -> [T] {
        root.subviews.flatMap { child -> [T] in
            ((child as? T).map { [$0] } ?? []) + descendants(of: child, ofType: type)
        }
    }

    /// Two panes, and the prose is on the opaque one. A column of 26 pt type
    /// over a gradient is the thing the split exists to avoid.
    func testTheColumnOfProseIsItsOwnPane() {
        let view = laidOutScreen()
        guard let gradient = descendants(of: view, ofType: OnboardingGradientView.self).first else {
            return XCTFail("no gradient pane")
        }
        XCTAssertEqual(gradient.frame.minX, OnboardingMetrics.leftPane, accuracy: 0.5)
        XCTAssertEqual(gradient.frame.maxX, view.bounds.maxX, accuracy: 0.5)
        let labels = descendants(of: view, ofType: NSTextField.self).filter { !$0.stringValue.isEmpty }
        XCTAssertFalse(labels.isEmpty)
        for label in labels where label.isDescendant(of: gradient) == false {
            XCTAssertLessThanOrEqual(
                label.convert(label.bounds, to: view).maxX,
                OnboardingMetrics.leftPane,
                "\(label.stringValue) has run into the gradient"
            )
        }
    }

    /// The answers stay at the foot of the column from the first page to the
    /// last, with the recommended one under the other — the order §5.2 uses,
    /// so the button nearest the thumb is the one that goes on.
    func testTheAnswersAreStackedAtTheFootOfTheColumn() {
        let view = laidOutScreen()
        let buttons = descendants(of: view, ofType: OnboardingButton.self)
        XCTAssertEqual(buttons.count, 2)
        guard let lowest = buttons.min(by: { $0.frame.minY < $1.frame.minY }),
              let upper = buttons.max(by: { $0.frame.minY < $1.frame.minY })
        else { return XCTFail("no answers") }
        XCTAssertEqual(lowest.frame.minY, OnboardingMetrics.margin, accuracy: 0.5)
        XCTAssertLessThan(lowest.frame.maxY, upper.frame.minY, "the two answers overlap")
        XCTAssertEqual(lowest.frame.width, upper.frame.width, accuracy: 0.5)
        XCTAssertEqual(lowest.accessibilityLabel(), OnboardingPage.welcome.continueTitle)
    }

    /// Nothing is behind the first page, so Back is not offered there.
    func testBackIsNotOfferedOnTheFirstPage() {
        let view = laidOutScreen()
        guard let back = descendants(of: view, ofType: OnboardingButton.self)
            .first(where: { $0.accessibilityLabel() == "Back" })
        else { return XCTFail("no Back") }
        XCTAssertEqual(back.alphaValue, 0, accuracy: 0.001)
        XCTAssertFalse(back.isEnabled)
    }
}

@MainActor
final class OnboardingImportListTests: XCTestCase {

    private func list(available: Int, unavailable: Int, preferring: ImportSource? = nil) -> OnboardingImportList {
        let ready = Array(ImportSource.allCases.prefix(available)).map {
            DetectedSource(source: $0, profiles: [ChromiumProfile(directoryName: "Default")], isAvailable: true)
        }
        let greyed = Array(ImportSource.allCases.suffix(unavailable)).map {
            DetectedSource(source: $0, profiles: [], isAvailable: false, unavailableReason: "Not installed.")
        }
        let list = OnboardingImportList(sources: ready + greyed, preferring: preferring)
        list.frame = NSRect(x: 0, y: 0, width: 400, height: 320)
        list.layoutSubtreeIfNeeded()
        return list
    }

    /// The first browser that can be read starts ticked. The screen's answer
    /// is "yes, bring it" — a list of empty circles asks the user to work that
    /// out from the button.
    func testTheFirstReadableBrowserIsAlreadyChosen() {
        let list = list(available: 2, unavailable: 3)
        XCTAssertEqual(list.chosen, [ImportSource.allCases[0]])
    }

    /// And a Mac with nothing to import from chooses nothing, rather than
    /// ticking a row it cannot act on.
    func testNothingIsChosenWhenNothingCanBeRead() {
        XCTAssertTrue(list(available: 0, unavailable: 4).chosen.isEmpty)
    }

    /// A greyed row is not a control: pressing it changes nothing.
    func testAnUnreadableBrowserCannotBeTicked() {
        let list = list(available: 1, unavailable: 2)
        guard let greyed = ImportSource.allCases.last, let row = list.row(for: greyed) else {
            return XCTFail("no greyed row")
        }
        XCTAssertFalse(row.accessibilityPerformPress())
        XCTAssertFalse(list.chosen.contains(greyed))
    }

    /// More than one, and off again — §30.17 says multi-select.
    func testPickingIsMultipleAndReversible() {
        let list = list(available: 3, unavailable: 1)
        let second = ImportSource.allCases[1]
        XCTAssertTrue(list.row(for: second)?.accessibilityPerformPress() ?? false)
        XCTAssertEqual(list.chosen.count, 2)
        XCTAssertTrue(list.row(for: second)?.accessibilityPerformPress() ?? false)
        XCTAssertEqual(list.chosen.count, 1)
    }

    /// The browser the Mac opens links with is the one already ticked, not
    /// whichever happens to be first in the list.
    func testTheDefaultBrowserIsTheOneAlreadyChosen() {
        let second = ImportSource.allCases[1]
        XCTAssertEqual(list(available: 3, unavailable: 1, preferring: second).chosen, [second])
    }

    /// And a default Luna cannot read — Safari without Full Disk Access, a
    /// browser installed but never opened — falls back rather than opening on
    /// a tick the user cannot act on.
    func testAnUnreadableDefaultFallsBackToTheFirstThatWorks() {
        guard let greyed = ImportSource.allCases.last else { return XCTFail("no sources") }
        let list = list(available: 2, unavailable: 2, preferring: greyed)
        XCTAssertEqual(list.chosen, [ImportSource.allCases[0]])
    }

    /// A card stands in from both edges of its pane, and clear of the top of
    /// the scroll view: `pressSwell` grows it, and what it grows into is the
    /// clip view.
    func testACardHasRoomToSwellWithoutBeingClipped() {
        let list = list(available: 2, unavailable: 1)
        guard let row = list.row(for: ImportSource.allCases[0]) else { return XCTFail("no row") }
        let inset = OnboardingMetrics.cardInset
        XCTAssertEqual(row.frame.minX, inset, accuracy: 0.5)
        XCTAssertEqual(row.frame.maxX, list.bounds.width - inset, accuracy: 0.5)
        let grown = row.frame.insetBy(
            dx: -row.frame.width * (Tokens.Motion.pressSwell - 1) / 2,
            dy: -row.frame.height * (Tokens.Motion.pressSwell - 1) / 2
        )
        XCTAssertGreaterThanOrEqual(grown.minX, 0)
        XCTAssertLessThanOrEqual(grown.maxX, list.bounds.width)
        XCTAssertGreaterThanOrEqual(grown.minY, 0)
    }

    /// A pointer aimed at the browser's name hits the card, and a card that
    /// is already ticked unticks. Both halves failed at once: the name is an
    /// `NSTextField` and a label answers `hitTest` for its own rectangle, so
    /// the middle of the row — the obvious place to aim, and the only place
    /// worth aiming at on the row that starts chosen — was not the row.
    func testTheNameIsPartOfTheCardAndTheCardUnticks() {
        let list = list(available: 2, unavailable: 1)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: list.frame.size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(list)
        list.layoutSubtreeIfNeeded()
        let first = ImportSource.allCases[0]
        guard let row = list.row(for: first) else { return XCTFail("no row") }
        XCTAssertTrue(list.chosen.contains(first), "the list did not open on a tick")
        let aim = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        XCTAssertTrue(window.contentView?.hitTest(aim) === row, "the name swallowed the press")
        guard let press = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: aim,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) else { return XCTFail("no event") }
        row.mouseDown(with: press)
        row.mouseUp(with: press)
        XCTAssertFalse(list.chosen.contains(first), "a card that is ticked will not untick")
    }

    /// The rows are stacked in the order they were given, from the top of the
    /// list rather than the bottom of it.
    func testTheRowsStackFromTheTop() {
        let list = list(available: 2, unavailable: 2)
        let rows = ImportSource.allCases.prefix(2).compactMap { list.row(for: $0) }
        XCTAssertEqual(rows.count, 2)
        guard let first = rows.first, let second = rows.last else { return XCTFail("no rows") }
        XCTAssertLessThan(first.frame.minY, second.frame.minY, "the list is upside down")
        XCTAssertEqual(first.frame.height, OnboardingMetrics.rowHeight, accuracy: 0.5)
    }
}
