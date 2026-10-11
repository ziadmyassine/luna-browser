//
//  LaunchRestoreUITests.swift
//  LunaUITests
//
//  §24.1: the app driven from outside, through the window server — launch,
//  the Command Bar, a page, ⌘Q, and the same page back after a relaunch.
//
//  This takes the pointer and the keyboard and brings Luna to the front, so it
//  is its own scheme (`make uitest`) and never part of `make test`. CI runs it;
//  a developer Mac does not have to.
//

import XCTest

@MainActor
final class LaunchRestoreUITests: XCTestCase {

    /// The fixture's `<title>`, which is what the sidebar row and the window
    /// show for it.
    private let fixtureTitle = "Luna UI Test Fixture"

    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // `AppDelegate.testDataKey`: the database, and every other test-host
        // guard, follow this folder instead of the user's own. Under /private/tmp
        // rather than this runner's temporary directory: the runner is
        // sandboxed, so that one is inside its container, which is another
        // app's data to Luna. One per test, the same for both launches.
        let folder = "/private/tmp/luna-uitests-\(UUID().uuidString)"
        app.launchEnvironment["LUNA_TEST_DATA"] = folder
        // §3.1's quit sheet is a question for a person. The argument domain is
        // read-only, so this is never written to anyone's preferences;
        // `<false/>` is parsed as a property list, where `NO` would be a string.
        app.launchArguments += ["-general.confirmQuit", "<false/>"]
    }

    override func tearDown() async throws {
        app.terminate()
    }

    func testANavigatedTabIsRestoredAfterQuitAndRelaunch() throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "restore", withExtension: "html"))

        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20), "no browser window after launch")

        // ⌘T asks for a new tab through the Command Bar.
        app.typeKey("t", modifierFlags: .command)
        let field = app.textFields["commandBar.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "⌘T did not open the Command Bar")

        // `absoluteString` is percent-encoded: a typed address with a space in
        // it is a search, not a URL (`CommandBarURL.direct`).
        field.typeText(fixture.absoluteString + "\n")
        XCTAssertTrue(titled(fixtureTitle).waitForExistence(timeout: 15), "the fixture never loaded")

        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15), "⌘Q did not quit")

        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20), "no browser window after relaunch")
        XCTAssertTrue(titled(fixtureTitle).waitForExistence(timeout: 15), "the tab was not restored")
    }

    /// Anything carrying the page's title: its sidebar row, whose label is the
    /// title (`SidebarRowView.configure`), or the window named after it.
    private func titled(_ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR title == %@", title, title)).firstMatch
    }
}
