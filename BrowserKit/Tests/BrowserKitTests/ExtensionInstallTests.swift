import Foundation
import Testing
@testable import BrowserKit

/// §16.2: nothing reaches the extensions folder unless it is a verified CRX3 or
/// a ZIP whose every entry stays inside it.
///
/// `json-formatter.crx` is JSON Formatter 0.10.2 (MIT, github.com/callumlocke/json-formatter)
/// exactly as the Chrome Web Store serves it, so it carries the developer's
/// signature and Google's.
@Suite("Extension install (§16.2)")
struct ExtensionInstallTests {

    static let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
    static let crx = fixtures.appending(path: "json-formatter.crx")
    static let webStoreID = "bcjindcccaagfpapjjmafapmmgkkhgoa"

    // MARK: - CRX3

    @Test func verifiesARealWebStorePackageAndDerivesItsID() throws {
        let package = try CRX3.unpack(try Data(contentsOf: Self.crx))
        #expect(package.id == Self.webStoreID)
        #expect(try ExtensionArchive.validate(package.zip).contains("manifest.json"))
    }

    /// One flipped byte in the ZIP and every signature over it fails.
    @Test func refusesATamperedArchive() throws {
        var data = try Data(contentsOf: Self.crx)
        data[data.count - 100] ^= 0xFF
        #expect(throws: CRX3.Failure.badSignature) { try CRX3.unpack(data) }
    }

    @Test func refusesWhatIsNotACRX3() throws {
        #expect(throws: CRX3.Failure.notACRX) { try CRX3.unpack(Data("PK\u{3}\u{4}".utf8)) }
        var crx2 = try Data(contentsOf: Self.crx)
        crx2[4] = 2
        #expect(throws: CRX3.Failure.unsupportedVersion(2)) { try CRX3.unpack(crx2) }
        let truncated = try Data(contentsOf: Self.crx).prefix(200)
        #expect(throws: CRX3.Failure.malformedHeader) { try CRX3.unpack(truncated) }
    }

    // MARK: - ZIP entries

    @Test(arguments: ["manifest.json", "icons/128.png", "_locales/en/messages.json", "a..b/c.js"])
    func acceptsPathsThatStayInside(_ name: String) {
        #expect(ExtensionArchive.isSafe(name))
    }

    @Test(arguments: ["/etc/passwd", "../evil.js", "icons/../../evil.js", "..\\evil.js", "\\abs", "C:/x", ""])
    func refusesPathsThatEscape(_ name: String) {
        #expect(!ExtensionArchive.isSafe(name))
    }

    @Test func refusesAnArchiveWithAnEscapingEntryBeforeWritingAnything() throws {
        let zip = makeZip([("manifest.json", "{}"), ("../escaped.js", "x")])
        #expect(throws: ExtensionArchive.Failure.unsafeEntry("../escaped.js")) { try ExtensionArchive.validate(zip) }
        let destination = temporaryDirectory()
        #expect(throws: (any Error).self) { try ExtensionArchive.extract(zip, into: destination) }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func refusesASymlinkEntry() {
        let zip = makeZip([("link", "/etc/passwd")], mode: 0o120777)
        #expect(throws: ExtensionArchive.Failure.unsafeEntry("link")) { try ExtensionArchive.validate(zip) }
    }

    @Test func refusesAnArchiveThatClaimsToUnpackTooLarge() {
        let zip = makeZip([("big.bin", "x")], declaredSize: UInt32(ExtensionArchive.maximumUnpackedBytes) + 1)
        #expect(throws: ExtensionArchive.Failure.tooLarge) { try ExtensionArchive.validate(zip) }
    }

    @Test func extractsASafeArchive() throws {
        let destination = temporaryDirectory()
        try ExtensionArchive.extract(makeZip([("manifest.json", "{}"), ("js/a.js", "1")]), into: destination)
        #expect(try String(contentsOf: destination.appending(path: "js/a.js"), encoding: .utf8) == "1")
    }

