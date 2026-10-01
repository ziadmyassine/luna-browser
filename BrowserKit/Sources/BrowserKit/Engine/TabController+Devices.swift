//
//  TabController+Devices.swift
//  BrowserKit
//
//  §17.8: a page asking for the camera, the microphone or the location, and
//  the camera and microphone while they are on. The question itself is the
//  delegate's to put; whether there is one to put, and keeping the answer, is
//  here, where it can be tested without a window.
//

import WebKit

/// What a page asked for, as the per-site answers it needs.
public enum DeviceRequest {

    /// One answer per device: a request for both needs both.
    public static func permissions(for type: WKMediaCaptureType) -> [BrowserStore.SitePermission] {
        switch type {
        case .camera: [.camera]
        case .microphone: [.microphone]
        case .cameraAndMicrophone: [.camera, .microphone]
        @unknown default: [.camera, .microphone]
        }
    }

    /// The answer already given, or nil when the site has to be asked. A no for any
    /// device it wants is a no; a yes needs a yes for every one.
    @MainActor
    public static func standingAnswer(
        for permissions: [BrowserStore.SitePermission],
        host: String?,
        in scope: SitePermissions
    ) -> Bool? {
        let answers = permissions.map { scope.answer($0, forHost: host) }
        if answers.contains(false) { return false }
        return answers.allSatisfy { $0 == true } ? true : nil
    }
}

/// A camera or microphone as a page has it: off, on, or paused by the page.
public enum CaptureState: Sendable, Equatable {
    case off, on, paused

    init(_ state: WKMediaCaptureState) {
        switch state {
        case .active: self = .on
        case .muted: self = .paused
        default: self = .off
        }
    }
}

extension TabState {

    /// What the page has on, or off for a tab with no page.
    mutating func takeDevices(from webView: WKWebView?) {
        camera = webView.map { CaptureState($0.cameraCaptureState) } ?? .off
        microphone = webView.map { CaptureState($0.microphoneCaptureState) } ?? .off
    }
}

extension TabController {

    /// WebKit posts both as the page turns a device on, pauses it or lets it go.
    func deviceObservations(
        of webView: WKWebView,
        republish: @escaping @Sendable (WKWebView, Any) -> Void
    ) -> [NSKeyValueObservation] {
        [
            webView.observe(\.cameraCaptureState, options: [.new]) { republish($0, $1) },
            webView.observe(\.microphoneCaptureState, options: [.new]) { republish($0, $1) }
        ]
    }
}

public extension TabController {

    /// Turns off the camera, the microphone, or both, where this page has them on.
    /// The page keeps its permission and can turn them on again, as it could after
    /// its own Stop button; the site menu's switch is what takes the permission away.
    func stopCapture(camera: Bool = true, microphone: Bool = true) {
        if camera { webView?.setCameraCaptureState(.none, completionHandler: nil) }
        if microphone { webView?.setMicrophoneCaptureState(.none, completionHandler: nil) }
    }

    /// A standing answer is given at once and nothing is shown; otherwise the delegate
    /// asks, and an answer is kept for the site. No answer (the question went unseen,
    /// or went away) is a no for now and is not kept, so the site may ask again.
    ///
    /// The host is the requesting frame's origin, not the tab's: a call embedded from
    /// another site asks as that site, and is answered as that site.
    internal func decide(_ permissions: [BrowserStore.SitePermission], host: String) async -> WKPermissionDecision {
        guard !host.isEmpty else { return .deny }
        if let standing = DeviceRequest.standingAnswer(for: permissions, host: host, in: sitePermissions) {
            return standing ? .grant : .deny
        }
        guard let delegate,
              let answer = await delegate.tabController(self, wantsAccessTo: permissions, forHost: host)
        else { return .deny }
        for permission in permissions { sitePermissions.setAllowed(answer, permission, forHost: host) }
        return answer ? .grant : .deny
    }
}
