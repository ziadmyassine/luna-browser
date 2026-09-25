import Foundation

/// Where installed extensions live on disk, and the file work of getting them
/// there (docs/EXTENSIONS.md §3.7): folder, `.zip` or `.crx` in, one checked
/// folder per extension out, at `<root>/<id>/`.
///
/// Every file operation here is `nonisolated async` on a `Sendable` value, so
/// it runs on the global executor and never on the main actor. Nothing here
/// is reachable from web content: the only callers are Luna's own install API.
public struct ExtensionLibrary: Sendable {

    public enum Failure: Error, Equatable {
        case noManifest
        case unsupportedFile
        case invalidIdentifier
        case webStoreIDMismatch
        case downloadFailed
    }

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// Where extension `id` is installed. `id` is a path component, so anything
    /// that is not Chrome's 32 letters `a`…`p` is refused rather than joined.
    public func directory(for id: String) throws -> URL {
        guard Self.isValidID(id) else { throw Failure.invalidIdentifier }
        return root.appending(path: id, directoryHint: .isDirectory)
    }

    static func isValidID(_ id: String) -> Bool {
        id.count == 32 && id.allSatisfy { ("a"..."p").contains($0) }
    }

    /// A Chrome-shaped id for a local install with no manifest `key`, stored
    /// with it so its storage survives relaunch.
    static func randomID() -> String {
        CRX3.extensionID(publicKey: Data(UUID().uuidString.utf8))
    }

    // MARK: - Staging

    /// Unpacks `file` into a staging folder beside the library and says what it is.
    ///
    /// Nothing is installed until ``commit(_:)`` moves it into place, so a
    /// declined prompt leaves nothing behind but what ``discard(_:)`` removes.
    public func stage(_ file: URL) async throws -> StagedExtension {
        let staging = root.appending(path: ".staging/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            let source: ExtensionSource
            var id: String?
            if (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                try copyFolder(file, to: staging)
                source = .local
            } else if file.pathExtension.lowercased() == "crx" {
                let package = try CRX3.unpack(try readArchive(file))
                try ExtensionArchive.extract(package.zip, into: staging)
                (id, source) = (package.id, .webStore)
            } else if file.pathExtension.lowercased() == "zip" {
                try ExtensionArchive.extract(try readArchive(file), into: staging)
                source = .local
            } else {
                throw Failure.unsupportedFile
            }
            let manifest = staging.appending(path: "manifest.json")
            guard FileManager.default.fileExists(atPath: manifest.path) else { throw Failure.noManifest }
            return StagedExtension(id: id ?? localID(manifest: manifest), source: source, directory: staging)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    /// Moves a staged extension into `<root>/<id>/`, replacing an older copy.
    @discardableResult
    public func commit(_ staged: StagedExtension) async throws -> URL {
        let destination = try directory(for: staged.id)
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: staged.directory)
        } else {
            try manager.moveItem(at: staged.directory, to: destination)
        }
        return destination
    }

    public func discard(_ staged: StagedExtension) async {
        try? FileManager.default.removeItem(at: staged.directory)
    }

    public func remove(_ id: String) async throws {
        let directory = try directory(for: id)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    /// Chrome's rule for an unpacked extension: a manifest `key` fixes the id,
    /// which is how a developer build keeps its store id. Without one, a fresh id.
    private func localID(manifest: URL) -> String {
        guard let data = try? Data(contentsOf: manifest),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = object["key"] as? String,
              let spki = Data(base64Encoded: key)
        else { return Self.randomID() }
        return CRX3.extensionID(publicKey: spki)
    }

    /// The size check comes before the read, so a huge file is never loaded.
    private func readArchive(_ file: URL) throws -> Data {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max
        guard size <= ExtensionArchive.maximumArchiveBytes else { throw ExtensionArchive.Failure.tooLarge }
        return try Data(contentsOf: file)
    }

    /// A folder gets the same checks a ZIP's entries do: no symlinks, a bounded size.
    private func copyFolder(_ folder: URL, to destination: URL) throws {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .fileSizeKey]
        var total = 0
        for case let url as URL in FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys)) ?? .init() {
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true { throw ExtensionArchive.Failure.unsafeEntry(url.lastPathComponent) }
            total += values.fileSize ?? 0
            if total > ExtensionArchive.maximumUnpackedBytes { throw ExtensionArchive.Failure.tooLarge }
        }
        try FileManager.default.copyItem(at: folder, to: destination)
    }

    // MARK: - Chrome Web Store

    /// Chrome's update endpoint, which redirects to the current CRX3 for `id`.
    /// `prodversion` is required and must be a Chrome the extension supports.
    public static func webStoreURL(id: String) -> URL {
        // Built as a string: `x` is itself a query, and its `=` and `&` must arrive escaped.
        URL(string: "https://clients2.google.com/service/update2/crx?response=redirect"
            + "&prodversion=\(WebViewFactory.chromeMajorVersion).0&acceptformat=crx3&x=id%3D\(id)%26uc")!
    }

    /// Downloads and stages the Web Store's current build of `id`. The CRX's
    /// own signed id must be the one asked for.
    public func stageFromWebStore(id: String) async throws -> StagedExtension {
        guard Self.isValidID(id) else { throw Failure.invalidIdentifier }
        let (download, response) = try await URLSession.shared.download(from: Self.webStoreURL(id: id))
        defer { try? FileManager.default.removeItem(at: download) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.downloadFailed }
        let crx = download.deletingLastPathComponent().appending(path: "\(UUID().uuidString).crx")
        try FileManager.default.moveItem(at: download, to: crx)
        defer { try? FileManager.default.removeItem(at: crx) }
        let staged = try await stage(crx)
        guard staged.id == id else {
            await discard(staged)
            throw Failure.webStoreIDMismatch
        }
        return staged
    }
}

public enum ExtensionSource: String, Sendable, Codable {
    /// A signed CRX; the id is the one Chrome gives it.
    case webStore
    /// A folder or ZIP; the id is the manifest `key`'s, or one Luna made.
    case local
}

/// An extension unpacked and checked, not yet installed.
public struct StagedExtension: Sendable {
    public let id: String
    public let source: ExtensionSource
    public let directory: URL
}
