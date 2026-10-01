//
//  WebLocationFile.swift
//  Luna
//
//  A saved link: the `.webloc` a link dragged to the desktop becomes, its
//  older `.inetloc` sibling, and Windows' `.url`. Not a page — the file holds
//  an address and nothing else, so opening one opens the address. Separate
//  from `LocalFileTypes`, whose files are shown in the tab as they are.
//

import Foundation
import UniformTypeIdentifiers

enum WebLocationFile {

    /// What `Info.plist` claims, under "Web location".
    static let identifiers = [
        "com.apple.web-internet-location",
        "com.apple.generic-internet-location",
        "com.microsoft.internet-shortcut"
    ]

    /// Whether a file is one of them, by its extension.
    static func handles(_ url: URL) -> Bool {
        guard url.isFileURL, let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return identifiers.compactMap(UTType.init).contains { type.conforms(to: $0) }
    }

    /// The web address the file holds, or nil for one that holds none, is
    /// unreadable, or points anywhere but the web — a `.inetloc` can carry a
    /// `mailto:` or a `file:` link, and those are not Luna's to open.
    static func link(in file: URL) -> URL? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return link(from: data)
    }

    static func link(from data: Data) -> URL? {
        let text = propertyListLink(data) ?? internetShortcutLink(data)
        guard let text, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased()), url.host() != nil
        else { return nil }
        return url
    }

    /// `.webloc` and `.inetloc`: a property list, XML or binary, with the
    /// address under `URL`.
    private static func propertyListLink(_ data: Data) -> String? {
        let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        return (plist as? [String: Any])?["URL"] as? String
    }

    /// `.url`: an INI file whose `[InternetShortcut]` section has a `URL=` line.
    private static func internetShortcutLink(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        var inSection = false
        for line in text.components(separatedBy: .newlines) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inSection = line.caseInsensitiveCompare("[InternetShortcut]") == .orderedSame
            } else if inSection, line.lowercased().hasPrefix("url=") {
                return String(line.dropFirst(4))
            }
        }
        return nil
    }
}
