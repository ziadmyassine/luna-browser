import Foundation
import LunaControl
import Testing

/// The capture tools' half that needs no web view: `screenshot`'s scale and
/// region, `gif`, `viewport`, how the gate weighs them, and coordinates from
/// a scaled screenshot mapped back to CSS pixels.
@Suite("Luna Control capture calls")
struct ControlCaptureCallTests {

    private func command(_ tool: String, _ args: [String: JSONValue]) -> ControlCommand? {
        try? ControlCall.parse(tool: tool, arguments: args)?.get().command
    }

    private func error(_ tool: String, _ args: [String: JSONValue]) -> String? {
        guard case let .failure(error)? = ControlCall.parse(tool: tool, arguments: args) else { return nil }
        return error.message
    }

    @Test func screenshotTakesAScaleAndARegion() {
        #expect(command("screenshot", [:]) == .screenshot())
        #expect(command("screenshot", ["scale": 0.5]) == .screenshot(scale: 0.5))
        #expect(command("screenshot", ["scale": 0.01]) == .screenshot(scale: 0.1))
        #expect(command("screenshot", ["scale": 3]) == .screenshot(scale: 1))
        #expect(command("screenshot", ["region": [10, 20, 110, 70]])
            == .screenshot(region: ControlCommand.Region(x: 10, y: 20, width: 100, height: 50)))
    }

    @Test func aRegionMustBeFourCornersInOrder() {
        #expect(error("screenshot", ["region": [10, 20, 5, 70]]) != nil)
        #expect(error("screenshot", ["region": [10, 20, 30]]) != nil)
        #expect(error("screenshot", ["region": [-1, 0, 30, 30]]) != nil)
    }

    @Test func gifStartsStopsAndExports() {
        #expect(command("gif", ["action": "start"]) == .gif(.start))
        #expect(command("gif", ["action": "stop"]) == .gif(.stop))
        #expect(command("gif", ["action": "export"]) == .gif(.export))
        #expect(error("gif", ["action": "rewind"]) != nil)
    }

    @Test func viewportIsBetweenAPhoneAndA4KScreen() {
        #expect(command("viewport", ["width": 390, "height": 844]) == .viewport(ControlCommand.Size(width: 390, height: 844)))
        #expect(command("viewport", [:]) == .viewport(nil))
        #expect(error("viewport", ["width": 319, "height": 844]) != nil)
        #expect(error("viewport", ["width": 390, "height": 3841]) != nil)
        #expect(error("viewport", ["width": 390]) != nil)
    }

    // They change nothing on the site: a picture, a recording kept in Luna's
    // own folder, the agent's own tab laid out at another size.
    @Test func captureToolsAreReadsThatNeverAsk() {
        for command: ControlCommand in [
            .screenshot(scale: 0.3, region: ControlCommand.Region(x: 0, y: 0, width: 10, height: 10)),
            .gif(.start), .gif(.stop), .gif(.export), .viewport(ControlCommand.Size(width: 390, height: 844)), .viewport(nil)
        ] {
            #expect(!command.acts, "\(command)")
            let decision = ControlPolicy.decide(
                command, site: "example.com", client: "a", facts: ControlFacts(), permissions: ControlPermissions(mode: .ask)
            )
            #expect(decision == .allow, "\(command)")
            // Luna's own pages stay unreadable, recordings included.
            #expect(ControlPolicy.decide(
                command, site: nil, client: "a", facts: ControlFacts(isInternalPage: true), permissions: ControlPermissions()
            ) == .deny(ControlPolicy.internalReason))
        }
    }

    @Test func pointsFromAScaledScreenshotMapBackToCSSPixels() {
        let click = ControlCommand.click(.point(x: 50, y: 20), clickCount: 1)
        #expect(click.fromScreenshot(scale: 0.5) == .click(.point(x: 100, y: 40), clickCount: 1))
        #expect(ControlCommand.click(.ref("e1"), clickCount: 1).fromScreenshot(scale: 0.5) == .click(.ref("e1"), clickCount: 1))
        #expect(ControlCommand.drag(from: .point(x: 1, y: 2), to: .point(x: 3, y: 4)).fromScreenshot(scale: 0.5)
            == .drag(from: .point(x: 2, y: 4), to: .point(x: 6, y: 8)))
        #expect(ControlCommand.hover(.point(x: 10, y: 10)).fromScreenshot(scale: 0.25) == .hover(.point(x: 40, y: 40)))
        #expect(ControlCommand.scroll(.down, amount: 1, target: .point(x: 5, y: 5)).fromScreenshot(scale: 0.5)
            == .scroll(.down, amount: 1, target: .point(x: 10, y: 10)))
        #expect(ControlCommand.pageText.fromScreenshot(scale: 0.5) == .pageText)
    }

    @Test func aRecordingTakesAFrameAfterWhatChangesThePage() {
        #expect(ControlCommand.click(.ref("e1"), clickCount: 1).recordsFrame)
        #expect(ControlCommand.scroll(.down, amount: 1, target: nil).recordsFrame)
        #expect(ControlCommand.viewport(nil).recordsFrame)
        #expect(!ControlCommand.pageText.recordsFrame)
        #expect(!ControlCommand.screenshot().recordsFrame)
        #expect(!ControlCommand.gif(.export).recordsFrame)
    }

    @Test func theLogNamesEachCaptureTool() {
        #expect(ControlAudit.tool(of: .screenshot(scale: 0.5)) == "screenshot")
        #expect(ControlAudit.summary(of: .gif(.export)) == "gif export")
        #expect(ControlAudit.summary(of: .viewport(ControlCommand.Size(width: 390, height: 844))) == "viewport 390×844")
        #expect(ControlAudit.summary(of: .viewport(nil)) == "viewport restore")
        #expect(ControlTools.names.isSuperset(of: ["gif", "viewport"]))
    }
}
