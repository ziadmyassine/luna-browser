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

    /// Where no upload may come from: SSH keys, the keychains, and Luna's
    /// own data — its profile, cookies and the activity log among it.
    public static func deniedFolders(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundleIdentifier: String
    ) -> [String] {
        let library = home.appending(path: "Library")
        let luna = ["Application Support", "Caches", "WebKit", "HTTPStorages", "Cookies", "Containers", "Logs"]
            .map { library.appending(path: $0).appending(path: bundleIdentifier) }
        return ([home.appending(path: ".ssh"), library.appending(path: "Keychains"), URL(filePath: "/Library/Keychains"),
                 library.appending(path: "Preferences/\(bundleIdentifier).plist"),
                 library.appending(path: "Saved Application State/\(bundleIdentifier).savedState")] + luna)
            .map { $0.path(percentEncoded: false) }
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

        // Non-blocking so a FIFO fails the regular-file test rather than
        // hanging the call waiting for a writer.
        let fd = open(standard, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            if errno == ELOOP { throw ControlError("“\(path)” is a symbolic link. Give the path of the file itself.") }
            throw ControlError("“\(path)” could not be opened: \(String(cString: strerror(errno))).")
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw ControlError("“\(path)” is not a file.")
        }
        // Where the file really is, after every link in the folders on the way.
        var real = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(fd, F_GETPATH, &real) == 0 else { throw refusal }
        if isDenied(String(decoding: real.prefix { $0 != 0 }, as: UTF8.self), by: denied) { throw refusal }
        // A second name for the file can sit anywhere, a denied folder included.
        guard info.st_nlink == 1 else { throw ControlError("“\(path)” has other hard links, so Luna will not upload it.") }
        guard info.st_uid == owner else { throw ControlError("“\(path)” is not owned by you, so Luna will not upload it.") }
        let name = URL(filePath: standard).lastPathComponent
        guard info.st_size <= limit else { throw tooBig(name, limit) }

        var data = Data(count: Int(info.st_size))
        let complete = data.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.read(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
        guard complete else { throw ControlError("“\(path)” could not be read.") }
        let type = UTType(filenameExtension: URL(filePath: standard).pathExtension)?.preferredMIMEType
        return File(name: name, mimeType: type ?? "application/octet-stream", data: data)
    }

    /// Compared without case: APFS is case-insensitive by default, so
    /// `~/.SSH` is `~/.ssh`.
    private static func isDenied(_ path: String, by denied: [String]) -> Bool {
        let path = path.lowercased()
        return denied.contains { root in
            [root, canonical(root)].contains { spelled in
                let root = spelled.lowercased()
                return path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
            }
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
