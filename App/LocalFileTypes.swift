//
//  LocalFileTypes.swift
//  Luna
//
//  The files Luna opens from Finder: what `Info.plist` claims, in one list the
//  open handler and a test both read, so the two cannot drift apart.
//
//  Every type here is one WebKit shows in the page — measured by loading one
//  of each and reading `canShowMIMEType` — or plain text, which Luna shows
//  itself when WebKit would not (`TabController`'s text fallback). A type
//  WebKit hands to the downloader, such as Photoshop or RTF, is left out: a
//  file already on this Mac copied into Downloads is not opening it.
//

import UniformTypeIdentifiers

enum LocalFileTypes {

    /// Grouped as `Info.plist` groups them.
    static let groups: [(name: String, identifiers: [String])] = [
        ("Web page", ["public.html", "public.xhtml", "com.apple.webarchive", "public.svg-image"]),
        ("PDF document", ["com.adobe.pdf"]),
        ("Image", [
            "public.png", "public.jpeg", "com.compuserve.gif", "org.webmproject.webp", "public.heic",
            "public.heif", "public.avif", "public.tiff", "com.microsoft.bmp", "com.microsoft.ico"
        ]),
        ("Text", [
            "public.plain-text", "public.utf8-plain-text", "net.daringfireball.markdown", "public.json",
            "public.xml", "public.comma-separated-values-text", "public.tab-separated-values-text",
            "public.log", "public.source-code", "public.script", "public.yaml", "public.css"
        ]),
        ("Movie", ["public.mpeg-4", "com.apple.quicktime-movie", "com.apple.m4v-video", "org.webmproject.webm"]),
        ("Audio", [
            "public.mp3", "public.mpeg-4-audio", "com.apple.m4a-audio", "public.aac-audio", "com.microsoft.waveform-audio",
            "public.aiff-audio", "org.xiph.flac", "org.xiph.ogg-audio", "public.opus-audio"
        ])
    ]

    static var identifiers: [String] { groups.flatMap(\.identifiers) }

    /// Whether a file is one of them, by its extension — a subtype counts, so
    /// `.htm` is HTML and `.py` is source code.
    static func opens(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return identifiers.compactMap(UTType.init).contains { type.conforms(to: $0) }
    }
}
