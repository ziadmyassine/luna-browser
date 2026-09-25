//
//  LunaControlSkyTests.swift
//  LunaTests
//
//  Luna Control's settings pane: the moon's phases, the permission cards, and
//  the sky the switch sits in (docs/LUNA-CONTROL.md, "The Settings pane").
//
//  The permission card is a button, so its press is asserted here the way
//  Tests/Design/ButtonFeedbackTests.swift asserts every other one — see
//  CLAUDE.md, "Buttons answer". It belongs in that register's list.
//

import LunaControl
import XCTest
@testable import Luna

@MainActor
final class LunaControlSkyTests: XCTestCase {

    // MARK: - The moon

    /// 0 is new and 1 is full, lit from the trailing side: a crescent is a
    /// sliver on the right, a half moon the right half, a full moon all of it.
    func testTheLitPartGrowsWithThePhase() {
        let centre = CGPoint(x: 50, y: 50), radius: CGFloat = 20
        func lit(_ phase: CGFloat, at across: CGFloat) -> Bool {
            ControlMoon.litPath(center: centre, radius: radius, phase: phase)
                .contains(CGPoint(x: centre.x + across * radius, y: centre.y))
        }
        XCTAssertFalse(lit(0, at: 0.5), "a new moon has a lit part")
        XCTAssertTrue(lit(0.2, at: 0.9), "a crescent is not lit at its edge")
        XCTAssertFalse(lit(0.2, at: 0.2), "a crescent is lit toward its middle")
        XCTAssertTrue(lit(0.5, at: 0.5), "a half moon is not lit on its trailing half")
        XCTAssertFalse(lit(0.5, at: -0.5), "a half moon is lit on its leading half")
        XCTAssertTrue(lit(1, at: -0.9), "a full moon is not lit on its leading edge")
        XCTAssertTrue(lit(1, at: 0.9), "a full moon is not lit on its trailing edge")
    }

    /// The surface is made once per size and handed back after that.
    func testTheMoonsSurfaceIsMadeOncePerSize() throws {
        let first = try XCTUnwrap(ControlMoon.surface(radius: 15, scale: 2))
        XCTAssertEqual(first.width, 60)
        XCTAssertTrue(ControlMoon.surface(radius: 15, scale: 2) === first)
    }

    /// Five apps, five colours, and a sixth takes the first again rather than
    /// running off the end of the palette.
    func testEveryKnownAppHasItsOwnColour() {
        let colours = (0..<5).map { Tokens.Moon.satellite($0) }
        XCTAssertEqual(Set(colours.map(\.description)).count, 5)
        XCTAssertEqual(Tokens.Moon.satellite(5), Tokens.Moon.satellite(0))
        XCTAssertEqual(Tokens.Moon.satellite(-1), Tokens.Moon.satellite(4))
    }

    func testAPlanetCarriesTheAppsInitials() {
        XCTAssertEqual(ControlPlanetView.initials(of: "Claude Code"), "CC")
        XCTAssertEqual(ControlPlanetView.initials(of: "VS Code"), "VS")
        XCTAssertEqual(ControlPlanetView.initials(of: "Codex"), "Co")
    }

    // MARK: - The sky

    /// A rebuild hands the sky the same apps again; each must stay where it
    /// had got to on its orbit rather than jumping back to where it started.
    func testAnAppKeepsItsPlaceOnItsOrbitAcrossARebuild() throws {
        let sky = ControlSkyView(title: "Title", subtitle: "Subtitle")
        sky.frame = NSRect(x: 0, y: 0, width: 460, height: Tokens.Metric.controlSkyHeight)
        let app = ControlSkyView.Satellite(
            id: "codex", name: "Codex", colour: .white, orbit: 1, startAngle: 0.6, isLive: false
        )
        sky.setSatellites([app])
        sky.bodies["codex"]?.angle = 2
        sky.setSatellites([app])
        XCTAssertEqual(try XCTUnwrap(sky.bodies["codex"]).angle, 2, accuracy: 0.0001)
    }

    func testTheSwitchIsInTheSkyAndSaysWhatItControls() throws {
        let section = LunaControlSection()
        let switches = descendants(of: section.view, ofType: SystemSwitch.self)
        let toggle = try XCTUnwrap(switches.first { $0.accessibilityLabel() == "Allow apps to control Luna" })
        XCTAssertEqual(toggle.isOn, ControlService.isEnabled)
        XCTAssertTrue(section.searchIndex.contains("allow apps to control luna"))
    }

    // MARK: - The permission cards

    func testTheCardsShowTheModeTheyAreGiven() {
        let picker = ControlModePicker(title: "Before an app acts on a page")
        picker.select(.allowAll, animated: false)
        let chosen = descendants(of: picker, ofType: ControlModeCard.self)
            .filter { ($0.accessibilityValue() as? Bool) == true }
            .map(\.choice.mode)
        XCTAssertEqual(chosen, [.allowAll])
    }

    func testChoosingACardReportsItsMode() throws {
        let picker = ControlModePicker(title: "Before an app acts on a page")
        var reported: [ControlMode] = []
        picker.onChange = { reported.append($0) }
        let perSite = try XCTUnwrap(descendants(of: picker, ofType: ControlModeCard.self)
            .first { $0.choice.mode == .allowPerSite })
        _ = perSite.accessibilityPerformPress()
        _ = perSite.accessibilityPerformPress()
        XCTAssertEqual(reported, [.allowPerSite], "choosing the chosen card again reported it twice")
    }

    func testAPermissionCardSwellsUnderAPress() {
        let card = ControlModeCard(choice: ControlModePicker.choices[0])
        card.frame = NSRect(x: 0, y: 0, width: 140, height: 118)
        card.layoutSubtreeIfNeeded()
        card.mouseDown(with: mouse(.leftMouseDown, in: card))
        XCTAssertEqual(card.layer?.transform.m11 ?? 1, Tokens.Motion.pressSwell, accuracy: 0.001)
        card.mouseUp(with: mouse(.leftMouseUp, in: card))
        XCTAssertEqual(card.layer?.transform.m11 ?? 1, 1, accuracy: 0.001)
    }

    // MARK: - Helpers

    private func mouse(_ type: NSEvent.EventType, in view: NSView) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: NSPoint(x: view.bounds.midX, y: view.bounds.midY), modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ) ?? NSEvent()
    }

    private func descendants<T: NSView>(of root: NSView, ofType type: T.Type) -> [T] {
        root.subviews.flatMap { view in ((view as? T).map { [$0] } ?? []) + descendants(of: view, ofType: type) }
    }
}
