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

    /// Light, Dark and back on the theme page: the left pane's plate is the
    /// colour its own appearance resolves, under ink that reads on it. The
    /// plate is a `CGColor`, which freezes whichever appearance was current
    /// when it was assigned.
    func testTheLeftPaneRedrawsForTheThemeItIsOn() throws {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let controller = OnboardingWindowController(store: try store(), sources: [])
        let window = try XCTUnwrap(controller.window)
        // On screen, as AppKit only carries a theme change down a window it is
        // drawing, but off every display and never key.
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        let view = try XCTUnwrap(window.contentView.flatMap { descendants(of: $0, ofType: OnboardingView.self).first })
        view.layoutSubtreeIfNeeded()
        try press(proceed(in: view))
        XCTAssertEqual(view.currentPage, .theme)
        let pane = try XCTUnwrap(view.subviews.first)
        let back = try XCTUnwrap(descendants(of: view, ofType: OnboardingButton.self).first { $0.accessibilityLabel() == "Back" })
        let inks = [descendants(of: pane, ofType: NSTextField.self).first, descendants(of: back, ofType: NSTextField.self).first]

        for name in [NSAppearance.Name.aqua, .darkAqua, .aqua] {
            NSApp.appearance = NSAppearance(named: name)
            // AppKit carries the change down the window on its own display
            // pass, not inside the setter.
            let deadline = Date().addingTimeInterval(2)
            while pane.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) != name, Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            window.displayIfNeeded()
            let appearance = pane.effectiveAppearance
            XCTAssertEqual(appearance.bestMatch(from: [.aqua, .darkAqua]), name)
            let lights = window.standardWindowButton(.closeButton)?.effectiveAppearance
            XCTAssertEqual(lights?.bestMatch(from: [.aqua, .darkAqua]), name)

            let plate = try XCTUnwrap(pane.layer?.backgroundColor.flatMap(NSColor.init(cgColor:)))
            let drawn = plate.srgbComponents(for: appearance)
            let wanted = Tokens.Surface.base.srgbComponents(for: appearance)
            XCTAssertEqual(drawn.red, wanted.red, accuracy: 0.01, "\(name): the plate is the other theme's")
            XCTAssertEqual(drawn.green, wanted.green, accuracy: 0.01)
            XCTAssertEqual(drawn.blue, wanted.blue, accuracy: 0.01)

            for ink in inks {
                let colour = try XCTUnwrap(ink?.textColor)
                let ratio = colour.contrastRatio(over: plate, in: appearance)
                XCTAssertGreaterThan(ratio, 4.5, "\(name): \(ink?.stringValue ?? "") does not read")
            }
        }
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
        delegate.presentOnboarding(store: store, session: session, detect: { [] })
        let deadline = Date().addingTimeInterval(3)
        while delegate.onboarding == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let first = try XCTUnwrap(delegate.onboarding, "first run did not come back")
        delegate.showWelcome(nil)
        XCTAssertTrue(delegate.onboarding === first, "a second first-run window")
        first.close()
        XCTAssertNil(delegate.onboarding)
        session.tearDown()
    }

    // MARK: - Before the browser

    /// A fresh install opens on the welcome window alone: no browser window,
    /// so no session and no page, until first run is over. A link handed over
    /// meanwhile waits for the browser, and the close button is an answer
    /// like the last page's — the browser opens either way, once.
    func testFirstRunComesBeforeTheBrowserWindow() async throws {
        let store = try store()
        let delegate = AppDelegate()
        var opened = 0
        delegate.presentFirstRun(opening: Task { store }, detect: { [] }, then: { opened += 1 })
        let deadline = Date().addingTimeInterval(3)
        while delegate.onboarding == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let onboarding = try XCTUnwrap(delegate.onboarding, "first run never came up")
        XCTAssertEqual(opened, 0, "the browser opened behind first run")
        XCTAssertTrue(delegate.windows.isEmpty)
        XCTAssertNil(delegate.session)

        let link = try XCTUnwrap(URL(string: "https://example.com/"))
        delegate.application(NSApp, open: [link])
        XCTAssertEqual(delegate.linksBeforeLaunch, [link], "a link opened somewhere other than after first run")
        XCTAssertTrue(delegate.windows.isEmpty)

        onboarding.close()
        XCTAssertEqual(opened, 1)
        XCTAssertNil(delegate.onboarding)
    }

    /// The store would not open: the browser opens to say so, rather than
    /// first run waiting on a store it can never import into.
    func testFirstRunWithoutAStoreGoesStraightToTheBrowser() async throws {
        let delegate = AppDelegate()
        var opened = 0
        let failing = Task<BrowserStore, any Error> { throw CocoaError(.fileReadNoPermission) }
        delegate.presentFirstRun(opening: failing, detect: { [] }, then: { opened += 1 })
        let deadline = Date().addingTimeInterval(3)
        while opened == 0, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(opened, 1)
        XCTAssertNil(delegate.onboarding)
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
