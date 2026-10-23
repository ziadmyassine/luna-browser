//
//  HelpMenuTests.swift
//  LunaTests
//
//  Help ▸ Luna Help opens the FAQ in a tab rather than asking for a Help Book
//  Luna does not ship, and the menu keeps AppKit's search field.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class HelpMenuTests: XCTestCase {

    /// `NSApp.helpMenu` is what earns the menu its search field.
    func testTheHelpMenuOpensTheHelpPage() throws {
        let help = try XCTUnwrap(NSApp.helpMenu)
        XCTAssertEqual(help.title, "Help")
        XCTAssertTrue(NSApp.mainMenu?.items.last?.submenu === help, "Help is not last in the menu bar")
        let item = try XCTUnwrap(help.items.first { $0.action == #selector(AppDelegate.showLunaHelp(_:)) })
        XCTAssertEqual(item.keyEquivalent, "?")
        XCTAssertEqual(item.keyEquivalentModifierMask, .command)
        XCTAssertFalse(help.items.contains { $0.action == #selector(NSApplication.showHelp(_:)) })
    }

    /// Without a Help Book `showHelp:` says "Help isn't available"; there must
    /// not be one half-declared.
    func testNoHelpBookIsDeclared() {
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "CFBundleHelpBookName"))
    }

    func testTheHelpPageIsTheFAQOnGitHub() {
        XCTAssertEqual(AppDelegate.helpPage.scheme, "https")
        XCTAssertEqual(AppDelegate.helpPage.host(), "github.com")
        XCTAssertTrue(AppDelegate.helpPage.path().hasSuffix("/docs/FAQ.md"))
    }

    /// It goes where a link from another app goes, so a press during launch
    /// waits for the window instead of being lost — and so it is never dimmed.
    func testItOpensThroughTheLinkPath() {
        let delegate = AppDelegate()
        let item = NSMenuItem(title: "Luna Help", action: #selector(AppDelegate.showLunaHelp(_:)), keyEquivalent: "?")
        XCTAssertTrue(delegate.validateMenuItem(item))
        delegate.showLunaHelp(item)
        XCTAssertEqual(delegate.linksBeforeLaunch, [AppDelegate.helpPage])
    }

    /// The submenu says only what differs; the Command Bar and Settings ▸
    /// Shortcuts show the whole title.
    func testTheBugSubmenuWearsShortTitles() throws {
        MainMenu.rebuild(in: NSApplication.shared)
        let help = try XCTUnwrap(NSApp.helpMenu)
        let bug = try XCTUnwrap(help.items.first { $0.title == "Report a Bug" }?.submenu)
        XCTAssertEqual(bug.items.filter { !$0.isHidden }.map(\.title), ["Whole Window", "Page Only", "Pick an Area…", "No Screenshot"])
        let window = try XCTUnwrap(bug.items.first)
        XCTAssertEqual(window.action, BrowserCommand.reportBugWindow.action)
        XCTAssertEqual(window.keyEquivalent, "i")
        XCTAssertEqual(window.keyEquivalentModifierMask, [.command, .shift])
        XCTAssertNotNil(help.items.first { $0.action == BrowserCommand.suggestIdea.action })
    }
}
