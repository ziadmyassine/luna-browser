//
//  ChromiumLocalStorage.swift
//  Luna
//
//  Reads what a page saved with `localStorage` in a Chromium browser — Dia,
//  Arc, Chrome — for one origin. Chromium keeps it in a LevelDB under the
//  profile's `Local Storage/leveldb`; this is a reader for exactly as much of
//  LevelDB as that takes: the write-ahead log, the sorted tables, and Snappy,
//  which the tables' blocks are compressed with.
//
//  Keys are `_` + origin + NUL + key and values are the string, each with a
//  first byte saying how it is encoded: 1 for Latin-1, 0 for UTF-16LE.
//  Measured on Dia 1.48: `_file://\0\1roosta-deck-board-v1`.
//
//  Read-only and tolerant. The browser may be running and writing, so a torn
//  record at the end of the log, a table half written, or anything else that
//  does not parse is skipped rather than trusted.
//

import Foundation

enum ChromiumLocalStorage {

    /// Every key the origin has, with its newest value.
    static func entries(origin: String, in leveldb: URL) -> [String: String] {
        let prefix = Data("_\(origin)".utf8) + Data([0])
        var newest: [Data: (sequence: UInt64, value: Data?)] = [:]
        func take(_ record: LevelDBRecord) {
            guard record.key.starts(with: prefix) else { return }
            if let seen = newest[record.key], seen.sequence >= record.sequence { return }
            newest[record.key] = (record.sequence, record.value)
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: leveldb, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
            switch file.pathExtension {
            case "log": LevelDB.logRecords(data).forEach(take)
            case "ldb", "sst": LevelDB.tableRecords(data, from: prefix).forEach(take)
            default: continue
            }
        }
        var result: [String: String] = [:]
        for (key, entry) in newest {
            guard let value = entry.value,
                  let name = decode(key.dropFirst(prefix.count)),
                  let text = decode(value)
            else { continue }
            result[name] = text
        }
        return result
    }

    /// A key or a value as Chromium stores it: an encoding byte, then the text.
    static func decode(_ bytes: Data) -> String? {
        guard let first = bytes.first else { return nil }
        let body = bytes.dropFirst()
        switch first {
        case 1: return String(data: body, encoding: .isoLatin1)
        case 0: return String(data: body, encoding: .utf16LittleEndian)
        default: return nil
        }
    }
}

// MARK: - LevelDB

struct LevelDBRecord: Equatable {
    let key: Data
    let sequence: UInt64
    /// Nil for a deletion.
    let value: Data?
}

enum LevelDB {

    // MARK: The write-ahead log

    /// The log is 32 KiB blocks of records, each a 7-byte header and a piece
    /// of a write batch; a batch split across blocks comes in FIRST, MIDDLE
    /// and LAST pieces.
    static func logRecords(_ data: Data) -> [LevelDBRecord] {
        let bytes = [UInt8](data)
        let blockSize = 32_768
        var records: [LevelDBRecord] = []
        var pending: [UInt8] = []
        var offset = 0
        while offset + 7 <= bytes.count {
            let left = blockSize - offset % blockSize
            if left < 7 {
                offset += left
                continue
            }
            let length = Int(bytes[offset + 4]) | Int(bytes[offset + 5]) << 8
            let type = bytes[offset + 6]
            let start = offset + 7
            guard type != 0, start + length <= bytes.count, length <= left - 7 else { break }
            let piece = bytes[start ..< start + length]
            switch type {
            case 1: records += batch(Array(piece))
            case 2: pending = Array(piece)
            case 3: pending += piece
            case 4:
                pending += piece
                records += batch(pending)
                pending = []
            default: break
            }
            offset = start + length
        }
        return records
    }

