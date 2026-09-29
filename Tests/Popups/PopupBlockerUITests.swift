//
//  PopupBlockerUITests.swift
//  LunaTests
//
//  §17's pop-up blocker, the chrome half: the chip's one line and what it
//  names, that a second block updates the chip rather than stacking another,
//  the site menu's band of recent blocks, and the Settings rows that only mean
//  something while blocking is on.
//
//  Every window here is off-screen and never made key.
//

@testable import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class PopupChipTests: XCTestCase {

    private let url = URL(string: "https://ads.example.net/landing/offer?id=7")!

    func testTheChipNamesTheHostOnlyWhenAskedTo() {
        let quiet = PopupChipView(count: 1, url: url, showsAddress: false, shortcut: nil)
        XCTAssertEqual(quiet.headline.stringValue, "Pop-up blocked")
        XCTAssertTrue(quiet.address.isHidden)

        let named = PopupChipView(count: 1, url: url, showsAddress: true, shortcut: nil)
        XCTAssertFalse(named.address.isHidden)
        XCTAssertEqual(named.address.stringValue, "ads.example.net")
        XCTAssertEqual(named.address.toolTip, url.absoluteString)
        XCTAssertEqual(named.address.accessibilityValue() as? String, url.absoluteString)
        XCTAssertEqual(named.address.lineBreakMode, .byTruncatingMiddle)
    }

    /// At a header's secondary ink the chip's two buttons read as disabled
    /// beside their own message; they rest at the headline's ink and size.
    func testTheChipsButtonsRestAtTheHeadlinesInk() {
        let view = PopupChipView(count: 1, url: url, showsAddress: false, shortcut: nil)
        for button in [view.open, view.allow] {
            let title = button.attributedTitle
            XCTAssertEqual(title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, view.headline.textColor)
            XCTAssertEqual(title.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, view.headline.font)
        }
    }

    func testTheCountAndTheShortcutAreInTheLine() {
        let view = PopupChipView(count: 3, url: url, showsAddress: false, shortcut: "⌥⌘P")
        XCTAssertEqual(view.headline.stringValue, "3 pop-ups blocked")
        XCTAssertEqual(view.open.title, "Open ⌥⌘P")
        XCTAssertEqual(view.open.toolTip, "Open the pop-up (⌥⌘P)")
        view.update(count: 1, url: url, showsAddress: false, shortcut: nil)
        XCTAssertEqual(view.open.title, "Open")
    }

    /// One line: as tall as the pill it hangs from, and no wider than the save
    /// chip even with a long host in it.
    func testTheChipIsOneLine() {
        let long = URL(string: "https://\(String(repeating: "very-long-label.", count: 12))example.net/")!
        let view = PopupChipView(count: 1, url: long, showsAddress: true, shortcut: "⌥⌘P")
        let size = view.fittingChipSize()
        XCTAssertEqual(size.height, Tokens.Metric.urlPill.height)
        XCTAssertLessThanOrEqual(size.width, Tokens.Metric.passwordChip.width)
    }

    /// A second block while the chip is up updates it; it never stacks.
    func testASecondBlockUpdatesTheChipInPlace() {
        let host = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 800, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        host.isReleasedWhenClosed = false
        defer { host.close() }
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        host.contentView = content

        let chip = PopupChip()
        chip.present(url, in: host, over: content)
        chip.present(URL(string: "https://other.example.net/")!, in: host, over: content)
        XCTAssertEqual(host.childWindows?.count, 1)
        XCTAssertEqual(chip.view?.headline.stringValue, "2 pop-ups blocked")
        XCTAssertFalse(host.isKeyWindow)

        chip.dismiss()
        XCTAssertFalse(chip.isShowing)
        chip.present(url, in: host, over: content)
        XCTAssertEqual(chip.view?.headline.stringValue, "Pop-up blocked", "the count outlived the chip")
        chip.dismiss()
    }
}

@MainActor
final class PopupSiteMenuTests: XCTestCase {

    private func blocked(_ count: Int) -> [BlockedPopup] {
        (0 ..< count).map { BlockedPopup(url: URL(string: "https://ads.example.net/p\($0)?q=1")!) }
    }

