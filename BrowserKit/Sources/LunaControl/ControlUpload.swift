import Darwin
import Foundation
import UniformTypeIdentifiers

/// What `file_upload` may take off this Mac, and the reading of it.
///
/// The policy has already made the user look at every path (unless they chose
/// allow-all); this is what holds when they did not look closely, or when the
/// file changed after they did. The file is opened once, without following a
/// link, and every check after that is on the open descriptor — so a path
/// swapped for a link between the check and the read reads nothing.
public enum ControlUpload {

    public static let maxFileBytes = 10 * 1024 * 1024
    /// Sent as base64 in one socket line, a third larger again. `LineReader`
    /// has no line limit, so this is the cap on what a page is handed.
    public static let maxTotalBytes = 25 * 1024 * 1024

    public struct File: Sendable, Equatable {
        public var name: String
        public var mimeType: String
        public var data: Data

        public init(name: String, mimeType: String, data: Data) {
            self.name = name
            self.mimeType = mimeType
            self.data = data
        }
    }

    /// Credential stores and dotfiles under the home folder: each one and
    /// everything under it.
    static let homeSecrets = [
        ".ssh", ".gnupg", ".aws", ".azure", ".config/gcloud", ".kube", ".docker", ".config/gh", ".netrc",
        ".git-credentials", ".npmrc", ".pypirc", ".password-store", ".1password", "Library/Keychains"
    ]
    /// Other browsers' profiles and the system's cookie jars, under `~/Library`.
    static let browserData = [
        "Application Support/Google/Chrome", "Application Support/Firefox", "Application Support/BraveSoftware",
        "Application Support/Arc", "Safari", "Cookies"
    ]
    /// Where Luna keeps its own profile, cookies and activity log, each under
    /// `~/Library/<folder>/<bundle id>`.
    static let lunaData = ["Application Support", "Caches", "WebKit", "HTTPStorages", "Cookies", "Containers", "Logs"]
    /// Globs matched against the whole path, case-insensitively, with `*`
    /// crossing folders: keys and env files wherever they are.
    static let secretNames = ["*/id_rsa", "*/id_dsa", "*/id_ecdsa", "*/id_ed25519", "*.pem", "*.key", "*.p12", "*.pfx",
                              "*/.env", "*/.env.*"]

    /// Everything no upload may come from: a path is refused if it is one of
    /// these or under one, or matches one that holds a `*`.
    public static func deniedPaths(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundleIdentifier: String
    ) -> [String] {
        let library = home.appending(path: "Library")
        let roots = homeSecrets.map { home.appending(path: $0) }
            + browserData.map { library.appending(path: $0) }
            + lunaData.map { library.appending(path: $0).appending(path: bundleIdentifier) }
            + [URL(filePath: "/Library/Keychains"),
               library.appending(path: "Preferences/\(bundleIdentifier).plist"),
               library.appending(path: "Saved Application State/\(bundleIdentifier).savedState"),
               // Any app's cookie store, which is where a session token lives.
               library.appending(path: "Application Support/*/Cookies*")]
        return roots.map { $0.path(percentEncoded: false) } + secretNames
    }

    /// Reads every source in order, holding each file and the whole call to
    /// the limits.
    public static func resolve(
        _ sources: [ControlCommand.UploadSource],
        denied: [String],
        owner: uid_t = getuid(),
        fileLimit: Int = maxFileBytes,
        totalLimit: Int = maxTotalBytes
    ) throws(ControlError) -> [File] {
        var total = 0
        return try sources.map { source throws(ControlError) in
            let file: File = switch source {
            case let .data(file): file
            case let .path(path): try read(path: path, denied: denied, owner: owner, limit: fileLimit)
            }
            guard file.data.count <= fileLimit else { throw tooBig(file.name, fileLimit) }
            total += file.data.count
            guard total <= totalLimit else {
                throw ControlError("The files come to more than \(megabytes(totalLimit)) MB, the most one call can upload.")
            }
            return file
        }
    }

