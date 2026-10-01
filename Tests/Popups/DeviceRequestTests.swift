//
//  DeviceRequestTests.swift
//  LunaTests
//
//  §17.8's question as the user sees it: what the toast says, that each of
//  its answers is heard once, that going away unanswered is heard as no
//  answer, and the tab row's camera and microphone while they are on.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class DeviceRequestTests: XCTestCase {

    private var answers: [Bool?] = []

    private func surface() -> ControlSurfaceView {
        let surface = ControlSurfaceView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        surface.topInset = 52
        return surface
    }

    private func request(_ permissions: [BrowserStore.SitePermission]) -> PageToast {
        PageToast.deviceRequest(permissions, host: "meet.example") { [weak self] in self?.answers.append($0) }
    }

    func testTheQuestionNamesTheDeviceAndTheSite() {
        XCTAssertEqual(request([.camera]).text, "Use the camera?")
        XCTAssertEqual(request([.microphone]).text, "Use the microphone?")
        XCTAssertEqual(request([.camera, .microphone]).text, "Use the camera and microphone?")
        XCTAssertEqual(request([.location]).text, "Use your location?")
        let toast = request([.camera])
        XCTAssertEqual(toast.detail, "meet.example")
        XCTAssertEqual(toast.actions.map(\.title), ["Allow", "Don’t Allow"])
    }

    func testAllowIsHeardOnceAndTheToastGoes() throws {
        let surface = surface()
        surface.showToast(request([.camera]))
        let allow = try XCTUnwrap(surface.toast?.buttons.first)
        allow.onActivate?()
        XCTAssertEqual(answers, [true])
        XCTAssertNil(surface.toast, "the toast stayed after it was answered")
    }

    func testDontAllowIsHeardOnce() throws {
        let surface = surface()
        surface.showToast(request([.microphone]))
        let refuse = try XCTUnwrap(surface.toast?.buttons.last)
        refuse.onActivate?()
        surface.hideToast()
        XCTAssertEqual(answers, [false])
    }

    /// The page is waiting on the answer, so the toast leaving without one has
    /// to be heard, or the call never hears back.
    func testGoingAwayUnansweredIsHeardAsNoAnswer() {
        let surface = surface()
        surface.showToast(request([.camera]))
        surface.hideToast()
        XCTAssertEqual(answers, [nil])
    }

    func testAnotherToastTakingItsPlaceIsNoAnswer() {
        let surface = surface()
        surface.showToast(request([.camera]))
        surface.showToast(.linkCopied)
        XCTAssertEqual(answers, [nil])
        surface.hideToast()
        XCTAssertEqual(answers, [nil], "the question was answered twice")
    }

    func testTheRowShowsTheCameraOrTheMicrophoneWhileOn() {
        XCTAssertNil(SidebarRowContent.Trailing.inUse(TabState()))
        XCTAssertNil(SidebarRowContent.Trailing.inUse(nil))
        XCTAssertEqual(SidebarRowContent.Trailing.inUse(TabState(microphone: .on)), .devices(camera: false))
        XCTAssertEqual(SidebarRowContent.Trailing.inUse(TabState(camera: .on, microphone: .on)), .devices(camera: true))
        XCTAssertEqual(
            SidebarRowContent.Trailing.inUse(TabState(camera: .paused)), .devices(camera: true),
            "a paused camera is still held by the page"
        )
    }
}
