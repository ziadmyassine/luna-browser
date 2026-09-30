import CryptoKit
import Foundation

// Adapted from Search's ExtensionShims.swift (github.com/driceroland/Search),
// MIT License, Copyright (c) 2026 Office Commun; the full notice is at the top
// of Resources/ExtensionShim.js.

/// The Chrome APIs WebKit lacks, filled in by Luna (docs/EXTENSIONS.md §9).
///
/// WebKit covers tabs, storage, scripting, request rules, cookies, menus,
/// alarms and messaging. Chrome extensions also reach for history, downloads,
/// offscreen documents, tab groups, OAuth and more, and fall over when those
/// are undefined; and where WebKit and Chrome both have an API they differ in
/// ways that stop real extensions (several `onMessage` listeners, a worker's
/// WebSocket, a port's first messages). So a script is put at the front of an
/// installed extension's background and of every page it ships. It defines
/// only what is missing and mends only what differs, and every call it cannot
/// answer itself becomes a native message to "luna" (`ExtensionShimAnswers`).
///
/// The files are changed after the install prompt has read the package, and
/// only by adding. What Luna added to the manifest is written beside it, so the
/// extension is still described by what it asked for.
enum ExtensionShim {

    /// The native application the shim's messages go to.
    static let application = "luna"
    /// The key of the word the shim and a native port exchange to learn the
    /// port has arrived (see `ExtensionNative.connect`).
    static let nativeKey = "__lunaNative"
    static let file = "luna-shim.js"
    /// The first line of a worker that already carries the shim, and the line after it.
    static let marker = "/* Luna: Chrome APIs WebKit lacks, filled in (ExtensionShim.swift) */"
    static let ender = "/* Luna: end of shim */"
    /// Written beside a prepared extension: which shim it carries. The same one
    /// needs nothing redone, which matters at launch — preparing reads every
    /// script and page an extension ships.
    static let stamp = ".luna-shim"
    /// The permissions Luna added to the manifest, as a JSON array.
    static let added = ".luna-added"