    /// One file off the disk: a regular file with no other hard links, owned
    /// by `owner`, outside `denied`, at most `limit` bytes.
    public static func read(
        path: String, denied: [String], owner: uid_t = getuid(), limit: Int = maxFileBytes
    ) throws(ControlError) -> File {
        let spelled = (path as NSString).expandingTildeInPath
        guard spelled.hasPrefix("/") else { throw ControlError("“\(path)” is not an absolute path.") }
        let standard = URL(filePath: spelled).standardized.path(percentEncoded: false)
        let refusal = ControlError("Uploading “\(path)” is not allowed: it is in a folder Luna keeps private.")
        // The spelling first, because a path through a folder that does not
        // exist fails to open before the real location can be asked.
        if isDenied(standard, by: denied) { throw refusal }

        let fd = try openFile(standard, spelled: path)
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw ControlError("“\(path)” is not a file.")
        }
        // Where the file really is, after every link in the folders on the way.
        var real = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(fd, F_GETPATH, &real) == 0, let location = String(bytes: real.prefix { $0 != 0 }, encoding: .utf8),
              !isDenied(location, by: denied) else { throw refusal }
        // A second name for the file can sit anywhere, a denied folder included.
        guard info.st_nlink == 1 else { throw ControlError("“\(path)” has other hard links, so Luna will not upload it.") }
        guard info.st_uid == owner else { throw ControlError("“\(path)” is not owned by you, so Luna will not upload it.") }
        let name = URL(filePath: standard).lastPathComponent
        guard info.st_size <= limit else { throw tooBig(name, limit) }
        guard let data = contents(of: fd, count: Int(info.st_size)) else { throw ControlError("“\(path)” could not be read.") }
        let type = UTType(filenameExtension: URL(filePath: standard).pathExtension)?.preferredMIMEType
        return File(name: name, mimeType: type ?? "application/octet-stream", data: data)
    }

    /// Opens without following a final link. Non-blocking so a FIFO fails
    /// the regular-file test rather than hanging the call on a writer.
    private static func openFile(_ standard: String, spelled path: String) throws(ControlError) -> Int32 {
        let fd = open(standard, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd < 0 else { return fd }
        if errno == ELOOP { throw ControlError("“\(path)” is a symbolic link. Give the path of the file itself.") }
        throw ControlError("“\(path)” could not be opened: \(String(cString: strerror(errno))).")
    }

    private static func contents(of fd: Int32, count: Int) -> Data? {
        var data = Data(count: count)
        let complete = data.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let read = Darwin.read(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if read < 0, errno == EINTR { continue }
                guard read > 0 else { return false }
                offset += read
            }
            return true
        }
        return complete ? data : nil
    }

    /// Compared without case: APFS is case-insensitive by default, so
    /// `~/.SSH` is `~/.ssh`.
    private static func isDenied(_ path: String, by denied: [String]) -> Bool {
        denied.contains { entry in
            guard let star = entry.firstIndex(of: "*") else {
                return [entry, canonical(entry)].contains { root in
                    let path = path.lowercased(), root = root.lowercased()
                    return path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
                }
            }
            // The glob's folder part is canonicalised like a root; a trailing
            // `*` also covers what is under a match.
            let folder = String(entry[..<star])
            let globs = folder.isEmpty ? [entry] : [entry, canonical(folder) + (folder.hasSuffix("/") ? "/" : "") + entry[star...]]
            return globs.contains { fnmatch($0, path, FNM_CASEFOLD) == 0 }
        }
    }

    /// `root` with every link resolved as far as it exists — `/var` is
    /// `/private/var` — so it compares with the path an open file reports.
    private static func canonical(_ root: String) -> String {
        var existing = URL(filePath: root)
        var rest: [String] = []
        while existing.path(percentEncoded: false) != "/" {
            if let real = realpath(existing.path(percentEncoded: false), nil) {
                defer { free(real) }
                return rest.reversed().reduce(URL(filePath: String(cString: real))) { $0.appending(path: $1) }
                    .path(percentEncoded: false)
            }
            rest.append(existing.lastPathComponent)
            existing.deleteLastPathComponent()
        }
        return root
    }

    private static func tooBig(_ name: String, _ limit: Int) -> ControlError {
        ControlError("“\(name)” is larger than \(megabytes(limit)) MB, the most Luna uploads per file.")
    }

    private static func megabytes(_ bytes: Int) -> Int { bytes / (1024 * 1024) }
}
