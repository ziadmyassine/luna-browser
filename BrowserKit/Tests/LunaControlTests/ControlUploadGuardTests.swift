import Darwin
import Foundation
import LunaControl
import Testing

/// `file_upload`'s path guard, against files made for each test in a temporary
/// home. Nothing here reads a real user file: the home and the folders it
/// denies are all under the test's own directory.
@Suite("Luna Control upload guard")
struct ControlUploadGuardTests {

    private let home: URL
    private let denied: [String]

    init() throws {
        home = URL.temporaryDirectory.appending(path: "lc-upload-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home.appending(path: ".ssh"), withIntermediateDirectories: true)
        denied = ControlUpload.deniedFolders(home: home, bundleIdentifier: "dk.novapps.luna")
    }

    private func file(_ name: String, _ contents: String = "hello") throws -> String {
        let url = home.appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url.path(percentEncoded: false)
    }

    private func read(_ path: String, owner: uid_t = getuid()) throws -> ControlUpload.File {
        try ControlUpload.read(path: path, denied: denied, owner: owner)
    }

    private func refused(_ path: String, owner: uid_t = getuid(), _ said: String) {
        #expect(throws: ControlError.self) { try read(path, owner: owner) }
        do {
            _ = try read(path, owner: owner)
        } catch {
            let message = (error as? ControlError)?.message ?? ""
            #expect(message.contains(said), "\(message)")
        }
    }

    @Test func aPlainFileIsRead() throws {
        let read = try read(try file("cv.pdf", "%PDF"))
        #expect(read.name == "cv.pdf")
        #expect(read.mimeType == "application/pdf")
        #expect(read.data == Data("%PDF".utf8))
    }

    @Test func testHardLinkRefused() throws {
        let original = try file("a.txt")
        let second = home.appending(path: "b.txt").path(percentEncoded: false)
        #expect(link(original, second) == 0)
        refused(original, "link")
        refused(second, "link")
    }

    @Test func testSymlinkRefused() throws {
        let target = try file("real.txt")
        let alias = home.appending(path: "alias.txt").path(percentEncoded: false)
        #expect(symlink(target, alias) == 0)
        refused(alias, "symbolic link")

        // A folder on the way that links into a denied one is caught by
        // where the file actually is, not by how the path was spelled.
        _ = try file(".ssh/id_ed25519", "PRIVATE KEY")
        let keys = home.appending(path: "keys").path(percentEncoded: false)
        #expect(symlink(home.appending(path: ".ssh").path(percentEncoded: false), keys) == 0)
        refused(keys + "/id_ed25519", "not allowed")
    }

    @Test func testOversizeRefused() throws {
        let big = home.appending(path: "big.bin")
        FileManager.default.createFile(atPath: big.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: UInt64(ControlUpload.maxFileBytes + 1))
        try handle.close()
        refused(big.path(percentEncoded: false), "10 MB")

        // Each under the limit, together over it.
        var paths: [ControlCommand.UploadSource] = []
        for index in 0 ..< 3 {
            let part = home.appending(path: "part\(index).bin")
            FileManager.default.createFile(atPath: part.path(percentEncoded: false), contents: nil)
            let handle = try FileHandle(forWritingTo: part)
            try handle.truncate(atOffset: UInt64(ControlUpload.maxFileBytes - 1))
            try handle.close()
            paths.append(.path(part.path(percentEncoded: false)))
        }
        #expect(throws: ControlError.self) { try ControlUpload.resolve(paths, denied: denied) }
        // Inline files count toward both limits too.
        let inline = ControlCommand.UploadSource.data(.init(name: "x", mimeType: "text/plain", data: Data(count: 10)))
        #expect(try ControlUpload.resolve([inline, inline], denied: denied, totalLimit: 25).count == 2)
        #expect(throws: ControlError.self) { try ControlUpload.resolve([inline, inline, inline], denied: denied, totalLimit: 25) }
        #expect(throws: ControlError.self) { try ControlUpload.resolve([inline], denied: denied, fileLimit: 9) }
    }

    @Test func testOtherOwnerRefused() throws {
        refused(try file("theirs.txt"), owner: getuid() + 1, "owned")
    }

    @Test func deniedFoldersAreRefused() throws {
        refused(try file(".ssh/id_ed25519", "PRIVATE KEY"), "not allowed")
        refused(try file("Library/Keychains/login.keychain-db"), "not allowed")
        refused(try file("Library/Application Support/dk.novapps.luna/Control/activity.jsonl"), "not allowed")
        refused(try file("Library/WebKit/dk.novapps.luna/cookies"), "not allowed")
        refused(try file("Library/Preferences/dk.novapps.luna.plist"), "not allowed")
        // Case does not get round it on a case-insensitive disk, nor `..`.
        refused(home.appending(path: ".SSH/id_ed25519").path(percentEncoded: false), "not allowed")
        refused(home.appending(path: "Documents/../.ssh/id_ed25519").path(percentEncoded: false), "not allowed")
        // A sibling whose name only starts the same is not Luna's.
        #expect(try read(try file("Library/Application Support/dk.novapps.lunar/notes.txt")).name == "notes.txt")
    }

    @Test func notAFileIsRefused() throws {
        refused(home.path(percentEncoded: false), "not a file")
        refused("relative/path.txt", "absolute")
        refused(home.appending(path: "missing.txt").path(percentEncoded: false), "could not be opened")
        let fifo = home.appending(path: "pipe").path(percentEncoded: false)
        #expect(mkfifo(fifo, 0o600) == 0)
        refused(fifo, "not a file")
    }
}