    static let script: String = {
        guard let url = Bundle.module.url(forResource: "ExtensionShim", withExtension: "js"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text
    }()

    static let version: String = SHA256.hash(data: Data(script.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()

    /// Names only Luna may write beside an extension, removed from a package
    /// as it is unpacked: a package that shipped its own `.luna-added` could
    /// hide what it asked for.
    static let reservedNames = [stamp, added]

    // MARK: - Preparing

    enum Failure: Error { case unreadableManifest }

    /// Writes the shim into the extension at `folder`, once per shim version.
    static func prepare(_ folder: URL) throws {
        let stampURL = folder.appending(path: stamp)
        if (try? String(contentsOf: stampURL, encoding: .utf8)) == version { return }
        let manifestURL = folder.appending(path: "manifest.json")
        guard var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any] else {
            throw Failure.unreadableManifest
        }
        let script = shim(for: folder)
        try script.write(to: folder.appending(path: file), atomically: true, encoding: .utf8)

        try addPermissions(to: &manifest, in: folder)
        addShim(to: &manifest, in: folder)
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: manifestURL, options: .atomic)

        tagPages(in: folder)
        try version.write(to: stampURL, atomically: true, encoding: .utf8)
    }

    /// Native messaging is how the shim reaches Luna, and user scripts are
    /// carried out through WebKit's registered content scripts, which need
    /// scripting. What is added is written down beside the manifest.
    private static func addPermissions(to manifest: inout [String: Any], in folder: URL) throws {
        var permissions = manifest["permissions"] as? [Any] ?? []
        let asked = Set(permissions.compactMap { $0 as? String })
        var addedNames = addedPermissions(in: folder)
        for needed in ["nativeMessaging"] + (asked.contains("userScripts") ? ["scripting"] : []) where !asked.contains(needed) {
            permissions.append(needed)
            addedNames.insert(needed)
        }
        manifest["permissions"] = permissions
        let addedData = try JSONSerialization.data(withJSONObject: addedNames.sorted())
        try addedData.write(to: folder.appending(path: added), options: .atomic)
    }

    /// The background, whichever kind it is, gets the shim first, and so does
    /// every content script; there only Chrome's behaviour is mended.
    private static func addShim(to manifest: inout [String: Any], in folder: URL) {
        if var background = manifest["background"] as? [String: Any] {
            prepareWorker(background, in: folder)
            // Scripts, alone or beside a worker: WebKit runs them as a page
            // when a manifest names both.
            if var scripts = background["scripts"] as? [String] {
                if scripts.first != file { scripts.insert(file, at: 0) }
                background["scripts"] = scripts
            }
            manifest["background"] = background
        }
        if let entries = manifest["content_scripts"] as? [[String: Any]] {
            manifest["content_scripts"] = entries.map { entry in
                var entry = entry
                if var scripts = entry["js"] as? [String], !scripts.contains(file) {
                    scripts.insert(file, at: 0)
                    entry["js"] = scripts
                }
                return entry
            }
        }
    }

    /// Every page it ships — popup, options, background page, side panel —
    /// loads the shim before anything else in its head.
    private static func tagPages(in folder: URL) {
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey])
        while let url = walker?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                  ["html", "htm"].contains(url.pathExtension.lowercased()),
                  var html = try? String(contentsOf: url, encoding: .utf8),
                  !html.contains(file)
            else { continue }
            let tag = "<script src=\"/\(file)\"></script>"
            if let head = html.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) {
                html.insert(contentsOf: tag, at: head.upperBound)
            } else {
                html = tag + html
            }
            try? html.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// A classic service worker gets the shim written at the top of its own
    /// file; a module one imports it first, as its imports run before anything
    /// written above them. An older shim already there is taken off first.
    private static func prepareWorker(_ background: [String: Any], in folder: URL) {
        guard let worker = background["service_worker"] as? String,
              let path = inside(worker, of: folder),
              var source = try? String(contentsOf: path, encoding: .utf8)
        else { return }
        if source.hasPrefix(marker), let end = source.range(of: ender) {
            source = String(String(source[end.upperBound...]).trimmingPrefix("\n"))
        }
        let first = "import \"/\(file)\";\n"
        while source.hasPrefix(first) { source.removeFirst(first.count) }
        let isModule = (background["type"] as? String) == "module"
        let written = isModule ? first + source : marker + "\n" + writtenShim(in: folder) + "\n" + ender + "\n" + source
        try? written.write(to: path, atomically: true, encoding: .utf8)
    }

    private static func writtenShim(in folder: URL) -> String {
        (try? String(contentsOf: folder.appending(path: file), encoding: .utf8)) ?? shim(for: folder)
    }

    /// A path a package names, kept inside the folder it came in: `..` in a
    /// manifest is not a way out of the package, and nor is a symbolic link —
    /// the worker is read through it and written back over it, so a link to a
    /// file elsewhere would put that file's bytes in the package.
    private static func inside(_ name: String, of folder: URL) -> URL? {
        let base = folder.standardizedFileURL
        let path = base.appending(path: name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).standardizedFileURL
        guard path.path.hasPrefix(base.path + "/"),
              (try? path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              path.resolvingSymlinksInPath().path.hasPrefix(folder.resolvingSymlinksInPath().path + "/")
        else { return nil }
        return path
    }

    /// The permissions Luna added to this extension's manifest.
    static func addedPermissions(in folder: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: folder.appending(path: added)),
              let names = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return [] }
        return Set(names)
    }

    // MARK: - The script as one extension gets it

    /// With the events its code mentions — `chrome.tabs.onUpdated`,
    /// `e.runtime.onInstalled` — so its worker can take their listeners late,
    /// and the scripts it ships, so its worker can be told at once that one
    /// is not there (see the end of the script and `importScripts` in it).
    static func shim(for folder: URL) -> String {
        var events = Set<String>()
        var scripts: [String] = []
        let pattern = #/\.([a-zA-Z]+)\.(on[A-Z][A-Za-z]+)\b/#
        let base = folder.standardizedFileURL.path
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "js", var text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            // An empty one is marked: there is nothing to run in it.
            let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            scripts.append((empty ? "-" : "") + String(url.standardizedFileURL.path.dropFirst(base.count)))
            guard url.lastPathComponent != file else { continue }
            // Not the shim's own words, in a worker that already carries it.
            if text.hasPrefix(marker), let end = text.range(of: ender) { text = String(text[end.upperBound...]) }
            for match in text.matches(of: pattern) { events.insert("\(match.1).\(match.2)") }
        }
        return script
            .replacingOccurrences(of: "__LUNA_EVENTS__", with: json(events.sorted()))
            .replacingOccurrences(of: "__LUNA_SCRIPTS__", with: json(scripts.sorted()))
            .replacingOccurrences(of: "__LUNA_CHROME__", with: "\(WebViewFactory.chromeMajorVersion).0.0.0")
            .replacingOccurrences(of: "__LUNA_VERBOSE__", with: "false")
    }

    private static func json(_ list: [String]) -> String {
        (try? JSONSerialization.data(withJSONObject: list)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
}
