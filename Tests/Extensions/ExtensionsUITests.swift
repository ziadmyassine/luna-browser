//
//  ExtensionsUITests.swift
//  LunaTests
//
//  §16.4: how many pins each surface gives room to, what a prompt says, the
//  pop-out's rows, and an installed, pinned extension arriving on §4's bar.
//

import AppKit
@testable import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class ExtensionsUITests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
    /// The pins live in the user's defaults, which a test host shares.
    private var savedPins: Any?
    private static let pinsKey = "luna.extensions.pinned"

    override func setUp() async throws {
        savedPins = UserDefaults.standard.object(forKey: Self.pinsKey)
        UserDefaults.standard.removeObject(forKey: Self.pinsKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedPins, forKey: Self.pinsKey)
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Fit

    func testPinsFitTheRoomAndNoMore() {
        XCTAssertEqual(ExtensionShelfFit.count(5, room: 100, pitch: 24), 4)
        XCTAssertEqual(ExtensionShelfFit.count(2, room: 100, pitch: 24), 2, "never more than are pinned")
        XCTAssertEqual(ExtensionShelfFit.count(5, room: 20, pitch: 24), 0)
        XCTAssertEqual(ExtensionShelfFit.count(5, room: -40, pitch: 24), 0, "no room is none, not a crash")
        XCTAssertEqual(ExtensionShelfFit.count(5, room: 100, pitch: 28, gap: 8), 3, "three 28s and two 8s are 100")
    }

    /// The sidebar's pill keeps half of itself for the address, so a
    /// narrower column shows fewer pins, and the sliders move to the front.
    func testTheSidebarPillGivesTheAddressHalfItsWidth() {
        let pill = URLPillView()
        pill.showsExtensions = true
        pill.extensionPins = (0 ..< 6).map { item("pin\($0)") }
        var counts: [Int] = []
        for width: CGFloat in [232, 264, 400] {
            pill.frame = NSRect(x: 0, y: 0, width: width, height: Tokens.Metric.urlPill.height)
            pill.layoutSubtreeIfNeeded()
            let shown = pill.pinGlyphs.filter { !$0.isHidden }
            counts.append(shown.count)
            let leftmost = shown.map(\.frame.minX).min() ?? pill.extensionsGlyph.frame.minX
            XCTAssertGreaterThanOrEqual(leftmost - pill.field.frame.minX, width / 2 - 1, "the address lost its half at \(width)")
            XCTAssertLessThan(pill.sliders.frame.midX, width / 2, "site settings did not move to the front")
        }
        XCTAssertEqual(counts, counts.sorted(), "a wider pill showed fewer pins")
        XCTAssertGreaterThan(counts.last ?? 0, counts.first ?? 0)
    }

    /// The pins stand left of the button, in pin order, touching it.
    func testThePillsPinsEndAtTheExtensionsButton() {
        let pill = URLPillView()
        pill.showsExtensions = true
        pill.extensionPins = [item("a"), item("b")]
        pill.frame = NSRect(x: 0, y: 0, width: 400, height: Tokens.Metric.urlPill.height)
        pill.layoutSubtreeIfNeeded()
        let (first, second) = (pill.pinGlyphs[0].frame, pill.pinGlyphs[1].frame)
        XCTAssertLessThan(first.minX, second.minX)
        XCTAssertEqual(second.maxX, pill.extensionsGlyph.frame.minX, accuracy: 1)
    }

    /// §3.2b's bar: the cylinder in the trailing corner grows with its pins
    /// and the pill keeps half of its full width.
    func testThePageBarsCylinderGrowsWithItsPins() {
        let bar = PageChromeBar()
        bar.frame = NSRect(x: 0, y: 0, width: 1100, height: Tokens.Metric.pageBar)
        bar.showsExtensions = true
        bar.layoutSubtreeIfNeeded()
        let alone = bar.shelf.frame
        XCTAssertEqual(alone.maxX, bar.bounds.maxX - Tokens.Metric.pageBarInset, accuracy: 1)
        XCTAssertEqual(alone.size, Tokens.Metric.sidebarCircle.size, "alone, it is the toggle's circle")
        XCTAssertTrue(bar.shelf.pinButtons.isEmpty)

        bar.extensionPins = [item("a"), item("b")]
        bar.layoutSubtreeIfNeeded()
        XCTAssertEqual(bar.shelf.pinButtons.map(\.id), ["a", "b"])
        XCTAssertEqual(bar.shelf.extensionsButton.frame.maxX, bar.shelf.bounds.maxX, accuracy: 0.5, "the button is not last")
        XCTAssertEqual(bar.shelf.frame.maxX, alone.maxX, accuracy: 1, "the cylinder grew to the right")
        XCTAssertLessThan(bar.shelf.frame.minX, alone.minX)
        XCTAssertLessThanOrEqual(bar.pill.frame.maxX, bar.shelf.frame.minX - Tokens.Metric.chromeGapWide + 1)

        bar.frame.size.width = 700
        bar.extensionPins = (0 ..< 10).map { item("pin\($0)") }
        bar.layoutSubtreeIfNeeded()
        XCTAssertGreaterThanOrEqual(
            bar.pill.frame.width,
            Tokens.Metric.pageBarPillWidth * Tokens.Metric.pinnedExtensionsAddressShare - 1,
            "ten pins squeezed the pill below half"
        )
    }

    /// The page bar's extensions button is the sidebar toggle beside it to
    /// the point: a `GlassButton` of the same circle, lit across the whole of
    /// it under the pointer, its ink lifting, and its glass swelling on a press.
    func testThePageBarsExtensionsButtonAnswersLikeTheToggle() {
        let bar = PageChromeBar()
        bar.frame = NSRect(x: 0, y: 0, width: 1100, height: Tokens.Metric.pageBar)
        bar.showsExtensions = true
        bar.layoutSubtreeIfNeeded()
        let button = bar.shelf.extensionsButton
        XCTAssertEqual(button.shape, bar.toggle.shape)
        XCTAssertEqual(button.frame.size, bar.toggle.frame.size)
        XCTAssertEqual(bar.shelf.frame.height, bar.toggle.frame.height, accuracy: 0.5)
        XCTAssertEqual(button.frame.height, bar.shelf.bounds.height, accuracy: 0.5, "the button does not fill the glass")
    }

    // MARK: - Words

    func testAWebStoreLinkGivesItsID() {
        let id = "ddkjiahejlhfcafbddmgiahcphecmpfh"
        XCTAssertEqual(ExtensionWebStoreLink.id(from: id), id)
        XCTAssertEqual(ExtensionWebStoreLink.id(from: "https://chromewebstore.google.com/detail/ublock-origin-lite/\(id)?hl=en"), id)
        XCTAssertEqual(ExtensionWebStoreLink.id(from: " https://chrome.google.com/webstore/detail/\(id) "), id)
        XCTAssertNil(ExtensionWebStoreLink.id(from: "https://example.com/detail/not-an-id"))
    }

    func testPermissionsAreSaidInWords() {
        XCTAssertEqual(
            ExtensionPermissionText.lines(permissions: ["storage", "tabs", "webNavigation"], hostPatterns: ["<all_urls>"]),
            ["Read and change your data on every website", "Read your browsing history"],
            "sites first, one line for two keys that say the same, nothing for storage"
        )
        XCTAssertEqual(
            ExtensionPermissionText.sites(["*://*.example.com/*", "https://github.com/*", "https://apple.com/*"]),
            "Read and change your data on example.com, github.com and 1 more"
        )
        XCTAssertTrue(ExtensionPermissionText.lines(permissions: ["storage", "alarms"], hostPatterns: []).isEmpty)
    }

    // MARK: - Pins

    func testAPinGoesToTheEndAndAnUnpinLeavesTheRest() {
        let center = ExtensionsCenter.shared
        center.setPinned(true, "a")
        center.setPinned(true, "b")
        center.setPinned(true, "a")
        XCTAssertEqual(center.pinned, ["b", "a"])
        center.setPinned(false, "b")
        XCTAssertEqual(center.pinned, ["a"])
    }

    // MARK: - Pop-out

    func testThePopoutListsRowsAndHandsUpWhatWasPressed() throws {
        var ran: String?
        var pinned: (String, Bool)?
        let panel = ExtensionsPanel(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), edge: .below, items: [
            item("a", pinned: true), item("b")
        ])
        panel.onRun = { ran = $0 }
        panel.onPin = { pinned = ($0, $1) }
        panel.layoutSubtreeIfNeeded()
        XCTAssertEqual(panel.rows.count, 2)
        XCTAssertEqual(panel.body.frame.height, ExtensionsPanelMetrics.height(rows: 2), accuracy: 0.5)
        panel.rows[1].choose()
        XCTAssertEqual(ran, "b")
        try XCTUnwrap(panel.rows[1].pin.onActivate)()
        XCTAssertEqual(pinned?.0, "b")
        XCTAssertEqual(pinned?.1, true, "an unpinned row's pin pins it")
    }

    /// An extension that is off in this Space is still listed, with its
    /// switch off and no pin to press; choosing it turns it on.
    func testAnOffRowTurnsOnRatherThanRunning() {
        var ran: String?
        var switched: (String, Bool)?
        var off = item("off")
        off.isOn = false
        let panel = ExtensionsPanel(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), edge: .below, items: [item("on"), off])
        panel.onRun = { ran = $0 }
        panel.onSwitch = { switched = ($0, $1) }
        panel.layoutSubtreeIfNeeded()
        XCTAssertFalse(panel.rows[1].toggle.isOn)
        XCTAssertTrue(panel.rows[1].pin.isHidden, "an extension that is off has nothing to pin")
        panel.rows[1].choose()
        XCTAssertNil(ran)
        XCTAssertEqual(switched?.0, "off")
        XCTAssertEqual(switched?.1, true)
    }

    /// Turning one off is a change to its row, not a new row: a switch built
    /// afresh mid-slide showed its end state at once, and read as a flash.
    func testASwitchedRowIsUpdatedNotReplaced() {
        let panel = ExtensionsPanel(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), edge: .below, items: [item("a"), item("b")])
        let row = panel.rows[1]
        let toggle = row.toggle
        var off = item("b")
        off.isOn = false
        panel.setItems([item("a"), off])
        XCTAssertTrue(panel.rows[1] === row)
        XCTAssertTrue(panel.rows[1].toggle === toggle)
        XCTAssertFalse(panel.rows[1].toggle.isOn)
        XCTAssertFalse(panel.rows[1].item.isOn)

        panel.setItems([item("b"), item("a")])
        XCTAssertEqual(panel.rows.map(\.item.id), ["b", "a"], "a different order is a different list")
    }

    /// Settings' Details: a switch for each Space, set where it runs, and
    /// the actions the card has no room for.
    func testDetailsHasASwitchPerSpaceAndItsActions() throws {
        let spaces = [
            Space(name: "Personal", symbolName: "person", gradient: Tokens.Gradient.spacePalette[0]),
            Space(name: "Work", symbolName: "briefcase", gradient: Tokens.Gradient.spacePalette[1])
        ]
        let info = ExtensionInfo(id: "x", source: .webStore, details: nil, enabledSpaces: [spaces[1].id], grants: [:])
        var set: (Bool, UUID)?
        var removed = false
        let view = ExtensionDetailsView(ExtensionDetailsView.Model(
            info: info,
            spaces: spaces,
            blocker: nil,
            setOn: { set = ($0, $1) },
            actions: [.init(title: "Remove…", isDestructive: true) { removed = true }]
        ))
        let personal = try XCTUnwrap(view.switches[spaces[0].id])
        XCTAssertFalse(personal.isOn)
        XCTAssertEqual(view.switches[spaces[1].id]?.isOn, true)
        personal.onChange?(true)
        XCTAssertEqual(set?.0, true)
        XCTAssertEqual(set?.1, spaces[0].id)
        view.buttons.first?.onActivate?()
        XCTAssertTrue(removed)
    }

    func testTheEmptyPopoutOffersToAddOne() {
        let panel = ExtensionsPanel(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), edge: .below, items: [])
        XCTAssertTrue(panel.rows.isEmpty)
        XCTAssertEqual(panel.footer.accessibilityLabel(), String(localized: "Add Extensions…"))
    }

    // MARK: - Installed, pinned, on the bar

    /// The whole path: an extension installed in a Space and pinned stands at
    /// the head of §4's capsule, and the extensions button at its end.
    func testAPinnedExtensionStandsOnTheTopBar() async throws {
        let store = try BrowserStore(path: directory.appending(path: "\(UUID().uuidString).sqlite"))
        let session = try await BrowserSession.restored(store: store)
        let window = UUID()
        session.openWindow(window)
        let space = session.activeSpaceID(inWindow: window)
        let manager = try XCTUnwrap(session.extensions)
        _ = session.extensionController(forSpace: space)
        ExtensionsCenter.shared.attach(session)

        let request = try await manager.prepareInstall(from: try fixture())
        try await ExtensionsCenter.shared.install(request, granting: request.grantingEverything, inSpace: space)
        ExtensionsCenter.shared.setPinned(true, request.id)

        let items = ExtensionsCenter.shared.items(in: session, window: window)
        XCTAssertEqual(items.map(\.id), [request.id])
        XCTAssertEqual(items.first?.name, "Luna Fixture")
        XCTAssertEqual(items.first?.isPinned, true)

        let bar = TopBarView(session: session, windowID: window)
        bar.frame = NSRect(x: 0, y: 0, width: 1400, height: TopBarMetrics.barHeight)
        bar.layoutSubtreeIfNeeded()
        bar.layoutSubtreeIfNeeded()
        let ids = bar.capsule.items.map(\.id)
        XCTAssertEqual(ids.first, "extension.\(request.id)", "the pin is not at the head of the capsule")
        XCTAssertEqual(ids.last, TopBarView.extensionsItem, "the extensions button is not after Downloads")
        XCTAssertNotNil(bar.extensionAnchor(request.id))
        // Settings ▸ Extensions lists it, and finds it by name.
        let section = ExtensionsSection()
        XCTAssertTrue(section.searchIndex.contains("luna fixture"), "Settings has no card for it")
        section.filter("fixture")
        XCTAssertFalse(section.searchIndex.isEmpty)

        try await ExtensionsCenter.shared.uninstall(request.id)
        XCTAssertTrue(ExtensionsCenter.shared.items(in: session, window: window).isEmpty)
        XCTAssertFalse(ExtensionsCenter.shared.isPinned(request.id), "a removed extension kept its pin")
    }

    /// A private window runs no extensions, so it shows no button for them.
    func testAPrivateWindowHasNoExtensionsButton() async throws {
        let store = try BrowserStore(path: directory.appending(path: "\(UUID().uuidString).sqlite"))
        let session = try await BrowserSession.restored(store: store, isPrivate: true)
        let window = UUID()
        session.openWindow(window)
        let bar = TopBarView(session: session, windowID: window)
        XCTAssertFalse(bar.capsule.items.contains { $0.id == TopBarView.extensionsItem })
    }

    // MARK: - Fixtures

    /// BrowserKit's fixture extension, written out afresh rather than read
    /// from the checkout: the app's test host needs the Documents folder
    /// granted to read the repo, macOS asks again after every rebuild, and
    /// unanswered the suite hung. Same files as
    /// `BrowserKit/Tests/BrowserKitTests/Fixtures/FixtureExtension`.
    private func fixture() throws -> URL {
        let folder = directory.appending(path: "FixtureExtension")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(FixtureExtensionFiles.manifest.utf8).write(to: folder.appending(path: "manifest.json"))
        try Data(FixtureExtensionFiles.background.utf8).write(to: folder.appending(path: "background.js"))
        return folder
    }

    private func item(_ id: String, pinned: Bool = false) -> ExtensionShelfItem {
        ExtensionShelfItem(id: id, name: id.uppercased(), icon: nil, badge: "", isPinned: pinned)
    }
}

/// `BrowserKit/Tests/BrowserKitTests/Fixtures/FixtureExtension`, as text.
private enum FixtureExtensionFiles {

    static let manifest = """
    {
      "manifest_version": 3,
      "name": "Luna Fixture",
      "version": "1.0",
      "description": "Proves its background ran by opening a tab that counts the tabs it can see.",
      "background": { "service_worker": "background.js" },
      "permissions": ["storage"],
      "host_permissions": ["https://example.com/*"]
    }
    """

    static let background = """
    chrome.storage.local.set({ ran: true }, () => {
      chrome.tabs.query({}, (tabs) => {
        chrome.tabs.create({ url: "https://example.com/?luna-fixture=" + tabs.length });
      });
    });
    """
}
