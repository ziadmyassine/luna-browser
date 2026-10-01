//
//  BrowserSession+Clipboard.swift
//  Luna
//
//  §18.8: the pasteboard handed to a page that may read it. Whether it may,
//  and asking (the camera's toast), is `TabController+Clipboard.swift`'s;
//  this only reads, and only for the page in front of the user.
//

import AppKit
import BrowserKit

extension BrowserSession {

    /// Nil, which the page hears as a refusal, unless the tab is the one on screen in
    /// the key window and nobody but the user is driving it. A site's yes is a yes to
    /// read while the user is looking at it, as Chrome's is to a focused page.
    func tabController(_ controller: TabController, readsClipboard request: ClipboardRequest) async -> [String: String]? {
        guard controller.id == activeTabID, control?.isAgents(tab: controller.id) != true,
              let window = hostWindow, window.isKeyWindow, let webView = controller.webView
        else { return nil }
        switch request {
        case .paste:
            // Edit ▸ Paste, into whatever the page has focused, and only while the page
            // has the keyboard: a field in the chrome the user is typing in is theirs.
            guard let responder = window.firstResponder as? NSView, responder === webView || responder.isDescendant(of: webView)
            else { return nil }
            NSApp.sendAction(#selector(NSText.paste(_:)), to: webView, from: nil)
            return [:]
        case .readText:
            return ClipboardReading.contents(of: .general, pictures: false)
        case .read:
            return ClipboardReading.contents(of: .general, pictures: true)
        }
    }
}

/// The pasteboard as the asynchronous Clipboard API hands it over: the three types
/// every engine supports, by MIME type.
enum ClipboardReading {

    static func contents(of pasteboard: NSPasteboard, pictures: Bool) -> [String: String] {
        var contents: [String: String] = [:]
        if let text = pasteboard.string(forType: .string) { contents["text/plain"] = text }
        guard pictures else { return contents }
        if let html = pasteboard.string(forType: .html) { contents["text/html"] = html }
        if let picture = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff).flatMap(pngFromTIFF) {
            contents["image/png"] = picture.base64EncodedString()
        }
        return contents
    }

    /// A screenshot copied on a Mac is often TIFF only, and the API speaks PNG.
    private static func pngFromTIFF(_ tiff: Data) -> Data? {
        NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
}
