//
//  SpaceGestureTests.swift
//  LunaTests
//
//  §30.9's swipe as a **gesture** rather than as arithmetic: real scroll events
//  with real phases, through the real controller, into a real session — the
//  half `SpaceSwipeTests` cannot reach.
//
//  **This was thought to need a trackpad, and it does not.** The gesture reacts
//  only to a scroll carrying an `NSEvent.Phase`, which no ordinary `NSEvent`
//  initialiser produces — but `CGEvent(scrollWheelEvent2Source:…)` does, its
//  `timestamp` arrives on the other side as `NSEvent.timestamp` one nanosecond
//  for one nanosecond, and both halves of what the gesture measures are
//  therefore controllable from a test: how far the fingers went, and how fast
//  they were still going when they left. That second one is the whole of the
//  difference between a page turn and a new Space, and until now nothing
//  checked it.
//
//  The defect these were written for: **a Space could not be created.** The
//  create asked for three pages of travel, which against the damping ceiling
//  needs longer than an ordinary stroke lasts — so the `+` closed, because its
//  ring only costs a third of that, and the release made nothing. Every time.
//  The two tests that matter most here are the same stroke twice, lifted two
//  different ways.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class SpaceGestureTests: XCTestCase {

    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var window: NSWindow?

    override func setUp() async throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        window = nil
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Making one (§6.1 from §30.9)

    /// **The reported defect.** One deliberate push, out to the end of the
    /// column and held there, makes a Space and opens its editor.
    func testAPagePushedOutAndHeldMakesASpace() async throws {
        let (session, gestures) = try await sidebar()
        let before = session.spaces.count
        push(gestures, page: gestures.contentRect.width, restingBeforeTheLift: true)
        try await eventually("the editor opened") { gestures.editor != nil }
        XCTAssertEqual(session.spaces.count, before + 1)
    }

    /// **The same stroke, lifted while it was still moving, makes nothing** —
    /// and this is the whole of the resistance. It used to be distance, which
    /// punished the deliberate gesture exactly as hard as the accidental one
    /// and is why the deliberate one became impossible. A flick off the end of
    /// the Spaces is a reflex that overshot; a push that comes to rest is a
    /// decision.
    func testTheSameStrokeFlickedMakesNothing() async throws {
        let (session, gestures) = try await sidebar()
        let before = session.spaces.count
        push(gestures, page: gestures.contentRect.width, restingBeforeTheLift: false)
        try await settling()
        XCTAssertEqual(session.spaces.count, before, "a flick past the last Space made one")
        XCTAssertNil(gestures.editor)
    }

    // MARK: - Turning a page (§30.9)

    /// **"One single fast swipe should also go to the next Space."** A quarter
    /// of a page — nowhere near the half that commits on distance — turns the
    /// page because the fingers were still moving when they left.
    func testOneFastSwipeChangesSpace() async throws {
        let (session, gestures) = try await sidebar(spaces: 2)
        let first = session.activeSpaceID
        flick(gestures, events: 6)
        try await eventually("the Space changed") { session.activeSpaceID != first }
    }

    /// **"A little swipe is too big a move."** Two fifths of a page, let go of
    /// gently, is a look at the next Space and not a move to it — the column
    /// springs back. Under the old ruler this same hand travel was three and a
    /// half Spaces and would have committed several times over.
    func testASmallSlowSwipeStaysWhereItIs() async throws {
        let (session, gestures) = try await sidebar(spaces: 2)
        let first = session.activeSpaceID
        drag(gestures, events: 20, perEvent: 6)
        try await settling()
        XCTAssertEqual(session.activeSpaceID, first, "a gentle look changed Space")
    }

    // MARK: - Whose scroll is it (§3.4)

    /// A scroll down the list is the list's, however much it wanders sideways.
    func testAVerticalScrollIsLeftToTheList() async throws {
        let (_, gestures) = try await sidebar()
        XCTAssertFalse(scrolled(gestures, dx: 5, dy: 60, events: 10), "the swipe took a vertical scroll")
    }

    /// …and a sideways swipe is the swipe's, however much *it* wanders.
    ///
    /// **The units used to disagree.** `drift` added the raw `scrollingDeltaY`
    /// to a comparison against an offset the damping ceiling had already folded
    /// down, so a brisk horizontal swipe lost to its own wobble and the list
    /// kept the scroll. Both sides come through the same curve now.
    func testASidewaysSwipeWithAWobbleIsStillASwipe() async throws {
        let (_, gestures) = try await sidebar()
        XCTAssertTrue(scrolled(gestures, dx: -60, dy: 20, events: 10), "a wobbly swipe was dropped")
    }

    // MARK: - Strokes

    /// A deliberate push out past the last Space: 30 pt of already-accelerated
    /// delta per frame for a quarter of a second, which is a firm, unhurried
    /// hand and about as long as a trackpad stroke lasts.
    ///
    /// **The length is the test.** Against the damping ceiling this carries a
    /// little over one page, which is comfortably past what a create now costs
    /// and comfortably short of the three pages it used to — so a stroke a real
    /// hand performs separates the two thresholds, and lengthening it here
    /// would quietly re-admit the bug.
    private func push(_ gestures: SidebarSpaceGestures, page: CGFloat, restingBeforeTheLift resting: Bool) {
        stroke(gestures, perEvent: -30, events: 15, hz: 60, restingBeforeTheLift: resting)
    }

    /// A flick: saturating deltas, over in a handful of events, lifted in
    /// flight.
    private func flick(_ gestures: SidebarSpaceGestures, events: Int) {
        stroke(gestures, perEvent: -200, events: events, hz: 120, restingBeforeTheLift: false)
    }

    /// A gentle drag, well under the damping knee, that stops where it stops.
    private func drag(_ gestures: SidebarSpaceGestures, events: Int, perEvent: Double) {
        stroke(gestures, perEvent: -perEvent, events: events, hz: 60, restingBeforeTheLift: false)
    }

    private func stroke(
        _ gestures: SidebarSpaceGestures,
        perEvent: Double,
        events: Int,
        hz: Double,
        restingBeforeTheLift: Bool
    ) {
        var now = 1.0
        _ = gestures.scrollWheel(with: scroll(dx: 0, dy: 0, phase: .began, at: now))
        for _ in 0..<events {
            now += 1 / hz
            _ = gestures.scrollWheel(with: scroll(dx: perEvent, dy: 0, phase: .changed, at: now))
        }
        // A hand that came to rest still sends no events while it rests, so the
        // only trace of the pause is the gap before the lift.
        if restingBeforeTheLift { now += 0.2 }
        _ = gestures.scrollWheel(with: scroll(dx: 0, dy: 0, phase: .ended, at: now))
    }

    /// Whether the swipe claimed the stroke. True means the list never saw it.
    private func scrolled(_ gestures: SidebarSpaceGestures, dx: Double, dy: Double, events: Int) -> Bool {
        var now = 1.0
        var taken = false
        _ = gestures.scrollWheel(with: scroll(dx: 0, dy: 0, phase: .began, at: now))
        for _ in 0..<events {
            now += 1.0 / 60
            taken = gestures.scrollWheel(with: scroll(dx: dx, dy: dy, phase: .changed, at: now)) || taken
        }
        _ = gestures.scrollWheel(with: scroll(dx: 0, dy: 0, phase: .ended, at: now))
        return taken
    }

    /// A precise trackpad scroll carrying a phase — the only kind §30.9 reads.
    ///
    /// **Field 99 is CoreGraphics' phase, not AppKit's**, and the two
    /// enumerations do not agree: `kCGScrollPhaseChanged` is 2 where
    /// `NSEvent.Phase.changed` is 4, so writing AppKit's bits into a `CGEvent`
    /// produces a stroke whose every move arrives as a *release*. The gesture
    /// then commits on the first event and sits out the rest, which is a way of
    /// passing tests without touching the code they are about. The round trip
    /// is asserted below rather than trusted.
    private func scroll(dx: Double, dy: Double, phase: NSEvent.Phase, at time: TimeInterval) -> NSEvent {
        let coreGraphicsPhase: Int64 = switch phase {
        case .began: 1
        case .changed: 2
        case .ended: 4
        case .cancelled: 8
        default: 0
        }
        guard
            let cg = CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0
            ),
            let field = CGEventField(rawValue: 99)
        else { preconditionFailure("a scroll event could not be built") }
        cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: dy)
        cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: dy)
        cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: dx)
        cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: dx)
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        cg.setIntegerValueField(field, value: coreGraphicsPhase)
        cg.timestamp = UInt64(time * 1_000_000_000)
        guard let event = NSEvent(cgEvent: cg) else { preconditionFailure("a scroll event did not convert") }
        precondition(event.phase == phase, "a \(phase) scroll arrived as \(event.phase)")
        // Nanoseconds in, seconds out, so the last digit is quantisation and
        // not a clock that disagrees — which is the thing worth knowing, since
        // every interval the gesture measures comes off this number.
        precondition(
            abs(event.timestamp - time) < 1e-6,
            "a scroll at \(time) arrived at \(event.timestamp)"
        )
        return event
    }

    // MARK: - The column

    /// A real sidebar over a real session, laid out at a real width — the
    /// gesture measures itself against the column, so a column with no width
    /// would measure nothing.
    private func sidebar(spaces: Int = 1) async throws -> (BrowserSession, SidebarSpaceGestures) {
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        let session = try await BrowserSession.restored(store: store)
        let first = session.activeSpaceID
        for index in 1..<max(spaces, 1) {
            _ = try await session.createSpace(name: "Space \(index + 1)")
        }
        // …and back to the first, so there is somewhere forward to go.
        session.switchSpace(first)
        let controller = SidebarViewController(session: session)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 800),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentViewController = controller
        controller.view.frame = NSRect(x: 0, y: 0, width: 300, height: 800)
        controller.view.layoutSubtreeIfNeeded()
        self.window = window
        guard let gestures = controller.spaces else { preconditionFailure("the column built no gesture") }
        return (session, gestures)
    }

    /// The release animates before it commits, so a negative assertion has to
    /// outlast the settle rather than race it.
    private func settling() async throws {
        try await Task.sleep(for: .seconds(Tokens.Motion.spaceSettleSlowest.duration * 3))
    }

    private func eventually(
        _ what: String,
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
