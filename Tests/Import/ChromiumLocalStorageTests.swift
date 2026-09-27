//
//  ChromiumLocalStorageTests.swift
//  LunaTests
//
//  The LevelDB reader behind carrying file pages' storage over from Dia:
//  the log, a table, Snappy, and the newest value winning.
//

import XCTest
@testable import Luna

final class ChromiumLocalStorageTests: XCTestCase {

    private let prefix = Array("_file://".utf8) + [0]

    private func key(_ name: String) -> [UInt8] { prefix + [1] + Array(name.utf8) }
    private func value(_ text: String) -> [UInt8] { [1] + Array(text.utf8) }

    private func varint(_ number: Int) -> [UInt8] {
        var number = number
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(number & 0x7F)
            number >>= 7
            if number > 0 { byte |= 0x80 }
            bytes.append(byte)
        } while number > 0
        return bytes
    }

    private func littleEndian(_ number: UInt64, width: Int) -> [UInt8] {
        (0 ..< width).map { UInt8(truncatingIfNeeded: number >> (8 * UInt64($0))) }
    }

    /// One write batch as one FULL log record.
    private func log(sequence: UInt64, _ operations: [(key: [UInt8], value: [UInt8]?)]) -> [UInt8] {
        var batch = littleEndian(sequence, width: 8) + littleEndian(UInt64(operations.count), width: 4)
        for operation in operations {
            if let value = operation.value {
                batch += [1] + varint(operation.key.count) + operation.key + varint(value.count) + value
            } else {
                batch += [0] + varint(operation.key.count) + operation.key
            }
        }
        return [0, 0, 0, 0] + littleEndian(UInt64(batch.count), width: 2) + [1] + batch
    }

    func testTheLogGivesTheNewestValueAndHonoursADeletion() {
        let bytes = log(sequence: 5, [(key("board"), value("old")), (key("gone"), value("x"))])
            + log(sequence: 7, [(key("board"), value("new")), (key("gone"), nil)])
        let records = LevelDB.logRecords(Data(bytes))
        XCTAssertEqual(records.count, 4)
        var newest: [Data: LevelDBRecord] = [:]
        for record in records where (newest[record.key]?.sequence ?? 0) < record.sequence { newest[record.key] = record }
        XCTAssertEqual(newest[Data(key("board"))]?.value, Data(value("new")))
        XCTAssertNil(newest[Data(key("gone"))]?.value)
    }

    func testSnappyExpandsLiteralsAndOverlappingCopies() {
        // "abc", then a 9-byte copy from 3 back that overlaps itself.
        let compressed: [UInt8] = [12, 0x08, 97, 98, 99, 0x15, 3]
        XCTAssertEqual(Snappy.decompress(compressed).flatMap { String(bytes: $0, encoding: .utf8) }, "abcabcabcabc")
        XCTAssertNil(Snappy.decompress([12, 0x08, 97]), "a truncated block is refused, not trusted")
    }

    /// A table of one data block and its index, as LevelDB lays them out.
    func testATableIsReadThroughItsIndex() {
        let internalKey = key("board") + littleEndian(9 << 8 | 1, width: 8)
        let stored = value("from a table")
        let entry = [0] + varint(internalKey.count) + varint(stored.count) + internalKey + stored
        let data = entry + littleEndian(0, width: 4) + littleEndian(1, width: 4)
        let dataHandle = varint(0) + varint(data.count)
        let indexEntry = [0] + varint(internalKey.count) + varint(dataHandle.count) + internalKey + dataHandle
        let index = indexEntry + littleEndian(0, width: 4) + littleEndian(1, width: 4)
        let indexOffset = data.count + 5
        var file = data + [0, 0, 0, 0, 0] + index + [0, 0, 0, 0, 0]
        var footer = varint(0) + varint(0) + varint(indexOffset) + varint(index.count)
        footer += [UInt8](repeating: 0, count: 40 - footer.count)
        file += footer + littleEndian(0xDB47_7524_8B80_FB57, width: 8)

        let records = LevelDB.tableRecords(Data(file), from: Data(prefix))
        XCTAssertEqual(records, [LevelDBRecord(key: Data(key("board")), sequence: 9, value: Data(stored))])
        XCTAssertTrue(LevelDB.tableRecords(Data(file), from: Data("_https://a.com".utf8) + Data([0])).isEmpty,
                      "a block outside the origin's range is not read")
    }

    func testKeysAndValuesDecodeInBothEncodings() {
        XCTAssertEqual(ChromiumLocalStorage.decode(Data([1] + Array("posted".utf8))), "posted")
        XCTAssertEqual(ChromiumLocalStorage.decode(Data([0, 104, 0, 105, 0])), "hi")
        XCTAssertNil(ChromiumLocalStorage.decode(Data()))
    }

    /// End to end, from a store folder on disk.
    func testTheOriginsEntriesComeOutOfAStoreFolder() throws {
        let folder = URL.temporaryDirectory.appending(path: "leveldb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let other = Array("_https://example.com".utf8) + [0, 1] + Array("k".utf8)
        try Data(log(sequence: 1, [(key("roosta-deck-board-v1"), value("{\"posted\":{}}")), (other, value("no"))]))
            .write(to: folder.appending(path: "000003.log"))
        XCTAssertEqual(
            ChromiumLocalStorage.entries(origin: "file://", in: folder),
            ["roosta-deck-board-v1": "{\"posted\":{}}"]
        )
    }
}