    func testTheBandIsHiddenWhenNothingWasBlocked() {
        XCTAssertTrue(SiteMenu.blockedBand([]) { _ in }.isEmpty)
    }

    func testTheBandListsTheThreeMostRecentByHostAndPath() {
        var opened: URL?
        let band = SiteMenu.blockedBand(blocked(5)) { opened = $0 }
        XCTAssertEqual(band.map(\.title), ["ads.example.net/p0", "ads.example.net/p1", "ads.example.net/p2"])
        band[1].run()
        XCTAssertEqual(opened?.absoluteString, "https://ads.example.net/p1?q=1")

        // A band of its own: header, the band, a hairline over it.
        var content = SiteSettingsContent(heading: "example.com")
        content.actions = [band]
        XCTAssertEqual(
            content.height,
            SiteSettingsMetrics.headerHeight + 3 * SiteSettingsMetrics.rowHeight
                + 2 * SiteSettingsMetrics.bandPadding + Tokens.Metric.hairline
        )
        let panel = SiteSettingsPanel(frame: NSRect(x: 0, y: 0, width: 800, height: 600), edge: .below, content: content)
        XCTAssertEqual(panel.rows.count, 3)
    }
}

@MainActor
final class PopupSettingsTests: XCTestCase {

    private let keys = [PopupPolicy.Key.mode, PopupChipSettings.notifiesKey, PopupChipSettings.positionKey]
    private var saved: [String: Any?] = [:]

    override func setUp() {
        super.setUp()
        saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
    }

    override func tearDown() {
        for (key, value) in saved { UserDefaults.standard.set(value, forKey: key) }
        super.tearDown()
    }

    func testTheDependentRowsFollowTheMode() {
        PopupPolicy.setMode(.smart)
        PopupChipSettings.notifies = true
        let section = PrivacySection()
        XCTAssertEqual(section.popupDependents.count, 3)
        XCTAssertTrue(section.popupDependents.allSatisfy { !$0.isHidden })

        section.setPopupMode(.off)
        XCTAssertEqual(PopupPolicy.mode(), .off)
        XCTAssertTrue(section.popupDependents.allSatisfy(\.isHidden))
        // §2's search shows every row on an empty query; these stay down.
        section.filter("")
        XCTAssertTrue(section.popupDependents.allSatisfy(\.isHidden))

        section.setPopupMode(.blockAll)
        XCTAssertTrue(section.popupDependents.allSatisfy { !$0.isHidden })
    }

    /// The position only means something while there is a chip to place.
    func testThePositionRowFollowsTheNotifySwitch() throws {
        PopupPolicy.setMode(.smart)
        PopupChipSettings.notifies = true
        let section = PrivacySection()
        let position = try XCTUnwrap(section.positionRow)
        XCTAssertFalse(position.isHidden)
        section.setNotifies(false)
        XCTAssertFalse(PopupChipSettings.notifies)
        XCTAssertTrue(position.isHidden)
        XCTAssertFalse(try XCTUnwrap(section.notifyRow).isHidden, "the switch that brings it back went with it")
        section.filter("")
        XCTAssertTrue(position.isHidden)
        section.setNotifies(true)
        XCTAssertFalse(position.isHidden)
        section.setPopupMode(.off)
        XCTAssertTrue(position.isHidden)
    }

    func testTheRowsAreFoundByWhatPeopleCallThem() {
        let index = PrivacySection().searchIndex
        for term in ["popup", "pop-up", "window", "tab-under", "notify", "notification", "position"] {
            XCTAssertTrue(index.contains { $0.contains(term) }, term)
        }
    }
}

/// Where the chip stands, measured against the content area it covers.
@MainActor
final class PopupChipPlacementTests: XCTestCase {

    private let size = CGSize(width: 240, height: Tokens.Metric.urlPill.height)

