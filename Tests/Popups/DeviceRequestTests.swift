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
        XCTAssertEqual(request([.clipboard]).text, "Read the clipboard?")
        let toast = request([.camera])
        XCTAssertEqual(toast.detail, "meet.example")
        XCTAssertEqual(toast.actions.map(\.title), ["Allow", "Don’t Allow"])
    }

    /// §18.8: what a site that may read the clipboard is handed — the text for
    /// `readText`, and the HTML and a PNG as well for `read` — from a pasteboard of
    /// the test's own, never the user's.
    func testAReadHandsOverTheClipboardByType() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("luna-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let picture = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )?.tiffRepresentation)
        pasteboard.setString("copied", forType: .string)
        pasteboard.setString("<b>copied</b>", forType: .html)
        pasteboard.setData(picture, forType: .tiff)

        XCTAssertEqual(ClipboardReading.contents(of: pasteboard, pictures: false), ["text/plain": "copied"])
        let all = ClipboardReading.contents(of: pasteboard, pictures: true)
        XCTAssertEqual(all["text/html"], "<b>copied</b>")
        let png = try XCTUnwrap(all["image/png"].flatMap { Data(base64Encoded: $0) })
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "a TIFF goes to the page as a PNG")

        pasteboard.clearContents()
        XCTAssertEqual(ClipboardReading.contents(of: pasteboard, pictures: true), [:], "empty is not a refusal")
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
