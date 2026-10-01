//
//  OnboardingFlowTests.swift
//  LunaTests
//
//  §30.17's first run, walked through: the theme page writes Settings' own
//  theme, finishing asks macOS once to make Luna the default browser, and
//  Help ▸ Welcome to Luna puts it back up.
//
//  The default-browser request is counted, never made: a test that changed
//  the Mac's default browser would change the developer's.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class OnboardingFlowTests: XCTestCase {

    private let hasRunKey = "luna.onboarding.hasRun"
    private var hadRun: Any?
    private var theme: String?
    private var appearance: NSAppearance?
    private var directory: URL!

    override func setUpWithError() throws {
        hadRun = UserDefaults.standard.object(forKey: hasRunKey)
        theme = UserDefaults.standard.string(forKey: AppearanceSection.themeKey)
        appearance = NSApp.appearance
        directory = URL.temporaryDirectory.appending(path: "luna-onboarding-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.set(hadRun, forKey: hasRunKey)
        UserDefaults.standard.set(theme, forKey: AppearanceSection.themeKey)
        NSApp.appearance = appearance
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - The theme page

    /// Settings ▸ Appearance's own control, on the theme page only, and what
    /// it writes is that setting.
    func testTheThemePageWritesTheAppearanceSetting() throws {
        let view = OnboardingView(sources: [])
        view.frame = NSRect(origin: .zero, size: OnboardingMetrics.size)
        view.layoutSubtreeIfNeeded()
        XCTAssertTrue(view.themeChoice.isHidden, "the theme answers are up on the welcome page")

        try press(proceed(in: view))
        XCTAssertEqual(view.currentPage, .theme)
        XCTAssertFalse(view.themeChoice.isHidden)
        XCTAssertGreaterThan(view.themeChoice.frame.width, 0)

        let dark = try XCTUnwrap(descendants(of: view.themeChoice, ofType: SettingsChoiceButton.self)
            .first { $0.accessibilityLabel() == AppearanceSection.Theme.dark.title })
        XCTAssertTrue(dark.accessibilityPerformPress())
        XCTAssertEqual(AppearanceSection.theme, .dark)
        XCTAssertEqual(NSApp.appearance?.name, .darkAqua)
    }

    // MARK: - Finishing

    /// The last page's button closes the window and asks macOS once.
    func testFinishingAsksToBeTheDefaultBrowserOnce() throws {
        var asked = 0
        let controller = OnboardingWindowController(store: try store(), sources: [], askToBeDefault: { asked += 1 })
        let view = try XCTUnwrap(controller.window?.contentView.flatMap { descendants(of: $0, ofType: OnboardingView.self).first })
        view.layoutSubtreeIfNeeded()
        for _ in OnboardingPage.allCases.dropLast() { try press(proceed(in: view)) }
        XCTAssertEqual(view.currentPage, .finish)
        XCTAssertEqual(asked, 0, "asked before the last page")

        try press(proceed(in: view))
        XCTAssertEqual(asked, 1)
        XCTAssertFalse(controller.window?.isVisible ?? false)
    }

    /// The close button is "not now", to the default browser as well.
    func testClosingTheWindowDoesNotAsk() throws {
        var asked = 0
        let controller = OnboardingWindowController(store: try store(), sources: [], askToBeDefault: { asked += 1 })
        controller.close()
        XCTAssertEqual(asked, 0)
    }

    // MARK: - Again

    func testHelpHasWelcomeToLuna() throws {
        MainMenu.rebuild(in: NSApplication.shared)
        let help = try XCTUnwrap(NSApp.mainMenu?.items.first { $0.title == "Help" }?.submenu)
        let item = try XCTUnwrap(help.items.first { $0.action == #selector(AppDelegate.showWelcome(_:)) })
        XCTAssertEqual(item.title, "Welcome to Luna")
        XCTAssertNotNil(BrowserCommand.command(id: BrowserCommand.showWelcome.id))
    }

    /// Run again after first run has happened, and brought forward rather than
    /// doubled when it is already up.
    func testWelcomeComesBackAfterFirstRun() async throws {
        OnboardingState.hasRun = true
        let store = try store()
        let session = try await BrowserSession.restored(store: store)
        let delegate = AppDelegate()
        delegate.presentOnboarding(store: store, session: session) { [] }
        let deadline = Date().addingTimeInterval(3)
        while delegate.onboarding == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let first = try XCTUnwrap(delegate.onboarding, "first run did not come back")
        delegate.showWelcome(nil)
        XCTAssertTrue(delegate.onboarding === first, "a second first-run window")
        first.close()
        XCTAssertNil(delegate.onboarding)
        session.tearDown()
    }

    // MARK: - Fixtures

    private func store() throws -> BrowserStore {
        try BrowserStore(path: directory.appending(path: "\(UUID().uuidString).sqlite"))
    }

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
