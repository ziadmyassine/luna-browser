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
//  Also the one reader and writer of a list of links on a pasteboard, which
//  §3.4b's Copy Links, ⌘V in the sidebar and §6.6's text drops share.
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
    /// put there as a URL, or else the ones written out in its text. Text that
    /// is one link per line — an address, or a Markdown `[title](url)` — is
    /// read a line at a time the way the Command Bar reads it, so `example.com`
    /// on its own is https and a domain in a title is not a second link;
    /// anything else is what the data detector finds. Only http and https — a
    /// `file:` or `javascript:` link in somebody's text is not something to
    /// open on their say-so.
    static func links(on pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        let web = urls.filter(isWeb)
        if !web.isEmpty { return web }
        guard let text = pasteboard.string(forType: .string) else { return [] }
        let lines = text.split(whereSeparator: \.isNewline).filter { !$0.allSatisfy(\.isWhitespace) }
        let perLine = lines.compactMap { line in link(onLine: String(line)).flatMap { isWeb($0) ? $0 : nil } }
        if !perLine.isEmpty, perLine.count == lines.count { return perLine }
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

    /// A line that is nothing but an address, or a Markdown link with an
    /// optional list bullet before it.
    private static func link(onLine line: String) -> URL? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let match = trimmed.wholeMatch(of: /(?:[-*+]\s+)?\[(?:\\.|[^\]\\])*\]\((\S+)\)/) {
            return URL(string: String(match.1))
        }
        return CommandBarURL.direct(from: trimmed)
    }

    // MARK: - Writing the pasteboard

    /// One item per link, each a URL and its text: a URL reader gets every
    /// one, and the plain text AppKit joins them into is one per line, which
    /// is what other browsers and editors paste.
    static func write(_ urls: [URL], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { url in
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .URL)
            item.setString(url.absoluteString, forType: .string)
            return item
        })
    }

    /// One `[title](url)` per line, as plain text only: a URL type alongside
    /// would win the paste in most apps and drop the titles.
    static func writeMarkdown(_ pages: [(title: String, url: URL)], to pasteboard: NSPasteboard) {
        let lines = pages.map { page in
            let title = page.title.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            return "[\(title)](\(page.url.absoluteString))"
        }
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private static func isWeb(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased()) && url.host() != nil
    }
}
