import Foundation
import Testing
import WebKit
@testable import BrowserKit

/// §17.8: when a page's request for the camera, the microphone or the location is
/// put to the user, what an answer does, and what no answer does. Private data
/// stores throughout, so every answer stays in memory and off the user's database.
@Suite("Camera, microphone and location (§17.8)")
@MainActor
struct DevicePermissionTests {

    /// Answers whatever it is asked with `answer`, and counts the questions.
    @MainActor private final class Asker: TabControllerDelegate {
        var answer: Bool?
        var asked: [[BrowserStore.SitePermission]] = []

        init(answer: Bool?) { self.answer = answer }

        func tabController(_ controller: TabController, didChange state: TabState) {}
        func tabController(
            _ controller: TabController,
            wantsNewTabFor url: URL?,
            configuration: WKWebViewConfiguration
        ) -> WKWebView? { nil }
        func tabController(_ controller: TabController, didStartDownload download: WKDownload) {}
        func tabController(_ controller: TabController, didFailWith error: Error) {}
        func tabController(
            _ controller: TabController,
            wantsAccessTo permissions: [BrowserStore.SitePermission],
            forHost host: String
        ) async -> Bool? {
            asked.append(permissions)
            return answer
        }
    }

    private func tab(answering answer: Bool?) -> (TabController, Asker) {
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        let asker = Asker(answer: answer)
        controller.delegate = asker
        return (controller, asker)
    }

    @Test func aCallForBothDevicesNeedsAnAnswerForEach() {
        #expect(DeviceRequest.permissions(for: .camera) == [.camera])
        #expect(DeviceRequest.permissions(for: .microphone) == [.microphone])
        #expect(DeviceRequest.permissions(for: .cameraAndMicrophone) == [.camera, .microphone])
    }

    @Test func noForEitherDeviceIsNoAndYesNeedsBoth() {
        let scope = SitePermissions.scope(for: .nonPersistent())
        let both: [BrowserStore.SitePermission] = [.camera, .microphone]
        #expect(DeviceRequest.standingAnswer(for: both, host: "meet.example", in: scope) == nil)
        scope.setAllowed(true, .camera, forHost: "meet.example")
        #expect(DeviceRequest.standingAnswer(for: both, host: "meet.example", in: scope) == nil, "the microphone was never answered")
        scope.setAllowed(true, .microphone, forHost: "meet.example")
        #expect(DeviceRequest.standingAnswer(for: both, host: "meet.example", in: scope) == true)
        scope.setAllowed(false, .microphone, forHost: "meet.example")
        #expect(DeviceRequest.standingAnswer(for: both, host: "meet.example", in: scope) == false)
    }

    @Test func anAnswerIsKeptSoTheSiteIsNotAskedTwice() async {
        let (controller, asker) = tab(answering: true)
        #expect(await controller.decide([.camera, .microphone], host: "meet.example") == .grant)
        #expect(await controller.decide([.camera], host: "meet.example") == .grant)
        #expect(asker.asked == [[.camera, .microphone]], "asked again after an Allow")
        #expect(controller.sitePermissions.answer(.microphone, forHost: "meet.example") == true)
    }

    @Test func aNoIsKeptToo() async {
        let (controller, asker) = tab(answering: false)
        #expect(await controller.decide([.location], host: "maps.example") == .deny)
        #expect(await controller.decide([.location], host: "maps.example") == .deny)
        #expect(asker.asked.count == 1, "asked again after Don't Allow")
    }

    /// The toast went away unanswered: a no for now, and the site may ask again.
    @Test func noAnswerIsNotKept() async {
        let (controller, asker) = tab(answering: nil)
        #expect(await controller.decide([.camera], host: "meet.example") == .deny)
        #expect(controller.sitePermissions.answer(.camera, forHost: "meet.example") == nil)
        asker.answer = true
        #expect(await controller.decide([.camera], host: "meet.example") == .grant)
        #expect(asker.asked.count == 2)
    }

    /// One site's answer is not another's, even inside the same tab.
    @Test func theAnswerBelongsToTheSiteThatAsked() async {
        let (controller, asker) = tab(answering: true)
        _ = await controller.decide([.camera], host: "meet.example")
        _ = await controller.decide([.camera], host: "other.example")
        #expect(asker.asked.count == 2)
    }

    @Test func aTabWithNoOneToAskRefuses() async {
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        #expect(await controller.decide([.camera], host: "meet.example") == .deny)
        #expect(await controller.decide([.camera], host: "") == .deny)
    }

    /// WebKit only asks a delegate that answers to this exact selector, so a
    /// misspelt Swift name would leave location refused without a word.
    @Test func theLocationQuestionReachesTheController() {
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        let selector = NSSelectorFromString("webView:requestGeolocationPermissionForOrigin:initiatedByFrame:decisionHandler:")
        #expect(controller.responds(to: selector))
    }

    @Test func aLiveTabStartsWithItsDevicesOff() {
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.activate()
        #expect(controller.state.camera == .off)
        #expect(controller.state.microphone == .off)
    }
}