    /// A write batch: an 8-byte starting sequence, a 4-byte count, then puts
    /// (tag 1, key, value) and deletions (tag 0, key), one sequence each.
    static func batch(_ bytes: [UInt8]) -> [LevelDBRecord] {
        guard bytes.count >= 12 else { return [] }
        var sequence = littleEndian(bytes, at: 0, width: 8)
        var reader = ByteReader(bytes, from: 12)
        var records: [LevelDBRecord] = []
        while !reader.isAtEnd {
            guard let tag = reader.byte(), let key = reader.lengthPrefixed() else { break }
            if tag == 1 {
                guard let value = reader.lengthPrefixed() else { break }
                records.append(LevelDBRecord(key: Data(key), sequence: sequence, value: Data(value)))
            } else if tag == 0 {
                records.append(LevelDBRecord(key: Data(key), sequence: sequence, value: nil))
            } else {
                break
            }
            sequence += 1
        }
        return records
    }

    // MARK: Sorted tables

    /// The entries of a table whose user keys start with `prefix`. Only the
    /// data blocks whose range can hold one are read and decompressed: a
    /// profile's tables are megabytes of other sites' storage.
    static func tableRecords(_ data: Data, from prefix: Data) -> [LevelDBRecord] {
        let bytes = [UInt8](data)
        guard bytes.count >= 48,
              littleEndian(bytes, at: bytes.count - 8, width: 8) == 0xDB47_7524_8B80_FB57
        else { return [] }
        var footer = ByteReader(bytes, from: bytes.count - 48)
        guard footer.varint() != nil, footer.varint() != nil,
              let indexOffset = footer.varint(), let indexSize = footer.varint(),
              let index = block(bytes, offset: Int(indexOffset), size: Int(indexSize))
        else { return [] }
        let upper = prefix.dropLast() + [prefix.last.map { $0 + 1 } ?? 1]
        var records: [LevelDBRecord] = []
        var previous: [UInt8]?
        for (separator, handle) in entries(of: index) {
            defer { previous = separator }
            // A block holds the keys after the previous separator, up to and
            // including its own.
            guard userKey(separator).lexicographicallyPrecedes(prefix) == false,
                  previous.map({ userKey($0).lexicographicallyPrecedes(upper) }) ?? true
            else { continue }
            var reader = ByteReader(handle, from: 0)
            guard let offset = reader.varint(), let size = reader.varint(),
                  let contents = block(bytes, offset: Int(offset), size: Int(size))
            else { continue }
            for (key, value) in entries(of: contents) where key.count >= 8 {
                let trailer = littleEndian(key, at: key.count - 8, width: 8)
                let isValue = trailer & 0xFF == 1
                records.append(LevelDBRecord(
                    key: Data(key.dropLast(8)),
                    sequence: trailer >> 8,
                    value: isValue ? Data(value) : nil
                ))
            }
        }
        return records
    }

    private static func userKey(_ internalKey: [UInt8]) -> [UInt8] {
        internalKey.count >= 8 ? Array(internalKey.dropLast(8)) : internalKey
    }

    /// A block's contents, decompressed. Its 5-byte trailer says how: 0 for
    /// none, 1 for Snappy.
    static func block(_ bytes: [UInt8], offset: Int, size: Int) -> [UInt8]? {
        guard offset >= 0, size >= 0, offset + size + 5 <= bytes.count else { return nil }
        let raw = Array(bytes[offset ..< offset + size])
        switch bytes[offset + size] {
        case 0: return raw
        case 1: return Snappy.decompress(raw)
        default: return nil
        }
    }

    /// A block's entries, each key rebuilt from the prefix it shares with the
    /// one before it.
    static func entries(of block: [UInt8]) -> [([UInt8], [UInt8])] {
        guard block.count >= 4 else { return [] }
        let restarts = Int(littleEndian(block, at: block.count - 4, width: 4))
        let end = block.count - 4 - restarts * 4
        guard end >= 0 else { return [] }
        var reader = ByteReader(Array(block[0 ..< end]), from: 0)
        var key: [UInt8] = []
        var result: [([UInt8], [UInt8])] = []
        while !reader.isAtEnd {
            guard let shared = reader.varint(), let unshared = reader.varint(), let length = reader.varint(),
                  Int(shared) <= key.count,
                  let delta = reader.bytes(Int(unshared)), let value = reader.bytes(Int(length))
            else { break }
            key = Array(key.prefix(Int(shared))) + delta
            result.append((key, value))
        }
        return result
    }

