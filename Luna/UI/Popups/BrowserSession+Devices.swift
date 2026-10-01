//
//  BrowserSession+Devices.swift
//  Luna
//
//  §17.8: a page asking for the camera, the microphone or the location, and
//  §18.8's clipboard, put to the user as a toast with Allow and Don't Allow. Whether to ask at all,
//  and keeping the answer for the site, is `TabController.decide`'s, under
//  test in BrowserKit; this only asks.
//

import AppKit
import BrowserKit

extension BrowserSession {

    /// Over the page that asked, or not at all: a question over some other tab
    /// would be about a page the user cannot see. Unasked is a no for now, so a
    /// tab in the background is refused and may ask again once it is in front.
    func tabController(
        _ controller: TabController,
        wantsAccessTo permissions: [BrowserStore.SitePermission],
        forHost host: String
    ) async -> Bool? {
        guard controller.id == activeTabID, let window = hostWindow else { return nil }
        return await withCheckedContinuation { continuation in
            let once = AnswerOnce(continuation)
            PageToast.deviceRequest(permissions, host: host, answer: once.give).show(in: window)
        }
    }
}

/// A continuation resumed by the first answer only: Allow, Don't Allow, and the
/// toast going away can each arrive, and a second resume is a crash.
@MainActor
private final class AnswerOnce {
    private var continuation: CheckedContinuation<Bool?, Never>?

    init(_ continuation: CheckedContinuation<Bool?, Never>) {
        self.continuation = continuation
    }

    func give(_ answer: Bool?) {
        continuation?.resume(returning: answer)
        continuation = nil
    }
}

extension PageToast {

    /// "Use the camera?" or "Read the clipboard?" with the site beside it, and the two
    /// answers. Going away unanswered answers nil.
    static func deviceRequest(
        _ permissions: [BrowserStore.SitePermission],
        host: String,
        answer: @escaping @MainActor (Bool?) -> Void
    ) -> PageToast {
        let wants = Set(permissions)
        let (symbol, text): (String, String) = if wants.contains(.clipboard) {
            ("doc.on.clipboard", String(localized: "Read the clipboard?"))
        } else if wants.contains(.location) {
            ("location", String(localized: "Use your location?"))
        } else if wants == [.camera, .microphone] {
            ("video", String(localized: "Use the camera and microphone?"))
        } else if wants == [.camera] {
            ("video", String(localized: "Use the camera?"))
        } else {
            ("mic", String(localized: "Use the microphone?"))
        }
        var toast = PageToast(symbol: symbol, text: text, detail: host, actions: [
            Action(title: String(localized: "Allow"), label: String(localized: "Allow \(host)")) { answer(true) },
            Action(title: String(localized: "Don’t Allow"), label: String(localized: "Don’t allow \(host)")) { answer(false) }
        ])
        toast.onUnanswered = { answer(nil) }
        return toast
    }
}
