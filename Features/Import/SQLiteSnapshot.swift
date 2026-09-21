//
//  SQLiteSnapshot.swift
//  Luna — §23.2
//
//  Reading another browser's live database, without breaking it or being
//  blocked by it.
//
//  Measured on 2026-09-17 against Dia 1.48.0's `Profile 1`: opening
//  `.../Profile 1/History` in place with `mode=ro` fails with `database is
//  locked (5)` while Dia is running, and copying the file plus its sidecar into
//  `TMPDIR` returns 8,247 `urls` and 17,931 `visits`. The copy is not a
//  precaution, it is the only thing that works.
//
//  Two details the copy has to get right:
//
//  1. Copy the sidecars. A WAL database's newest writes live entirely in
//     `-wal`; a rollback-journal database needs `-journal` to roll back
//     correctly. Dia's live `History` uses a rollback journal today
//     (`History-journal`, no `-wal`) — Chromium uses both depending on version
//     and file, so copy whichever exist.
//  2. `?immutable=1` is not an alternative. It skips the lock by promising
//     the file cannot change, which makes SQLite ignore the WAL entirely and
//     report `no such table` for data that has not been checkpointed.
//
//  Luna never writes to the source: the copy is what gets opened, and it is
//  opened `SQLITE_OPEN_READONLY`.
//

import Foundation
import SQLite3

/// SQLite's "the caller owns this buffer" marker, needed when binding a Swift
/// `String` whose storage may not outlive `sqlite3_bind_text`.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A private snapshot of the files an import reads, deleted when it is done.
///
/// A class rather than a value so `deinit` can clean up: the snapshot outlives
/// several `await`s and nobody should have to remember to remove it.
final class ImportSnapshot: Sendable {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "LunaImport-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Every sidecar SQLite might have written next to a store.
    static let sidecarSuffixes = ["-wal", "-shm", "-journal"]

    /// Copies `store` and its sidecars in. Returns `nil` when the store is not
    /// there — a Dia profile with no `Bookmarks` file is normal, not an error
    /// (verified: Dia's `Default` profile has `History` but no `Bookmarks`).
    @discardableResult
    func copyIn(_ store: URL) throws -> URL? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: store.path) else { return nil }

        let destination = directory.appending(path: store.lastPathComponent)
        try? fileManager.removeItem(at: destination)
        try fileManager.copyItem(at: store, to: destination)

        for suffix in Self.sidecarSuffixes {
            let sidecar = URL(fileURLWithPath: store.path + suffix)
            guard fileManager.fileExists(atPath: sidecar.path) else { continue }
            let sidecarDestination = URL(fileURLWithPath: destination.path + suffix)
            try? fileManager.removeItem(at: sidecarDestination)
            try? fileManager.copyItem(at: sidecar, to: sidecarDestination)
        }
        return destination
    }
}

enum SQLiteError: LocalizedError, Equatable {
    case open(String)
    case query(String)

    var errorDescription: String? {
        switch self {
        case let .open(message), let .query(message):
            String(localized: "Luna couldn't read that database: \(message)")
        }
    }
}

/// A minimal read-only wrapper over the system SQLite.
///
/// `import SQLite3` autolinks; no package dependency, which matters for a
/// project whose premise is staying small. Not `Sendable` on purpose — the
/// handle belongs to whichever task opened it and never crosses.
final class SQLiteReader {
    private var handle: OpaquePointer?

    init(readOnly url: URL) throws {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(result)"
            sqlite3_close(handle)
            throw SQLiteError.open(message)
        }
        self.handle = handle
    }

    deinit { close() }

    func close() {
        if let handle {
            sqlite3_close(handle)
            self.handle = nil
        }
    }

    /// Whether a table exists. Chromium schema versions come and go; a reader
    /// that asks first degrades to "nothing to import" instead of throwing.
    func hasTable(_ name: String) -> Bool {
        let rows = (try? query(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
            bindings: [.text(name)]
        ) { _ in true }) ?? []
        return !rows.isEmpty
    }

    enum Binding {
        case int(Int64)
        case text(String)
    }

    func query<T>(_ sql: String, bindings: [Binding] = [], transform: (Row) throws -> T?) throws -> [T] {
        var results: [T] = []
        try forEachRow(sql, bindings: bindings) { row in
            if let value = try transform(row) { results.append(value) }
        }
        return results
    }

    /// Steps every row, retaining nothing between them.
    func forEachRow(_ sql: String, bindings: [Binding] = [], _ body: (Row) throws -> Void) throws {
        guard let handle else { throw SQLiteError.query("database is closed") }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            let message = String(cString: sqlite3_errmsg(handle))
            sqlite3_finalize(statement)
            throw SQLiteError.query(message)
        }
        defer { sqlite3_finalize(statement) }

        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            switch binding {
            case let .int(value): sqlite3_bind_int64(statement, index, value)
            case let .text(value): sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
            }
        }

        let row = Row(statement: statement)
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: try body(row)
            case SQLITE_DONE: return
            default: throw SQLiteError.query(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }

    /// One result row, valid only inside the callback it is handed to.
    struct Row {
        fileprivate let statement: OpaquePointer

        func int(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
        func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }

        func text(_ column: Int32) -> String? {
            guard let pointer = sqlite3_column_text(statement, column) else { return nil }
            return String(cString: pointer)
        }
    }
}

/// Chromium's time epoch, and the guards a conversion needs.
///
/// Times are microseconds since 1601-01-01 UTC in every column read here,
/// and in `Bookmarks` the same number arrives as a JSON string — verified in
/// Dia's file, where `date_added` is `"13429579614840426"`. That is the one
/// detail a default `Decodable` gets wrong.
///
/// Two values are rejected rather than converted: `0` means "never" and would
/// become 1601, sorting to the top of every list forever; anything outside a
/// plausible range is a corrupt or differently-scaled column.
enum ChromiumTimestamp {
    static let epochOffsetSeconds: TimeInterval = 11_644_473_600
    static let earliest = Date(timeIntervalSince1970: 0)
    /// 2100-01-01 — past any real clock, well short of what a bad column gives.
    static let latest = Date(timeIntervalSince1970: 4_102_444_800)

    static func date(microsecondsSince1601 raw: Int64) -> Date? {
        guard raw > 0 else { return nil }
        let seconds = Double(raw) / 1_000_000 - epochOffsetSeconds
        guard seconds.isFinite else { return nil }
        let date = Date(timeIntervalSince1970: seconds)
        guard date >= earliest, date <= latest else { return nil }
        return date
    }

    /// The `Bookmarks` JSON variant: the same number, written as a string.
    static func date(microsecondsSince1601 raw: String) -> Date? {
        guard let value = Int64(raw.trimmingCharacters(in: .whitespaces)) else { return nil }
        return date(microsecondsSince1601: value)
    }

    /// Safari and the Swift-side Arc/Dia JSON both use seconds since 2001.
    static func date(secondsSince2001 raw: Double) -> Date? {
        guard raw > 0, raw.isFinite else { return nil }
        let date = Date(timeIntervalSinceReferenceDate: raw)
        guard date >= earliest, date <= latest else { return nil }
        return date
    }
}