    static func littleEndian(_ bytes: [UInt8], at offset: Int, width: Int) -> UInt64 {
        guard offset >= 0, offset + width <= bytes.count else { return 0 }
        var value: UInt64 = 0
        for index in 0 ..< width { value |= UInt64(bytes[offset + index]) << (8 * UInt64(index)) }
        return value
    }
}

// MARK: - Snappy

enum Snappy {

    /// The raw Snappy format, as LevelDB writes it: the uncompressed length as
    /// a varint, then literals and back-references.
    static func decompress(_ input: [UInt8]) -> [UInt8]? {
        var reader = ByteReader(input, from: 0)
        guard let length = reader.varint(), length < 1 << 28 else { return nil }
        var output: [UInt8] = []
        output.reserveCapacity(Int(length))
        while !reader.isAtEnd {
            guard let tag = reader.byte() else { return nil }
            if tag & 3 == 0 {
                guard let literal = literal(tag, &reader) else { return nil }
                output += literal
            } else {
                guard let (count, offset) = reference(tag, &reader), copy(&output, length: count, offset: offset) else {
                    return nil
                }
            }
        }
        return output.count == Int(length) ? output : nil
    }

    /// Up to 60 bytes have their length in the tag; longer ones in the 1–4
    /// bytes after it.
    private static func literal(_ tag: UInt8, _ reader: inout ByteReader) -> [UInt8]? {
        var count = Int(tag >> 2) + 1
        if count > 60 {
            guard let extra = reader.bytes(count - 60) else { return nil }
            count = Int(LevelDB.littleEndian(extra, at: 0, width: extra.count)) + 1
        }
        return reader.bytes(count)
    }

    /// A copy's length and how far back it starts, in the three widths the
    /// format has for the distance.
    private static func reference(_ tag: UInt8, _ reader: inout ByteReader) -> (Int, Int)? {
        switch tag & 3 {
        case 1:
            guard let low = reader.byte() else { return nil }
            return (Int((tag >> 2) & 7) + 4, Int(tag >> 5) << 8 | Int(low))
        case 2:
            guard let raw = reader.bytes(2) else { return nil }
            return (Int(tag >> 2) + 1, Int(LevelDB.littleEndian(raw, at: 0, width: 2)))
        default:
            guard let raw = reader.bytes(4) else { return nil }
            return (Int(tag >> 2) + 1, Int(LevelDB.littleEndian(raw, at: 0, width: 4)))
        }
    }

    /// A back-reference, byte by byte: it may overlap what it is writing.
    private static func copy(_ output: inout [UInt8], length: Int, offset: Int) -> Bool {
        guard offset > 0, offset <= output.count else { return false }
        let start = output.count - offset
        for index in 0 ..< length { output.append(output[start + index]) }
        return true
    }
}

// MARK: - Bytes

struct ByteReader {
    private let bytes: [UInt8]
    private(set) var position: Int

    init(_ bytes: [UInt8], from position: Int) {
        self.bytes = bytes
        self.position = position
    }

    var isAtEnd: Bool { position >= bytes.count }

    mutating func byte() -> UInt8? {
        guard position < bytes.count else { return nil }
        defer { position += 1 }
        return bytes[position]
    }

    mutating func bytes(_ count: Int) -> [UInt8]? {
        guard count >= 0, position + count <= bytes.count else { return nil }
        defer { position += count }
        return Array(bytes[position ..< position + count])
    }

    mutating func varint() -> UInt64? {
        var value: UInt64 = 0
        for shift in stride(from: 0, to: 64, by: 7) {
            guard let next = byte() else { return nil }
            value |= UInt64(next & 0x7F) << UInt64(shift)
            if next & 0x80 == 0 { return value }
        }
        return nil
    }

    mutating func lengthPrefixed() -> [UInt8]? {
        guard let length = varint() else { return nil }
        return bytes(Int(length))
    }
}
