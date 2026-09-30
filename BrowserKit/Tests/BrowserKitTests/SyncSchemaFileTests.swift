@testable import BrowserKit
import Foundation
import Testing

/// `Config/CloudKit/Schema.ckdb` against what the mappers write (docs/SYNC-PLAN.md §2, S4).
///
/// Production has no just-in-time schema and can only grow, so a field a mapper writes
/// that the schema lacks fails every save, and a field declared with the wrong encryption
/// can never be corrected. This is the check that runs before either reaches the server.
@Suite("CloudKit schema file (§31.2)")
struct SyncSchemaFileTests {

    struct Field: Equatable {
        var type: String
        var isEncrypted: Bool
    }

    /// Declared but deliberately never written.
    private static let reserved: Set = ["SiteSetting.zoom"]

    private static let schemaURL = URL(filePath: #filePath)
        .deletingLastPathComponent()   // BrowserKitTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // BrowserKit
        .deletingLastPathComponent()   // repository root
        .appending(path: "Config/CloudKit/Schema.ckdb")

    /// Record type → field → declaration. System fields (`"___…"`) and `GRANT`s are skipped.
    static func parse(_ text: String) -> [String: [String: Field]] {
        var types: [String: [String: Field]] = [:]
        var current: String?
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("RECORD TYPE ") {
                current = line.dropFirst("RECORD TYPE ".count).split(separator: " ").first.map(String.init)
                types[current ?? ""] = [:]
                continue
            }
            if line.hasPrefix(");") { current = nil; continue }
            guard let current, !line.hasPrefix("\""), !line.hasPrefix("GRANT") else { continue }
            let words = line.trimmingCharacters(in: CharacterSet(charactersIn: ",")).split(separator: " ").map(String.init)
            guard words.count >= 2 else { continue }
            let isEncrypted = words[1] == "ENCRYPTED"
            guard let type = isEncrypted ? words.dropFirst(2).first : words[1] else { continue }
            types[current]?[words[0]] = Field(type: type, isEncrypted: isEncrypted)
        }
        return types
    }

    private static func schemaType(of value: SyncValue) -> String {
        switch value {
        case .string: "STRING"
        case .int: "INT64"
        case .double: "DOUBLE"
        case .date: "TIMESTAMP"
        case .bytes: "BYTES"
        }
    }

    private func schema() throws -> [String: [String: Field]] {
        Self.parse(try String(contentsOf: Self.schemaURL, encoding: .utf8))
    }

    @Test func theParserReadsThePlansNotation() {
        let parsed = Self.parse("""
        DEFINE SCHEMA
          RECORD TYPE Thing (
            "___recordID"   REFERENCE QUERYABLE,
            schemaVersion   INT64,
            name            ENCRYPTED STRING,
            GRANT WRITE TO "_creator", GRANT READ TO "_world"
          );
        """)
        #expect(parsed == ["Thing": [
            "schemaVersion": Field(type: "INT64", isEncrypted: false),
            "name": Field(type: "STRING", isEncrypted: true)
        ]])
    }

    @Test func everyFieldAMapperWritesIsDeclaredWithMatchingEncryptionAndType() throws {
        let schema = try schema()
        for record in SyncSamples.allRecords {
            let declared = try #require(schema[record.recordType], "\(record.recordType) is not in Schema.ckdb")
            #expect(declared[SyncCloudKit.schemaVersionKey] == Field(type: "INT64", isEncrypted: false))
            for (key, field) in record.fields {
                let name = "\(record.recordType).\(key)"
                let declaration = try #require(declared[key], "\(name) is written but not declared")
                #expect(declaration.isEncrypted == field.isEncrypted, "\(name): ENCRYPTED does not match the mapper")
                let value = try #require(field.value, "\(name): the sample should populate every field")
                #expect(declaration.type == Self.schemaType(of: value), "\(name): declared \(declaration.type)")
            }
        }
    }

    /// The other way round: a declared field nothing writes is a typo or a field that
    /// was renamed in one place, and Production would keep it forever.
    @Test func everyDeclaredFieldIsWrittenOrReserved() throws {
        let written = Dictionary(grouping: SyncSamples.allRecords, by: \.recordType)
            .mapValues { Set($0.flatMap(\.fields.keys)).union([SyncCloudKit.schemaVersionKey]) }
        for (type, fields) in try schema() where type != "Users" {
            let known = try #require(written[type], "\(type) is declared but no mapper writes it")
            for field in fields.keys where !known.contains(field) {
                #expect(Self.reserved.contains("\(type).\(field)"), "\(type).\(field) is declared but never written")
            }
        }
    }
}
