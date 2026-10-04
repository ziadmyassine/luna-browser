//
//  OnboardingMappingTests.swift
//  LunaTests
//
//  §23.2's mapping step on first run: choosing Dia and going on shows where
//  each kind of thing Dia keeps will land, and the import waits for it. The
//  window is never shown; the view is laid out off-screen and pressed through
//  accessibility, so nothing takes focus.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class OnboardingMappingTests: XCTestCase {

    private var requested: Set<ImportSource>?

    private func transferPage(offering mapping: ImportMapping?) throws -> OnboardingView {
        let dia = DetectedSource(source: .dia, profiles: [ChromiumProfile(directoryName: "Profile 1")], isAvailable: true)
        let view = OnboardingView(sources: [dia], preferring: .dia)
        view.frame = NSRect(origin: .zero, size: OnboardingMetrics.size)
        view.onImportRequested = { [weak self] chosen in self?.requested = chosen }
        if let mapping { view.offerMapping(mapping, for: .dia) }
        view.layoutSubtreeIfNeeded()
        while view.currentPage != .transfer { try press(proceed(in: view)) }
        return view
    }

    private let diaMapping = ImportMapping(counts: [.bookmarkBar: 1, .bookmarkFolders: 44, .history: 9])

    func testChoosingDiaShowsTheMappingStepBeforeImporting() throws {
        let view = try transferPage(offering: diaMapping)
        try press(proceed(in: view))
        XCTAssertTrue(view.isShowingMapping)
        XCTAssertNil(requested, "the import started before the mapping was answered")
        let rows = descendants(of: view, ofType: SettingsRowView.self)
        XCTAssertEqual(rows.count, 3, "one row per category Dia has")

        try press(proceed(in: view))
        XCTAssertEqual(requested, [.dia])
    }

    func testTheStepEditsTheMapping() throws {
        let view = try transferPage(offering: diaMapping)
        try press(proceed(in: view))
        let row = try XCTUnwrap(descendants(of: view, ofType: SettingsRowView.self)
            .first { $0.searchTerms.contains(ImportCategory.bookmarkFolders.title.lowercased()) })
        let skip = try XCTUnwrap(descendants(of: row, ofType: SettingsChoiceButton.self)
            .first { $0.accessibilityLabel() == ImportDestination.skip.title })
        XCTAssertTrue(skip.accessibilityPerformPress())
        XCTAssertEqual(view.mapping(for: .dia)?[.bookmarkFolders], .skip)
    }

    func testBackLeavesTheStepForTheList() throws {
        let view = try transferPage(offering: diaMapping)
        try press(proceed(in: view))
        let back = try XCTUnwrap(descendants(of: view, ofType: OnboardingButton.self)
            .first { $0.accessibilityLabel() == "Back" })
        try press(back)
        XCTAssertFalse(view.isShowingMapping)
        XCTAssertEqual(view.currentPage, .transfer)
        XCTAssertNil(requested)
    }

    func testWithoutAMappingTheImportStartsStraightAway() throws {
        let view = try transferPage(offering: nil)
        try press(proceed(in: view))
        XCTAssertFalse(view.isShowingMapping)
        XCTAssertEqual(requested, [.dia])
    }

    /// Measured, not looked at: every row and every answer stands inside the
    /// right pane, clear of its margin.
    func testTheStepFitsTheRightPane() throws {
        let view = try transferPage(offering: ImportMapping(counts: [
            .favorites: 1, .pinnedFolders: 2, .pinnedTabs: 3, .bookmarkBar: 4, .bookmarkFolders: 5, .history: 6
        ]))
        try press(proceed(in: view))
        view.layoutSubtreeIfNeeded()
        let pane = try XCTUnwrap(descendants(of: view, ofType: OnboardingGradientView.self).first)
        let inner = pane.frame.insetBy(dx: OnboardingMetrics.margin - 0.5, dy: OnboardingMetrics.margin - 0.5)
        let step = try XCTUnwrap(descendants(of: view, ofType: OnboardingMappingView.self).first)
        let answers = descendants(of: step, ofType: SettingsChoiceButton.self)
        XCTAssertEqual(answers.count, 3 + 2 + 3 + 3 + 2 + 2)
        for answer in answers {
            let frame = answer.convert(answer.bounds, to: view)
            XCTAssertTrue(inner.contains(frame), "\(answer.accessibilityLabel() ?? "") at \(frame) is outside \(inner)")
        }
    }

    // MARK: - Plumbing

    private func proceed(in view: OnboardingView) throws -> OnboardingButton {
        let buttons = descendants(of: view, ofType: OnboardingButton.self).filter { $0.accessibilityLabel() != "Back" }
        return try XCTUnwrap(buttons.min { $0.frame.minY < $1.frame.minY })
    }

    private func press(_ button: OnboardingButton) throws {
        XCTAssertTrue(button.accessibilityPerformPress(), "\(button.accessibilityLabel() ?? "") would not go on")
    }

    private func descendants<T: NSView>(of root: NSView, ofType type: T.Type) -> [T] {
        root.subviews.flatMap { child -> [T] in
            ((child as? T).map { [$0] } ?? []) + descendants(of: child, ofType: type)
        }
    }
}
