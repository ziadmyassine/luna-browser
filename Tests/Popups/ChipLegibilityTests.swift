//
//  ChipLegibilityTests.swift
//  LunaTests
//
//  The two chips that float over the page — §17's pop-up chip and §14.4's
//  save chip — are panels of their own, and a panel resolves its appearance
//  from the app, not from the browser window it hangs off. With the app dark
//  and the window light, the same glass and the same ink tokens drew white
//  words on a pale chip. So what is measured here is what is on screen: the
//  panel's own effective appearance against its window's, and the ink and the
//  material's fill each resolved under that appearance.
//

@testable import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class ChipLegibilityTests: XCTestCase {

    private let url = URL(string: "https://ads.example.net/x")!
    private let names: [NSAppearance.Name] = [.aqua, .darkAqua]
    private var savedAppearance: NSAppearance?

    override func setUp() {
        super.setUp()
        savedAppearance = NSApp.appearance
    }

    override func tearDown() {
        NSApp.appearance = savedAppearance
        super.tearDown()
    }

    private func host(_ name: NSAppearance.Name) -> (NSWindow, NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 900, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: name)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        window.contentView = content
        return (window, content)
    }

    private func match(_ appearance: NSAppearance?) -> NSAppearance.Name? {
        appearance?.bestMatch(from: names)
    }

    private func descendants<T: NSView>(of root: NSView, ofType type: T.Type) -> [T] {
        root.subviews.flatMap { child -> [T] in
            (child as? T).map { [$0] } ?? [] + descendants(of: child, ofType: type)
        }
    }

    /// Every label on `view`, and every button's title over the heavier of
    /// the two washes it can wear, against `style`'s fill — all resolved
    /// under the chip's own appearance.
    private func assertLegible(_ view: NSView, on style: Glass.Style, _ what: String) {
        assertLegible(view, fill: style.solidFallback, what)
    }

    private func assertLegible(_ view: NSView, fill: NSColor, _ what: String) {
        let appearance = view.effectiveAppearance
        for label in descendants(of: view, ofType: NSTextField.self) where !label.isHidden && !label.stringValue.isEmpty {
            let ratio = (label.textColor ?? .clear).contrastRatio(over: fill, in: appearance)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(what) '\(label.stringValue)' in \(appearance.name.rawValue)")
        }
        let pressed = Tokens.Surface.selected.flattened(over: fill, in: appearance)
        for button in descendants(of: view, ofType: NSButton.self) {
            let ink = button.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
            let ratio = (ink ?? .clear).contrastRatio(over: pressed, in: appearance)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(what) '\(button.title)' in \(appearance.name.rawValue)")
        }
    }

    /// The window forced one way while the app is the other, both ways round.
    func testThePopupChipWearsItsWindowsAppearance() throws {
        for (app, window) in [(NSAppearance.Name.darkAqua, NSAppearance.Name.aqua), (.aqua, .darkAqua)] {
            NSApp.appearance = NSAppearance(named: app)
            let (host, content) = host(window)
            defer { host.close() }
            let chip = PopupChip()
            chip.present(url, in: host, over: content)
            let panel = try XCTUnwrap(chip.panel)
            XCTAssertEqual(match(panel.effectiveAppearance), window, "the chip took the app's appearance")
            let view = try XCTUnwrap(chip.view)
            XCTAssertEqual(match(view.effectiveAppearance), window)
            assertLegible(view, fill: PopupChip.fill, "pop-up chip")
            XCTAssertTrue(descendants(of: view, ofType: GlassBackingView.self).isEmpty, "glass over a page shows the page")
            view.updateLayer()
            let plate = try XCTUnwrap(view.layer?.backgroundColor)
            XCTAssertEqual(plate.alpha, 1, "a see-through chip is only as readable as the page behind it")
            chip.dismiss()
        }
    }

    /// And keeps following it: a page bar that re-dresses itself for a new
    /// page changes the appearance under a chip that is already up.
    func testThePopupChipFollowsItsWindowWhenItChanges() throws {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let (host, content) = host(.darkAqua)
        defer { host.close() }
        let chip = PopupChip()
        chip.present(url, in: host, over: content)
        host.appearance = NSAppearance(named: .aqua)
        let panel = try XCTUnwrap(chip.panel)
        XCTAssertEqual(match(panel.effectiveAppearance), .aqua)
        chip.dismiss()
    }

    func testTheSaveChipWearsItsWindowsAppearance() throws {
        let request = PasswordSaveRequest(
            kind: .save, site: "example.com", username: "someone", isInsecure: false,
            password: "hunter2", originURL: nil
        )
        for (app, window) in [(NSAppearance.Name.darkAqua, NSAppearance.Name.aqua), (.aqua, .darkAqua)] {
            NSApp.appearance = NSAppearance(named: app)
            let (host, content) = host(window)
            defer { host.close() }
            let chip = SavePasswordChip()
            chip.present(request, in: host, over: content)
            let panel = try XCTUnwrap(chip.panel)
            XCTAssertEqual(match(panel.effectiveAppearance), window, "the save chip took the app's appearance")
            let view = try XCTUnwrap(panel.contentView)
            assertLegible(view, on: SavePasswordChip.material, "save chip")
            chip.dismiss(answering: true)
        }
    }
}
