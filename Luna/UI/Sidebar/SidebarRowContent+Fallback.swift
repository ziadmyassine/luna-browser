//
//  SidebarRowContent+Fallback.swift
//  Luna
//
//  The icon a tab wears when its page gives none: a file by its kind — a
//  Markdown document, a web page, a PDF, an image — a server on this Mac by
//  its own mark, and anything else the globe. A file or a local server has no
//  favicon to fetch, and a column of globes said nothing about which was which.
//

import Foundation

extension SidebarRowContent {

    static func fallbackSymbol(for url: URL) -> String {
        if url.isFileURL { return fileSymbol(url.pathExtension.lowercased()) }
        if isLocalServer(url.host(percentEncoded: false)) { return "server.rack" }
        return siteFallbackSymbol
    }

    private static func fileSymbol(_ kind: String) -> String {
        switch kind {
        case "md", "markdown", "mdown", "mkd": "doc.text"
        case "html", "htm", "xhtml": "chevron.left.forwardslash.chevron.right"
        case "pdf": "doc.richtext"
        case "txt", "log", "csv", "tsv": "doc.plaintext"
        case "json", "xml", "yaml", "yml", "js", "css", "swift": "curlybraces"
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "svg", "tiff", "bmp": "photo"
        case "mp4", "mov", "m4v", "webm": "film"
        case "mp3", "m4a", "wav", "aac", "flac": "music.note"
        case "": "folder"
        default: "doc"
        }
    }

    /// A development server on this Mac: the loopback addresses, `localhost`,
    /// and the names reserved for local use.
    private static func isLocalServer(_ host: String?) -> Bool {
        guard let host = host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]")) else { return false }
        if ["localhost", "127.0.0.1", "::1", "0.0.0.0"].contains(host) { return true }
        return [".localhost", ".local", ".test"].contains { host.hasSuffix($0) }
    }
}
