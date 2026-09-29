//
//  PopupBlockerUITests.swift
//  LunaTests
//
//  §17's pop-up blocker, the chrome half: the notice's one line and what it
//  names, that a second block counts up on it rather than stacking another,
//  the site menu's band of recent blocks, and the Settings rows that only mean
//  something while blocking is on.
//
//  Every window here is off-screen and never made key.
//

@testable import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class PopupNoticeTests: XCTestCase {

    private let url = URL(string: "https://ads.example.net/landing/offer?id=7")!

    private func notice(count: Int = 1, showsAddress: Bool = false, shortcut: String? = nil) -> PageToast {
        .popupBlocked(count: count, address: showsAddress ? "ads.example.net" : nil, shortcut: shortcut, open: {}, allow: {})
    }

    func testTheNoticeNamesTheHostOnlyWhenAskedTo() throws {
        let notices = PopupNotice()
        XCTAssertNil(notices.next(url, shortcut: nil, showsAddress: false, open: {}, allow: {}).detail)
        notices.putAway(in: nil)
        XCTAssertEqual(notices.next(url, shortcut: nil, showsAddress: true, open: {}, allow: {}).detail, "ads.example.net")

        let view = PageToastView()
        view.configure(notice(showsAddress: true))
        XCTAssertFalse(view.detail.isHidden)
        XCTAssertEqual(view.detail.lineBreakMode, .byTruncatingMiddle)
        view.configure(.linkCopied)
        XCTAssertTrue(view.detail.isHidden, "a plain toast kept the last one's host")
    }

    func testTheCountAndTheShortcutAreInTheLine() {
        let toast = notice(count: 3, shortcut: "⌥⌘P")
        XCTAssertEqual(toast.text, "3 pop-ups blocked")
        XCTAssertEqual(toast.actions.map(\.title), ["Open ⌥⌘P", "Always Allow"])
        XCTAssertEqual(toast.actions.first?.toolTip, "Open the pop-up (⌥⌘P)")
        XCTAssertEqual(notice().actions.first?.title, "Open")
        XCTAssertNotNil(NSImage(systemSymbolName: toast.symbol, accessibilityDescription: nil), toast.symbol)
    }

    /// It is the page toast, dressed as every other one: the same pill, at
    /// the toast's height, with its words at the text's own ink.
    func testTheNoticeIsAPageToastWithWords() throws {
        let view = PageToastView()
        view.configure(notice())
        XCTAssertEqual(view.buttons.count, 2)
        for button in view.buttons {
            let title = button.attributedTitle
            XCTAssertEqual(title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, Tokens.Text.primary)
        }
        XCTAssertEqual(notice().dwell, Tokens.Motion.toastActionDwell, "a toast with words went up before they could be reached")
        XCTAssertEqual(PageToast.linkCopied.dwell, Tokens.Motion.toastDwell)
    }

    /// The words take the pointer; the rest of the pill leaves it to the page.
    func testOnlyTheWordsTakeThePointer() async throws {
        // In a parent, as in a window: `hitTest` takes its point in the
        // superview's space, and a flipped view with none reads it upside down.
        let page = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let surface = ControlSurfaceView(frame: page.bounds)
        page.addSubview(surface)
        surface.topInset = 52
        var opened = 0
        surface.showToast(.popupBlocked(count: 1, address: nil, shortcut: nil, open: { opened += 1 }, allow: {}))
        try await Task.sleep(for: .milliseconds(400))
        page.layoutSubtreeIfNeeded()
        let toast = try XCTUnwrap(surface.toast)
        let open = try XCTUnwrap(toast.buttons.first)
        let onWord = open.convert(NSPoint(x: open.bounds.midX, y: open.bounds.midY), to: page)
        let hit = page.hitTest(onWord)
        XCTAssertTrue(hit === open || hit?.isDescendant(of: open) == true, "the word did not take the click")
        let onText = toast.convert(NSPoint(x: Tokens.Agent.capsuleHeight, y: toast.bounds.midY), to: page)
        XCTAssertTrue(page.hitTest(onText) === page, "the pill's text took a click from the page")
        open.onActivate?()
        XCTAssertEqual(opened, 1)
        XCTAssertNil(surface.toast, "the toast stayed after its word was used")
    }

    /// A second block while the notice is down counts up on it; it never stacks.
    func testASecondBlockCountsUpOnTheSameNotice() {
        let notices = PopupNotice()
        let now = Date()
        XCTAssertEqual(notices.next(url, shortcut: nil, now: now, open: {}, allow: {}).text, "Pop-up blocked")
        XCTAssertEqual(notices.next(url, shortcut: nil, now: now + 1, open: {}, allow: {}).text, "2 pop-ups blocked")
        let later = now + Tokens.Motion.toastActionDwell + 2
        let fresh = notices.next(url, shortcut: nil, now: later, open: {}, allow: {})
        XCTAssertEqual(fresh.text, "Pop-up blocked", "the count outlived the notice")
        notices.putAway(in: nil)
        XCTAssertEqual(notices.next(url, shortcut: nil, now: later + 1, open: {}, allow: {}).text, "Pop-up blocked")
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

    private let keys = [PopupPolicy.Key.mode, PopupNoticeSettings.notifiesKey]
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
        PopupNoticeSettings.notifies = true
        let section = PrivacySection()
        XCTAssertEqual(section.popupDependents.count, 2)
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

    func testTheRowsAreFoundByWhatPeopleCallThem() {
        let index = PrivacySection().searchIndex
        for term in ["popup", "pop-up", "window", "tab-under", "notify", "notification"] {
            XCTAssertTrue(index.contains { $0.contains(term) }, term)
        }
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
        saved = UserDefaults.standard.object(forKey: PopupNoticeSettings.notifiesKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(saved, forKey: PopupNoticeSettings.notifiesKey)
        try? FileManager.default.removeItem(at: directory)
    }

    func testNotifyOffRecordsTheBlockAndShowsNoNotice() async throws {
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

        PopupNoticeSettings.notifies = false
        controller.noteBlockedPopup(url)
        XCTAssertEqual(controller.popups.blocked.first?.url, url)
        XCTAssertNil(session.popupNotice.toast)
        XCTAssertEqual(session.latestBlockedPopup, url, "the shortcut has nothing to open")

        PopupNoticeSettings.notifies = true
        controller.noteBlockedPopup(URL(string: "https://other.example.net/")!)
        XCTAssertEqual(session.popupNotice.toast?.text, "Pop-up blocked")
        session.popupNotice.putAway(in: nil)
    }
}