    /// The sidebar layout's content area starts past the sidebar; the top
    /// bar's is the window's width under the bar. Either way the chip is
    /// centred on the page and a chrome gap above its foot.
    func testBottomCentreIsCentredOnTheContentAreaInBothLayouts() {
        let layouts = [
            CGRect(x: 280, y: 8, width: 912, height: 760),
            CGRect(x: 8, y: 8, width: 1184, height: 712)
        ]
        for area in layouts {
            let frame = PopupChip.frame(size: size, in: area, below: nil, position: .bottomCentre)
            XCTAssertEqual(frame.midX, area.midX, accuracy: 0.5)
            XCTAssertEqual(frame.minY, area.minY + Tokens.Metric.chromeGap, accuracy: 0.5)
            XCTAssertEqual(frame.size, size)
        }
    }

    /// Under the glyph, when there is one; the glyph means nothing at the foot.
    func testUnderSiteSettingsStandsUnderTheGlyph() {
        let area = CGRect(x: 280, y: 8, width: 912, height: 760)
        let glyph = CGRect(x: 300, y: 780, width: 20, height: 20)
        let under = PopupChip.frame(size: size, in: area, below: glyph, position: .underSiteSettings)
        XCTAssertEqual(under.maxY, glyph.minY - Tokens.Metric.chromeGap, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(under.minX, area.minX)
        let foot = PopupChip.frame(size: size, in: area, below: glyph, position: .bottomCentre)
        XCTAssertEqual(foot.midX, area.midX, accuracy: 0.5)
    }

    /// A sidebar drag or a window resize moves the page; the chip goes with it.
    func testBottomCentreFollowsTheContentArea() throws {
        let host = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 1200, height: 800),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        host.isReleasedWhenClosed = false
        defer { host.close() }
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        host.contentView = root
        let page = NSView(frame: NSRect(x: 280, y: 0, width: 920, height: 800))
        root.addSubview(page)

        let chip = PopupChip()
        chip.present(URL(string: "https://ads.example.net/")!, in: host, over: page, position: .bottomCentre)
        func pageOnScreen() -> CGRect { host.convertToScreen(page.convert(page.bounds, to: nil)) }
        var panel = try XCTUnwrap(chip.panel).frame
        XCTAssertEqual(panel.midX, pageOnScreen().midX, accuracy: 0.5)

        page.frame = NSRect(x: 420, y: 0, width: 780, height: 800)
        panel = try XCTUnwrap(chip.panel).frame
        XCTAssertEqual(panel.midX, pageOnScreen().midX, accuracy: 0.5, "the chip stayed where the page was")
        XCTAssertEqual(panel.minY, pageOnScreen().minY + Tokens.Metric.chromeGap, accuracy: 0.5)
        chip.dismiss()
    }
}

/// Notify off: the block still happens and is still listed, and nothing
/// appears over the page.
@MainActor
final class PopupNotifyTests: XCTestCase {

    private var directory: URL!
    private var saved: Any?

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appending(path: "luna-popup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        saved = UserDefaults.standard.object(forKey: PopupChipSettings.notifiesKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(saved, forKey: PopupChipSettings.notifiesKey)
        try? FileManager.default.removeItem(at: directory)
    }

    func testNotifyOffRecordsTheBlockAndShowsNoChip() async throws {
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        try await store.seedIfEmpty()
        let session = try await BrowserSession.restored(store: store)
        let host = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 900, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        host.isReleasedWhenClosed = false
        defer { host.close() }
        session.hostWindow = host
        let id = session.newTab(url: URL(string: "about:blank")!)
        let controller = try XCTUnwrap(session.controller(for: id))
        let url = URL(string: "https://ads.example.net/")!

        PopupChipSettings.notifies = false
        controller.noteBlockedPopup(url)
        XCTAssertEqual(controller.popups.blocked.first?.url, url)
        XCTAssertFalse(session.popupChip.isShowing)
        XCTAssertEqual(session.latestBlockedPopup, url, "the shortcut has nothing to open")

        PopupChipSettings.notifies = true
        controller.noteBlockedPopup(URL(string: "https://other.example.net/")!)
        XCTAssertTrue(session.popupChip.isShowing)
        session.popupChip.dismiss()
    }
}
