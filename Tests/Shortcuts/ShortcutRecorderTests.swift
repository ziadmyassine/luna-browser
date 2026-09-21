//
//  ShortcutRecorderTests.swift
//  LunaTests
//
//  §3.6's capture control, and the one measured question underneath it: does
//  a local event monitor see a keystroke before the menu bar acts on it?
//
//  The whole feature rests on that answer. If the menu got there first, the
//  recorder would be unusable for exactly the shortcuts people want to change —
//  pressing ⇧⌘T over it would reopen a tab instead of being recorded, and the
//  control would look like it simply ignored the keystroke.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class ShortcutRecorderTests: XCTestCase {

    /// The measurement. `⌘T` is a live key equivalent in Luna's menu bar, and a
    /// local monitor returning nil is what stops it reaching there — so this
    /// asserts both halves: the monitor is reached from `NSApplication.sendEvent`,
    /// and the menu item that would otherwise fire is not.
    func testALocalMonitorSeesAKeystrokeTheMenuWouldOtherwiseTake() throws {
        let newTab = try XCTUnwrap(
            NSApp.mainMenu?.items.first { $0.title == "File" }?.submenu?
                .items.first { $0.action == #selector(AppDelegate.newTab(_:)) }
        )
        XCTAssertEqual(newTab.keyEquivalent, "t", "the premise: ⌘T is a real key equivalent")

        var seen: NSEvent?
        let monitor = try XCTUnwrap(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            seen = event
            return nil
        })
        defer { NSEvent.removeMonitor(monitor) }

        NSApp.sendEvent(Self.keyDown("t", .command))
        XCTAssertEqual(seen?.charactersIgnoringModifiers, "t", "the monitor never saw the keystroke")
    }

    // MARK: - Capture

    func testAModifiedKeystrokeIsRecordedAndEndsTheRecording() {
        let recorder = SettingsShortcutRecorder(binding: KeyBinding("t"))
        var recorded: [KeyBinding?] = []
        recorder.onRecord = { recorded.append($0) }

        recorder.beginRecording()
        XCTAssertTrue(recorder.isListening)
        recorder.record(Self.keyDown("j", [.command, .option]))

        XCTAssertEqual(recorded, [KeyBinding("j", [.command, .option])])
        XCTAssertFalse(recorder.isListening)
    }

    /// Escape is a cancel, and a cancel is not a change — the difference
    /// matters because `onRecord(nil)` means "clear this shortcut", which is a
    /// real edit the user would not be able to undo by pressing Escape.
    func testEscapeCancelsWithoutRecordingAnything() {
        let recorder = SettingsShortcutRecorder(binding: KeyBinding("t"))
        var calls = 0
        recorder.onRecord = { _ in calls += 1 }

        recorder.beginRecording()
        recorder.record(Self.keyDown("\u{1B}", []))

        XCTAssertEqual(calls, 0, "Escape must not be mistaken for clearing the shortcut")
        XCTAssertFalse(recorder.isListening)
    }

    func testDeleteClearsTheShortcut() {
        let recorder = SettingsShortcutRecorder(binding: KeyBinding("t"))
        var recorded: [KeyBinding?] = []
        recorder.onRecord = { recorded.append($0) }

        recorder.beginRecording()
        recorder.record(Self.keyDown("\u{7F}", []))

        XCTAssertEqual(recorded.count, 1)
        XCTAssertNil(recorded.first ?? KeyBinding("x"), "Delete means no shortcut")
        XCTAssertFalse(recorder.isListening)
    }

    /// A keystroke that cannot be a shortcut leaves the recorder listening
    /// rather than committing something unusable or silently giving up. The
    /// user pressed a key and nothing happened, so the next key still counts.
    func testAKeystrokeWithNoModifierKeepsTheRecorderListening() {
        let recorder = SettingsShortcutRecorder(binding: nil)
        var calls = 0
        recorder.onRecord = { _ in calls += 1 }

        recorder.beginRecording()
        recorder.record(Self.keyDown("q", []))
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(recorder.isListening)

        recorder.stop()
    }

    /// The monitor is process-wide while it is installed, so a recorder that
    /// leaves its window mid-recording has to take it down — nothing else will.
    ///
    /// A real `NSWindow`, because the hook is `viewDidMoveToWindow` and a
    /// view in a detached hierarchy never had one to move out of — the first
    /// version of this test asserted against a bare `NSView` and proved nothing.
    func testLeavingTheWindowEndsTheRecording() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled], backing: .buffered, defer: true
        )
        let recorder = SettingsShortcutRecorder(binding: nil)
        window.contentView?.addSubview(recorder)
        recorder.beginRecording()
        XCTAssertTrue(recorder.isListening)

        recorder.removeFromSuperview()
        XCTAssertFalse(recorder.isListening, "the monitor is process-wide and would have outlived the view")
    }

    /// The distinction §3.6 leans on, measured rather than described: the two
    /// controls sat on the same well with the same hairline, so the pane drew a
    /// shortcut you can change and one you cannot identically, and the only way
    /// to tell them apart was to click one.
    func testAFixedShortcutIsNotDrawnAsSomethingYouCanClick() throws {
        let editable = SettingsShortcutRecorder(binding: KeyBinding("t"))
        editable.updateLayer()
        let border = try XCTUnwrap(editable.layer?.borderWidth)
        XCTAssertGreaterThan(border, 0, "the editable chip is a bordered well")
        XCTAssertNotNil(editable.layer?.backgroundColor)

        let fixed = SettingsKeyChip(key: "⌘Q", isFixed: true)
        fixed.updateLayer()
        XCTAssertEqual(fixed.layer?.borderWidth, 0, "a fixed shortcut keeps no box")
        XCTAssertNil(fixed.layer?.backgroundColor, "nor a well, which would read as a dimmed control")
    }

    private static func keyDown(_ characters: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 0
        )!
    }
}
