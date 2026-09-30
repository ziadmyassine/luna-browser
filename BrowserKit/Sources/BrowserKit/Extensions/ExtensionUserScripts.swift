import CryptoKit
import Foundation

// Adapted from Search's ExtensionShims.swift (github.com/driceroland/Search),
// MIT License, Copyright (c) 2026 Office Commun; the full notice is at the top
// of Resources/ExtensionShim.js.

/// `chrome.userScripts`, carried out through WebKit's registered content
/// scripts: each script is written into a file of the extension's own, under
/// `_luna/`, since content scripts come from files.
enum ExtensionUserScripts {

    static let folderName = "_luna"

    /// A user script as a file WebKit can inject: its code, inline or read from
    /// the extension's own files, inside a block that leaves at once on a page
    /// its globs rule out and, for Chrome's USER_SCRIPT world, gives the code a
    /// `chrome` whose messages are marked as a user script's. Named by what is
    /// in it, so a changed script is a new file and never a stale one.
    static func file(_ script: [String: Any], in folder: URL) throws -> String {
        var code = ""
        for source in script["js"] as? [[String: Any]] ?? [] {
            if let inline = source["code"] as? String {
                code += inline + "\n;\n"
            } else if let name = source["file"] as? String, let path = inside(name, of: folder),
                      let text = try? String(contentsOf: path, encoding: .utf8) {
                code += text + "\n;\n"
            }
        }
        let userWorld = (script["world"] as? String) != "MAIN"
        let prelude = #"""
          const chrome = (() => {
            const runtime = globalThis.chrome.runtime;
            return { runtime: {
              id: runtime.id, getURL: (path) => runtime.getURL(path), get lastError() { return runtime.lastError; },
              sendMessage: (message, ...rest) => runtime.sendMessage({ __lunaUserScript: true, message },
                ...rest.filter((r) => typeof r === "function" || (r && typeof r === "object"))),
              connect: (info) => runtime.connect({ ...(info || {}), name: "luna-us:" + ((info && info.name) || "") }),
            } };
          })();
          const browser = chrome;
        """#
        let text = #"""
        /* Luna: a user script (chrome.userScripts) */
        luna_user_script: {
          const __lunaHref = location.href;
          const __lunaGlob = (g) => new RegExp("^" + g.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*").replace(/\?/g, ".") + "$");
          const __lunaIn = \#(json(script["includeGlobs"] ?? [])), __lunaOut = \#(json(script["excludeGlobs"] ?? []));
          if ((__lunaIn.length && !__lunaIn.some((g) => __lunaGlob(g).test(__lunaHref)))
            || __lunaOut.some((g) => __lunaGlob(g).test(__lunaHref))) break luna_user_script;
        \#(userWorld ? prelude : "")
        \#(code)
        }
        """#
        return try write(text, prefix: "us-", in: folder)
    }

    static func list(in folder: URL) -> Any {
        (try? JSONSerialization.jsonObject(with: Data(contentsOf: folder.appending(path: "\(folderName)/userscripts.json")))) ?? []
    }

    /// Files no saved script is written in any more go once a minute has
    /// passed: one being injected right now is left alone.
    static func save(_ scripts: [[String: Any]], in folder: URL) throws {
        let directory = folder.appending(path: folderName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: scripts).write(to: directory.appending(path: "userscripts.json"), options: .atomic)
        let keep = Set(scripts.compactMap { try? file($0, in: folder) }.map { URL(filePath: $0).lastPathComponent })
        sweep(directory, prefix: "us-", keeping: keep)
    }

    static func worlds(in folder: URL) -> [[String: Any]] {
        let url = folder.appending(path: "\(folderName)/worlds.json")
        return (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [[String: Any]] ?? []
    }

    static func configureWorld(_ properties: [String: Any], in folder: URL) throws {
        let world = properties["worldId"] as? String ?? ""
        var all = worlds(in: folder).filter { ($0["worldId"] as? String ?? "") != world }
        if properties["reset"] as? Bool != true { all.append(properties) }
        let directory = folder.appending(path: folderName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: all).write(to: directory.appending(path: "worlds.json"), options: .atomic)
    }

    /// Writes `text` under `_luna/`, named by its hash, and returns the path
    /// WebKit takes it by.
    static func write(_ text: String, prefix: String, in folder: URL) throws -> String {
        let hash = SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let name = prefix + hash + ".js"
        let directory = folder.appending(path: folderName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        if !FileManager.default.fileExists(atPath: url.path) { try text.write(to: url, atomically: true, encoding: .utf8) }
        if prefix == "script-" { sweep(directory, prefix: prefix, keeping: [name]) }
        return "\(folderName)/\(name)"
    }

    private static func sweep(_ directory: URL, prefix: String, keeping: Set<String>) {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(prefix) && !keeping.contains(file.lastPathComponent) {
            let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let modified, -modified.timeIntervalSinceNow > 60 { try? FileManager.default.removeItem(at: file) }
        }
    }

    /// One of the extension's own files, and nothing outside its folder.
    private static func inside(_ name: String, of folder: URL) -> URL? {
        let base = folder.standardizedFileURL
        let path = base.appending(path: name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).standardizedFileURL
        guard path.path.hasPrefix(base.path + "/"),
              path.resolvingSymlinksInPath().path.hasPrefix(folder.resolvingSymlinksInPath().path + "/")
        else { return nil }
        return path
    }

    private static func json(_ value: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: value)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
}
