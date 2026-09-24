import Foundation

/// A ZIP checked before a byte of it is written out (docs/EXTENSIONS.md §3.7).
///
/// The central directory is read and every entry judged first: no absolute
/// path, no `..`, no symlink, and totals under the caps below. Only then does
/// `ditto` extract it, and the result is walked once more, because a ZIP's
/// declared sizes are the archive's word rather than a fact.
public enum ExtensionArchive {

    public enum Failure: Error, Equatable {
        case tooLarge
        case notAZip
        case zip64Unsupported
        case unsafeEntry(String)
        case extractionFailed
    }

    /// Not measurements: ceilings far above any real extension and far below a
    /// full disk.
    static let maximumArchiveBytes = 256 << 20
    static let maximumUnpackedBytes = 1 << 30
    static let maximumEntries = 20_000

    /// The entries' names, once all of them have passed.
    @discardableResult
    public static func validate(_ zip: Data) throws -> [String] {
        guard zip.count <= maximumArchiveBytes else { throw Failure.tooLarge }
        let bytes = [UInt8](zip)
        guard let end = endOfCentralDirectory(bytes) else { throw Failure.notAZip }
        let count = Int(u16(bytes, end + 10))
        let offset = Int(u32(bytes, end + 16))
        guard count != 0xFFFF, offset != 0xFFFF_FFFF else { throw Failure.zip64Unsupported }
        guard count <= maximumEntries else { throw Failure.tooLarge }

        var names: [String] = []
        var unpacked = 0
        var index = offset
        for _ in 0..<count {
            guard index + 46 <= bytes.count, u32(bytes, index) == 0x0201_4B50 else { throw Failure.notAZip }
            let size = u32(bytes, index + 24)
            guard size != 0xFFFF_FFFF else { throw Failure.zip64Unsupported }
            let nameLength = Int(u16(bytes, index + 28))
            let skip = nameLength + Int(u16(bytes, index + 30)) + Int(u16(bytes, index + 32))
            guard index + 46 + nameLength <= bytes.count else { throw Failure.notAZip }
            // A name that is not UTF-8 reads as empty, which `isSafe` refuses.
            let name = String(bytes: bytes[(index + 46)..<(index + 46 + nameLength)], encoding: .utf8) ?? ""
            let mode = u32(bytes, index + 38) >> 16
            guard isSafe(name), mode & 0o170000 != 0o120000 else { throw Failure.unsafeEntry(name) }
            unpacked += Int(size)
            guard unpacked <= maximumUnpackedBytes else { throw Failure.tooLarge }
            names.append(name)
            index += 46 + skip
        }
        return names
    }

    /// A relative path that stays inside the folder it is extracted into.
    /// Backslashes count as separators: a ZIP written on Windows may use them,
    /// and `..\` is the same escape.
    static func isSafe(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.hasPrefix("\\"), !name.contains("\0") else { return false }
        let parts = name.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        return !parts.contains("..") && !(parts.first?.contains(":") ?? false)
    }

    /// Validates `zip`, then extracts it into `directory`, which must not exist yet.
    public static func extract(_ zip: Data, into directory: URL) throws {
        try validate(zip)
        let file = FileManager.default.temporaryDirectory.appending(path: "luna-\(UUID().uuidString).zip")
        try zip.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", "--noqtn", file.path, directory.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw Failure.extractionFailed }
        try checkExtracted(directory)
    }

    private static func checkExtracted(_ directory: URL) throws {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .fileSizeKey]
        guard let walk = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else {
            throw Failure.extractionFailed
        }
        var total = 0
        for case let url as URL in walk {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true { throw Failure.unsafeEntry(url.lastPathComponent) }
            total += values.fileSize ?? 0
            if total > maximumUnpackedBytes { throw Failure.tooLarge }
        }
    }

    // MARK: - Reading

    /// The end-of-central-directory record: the last `PK\5\6` within the final
    /// 64 KiB + 22 bytes, which is as far back as a trailing comment can push it.
    private static func endOfCentralDirectory(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        let floor = max(0, bytes.count - 22 - 0xFFFF)
        for index in stride(from: bytes.count - 22, through: floor, by: -1) where u32(bytes, index) == 0x0605_4B50 {
            return index
        }
        return nil
    }

    private static func u16(_ bytes: [UInt8], _ at: Int) -> UInt16 {
        UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
    }

    private static func u32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        UInt32(u16(bytes, at)) | UInt32(u16(bytes, at + 2)) << 16
    }
}
