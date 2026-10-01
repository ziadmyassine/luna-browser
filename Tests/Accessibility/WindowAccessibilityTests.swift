//
//  WindowAccessibilityTests.swift
//  LunaTests
//
//  §21.1: what VoiceOver reads in a browser window, and in what order — the
//  sidebar or the top bar, then the page bar when it is on, then the page —
//  and that every control in it has a name. The window is built the way the
//  app builds one (`AppDelegate.buildChrome`) and never put on screen.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class WindowAccessibilityTests: XCTestCase {

    private var directory: URL!
    private var stored: (ChromeLayoutPreference, SearchBarPlacement)!
    private var built: [BrowserWindow] = []

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
        stored = (Settings.chromeLayout, Settings.searchBarPlacement)
    }

    override func tearDown() async throws {
        for window in built { window.close() }
        built = []
        (Settings.chromeLayout, Settings.searchBarPlacement) = stored
        try? FileManager.default.removeItem(at: directory)
    }

    /// A window with a Favorite, two tabs in the list and the second of them
    /// on screen, in the layout asked for, once its layout fade has run out.
    private func window(
        _ layout: ChromeLayoutPreference,
        searchBar: SearchBarPlacement = .sidebar
    ) async throws -> (window: BrowserWindow, tree: AccessibilityNode) {
        Settings.chromeLayout = layout
        Settings.searchBarPlacement = searchBar
        let store = try BrowserStore(path: directory.appending(path: "\(UUID().uuidString).sqlite"))
        let session = try await BrowserSession.restored(store: store)
        let space = try XCTUnwrap(session.spaces.first).id
        let blank = try XCTUnwrap(URL(string: "about:blank"))
        let tabs = [
            Tab(spaceID: space, kind: .essential, url: blank, title: "Mail", order: 0),
            Tab(spaceID: space, kind: .today, url: blank, title: "First", order: 0),
            Tab(spaceID: space, kind: .today, url: blank, title: "Second", order: 1)
        ]
        for tab in tabs { session.persistAll(session.list.insert(tab)) }
        let window = BrowserWindow(session: session, controller: BrowserWindowController())
        built.append(window)
        AppDelegate().buildChrome(in: window)
        session.activateTab(tabs[2].id, inWindow: window.id)
        window.render()
        window.sidebar?.willAppear()
        try await Task.sleep(for: .seconds(Tokens.Motion.layoutSwitch.duration + 0.3))
        let host = try XCTUnwrap(window.controller.window)
        host.contentView?.layoutSubtreeIfNeeded()
        return (window, AccessibilityNode(host))
    }

    /// The window's own top level, without the titlebar's buttons.
    private func areas(_ tree: AccessibilityNode) -> [AccessibilityNode] {
        tree.children.filter { !$0.isWindowWidget }
    }

    private func isPage(_ node: AccessibilityNode) -> Bool { node.element is LunaWebView }

    // MARK: - Order

    func testTheSidebarLayoutReadsTheSidebarThenThePage() async throws {
        let (_, tree) = try await window(.sidebar)
        let top = areas(tree)
        XCTAssertEqual(top.first?.name, "Sidebar", "\(top.map(\.name))")
        XCTAssertEqual(top.first?.role, .group)
        XCTAssertTrue(top.dropFirst().first.map(isPage) ?? false, "the page is not read straight after the sidebar")
    }

    /// Top to bottom, as the column is drawn: its buttons, the address,
    /// the Favorites, the tabs, then the Space at its foot — and the resize
    /// handle, which runs the column's full height, last.
    func testTheSidebarIsReadTopToBottom() async throws {
        let (window, tree) = try await window(.sidebar)
        let sidebar = try XCTUnwrap(tree.first(named: "Sidebar"))
        let space = "Space: \(try XCTUnwrap(window.session.spaces.first).name)"
        let order = [
            "Hide Sidebar", "Back and Forward", "Reload", "Address", "Favorites", "Mail",
            space, "Spaces", "Library", "Downloads", "History", "Sidebar width"
        ]
        let positions = order.map { sidebar.position(of: $0) }
        XCTAssertFalse(positions.contains(nil), "missing: \(zip(order, positions).filter { $1 == nil }.map(\.0))")
        let found = positions.compactMap { $0 }
        XCTAssertEqual(found, found.sorted(), "read as \(sidebar.all.map(\.name).filter { !$0.isEmpty })")
        let list = try XCTUnwrap(sidebar.all.firstIndex { $0.role == .scrollArea })
        XCTAssertLessThan(try XCTUnwrap(sidebar.position(of: "Favorites")), list)
        XCTAssertLessThan(list, try XCTUnwrap(sidebar.position(of: space)))
    }

    /// §3.2b: the address is on the page, and read between the column and it.
    func testWithTheSearchBarOnThePageItIsReadBeforeThePage() async throws {
        let (_, tree) = try await window(.sidebar, searchBar: .page)
        let top = areas(tree)
        XCTAssertEqual(top.prefix(2).map(\.name), ["Sidebar", "Page bar"])
        XCTAssertTrue(top.dropFirst(2).first.map(isPage) ?? false, "the page is not read after the page bar")
        let bar = try XCTUnwrap(top.dropFirst().first)
        let order = ["Hide Sidebar", "Back and Forward", "Site settings", "Address", "Reload"]
        let positions = order.compactMap { bar.position(of: $0) }
        XCTAssertEqual(positions.count, order.count, "read as \(bar.all.map(\.name))")
        XCTAssertEqual(positions, positions.sorted(), "read as \(bar.all.map(\.name))")
        XCTAssertNil(tree.first(named: "Top bar"), "the hidden layout is still being read")
    }

    func testTheTopBarLayoutReadsTheBarThenThePage() async throws {
        let (_, tree) = try await window(.topBar)
        let top = areas(tree)
        XCTAssertEqual(top.first?.name, "Top bar", "\(top.map(\.name))")
        XCTAssertEqual(top.first?.role, .toolbar)
        XCTAssertTrue(top.dropFirst().first.map(isPage) ?? false, "the page is not read straight after the bar")
        XCTAssertNil(tree.first(named: "Sidebar"), "the hidden layout is still being read")
        let bar = try XCTUnwrap(top.first)
        let order = ["Back and Forward", "Tabs", "Mail", "First", "Second", "Actions", "Space"]
        let positions = order.compactMap { bar.position(of: $0) }
        XCTAssertEqual(positions.count, order.count, "read as \(bar.all.map(\.name))")
        XCTAssertEqual(positions, positions.sorted(), "read as \(bar.all.map(\.name))")
        XCTAssertEqual(bar.first(named: "Tabs")?.role, .tabGroup)
    }

    // MARK: - Names

    /// Every control, and every group, says what it is. A control with no
    /// name is read as its role alone — "button" — which is a control nobody
    /// can use without seeing it.
    func testEveryControlAndGroupHasAName() async throws {
        let named: Set<NSAccessibility.Role> = [
            .button, .radioButton, .checkBox, .popUpButton, .menuButton, .group, .toolbar, .tabGroup, .splitter, .cell
        ]
        for (layout, searchBar) in [(ChromeLayoutPreference.sidebar, SearchBarPlacement.sidebar), (.sidebar, .page), (.topBar, .sidebar)] {
            let (_, tree) = try await window(layout, searchBar: searchBar)
            let nodes = areas(tree).filter { !isPage($0) }.flatMap(\.all)
            for node in nodes {
                guard let role = node.role, named.contains(role) else { continue }
                XCTAssertFalse(node.name.isEmpty, "\(layout) \(searchBar): a \(role.rawValue) (\(type(of: node.element))) has no name")
            }
            XCTAssertFalse(
                nodes.contains { $0.role == .staticText && $0.name.isEmpty && $0.value.isEmpty },
                "\(layout) \(searchBar): an empty line of text is read out"
            )
            XCTAssertFalse(
                nodes.contains { ($0.element as? NSCell)?.controlView?.superview is GlassButton },
                "\(layout) \(searchBar): a button's glyph is read as a picture inside it"
            )
        }
    }

    /// The list's rows are read by the tab's title, in the list's order, as
    /// cells VoiceOver can select. The rows are asked for directly: a window
    /// that is never drawn makes no row views until something does.
    func testTheTabListsRowsAreReadByTitle() async throws {
        let (window, _) = try await window(.sidebar)
        let table = try XCTUnwrap(window.sidebar?.list.table)
        let cells = (0 ..< table.numberOfRows).flatMap { row in
            table.view(atColumn: 0, row: row, makeIfNecessary: true).map { AccessibilityNode($0).all } ?? []
        }
        let tabs = cells.filter { ["First", "Second"].contains($0.name) }
        XCTAssertEqual(tabs.map(\.name), ["First", "Second"])
        XCTAssertEqual(tabs.map(\.role), [.cell, .cell])
    }

    /// The page bar's sidebar button says which way it will go.
    func testThePageBarsSidebarButtonSaysWhatItWillDo() async throws {
        let (window, tree) = try await window(.sidebar, searchBar: .page)
        let bar = try XCTUnwrap(tree.first(named: "Page bar"))
        XCTAssertNotNil(bar.first(named: "Hide Sidebar"))
        window.toggleSidebar()
        let after = try XCTUnwrap(AccessibilityNode(try XCTUnwrap(window.controller.window)).first(named: "Page bar"))
        XCTAssertNotNil(after.first(named: "Show Sidebar"), "read as \(after.all.map(\.name))")
    }
}
