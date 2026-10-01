//
//  SiteSettingsPanelTests.swift
//  LunaTests
//
//  §3.2's site settings as a pop-out: the panel is as tall as what is in it,
//  a switch row is the system's switch and a click on the row moves it, an
//  action row hands its action up, and §4's selected tab carries the glyph
//  that opens it — the one tab that does, standing the pop-out off the tab.
//

@testable import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class SiteSettingsPanelTests: XCTestCase {

    private var directory: URL!

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appending(path: "luna-site-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - The panel

    private func sample(on: Bool = false, set: @escaping (Bool) -> Void = { _ in }, run: @escaping () -> Void = {}) -> SiteSettingsContent {
        var content = SiteSettingsContent(heading: "Connection is Secure", connection: .secure)
        content.toggles = [
            .init(title: "Block Ads & Trackers", symbol: SiteMenu.Glyph.blocking, isOn: on, set: set),
            .init(title: "Local Network", symbol: SiteMenu.Glyph.localNetwork, isOn: true) { _ in }
        ]
        content.actions = [[.init(title: "Copy Link", symbol: SiteMenu.Glyph.link, run: run)]]
        return content
    }

    private func panel(_ content: SiteSettingsContent) -> SiteSettingsPanel {
        let panel = SiteSettingsPanel(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), edge: .below, content: content)
        panel.layoutSubtreeIfNeeded()
        return panel
    }

    /// Header, two bands of rows, a hairline over each band.
    func testThePanelIsAsTallAsItsRows() {
        let content = sample()
        let expected = SiteSettingsMetrics.headerHeight
            + 3 * SiteSettingsMetrics.rowHeight
            + 4 * SiteSettingsMetrics.bandPadding
            + 2 * Tokens.Metric.hairline
        XCTAssertEqual(content.height, expected)
        let panel = panel(content)
        XCTAssertEqual(panel.body.frame.height, expected)
        XCTAssertEqual(panel.body.frame.width, Tokens.Metric.siteSettingsPanel)
        XCTAssertEqual(panel.rows.count, 3)
    }

    /// §4.6: the user agent is a row at the foot of the switches' band, not a band
    /// of its own, and picking a mode keeps it for the site and fetches the page again.
    func testTheUserAgentRowSitsWithTheSwitchesAndKeepsTheChoice() throws {
        let scope = SitePermissions.scope(for: .nonPersistent())
        var reloads = 0
        var content = sample()
        content.toggleControls = [SiteMenu.userAgent(host: "chrome-only.example", scope: scope) { reloads += 1 }]
        let expected = SiteSettingsMetrics.headerHeight
            + 4 * SiteSettingsMetrics.rowHeight
            + 4 * SiteSettingsMetrics.bandPadding
            + 2 * Tokens.Metric.hairline
        XCTAssertEqual(content.height, expected)
        XCTAssertEqual(panel(content).rows.count, 4)

        let popup = try XCTUnwrap(content.toggleControls.first?.view as? ChoicePopUp)
        XCTAssertEqual(popup.itemTitles, ["Default", "Luna", "Safari", "Chrome", "Custom"])
        XCTAssertEqual(popup.indexOfSelectedItem, 0, "a site with no choice of its own follows Settings")

        popup.selectItem(at: 3)
        popup.sendAction(popup.action, to: popup.target)
        XCTAssertEqual(scope.userAgentMode(forHost: "chrome-only.example"), .chrome)
        XCTAssertEqual(reloads, 1)
        let reopened = try XCTUnwrap(SiteMenu.userAgent(host: "chrome-only.example", scope: scope).view as? ChoicePopUp)
        XCTAssertEqual(reopened.indexOfSelectedItem, 3)

        reopened.selectItem(at: 0)
        reopened.sendAction(reopened.action, to: reopened.target)
        XCTAssertNil(scope.userAgentMode(forHost: "chrome-only.example"))
    }

    /// The pop-out borrows the keyboard for its arrow keys and gives it back
    /// when it closes, so Escape and Space reach the page again.
    func testClosingThePopOutGivesTheKeyboardBack() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false
        )
        let page = FocusableView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        let anchor = NSView(frame: NSRect(x: 400, y: 560, width: 18, height: 18))
        window.contentView?.addSubview(page)
        window.contentView?.addSubview(anchor)
        window.makeFirstResponder(page)

        let controller = SiteSettingsController()
        controller.toggle(in: window, from: anchor, edge: .below, content: sample())
        XCTAssertTrue(window.firstResponder is SiteSettingsPanel)
        controller.dismiss()
        XCTAssertTrue(window.firstResponder === page)
    }

    private final class FocusableView: NSView {
        override var acceptsFirstResponder: Bool { true }
    }

    /// Where `NSGlassEffectView` at the pop-out's width reaches its full
    /// thickness: measured 161 → 150 → 137 → 134 brightness over one
    /// background at 44, 80, 101 and 107 pt tall, and 134 from there up.
    private static let fullGlassHeight: CGFloat = 107

    /// A page with no host keeps the actions that need no site. Only its
    /// heading, it was a strip of glass the system drew lighter than every
    /// other pop-out.
    func testAPageThatIsNotASiteKeepsItsActionsAndItsGlass() throws {
        let newTab = SiteMenu.withoutSite(url: URL(string: "luna:new-tab"), tools: [], from: NSView())
        XCTAssertEqual(newTab.actions.flatMap { $0 }.map(\.title), ["More Settings…"])
        XCTAssertGreaterThanOrEqual(newTab.height, Self.fullGlassHeight, "the pop-out is small enough for thin glass")
        XCTAssertEqual(panel(newTab).rows.count, 1)

        let file = URL(fileURLWithPath: "/tmp/README.md")
        let local = SiteMenu.withoutSite(url: file, tools: [], from: NSView())
        XCTAssertEqual(local.actions.flatMap { $0 }.map(\.title), ["Share…", "Copy Link", "More Settings…"])
    }

    /// The switch is the Mac's, and the row around it is its target too.
    func testAClickOnASwitchRowMovesTheSwitch() throws {
        var seen: Bool?
        let panel = panel(sample(on: false) { seen = $0 })
        let row = try XCTUnwrap(panel.rows.first)
        let toggle = try XCTUnwrap(row.toggle)
        XCTAssertTrue(toggle.isKind(of: NSSwitch.self))
        XCTAssertFalse(toggle.isOn)
        row.choose()
        XCTAssertTrue(toggle.isOn)
        XCTAssertEqual(seen, true)
        // The switch sits inside the pill's trailing end, clear of the title.
        XCTAssertLessThanOrEqual(toggle.frame.maxX, row.bounds.maxX - Tokens.Metric.rowInset)
    }

    func testAnActionRowHandsItsActionUp() throws {
        var ran = false
        let panel = panel(sample(run: { ran = true }))
        var chosen: String?
        panel.onAction = { action in
            chosen = action.title
            action.run()
        }
        let row = try XCTUnwrap(panel.rows.last)
        XCTAssertNil(row.toggle)
        row.choose()
        XCTAssertEqual(chosen, "Copy Link")
        XCTAssertTrue(ran)
    }

    /// The padlock is green in both themes; the words only where green can
    /// carry text.
    func testASecureConnectionIsGreen() {
        let header = SiteSettingsHeader(heading: "Connection is Secure", connection: .secure)
        let dark = NSAppearance(named: .darkAqua)!
        var ink: NSColor?
        dark.performAsCurrentDrawingAppearance {
            ink = header.title.textColor?.usingColorSpace(.sRGB)
        }
        var green: NSColor?
        dark.performAsCurrentDrawingAppearance {
            green = NSColor.systemGreen.usingColorSpace(.sRGB)
        }
        XCTAssertEqual(ink, green)
        let plain = SiteSettingsHeader(heading: "example.com", connection: nil)
        XCTAssertEqual(plain.title.textColor, Tokens.Text.primary)
    }

    /// Centred across its button, not hung from the button's leading edge,
    /// and still kept inside the window.
    func testThePopOutStandsCentredOnItsButton() {
        let panel = SiteSettingsPanel(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), edge: .below, content: sample())
        let button = NSRect(x: 600, y: 850, width: 18, height: 18)
        panel.anchorRect = { button }
        panel.layoutSubtreeIfNeeded()
        XCTAssertEqual(panel.body.frame.midX, button.midX, accuracy: 0.5)

        panel.anchorRect = { NSRect(x: 4, y: 850, width: 18, height: 18) }
        panel.needsLayout = true
        panel.layoutSubtreeIfNeeded()
        XCTAssertEqual(panel.body.frame.minX, PopoutMetrics.inset)
    }

    // MARK: - The tab

    /// A kept tile has no room for the glyph, so its right-click has the
    /// item; a page that is not a site has nothing to offer.
    func testTheTabMenuOffersSiteSettingsOnASite() async throws {
        let store = try BrowserStore(path: directory.appending(path: "menu.sqlite"))
        let session = try await BrowserSession.restored(store: store)
        let window = UUID()
        session.openWindow(window)
        let space = try XCTUnwrap(session.spaces.first).id
        let site = insert("One", in: space, on: session)
        let strip = TopBarTabStrip(session: session, windowID: window)
        // Each title carries its glyph ahead of the words.
        let titles = try XCTUnwrap(strip.tabMenu(site)).items.map(\.title)
        XCTAssertTrue(titles.contains { $0.hasSuffix("Site Settings…") })

        let blank = Tab(spaceID: space, kind: .today, url: URL(string: "about:blank")!, title: "Blank", order: 1)
        session.persistAll(session.list.insert(blank))
        XCTAssertFalse(try XCTUnwrap(strip.tabMenu(blank.id)).items.contains { $0.title.hasSuffix("Site Settings…") })
    }

    func testOnlyTheSelectedTabCarriesTheGlyph() async throws {
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        let session = try await BrowserSession.restored(store: store)
        let window = UUID()
        session.openWindow(window)
        let space = try XCTUnwrap(session.spaces.first).id
        let first = insert("One", in: space, on: session)
        let second = insert("Two", in: space, on: session)
        session.activateTab(first, inWindow: window)

        let bar = TopBarView(session: session, windowID: window)
        bar.frame = NSRect(x: 0, y: 0, width: 1400, height: TopBarMetrics.barHeight)
        bar.layoutSubtreeIfNeeded()

        let selected = try XCTUnwrap(row(first, in: bar))
        let other = try XCTUnwrap(row(second, in: bar))
        XCTAssertTrue(selected.content.siteSettings)
        XCTAssertEqual(selected.content.trailing, .close, "the glyph's neighbour stays put")
        XCTAssertFalse(other.content.siteSettings)
        XCTAssertEqual(other.content.trailing, .none)

        // Up and down, the pop-out stands off the tab, not off the glyph.
        let glyph = selected.row.siteButton
        XCTAssertFalse(glyph.isHidden)
        let rect = PopoutController.standingRect(of: glyph, in: bar)
        let tab = bar.convert(selected.bounds, from: selected)
        XCTAssertEqual(rect.minY, tab.minY)
        XCTAssertEqual(rect.maxY, tab.maxY)
        XCTAssertEqual(rect.minX, bar.convert(glyph.bounds, from: glyph).minX)
    }

    /// The title gives the glyph its slot as well as the close glyph's.
    func testTheTitleStopsShortOfTheGlyph() {
        let width = TopBarMetrics.tabWidth + 2 * Tokens.Metric.rowInset
        let closeOnly = SidebarRowView.titleColumn(inRowOfWidth: width, hasUnread: false, slotOccupied: true)
        let both = SidebarRowView.titleColumn(inRowOfWidth: width, hasUnread: false, slotOccupied: true, siteSlot: true)
        XCTAssertEqual(
            closeOnly.width - both.width,
            Tokens.Metric.rowTrailingChip.width + Tokens.Metric.rowInset / 2
        )
        XCTAssertGreaterThan(both.width, 0)
    }

    // MARK: - Fixtures

    private func insert(_ title: String, in space: UUID, on session: BrowserSession) -> UUID {
        let tab = Tab(spaceID: space, kind: .today, url: URL(string: "https://example.com/\(title)")!, title: title, order: 0)
        session.persistAll(session.list.insert(tab))
        return tab.id
    }

    private func row(_ id: UUID, in root: NSView) -> TopBarTabRow? {
        for sub in root.subviews {
            if let row = sub as? TopBarTabRow, row.identifier?.rawValue == id.uuidString { return row }
            if let found = row(id, in: sub) { return found }
        }
        return nil
    }
}
