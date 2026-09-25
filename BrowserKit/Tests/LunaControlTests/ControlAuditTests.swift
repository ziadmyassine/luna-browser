import Foundation
import LunaControl
import Testing

/// The activity log: one JSON line per call, readable only by the user, and
/// read back newest first.
@Suite("Luna Control audit log")
struct ControlAuditTests {

    @Test func appendedRecordsReadBackNewestFirstFromAUserOnlyFile() throws {
        let folder = URL.temporaryDirectory.appending(path: "control-audit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "activity.jsonl")
        let first = ControlAudit.Record(
            time: Date(timeIntervalSince1970: 1), client: "Codex", tool: "click", tab: 3, site: "example.com",
            summary: "click e4", decision: "allowed", outcome: "ok"
        )
        var second = first
        second.tool = "type"
        second.time = Date(timeIntervalSince1970: 2)
        try ControlAudit.append(first, to: file)
        try ControlAudit.append(second, to: file)

        #expect(ControlAudit.read(from: file) == [second, first])
        #expect(ControlAudit.read(from: file, limit: 1) == [second])
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 2)
    }

    @Test func whatWasTypedIsCountedNotKept() {
        #expect(ControlAudit.summary(of: .type("hunter2", ref: "e5")) == "type 7 characters into e5")
        #expect(ControlAudit.summary(of: .fill(ref: "e2", value: "4111111111111111")) == "form_input e2")
        #expect(!ControlAudit.summary(of: .javascript("fetch('/?token=abc')")).contains("abc"))
    }
}
