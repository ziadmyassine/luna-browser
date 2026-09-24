//
//  SettingsLayoutPickerTests.swift
//  LunaTests
//
//  Appearance's Layout row as pictures: one per layout, the chosen one
//  ringed, a click on the other choosing it, and a press swelling the
//  picture the way every button in the app answers one.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class SettingsLayoutPickerTests: XCTestCase {

    private func mouse(_ type: NSEvent.EventType, in view: NSView) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    }

    func testThereIsAPictureForEachLayoutAndOneIsChosen() {
        let picker = SettingsLayoutPicker(selected: .topBar)
        XCTAssertEqual(picker.options.map(\.layout), ChromeLayoutPreference.allCases)
        XCTAssertEqual(picker.options.filter(\.isChosen).map(\.layout), [.topBar])
    }

    func testAClickOnTheOtherPictureChoosesIt() throws {
        let picker = SettingsLayoutPicker(selected: .sidebar)
        picker.frame = NSRect(x: 0, y: 0, width: 400, height: 120)
        picker.layoutSubtreeIfNeeded()
        var chosen: ChromeLayoutPreference?
        picker.onChoose = { chosen = $0 }
        let top = try XCTUnwrap(picker.options.first { $0.layout == .topBar })
        top.mouseDown(with: try XCTUnwrap(mouse(.leftMouseDown, in: top)))
        XCTAssertEqual(top.picture.layer?.transform.m11 ?? 1, Tokens.Motion.pressSwell, accuracy: 0.001)
        top.mouseUp(with: try XCTUnwrap(mouse(.leftMouseUp, in: top)))
        XCTAssertEqual(top.picture.layer?.transform.m11 ?? 1, 1, accuracy: 0.001)
        XCTAssertEqual(chosen, .topBar)
        XCTAssertEqual(picker.selected, .topBar)
        XCTAssertEqual(picker.options.filter(\.isChosen).map(\.layout), [.topBar])
        // Choosing what is already chosen says nothing.
        chosen = nil
        XCTAssertTrue(top.accessibilityPerformPress())
        XCTAssertNil(chosen)
    }
}
