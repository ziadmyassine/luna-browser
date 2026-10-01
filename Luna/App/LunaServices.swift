//
//  LunaServices.swift
//  Luna
//
//  The two entries Luna adds to every app's Services menu (`NSServices` in
//  `Info.plist`): Open in Luna for a selected link, and Search with Luna for
//  selected text. Each hands its page to the same path a link from another
//  app takes (`AppDelegate+OpenURLs.swift`), so it opens as a tab in the front
//  window's Space and brings Luna forward.
//

import AppKit

@MainActor
final class LunaServices: NSObject {

    /// Where a page goes once it has been read off the pasteboard.
    private let open: ([URL]) -> Void

    init(open: @escaping ([URL]) -> Void) {
        self.open = open
    }

    /// `NSMessage` "openURL" in `Info.plist`.
    @objc(openURL:userData:error:)
    func openURL(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let links = Self.links(on: pasteboard)
        guard !links.isEmpty else {
            error.pointee = String(localized: "The selection has no web address in it.") as NSString
            return
        }
        open(links)
    }

    /// `NSMessage` "search" in `Info.plist`.
    @objc(search:userData:error:)
    func search(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let page = Self.search(on: pasteboard) else {
            error.pointee = String(localized: "There is no text selected to search for.") as NSString
            return
        }
        open([page])
    }

    // MARK: - Reading the pasteboard

    /// The web addresses in the selection, in order: a link the source app
    /// put there as a URL, or else the ones written out in its text. The text
    /// is read the way the Command Bar reads it, so `example.com` on its own
    /// is a link; inside a sentence, a link is what the data detector finds.
    /// Only http and https — a `file:` or `javascript:` link in somebody's
    /// text is not something to open on their say-so.
    static func links(on pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        let web = urls.filter(isWeb)
        if !web.isEmpty { return web }
        guard let text = pasteboard.string(forType: .string) else { return [] }
        if let whole = CommandBarURL.direct(from: text), isWeb(whole) { return [whole] }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let found = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
        return found.compactMap(\.url).filter(isWeb)
    }

    /// The selected text as a search with the user's engine (Settings ▸
    /// Search), or nil when there is nothing but whitespace.
    static func search(on pasteboard: NSPasteboard) -> URL? {
        guard let text = pasteboard.string(forType: .string) else { return nil }
        let query = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return CommandBarURL.search(for: query)
    }

    private static func isWeb(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased()) && url.host() != nil
    }
}
