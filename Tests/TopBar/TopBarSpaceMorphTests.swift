//
//  TopBarSpaceMorphTests.swift
//  LunaTests
//
//  §4's bar across a Space switch: the Space capsule and the kept tabs' plate
//  change size frame by frame instead of in one frame, a click switch fades
//  the tabs where they stand, and a swipe, which carries the whole run, takes
//  the old tabs at once.
//
//  Also the bar's own height, which a tab stands in the middle of.
//
//  The CI runner has Reduce Motion on, where every morph lands at once, so
//  each test asserts whichever of the two the machine asks for.
//

@testable import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class TopBarSpaceMorphTests: XCTestCase {

    private var directory: URL!
    private var windows: [NSWindow] = []

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appending(path: "luna-morph-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        for window in windows { window.close() }
        windows = []
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - The Space capsule

    /// A shorter name shrinks the capsule from the old width rather than
    /// jumping to the new one, and lands on the new one.
    func testTheSpaceCapsuleMorphsToTheNewName() {
        let spaces = ["Personal", "Work"].map {
            Space(name: $0, symbolName: "square.grid.2x2", gradient: .defaultSpace)
        }
        let name = TopBarSpaceName()
        host(name)
        name.show(spaces: spaces, activeSpaceID: spaces[0].id)
        let personal = name.intrinsicContentSize.width

        name.show(spaces: spaces, activeSpaceID: spaces[1].id)
        let work = name.naturalWidth
        XCTAssertLessThan(work, personal)
        if Tokens.Motion.reduceMotion {
            XCTAssertEqual(name.intrinsicContentSize.width, work, accuracy: 0.5)
            return
        }
        XCTAssertEqual(name.intrinsicContentSize.width, personal, accuracy: 0.5, "the capsule jumped")
        // The bar refreshes more than once in a switch; a second pass must
        // not start the morph over.
        spin(0.1)
        let partway = name.widthMorph
        XCTAssertGreaterThan(partway, 0)
        name.show(spaces: spaces, activeSpaceID: spaces[1].id)
        XCTAssertGreaterThanOrEqual(name.widthMorph, partway)
        spin(0.5)
        XCTAssertEqual(name.intrinsicContentSize.width, work, accuracy: 0.5)
    }

    // MARK: - The plate

    /// A folder's plate lights round the whole folder under the pointer, with
    /// the column's plate's hairline; the Space's plate stays as it is.
    func testAFoldersPlateLightsUnderThePointerAndTheSpacesDoesNot() {
        let folder = TopBarPlate()
        folder.lightsUnderPointer = true
        let space = TopBarPlate()
        for plate in [folder, space] {
            host(plate)
            plate.mouseEntered(with: NSEvent())
        }
        XCTAssertEqual(folder.wash.layer?.borderColor, Tokens.Line.border.cgColor)
        XCTAssertNotNil(folder.wash.layer?.backgroundColor)
        XCTAssertNotEqual(folder.wash.layer?.backgroundColor?.alpha ?? 0, 0)
        XCTAssertNotEqual(space.wash.layer?.borderColor?.alpha ?? 0, 1)

        folder.mouseExited(with: NSEvent())
        XCTAssertEqual(folder.wash.layer?.borderColor?.alpha ?? 0, 0, accuracy: 0.001)
    }

    /// The plate reshapes from where it stood, and a layout pass during the
    /// morph moves where it is going instead of landing it.
    func testThePlateMorphsAndALayoutPassRetargetsIt() {
        let plate = TopBarPlate()
        host(plate)
        let from = NSRect(x: 0, y: 8, width: 36, height: 36)
        let to = NSRect(x: 0, y: 8, width: 108, height: 36)
        let moved = NSRect(x: 20, y: 8, width: 108, height: 36)
        plate.settle(at: from)
        XCTAssertEqual(plate.frame, from)

        plate.morph(to: to, on: Tokens.Motion.spaceSettleSlowest)
        guard !Tokens.Motion.reduceMotion else {
            XCTAssertEqual(plate.frame, to)
            return
        }
        XCTAssertEqual(plate.frame, from, "the plate took its new width in one frame")
        XCTAssertTrue(plate.isMorphing)
        plate.settle(at: moved)
        XCTAssertNotEqual(plate.frame, moved, "a layout pass landed a plate that was morphing")
        spin(0.5)
        XCTAssertFalse(plate.isMorphing)
        XCTAssertEqual(plate.frame, moved)
    }

    // MARK: - The tabs

    /// A click switch leaves the old Space's tab fading out where it stood,
    /// under the new Space's.
    func testAClickSwitchFadesTheOldTabsOut() async throws {
        let fixture = try await switching()
        let (strip, old, new) = (fixture.strip, fixture.old, fixture.new)
        strip.reload()
        strip.layoutSubtreeIfNeeded()
        XCTAssertNotNil(view(new, in: strip))
        if Tokens.Motion.reduceMotion {
            XCTAssertNil(view(old, in: strip))
        } else {
            XCTAssertNotNil(view(old, in: strip), "the old tab went in one frame")
            // Slept, not spun: inside an async test the main queue the fade
            // finishes on is the one this is already running on.
            try await Task.sleep(for: .seconds(0.1))
            XCTAssertLessThan(try XCTUnwrap(view(old, in: strip)).alphaValue, 1, "the old tab is not fading out")
            try await Task.sleep(for: .seconds(0.6))
            XCTAssertNil(view(old, in: strip), "the old tab stayed after its fade")
        }
    }

    /// A swipe has already carried the old run out, so its tabs go at once
    /// rather than fading in the run sliding in.
    func testASwipeSwitchTakesTheOldTabsAtOnce() async throws {
        let fixture = try await switching()
        let (strip, old, new) = (fixture.strip, fixture.old, fixture.new)
        strip.reload(slidingSpace: true)
        strip.layoutSubtreeIfNeeded()
        XCTAssertNotNil(view(new, in: strip))
        XCTAssertNil(view(old, in: strip))
    }

    // MARK: - The bar's height

    /// A tab has the same room above it as below it, and stands on the
    /// traffic lights' line.
    func testATabHasTheSameRoomAboveAndBelow() async throws {
        let session = try await session()
        let window = UUID()
        session.openWindow(window)
        let space = try XCTUnwrap(session.spaces.first).id
        let tab = insert(tab: "One", in: space, on: session)
        let bar = TopBarView(session: session, windowID: window)
        bar.frame = NSRect(x: 0, y: 0, width: 1400, height: TopBarMetrics.barHeight)
        bar.layoutSubtreeIfNeeded()
        let row = try XCTUnwrap(view(tab, in: bar))
        let frame = bar.convert(row.bounds, from: row)
        XCTAssertEqual(frame.minY, bar.bounds.height - frame.maxY, accuracy: 0.5)
        XCTAssertEqual(
            bar.bounds.height - frame.midY,
            Tokens.Metric.trafficLightInset + Tokens.Metric.trafficLightHeight / 2,
            accuracy: 0.5
        )
    }

    // MARK: - Fixtures

    private struct Switching {
        let strip: TopBarTabStrip
        let old: UUID
        let new: UUID
    }

    /// A strip in a window, showing a Space with one tab, and the window then
    /// switched to a second Space with one of its own — not yet reloaded.
    private func switching() async throws -> Switching {
        let session = try await session()
        let window = UUID()
        session.openWindow(window)
        let first = try XCTUnwrap(session.spaces.first).id
        let old = insert(tab: "Old", in: first, on: session)
        let second = try await session.createSpace(name: "Work").id
        let new = insert(tab: "New", in: second, on: session)
        session.switchSpace(first, inWindow: window)

        let strip = TopBarTabStrip(session: session, windowID: window)
        host(strip)
        strip.frame = NSRect(x: 0, y: 0, width: 1400, height: TopBarMetrics.barHeight)
        strip.reload()
        strip.layoutSubtreeIfNeeded()
        XCTAssertNotNil(view(old, in: strip))

        session.switchSpace(second, inWindow: window)
        return Switching(strip: strip, old: old, new: new)
    }

    private func host(_ view: NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        // `close()` in `tearDown` would free it a second time otherwise.
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(view)
        windows.append(window)
    }

    /// Lets AppKit's animation clock run.
    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    }

    private func session() async throws -> BrowserSession {
        let store = try BrowserStore(path: directory.appending(path: "\(UUID().uuidString).sqlite"))
        return try await BrowserSession.restored(store: store)
    }

    private func insert(tab title: String, in space: UUID, on session: BrowserSession) -> UUID {
        let tab = Tab(spaceID: space, kind: .today, url: URL(string: "https://example.com/\(title)")!, title: title, order: 0)
        session.persistAll(session.list.insert(tab))
        return tab.id
    }

    /// The tile or row drawing `id`, or nil when the bar is not drawing it.
    private func view(_ id: UUID, in root: NSView) -> NSView? {
        for sub in root.subviews {
            if sub.identifier?.rawValue == id.uuidString { return sub }
            if let found = view(id, in: sub) { return found }
        }
        return nil
    }
}
