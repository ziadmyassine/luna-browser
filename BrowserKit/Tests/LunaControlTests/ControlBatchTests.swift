import Foundation
import LunaControl
import Synchronization
import Testing

/// `batch` as `ControlSession` runs it: every step handed to the performer —
/// the app's gate — on its own, in order, and nothing after a failure.
@Suite("Luna Control batch")
struct ControlBatchTests {

    /// Stands in for the gate: records every call, answers from `answer`.
    final class Gate: Sendable {
        let seen = Mutex<[ControlCall]>([])
        let answer: @Sendable (ControlCall) -> ControlResult
        init(_ answer: @escaping @Sendable (ControlCall) -> ControlResult = { _ in .text("done") }) {
            self.answer = answer
        }
        var calls: [ControlCall] { seen.withLock { $0 } }
    }

    private func batch(_ actions: [JSONValue], gate: Gate) async -> JSONValue? {
        let session = ControlSession { call, _ in
            gate.seen.withLock { $0.append(call) }
            return gate.answer(call)
        }
        let request: JSONValue = [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": ["name": "batch", "arguments": ["actions": .array(actions)]]
        ]
        return await session.handle(request.encoded()).flatMap(JSONValue.parse)?["result"]
    }

    private func texts(_ result: JSONValue?) -> String {
        guard case let .array(items)? = result?["content"] else { return "" }
        return items.compactMap { $0["text"]?.string }.joined(separator: "\n")
    }

    @Test func batchIsListed() {
        #expect(ControlTools.names.contains("batch"))
    }

    @Test func eachStepGated() async {
        let gate = Gate()
        let result = await batch([
            ["tool": "navigate", "args": ["url": "example.com", "tabId": 2]],
            ["tool": "click", "args": ["ref": "e3"]],
            ["tool": "type", "args": ["text": "hi"]]
        ], gate: gate)
        #expect(result?["isError"] == false)
        #expect(gate.calls == [
            ControlCall(tab: 2, .navigate(.url(URL(string: "https://example.com")!))),
            ControlCall(.click(.ref("e3"), clickCount: 1)),
            ControlCall(.type("hi", ref: nil))
        ])
        #expect(texts(result).components(separatedBy: "done").count == 4)
    }

    @Test func declinedStepStopsTheRest() async {
        let gate = Gate { call in
            if case .click = call.command { return .error("The user declined “click e3”.") }
            return .text("done")
        }
        let result = await batch([
            ["tool": "find", "args": ["query": "Buy"]],
            ["tool": "click", "args": ["ref": "e3"]],
            ["tool": "click", "args": ["ref": "e4"]]
        ], gate: gate)
        #expect(result?["isError"] == true)
        #expect(gate.calls.count == 2)
        #expect(texts(result).contains("declined"))
        #expect(texts(result).contains("step 2"))
    }

    @Test func stopsOnFirstError() async {
        let gate = Gate()
        let result = await batch([
            ["tool": "find", "args": ["query": "Buy"]],
            ["tool": "navigate", "args": [:]],
            ["tool": "click", "args": ["ref": "e4"]]
        ], gate: gate)
        #expect(result?["isError"] == true)
        #expect(gate.calls.count == 1)
        #expect(texts(result).contains("url is required"))
    }

    @Test func refSubstitution() async {
        let gate = Gate { call in
            if case .find = call.command { return .text("button \"Buy\" [e7]\nlink \"Help\" [e9]") }
            return .text("done")
        }
        let result = await batch([
            ["tool": "find", "args": ["query": "Buy"]],
            ["tool": "click", "args": ["ref": "$1"]],
            ["tool": "type", "args": ["ref": "$1", "text": "$1"]]
        ], gate: gate)
        #expect(result?["isError"] == false)
        #expect(gate.calls.dropFirst().map(\.command) == [.click(.ref("e7"), clickCount: 1), .type("$1", ref: "e7")])
    }

    @Test func refToAStepWithoutOneStops() async {
        let gate = Gate()
        let result = await batch([
            ["tool": "find", "args": ["query": "Buy"]],
            ["tool": "click", "args": ["ref": "$1"]]
        ], gate: gate)
        #expect(result?["isError"] == true)
        #expect(gate.calls.count == 1)
        let later = await batch([["tool": "click", "args": ["ref": "$2"]], ["tool": "find", "args": ["query": "x"]]], gate: Gate())
        #expect(later?["isError"] == true)
    }

    @Test func nestedBatchRefused() async {
        let gate = Gate()
        let result = await batch([
            ["tool": "find", "args": ["query": "Buy"]],
            ["tool": "batch", "args": ["actions": [["tool": "click", "args": ["ref": "e1"]]]]]
        ], gate: gate)
        #expect(result?["isError"] == true)
        #expect(gate.calls.isEmpty)
    }

    @Test func refusesTooManyUnknownOrNone() async {
        let gate = Gate()
        let many = Array(repeating: ["tool": "wait", "args": ["seconds": 0]] as JSONValue, count: 21)
        #expect(await batch(many, gate: gate)?["isError"] == true)
        #expect(await batch([["tool": "format_disk"]], gate: gate)?["isError"] == true)
        #expect(await batch([], gate: gate)?["isError"] == true)
        #expect(gate.calls.isEmpty)
    }
}
