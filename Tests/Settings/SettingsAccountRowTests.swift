//
//  SettingsAccountRowTests.swift
//  LunaTests
//
//  The account row at the head of Settings' column (docs/SYNC-PLAN.md §5):
//  where it stands, what it says, and that it opens the iCloud page without
//  becoming a numbered section.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class SettingsAccountRowTests: XCTestCase {

    private func texts(in view: NSView) -> [String] {
        view.subviews.flatMap { child -> [String] in
            let own = (child as? NSTextField).map { $0.isHidden ? [] : [$0.stringValue] } ?? []
            return own + texts(in: child)
        }
    }

    private func descendants<T: NSView>(of root: NSView, ofType type: T.Type) -> [T] {
        root.subviews.flatMap { child -> [T] in
            ((child as? T).map { [$0] } ?? []) + descendants(of: child, ofType: type)
        }
    }

    private func laidOut(_ sync: SyncSettings = SyncSettings()) throws -> (SettingsWindowController, NSView) {
        let controller = SettingsWindowController(sync: sync)
        let root = try XCTUnwrap(controller.window?.contentView)
        root.layoutSubtreeIfNeeded()
        return (controller, root)
    }

    private func onWindow(_ view: NSView) -> NSRect {
        view.convert(view.bounds, to: nil)
    }

    // MARK: - Placement

    /// Under the search field and above General, in window coordinates, which
    /// run upwards.
    func testTheRowSitsUnderTheSearchFieldAndAboveGeneral() throws {
        let (controller, root) = try laidOut()
        defer { controller.window?.close() }
        let row = try XCTUnwrap(descendants(of: root, ofType: SettingsAccountRow.self).first, "no account row")
        let search = try XCTUnwrap(descendants(of: root, ofType: SettingsSearchField.self).first)
        let general = try XCTUnwrap(descendants(of: root, ofType: SettingsSectionRowView.self).first)

        XCTAssertGreaterThan(onWindow(row).height, 0)
        XCTAssertLessThanOrEqual(onWindow(row).maxY, onWindow(search).minY, "the row overlaps the search field")
        XCTAssertGreaterThanOrEqual(onWindow(row).minY, onWindow(general).maxY, "the row overlaps General")
        XCTAssertEqual(
            onWindow(row).minX - onWindow(search).minX,
            0,
            accuracy: 0.5,
            "the row's plate starts where the search field's does"
        )
    }

    /// Not a numbered page: ⌘1…⌘8 still count the same eight, and About is
    /// still the last of them.
    func testTheAccountPageIsNotInTheRegister() {
        XCTAssertFalse(SettingsSectionRegistry.ids.contains(AccountSection.id))
        XCTAssertEqual(SettingsSectionRegistry.all.count, 8)
        XCTAssertEqual(SettingsSectionRegistry.ids.last, AboutSection.id)
        XCTAssertFalse(SettingsSectionRegistry.commandBarEntries.contains { $0.id == AccountSection.id })
    }

    // MARK: - Content

    func testTheRowShowsTheUsersFullName() throws {
        let (controller, root) = try laidOut()
        defer { controller.window?.close() }
        let row = try XCTUnwrap(descendants(of: root, ofType: SettingsAccountRow.self).first)
        XCTAssertTrue(texts(in: row).contains(NSFullUserName()))
    }

    func testWithoutAPictureTheAvatarIsInitials() {
        let bare = SettingsAccountRow(name: "Jane Appleseed", picture: nil, status: .off)
        XCTAssertTrue(texts(in: bare).contains("JA"), "no initials in \(texts(in: bare))")

        let pictured = SettingsAccountRow(
            name: "Jane Appleseed",
            picture: NSImage(size: NSSize(width: 8, height: 8)),
            status: .off
        )
        XCTAssertFalse(texts(in: pictured).contains("JA"), "initials drawn over a picture")
    }

    func testInitialsTakeTheFirstAndLastWord() {
        XCTAssertEqual(SettingsAccountRow.initials(of: "Jane Appleseed"), "JA")
        XCTAssertEqual(SettingsAccountRow.initials(of: "jane q appleseed"), "JA")
        XCTAssertEqual(SettingsAccountRow.initials(of: "Cher"), "C")
        XCTAssertEqual(SettingsAccountRow.initials(of: "  "), "")
    }

    /// The subtitle is a word, not the status: the status lines were cut off
    /// at the column's width. The status is still the tooltip and what
    /// VoiceOver reads.
    func testTheSubtitleSaysICloudAndTheTooltipCarriesTheStatus() {
        let row = SettingsAccountRow(name: "Jane Appleseed", picture: nil, status: .off)
        let statuses: [SyncStatus] = [
            .needsSignedBuild, .off, .syncing, .synced(Date()), .noAccount, .unavailable,
            .switchedAccount, .storageFull, .offline, .removedElsewhere
        ]
        for status in statuses {
            row.status = status
            XCTAssertTrue(texts(in: row).contains("iCloud"))
            XCTAssertFalse(texts(in: row).contains(status.line()), "the status is back in the row")
            XCTAssertEqual(row.toolTip, status.line())
            XCTAssertEqual(row.accessibilityLabel(), "iCloud, Jane Appleseed, \(status.line())")
        }
        XCTAssertEqual(row.accessibilityRole(), .radioButton)
    }

    /// The row in the window reads the same status the page does.
    func testTheWindowsRowFollowsSync() throws {
        let sync = SyncSettings()
        sync.status = .off
        let (controller, root) = try laidOut(sync)
        defer { controller.window?.close() }
        let row = try XCTUnwrap(descendants(of: root, ofType: SettingsAccountRow.self).first)
        XCTAssertEqual(row.toolTip, "iCloud sync off")
        sync.status = .offline
        XCTAssertEqual(row.toolTip, SyncStatus.offline.line())
    }

    // MARK: - Style

    /// A row of the list under it, not a card: no plate or border of its own,
    /// no swell, and the list's glass pill while its page is showing.
    func testItIsDressedAsAListRow() throws {
        let row = SettingsAccountRow(name: "Jane Appleseed", picture: nil, status: .off)
        row.frame = NSRect(x: 0, y: 0, width: 240, height: SettingsMetrics.accountRowHeight)
        row.layoutSubtreeIfNeeded()
        XCTAssertEqual(row.layer?.borderWidth ?? 0, 0, "the row has a border")
        XCTAssertNil(row.layer?.backgroundColor, "the row has a plate")
        let pills = descendants(of: row, ofType: RowPillView.self)
        XCTAssertEqual(pills.count, 2, "the row does not carry the list's two fills")
        XCTAssertTrue(pills.allSatisfy { $0.alphaValue == 0 }, "a fill shows on a row nobody chose")

        row.isOn = true
        row.layoutSubtreeIfNeeded()
        XCTAssertTrue(pills.contains { $0.alphaValue > 0 && $0.frame == row.bounds }, "no pill under the chosen row")
        XCTAssertEqual(row.layer?.affineTransform() ?? .identity, .identity, "the row swelled")
    }

    // MARK: - Opening the page

    /// `settings.lastSection` names the page the window closed on, the iCloud
    /// page included, though the register does not know it.
    func testTheICloudPageComesBackOnRelaunch() throws {
        let saved = SettingsDefaults.lastSection
        defer { SettingsDefaults.lastSection = saved }
        SettingsDefaults.lastSection = AccountSection.id

        let (controller, root) = try laidOut()
        defer { controller.window?.close() }

        XCTAssertTrue(texts(in: root).contains(AccountSection.cookieLine), "the window opened on another page")
        XCTAssertTrue(try XCTUnwrap(descendants(of: root, ofType: SettingsAccountRow.self).first).isOn)
    }

    /// The row holds the selection while its page is showing, and the list's
    /// pill steps aside: one thing in the column is selected, always.
    func testClickingOpensTheICloudPageAndFadesTheListsPill() throws {
        let (controller, root) = try laidOut()
        defer { controller.window?.close() }
        let row = try XCTUnwrap(descendants(of: root, ofType: SettingsAccountRow.self).first)
        let list = try XCTUnwrap(descendants(of: root, ofType: SettingsSectionList.self).first)
        let pill = try XCTUnwrap(descendants(of: list, ofType: RowPillView.self).first, "no selection pill")
        XCTAssertFalse(texts(in: root).contains(AccountSection.cookieLine))

        XCTAssertTrue(row.accessibilityPerformPress())

        XCTAssertTrue(texts(in: root).contains(AccountSection.cookieLine), "the iCloud page did not open")
        XCTAssertTrue(row.isOn)
        XCTAssertEqual(pill.alphaValue, 0, accuracy: 0.001, "the list's pill stayed on General")

        let general = try XCTUnwrap(descendants(of: list, ofType: SettingsSectionRowView.self).first)
        XCTAssertTrue(general.accessibilityPerformPress())
        XCTAssertFalse(row.isOn, "the row kept the selection after General was picked")
        XCTAssertEqual(pill.alphaValue, 1, accuracy: 0.001)
    }
}