    // MARK: - The library

    @Test func stagesAWebStorePackageUnderItsSignedID() async throws {
        let library = ExtensionLibrary(root: temporaryDirectory())
        let staged = try await library.stage(Self.crx)
        #expect(staged.id == Self.webStoreID)
        #expect(staged.source == .webStore)
        let installed = try await library.commit(staged)
        #expect(installed == (try library.directory(for: Self.webStoreID)))
        #expect(FileManager.default.fileExists(atPath: installed.appending(path: "manifest.json").path))
    }

    @Test func givesAnUnpackedFolderAStableShapedID() async throws {
        let library = ExtensionLibrary(root: temporaryDirectory())
        let staged = try await library.stage(Self.fixtures.appending(path: "FixtureExtension"))
        #expect(staged.source == .local)
        #expect(ExtensionLibrary.isValidID(staged.id))
    }

    /// Chrome's rule: a manifest `key` decides the id, so a developer build
    /// keeps its store identity.
    @Test func takesAnUnpackedIDFromTheManifestKey() async throws {
        let folder = temporaryDirectory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let key = Data((0..<64).map { UInt8($0) })
        try Data(#"{"manifest_version":3,"name":"K","version":"1","key":"\#(key.base64EncodedString())"}"#.utf8)
            .write(to: folder.appending(path: "manifest.json"))
        let staged = try await ExtensionLibrary(root: temporaryDirectory()).stage(folder)
        #expect(staged.id == CRX3.extensionID(publicKey: key))
    }

    @Test func refusesAnIDThatIsNotChromesShape() {
        let library = ExtensionLibrary(root: temporaryDirectory())
        #expect(throws: ExtensionLibrary.Failure.invalidIdentifier) { try library.directory(for: "../../etc") }
        #expect(throws: ExtensionLibrary.Failure.invalidIdentifier) { try library.directory(for: "abc") }
    }

    @Test func buildsTheWebStoreURLWithTheSameChromeVersion() {
        let url = ExtensionLibrary.webStoreURL(id: Self.webStoreID).absoluteString
        #expect(url.contains("prodversion=\(WebViewFactory.chromeMajorVersion).0"))
        #expect(url.hasSuffix("x=id%3D\(Self.webStoreID)%26uc"))
    }
}

/// A fresh path under the temporary directory; nothing is created there.
func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "luna-tests/\(UUID().uuidString)", directoryHint: .isDirectory)
}

/// A stored (uncompressed) ZIP, written by hand so a test can say things a
/// real archiver refuses to: `..` in a name, a symlink, a size that lies.
func makeZip(_ entries: [(String, String)], mode: UInt32 = 0o100644, declaredSize: UInt32? = nil) -> Data {
    func le16(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)] }
    func le32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8(value >> (8 * $0) & 0xFF) } }
    var local: [UInt8] = [], central: [UInt8] = []
    for (name, body) in entries {
        let nameBytes = Array(name.utf8), bodyBytes = Array(body.utf8)
        let size = le32(UInt32(bodyBytes.count)), crc = le32(crc32(bodyBytes))
        let offset = le32(UInt32(local.count))
        local += le32(0x0403_4B50) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0) + crc + size + size
            + le16(nameBytes.count) + le16(0) + nameBytes + bodyBytes
        central += le32(0x0201_4B50) + le16(0x0314) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0) + crc + size
            + le32(declaredSize ?? UInt32(bodyBytes.count)) + le16(nameBytes.count) + le16(0) + le16(0) + le16(0) + le16(0)
            + le32(mode << 16) + offset + nameBytes
    }
    let end = le32(0x0605_4B50) + le16(0) + le16(0) + le16(entries.count) + le16(entries.count)
        + le32(UInt32(central.count)) + le32(UInt32(local.count)) + le16(0)
    return Data(local + central + end)
}

private func crc32(_ bytes: [UInt8]) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in bytes {
        crc ^= UInt32(byte)
        for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
    }
    return ~crc
}
