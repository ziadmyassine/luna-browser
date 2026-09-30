//
//  ReadingPanelTests.swift
//  LunaTests
//
//  The Reading pop-out behind the Aa glyph: site settings' panel measure for
//  measure, a band per hairline, actions that fit where the document came
//  from, one pop-out on the pill at a time, and the Aa glyph standing between
//  the address and reload on a reading page only.
//

@testable import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class ReadingPanelTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "luna-reading-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        ReadingMenu.controller.dismiss()
        SiteMenu.controller.dismiss()
    }

    // MARK: - Content

    private func document(_ address: String) -> MarkdownDocument {
        MarkdownDocument(url: URL(string: address)!, data: Data("# Hello\n".utf8), modificationDate: nil)
    }

    private func content(
        _ document: MarkdownDocument?,
        apply: @escaping (ReadingPreferences) -> Void = { _ in }
    ) -> SiteSettingsContent {
        ReadingMenu.content(document: document, view: .read, defaults: defaults, apply: apply) { _ in }
    }

    private func panel(_ content: SiteSettingsContent) -> SiteSettingsPanel {
        let panel = SiteSettingsPanel(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), edge: .below, content: content)
        panel.layoutSubtreeIfNeeded()
        return panel
    }

    private var local: MarkdownDocument { document("file:///tmp/README.md") }
    private var web: MarkdownDocument { document("https://example.com/README.md") }

    // MARK: - Geometry

    func testThePanelIsSiteSettingsMeasureForMeasure() throws {
        XCTAssertEqual(SiteSettingsMetrics.width, 280)
        XCTAssertEqual(SiteSettingsMetrics.headerHeight, 52)
        XCTAssertEqual(SiteSettingsMetrics.rowHeight, 38)
        XCTAssertEqual(SiteSettingsMetrics.glyphX, 17.5)
        XCTAssertEqual(SiteSettingsMetrics.titleX, 45.5)

        let panel = panel(content(local))
        XCTAssertEqual(panel.body.frame.width, 280)
        let header = try XCTUnwrap(panel.body.subviews.first { $0 is SiteSettingsHeader })
        XCTAssertEqual(header.frame.height, 52)
        for row in panel.rows {
            XCTAssertEqual(row.frame.height, 38)
            let glyph = try XCTUnwrap(row.subviews.first { $0 is NSImageView })
            XCTAssertEqual(glyph.frame.minX, 17.5, accuracy: 0.01)
        }
    }

    /// Measured, not guessed: every control sits clear of its row's title
    /// and inside the panel.
    func testEveryControlFitsBesideItsTitle() throws {
        let panel = panel(content(local))
        let rows = panel.rows.filter { $0.control != nil }
        XCTAssertEqual(rows.count, 5, "View, Font, Text Size, Width, Page")
        for row in rows {
            let control = try XCTUnwrap(row.control)
            let title = try XCTUnwrap(row.subviews.compactMap { $0 as? NSTextField }.first)
            let textEnd = SiteSettingsMetrics.titleX + title.intrinsicContentSize.width
            // The row ends the title a row inset short of its control, so the
            // text has to fit before that, not merely before the control.
            let room = control.frame.minX - Tokens.Metric.rowInset
            XCTAssertLessThanOrEqual(textEnd, room, "\(title.stringValue) truncates beside its control")
            XCTAssertLessThanOrEqual(control.frame.maxX, row.bounds.maxX - Tokens.Metric.rowInset)
        }
    }

    func testOneHairlinePerBand() {
        let hairlines = { (panel: SiteSettingsPanel) in
            panel.body.subviews.filter { type(of: $0) == NSView.self && $0.frame.height == Tokens.Metric.hairline }.count
        }
        // View; the four style rows; Outline and Wrap; the actions.
        XCTAssertEqual(hairlines(panel(content(local))), 4)
        // Reader: the style rows alone.
        XCTAssertEqual(hairlines(panel(content(nil))), 1)
    }

    func testTheHeaderSaysReadingUnderItsOwnGlyph() {
        let content = content(local)
        XCTAssertEqual(content.heading, "Reading")
        XCTAssertEqual(content.symbol, ReadingMenu.Glyph.header)
        XCTAssertNil(content.connection)
    }

    // MARK: - What it offers

    func testTheActionsFollowWhereTheDocumentCameFrom() {
        XCTAssertEqual(content(local).actions.flatMap { $0 }.map(\.title), ["Show in Finder", "Open With…"])
        XCTAssertEqual(content(web).actions.flatMap { $0 }.map(\.title), ["Save to Downloads", "Copy Markdown"])
    }

    func testReaderHasNoViewOutlineOrWrap() {
        let reader = content(nil)
        XCTAssertTrue(reader.toggles.isEmpty)
        XCTAssertTrue(reader.actions.isEmpty)
        XCTAssertEqual(reader.controls.flatMap { $0 }.map(\.title), ["Font", "Text Size", "Width", "Page"])
        XCTAssertEqual(content(local).controls.first?.map(\.title), ["View"])
    }

    /// Edit is offered only for a file on this Mac whose bytes are UTF-8.
    func testEditIsOfferedOnlyForALocalUTF8File() throws {
        func segments(_ document: MarkdownDocument) throws -> Int {
            let row = try XCTUnwrap(content(document).controls.first?.first)
            let stack = try XCTUnwrap(row.view.subviews.first as? NSStackView)
            return stack.arrangedSubviews.count
        }
        let latin1 = MarkdownDocument(url: URL(string: "file:///tmp/old.md")!, data: Data([0x23, 0x20, 0xE9]), modificationDate: nil)
        XCTAssertTrue(latin1.isReadOnly)
        XCTAssertEqual(try segments(local), 3)
        XCTAssertEqual(try segments(web), 2)
        XCTAssertEqual(try segments(latin1), 2)

        var chosen: ReadingView?
        let edit = ReadingMenu.content(document: local, view: .read, defaults: defaults, apply: { _ in }, setView: { chosen = $0 })
        let choice = try XCTUnwrap(edit.controls.first?.first?.view as? SettingsChoice)
        choice.onSelect?(2)
        XCTAssertEqual(chosen, .edit)
    }

    func testThePageSwatchesAreSpaceSwatches() throws {
        let page = try XCTUnwrap(content(nil).controls.flatMap { $0 }.first { $0.title == "Page" })
        let chips = page.view.subviews.compactMap { $0 as? SpaceSwatchChip }
        XCTAssertEqual(chips.count, 4)
        XCTAssertNotEqual(chips[0].gradient.start, chips[0].gradient.end, "Match runs light to dark")
        for chip in chips.dropFirst() { XCTAssertEqual(chip.gradient.start, chip.gradient.end) }
    }

    func testTheSizeStepperStoresAndAppliesTheNewSize() throws {
        var applied: [ReadingPreferences] = []
        let size = try XCTUnwrap(content(nil, apply: { applied.append($0) }).controls.flatMap { $0 }.first { $0.title == "Text Size" })
        let stepper = try XCTUnwrap(size.view as? ReadingSizeStepper)
        let start = ReadingPreferences.stored(in: defaults).size
        XCTAssertTrue(stepper.larger.accessibilityPerformPress())
        XCTAssertEqual(ReadingPreferences.stored(in: defaults).size, start + 1)
        XCTAssertEqual(applied.last?.size, start + 1)
        XCTAssertEqual(stepper.value.stringValue, "\(start + 1)")
    }

    func testTheSwitchesStoreTheirPreference() {
        let toggles = content(local).toggles
        toggles.first { $0.title == "Outline" }?.set(false)
        XCTAssertFalse(ReadingPreferences.stored(in: defaults).outline)
        toggles.first { $0.title == "Wrap Long Lines" }?.set(false)
        XCTAssertFalse(ReadingPreferences.stored(in: defaults).wrap)
    }

    func testSavingToDownloadsNeverOverwrites() throws {
        let folder = URL.temporaryDirectory.appending(path: "luna-dl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try ReadingMenu.saveToDownloads(web, in: folder)
        let second = try ReadingMenu.saveToDownloads(web, in: folder)
        XCTAssertEqual(first.lastPathComponent, "README.md")
        XCTAssertEqual(second.lastPathComponent, "README 2.md")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), web.text)
    }

    func testEveryGlyphTheReadingMenuDrawsExists() {
        for name in ReadingMenu.Glyph.all {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), "the system has no symbol called \(name)")
        }
    }

    // MARK: - One pop-out at a time

    func testReadingAndSiteSettingsCloseEachOther() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false
        )
        let anchor = NSView(frame: NSRect(x: 400, y: 560, width: 18, height: 18))
        window.contentView?.addSubview(anchor)

        ReadingMenu.show(content(local), from: anchor)
        XCTAssertTrue(ReadingMenu.controller.isPresented)
        SiteMenu.present(from: anchor)
        XCTAssertTrue(SiteMenu.controller.isPresented)
        XCTAssertFalse(ReadingMenu.controller.isPresented, "Site settings opened over Reading")

        ReadingMenu.show(content(local), from: anchor)
        XCTAssertTrue(ReadingMenu.controller.isPresented)
        XCTAssertFalse(SiteMenu.controller.isPresented, "Reading opened over site settings")
    }

    // MARK: - The Aa glyph

    private func pill(reading: Bool) -> URLPillView {
        let pill = URLPillView()
        pill.onReload = { _ in }
        pill.showsReading = reading
        pill.show(url: URL(string: "https://example.com/README.md"))
        pill.frame = NSRect(x: 0, y: 0, width: 400, height: Tokens.Metric.urlPill.height)
        pill.layoutSubtreeIfNeeded()
        return pill
    }

    /// Aa only where its settings change the page: Reader and Markdown, not an
    /// ordinary site that happens to read as an article.
    func testTheGlyphIsOnlyOnReadingPages() {
        XCTAssertTrue(URLPillView.showsReading(for: TabState(isReading: true)))
        XCTAssertFalse(URLPillView.showsReading(for: TabState(isArticle: true)), "an article page wore Aa")
        XCTAssertFalse(URLPillView.showsReading(for: TabState()))
        XCTAssertFalse(URLPillView.showsReading(for: nil))
    }

    func testTheGlyphsRunSlidersAddressReadingReload() {
        let pill = pill(reading: true)
        XCTAssertFalse(pill.reading.isHidden)
        XCTAssertLessThan(pill.sliders.frame.minX, pill.field.frame.minX)
        XCTAssertLessThan(pill.field.frame.minX, pill.reading.frame.minX)
        XCTAssertLessThanOrEqual(pill.field.frame.maxX, pill.reading.frame.minX, "the address runs under Aa")
        XCTAssertLessThan(pill.reading.frame.minX, pill.reload.frame.minX)
        XCTAssertLessThanOrEqual(pill.reading.frame.maxX, pill.reload.frame.minX)
    }

    func testAnOrdinaryPageHasNoReadingGlyph() {
        XCTAssertTrue(pill(reading: false).reading.isHidden)
    }
}
