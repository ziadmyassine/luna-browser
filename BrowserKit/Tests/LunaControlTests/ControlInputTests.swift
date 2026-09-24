import Foundation
import LunaControl
import Testing

/// The trusted-input half that needs no window: key names to virtual key
/// codes, modifier spellings, and the new arguments of the input tools.
@Suite("Luna Control input")
struct ControlInputTests {

    private func parse(_ tool: String, _ args: [String: JSONValue]) -> Result<ControlCall, ControlError>? {
        ControlCall.parse(tool: tool, arguments: args)
    }

    private func command(_ tool: String, _ args: [String: JSONValue]) -> ControlCommand? {
        try? parse(tool, args)?.get().command
    }

    @Test func namedKeysHaveTheirKeyCodesAndCharacters() throws {
        let enter = try ControlInput.key("Enter")
        #expect(enter.keyCode == 36 && enter.characters == "\r" && enter.modifiers.isEmpty)
        #expect(try ControlInput.key("return").keyCode == 36)
        #expect(try ControlInput.key("Escape").keyCode == 53)
        #expect(try ControlInput.key("Tab").characters == "\t")
        #expect(try ControlInput.key("ArrowUp").characters == "\u{F700}")
        #expect(try ControlInput.key("ArrowUp").keyCode == 126)
        #expect(try ControlInput.key("PageDown").keyCode == 121)
        #expect(try ControlInput.key("F5").keyCode == 96)
        #expect(try ControlInput.key("space").characters == " ")
    }

    @Test func combosCarryTheirModifiers() throws {
        let selectAll = try ControlInput.key("cmd+a")
        #expect(selectAll.modifiers == [.command])
        #expect(selectAll.keyCode == 0 && selectAll.charactersIgnoringModifiers == "a")
        let back = try ControlInput.key("shift+Tab")
        #expect(back.modifiers == [.shift] && back.keyCode == 48)
        let capital = try ControlInput.key("shift+a")
        #expect(capital.characters == "A" && capital.charactersIgnoringModifiers == "a")
        #expect(try ControlInput.key("Meta+Option+Control+x").modifiers == [.command, .option, .control])
    }

    @Test func anUnknownKeyIsAnErrorTheModelCanRead() throws {
        #expect(throws: ControlError.self) { try ControlInput.key("Hyper") }
        #expect(throws: ControlError.self) { try ControlInput.key("super+a") }
        #expect(throws: ControlError.self) { try ControlInput.modifiers("cmd+banana") }
        #expect(try ControlInput.modifiers("cmd+shift") == [.command, .shift])
        #expect(try ControlInput.modifiers("") == [])
    }

    @Test func typingMapsEachCharacterToAKey() {
        let keys = ControlInput.keys(typing: "Hi!\n")
        #expect(keys.map(\.characters) == ["H", "i", "!", "\r"])
        #expect(keys.map(\.keyCode) == [4, 34, 18, 36])
        #expect(keys.map(\.modifiers) == [[.shift], [], [.shift], []])
        // A character with no key on a US layout still goes as itself.
        #expect(ControlInput.keys(typing: "é").first?.characters == "é")
    }

    @Test func clickTakesAButtonAndModifiers() {
        #expect(command("click", ["ref": "e1", "button": "right"])
            == .click(.ref("e1"), clickCount: 1, button: .right, modifiers: [], trusted: true))
        #expect(command("click", ["coordinate": [1, 2], "button": "middle", "modifiers": "cmd+shift", "click_count": 9])
            == .click(.point(x: 1, y: 2), clickCount: 3, button: .middle, modifiers: [.command, .shift], trusted: true))
        #expect(command("click", ["ref": "e1", "trusted": false])
            == .click(.ref("e1"), clickCount: 1, button: .left, modifiers: [], trusted: false))
        if case .failure(let error)? = parse("click", ["ref": "e1", "button": "fourth"]) {
            #expect(error.message.contains("left, right or middle"))
        } else {
            Issue.record("a bad button parsed")
        }
        #expect(command("click", ["ref": "e1", "modifiers": "hyper"]) == nil)
    }

    @Test func hoverAndDragTakeRefsOrCoordinates() {
        #expect(command("hover", ["ref": "e4"]) == .hover(.ref("e4")))
        #expect(command("hover", ["coordinate": [3, 4]]) == .hover(.point(x: 3, y: 4)))
        #expect(command("hover", [:]) == nil)
        #expect(command("drag", ["start_coordinate": [1, 2], "coordinate": [30, 40]])
            == .drag(from: .point(x: 1, y: 2), to: .point(x: 30, y: 40), trusted: true))
        #expect(command("drag", ["ref": "e1", "to_ref": "e2"]) == .drag(from: .ref("e1"), to: .ref("e2"), trusted: true))
        #expect(command("drag", ["ref": "e1"]) == nil)
    }

    @Test func keyRepeatsAndIsCheckedOnTheWayIn() {
        #expect(command("key", ["key": "ArrowDown", "repeat": 3]) == .key("ArrowDown", repeat: 3, trusted: true))
        #expect(command("key", ["key": "Tab", "repeat": 500]) == .key("Tab", repeat: 50, trusted: true))
        #expect(command("key", ["key": "cmd+a Backspace"]) == .key("cmd+a Backspace", repeat: 1, trusted: true))
        #expect(command("key", ["key": "Hyper"]) == nil)
        #expect(command("type", ["text": "x", "trusted": false]) == .type("x", ref: nil, trusted: false))
    }

    @Test func theNewToolsAreListedAndHoverNeverAsks() {
        #expect(ControlTools.names.isSuperset(of: ["hover", "drag"]))
        #expect(!ControlCommand.hover(.ref("e1")).acts)
        #expect(ControlCommand.drag(from: .ref("e1"), to: .ref("e2"), trusted: true).acts)
        #expect(ControlAudit.summary(of: .drag(from: .ref("e1"), to: .point(x: 5, y: 6), trusted: true))
            == "drag e1 to at 5,6")
        #expect(ControlAudit.summary(of: .hover(.ref("e3"))) == "hover e3")
        #expect(ControlAudit.summary(of: .click(.ref("e1"), clickCount: 1, button: .right, modifiers: [], trusted: true))
            == "click e1 right")
    }

    // The gate inspects a drag at both ends: a slider CAPTCHA is pressed at
    // the start, and a drop on "Delete" or "Pay" lands at the end.
    @Test func aDragIsInspectedAtBothEnds() {
        let drag = ControlCommand.drag(from: .ref("e1"), to: .point(x: 10, y: 20))
        #expect(drag.inspections == [["op": "click", "ref": "e1"], ["op": "click", "x": 10.0, "y": 20.0]])
        #expect(ControlCommand.click(.ref("e2"), clickCount: 2, button: .right).inspections == [["op": "click", "ref": "e2"]])
        #expect(ControlCommand.key("Enter", repeat: 3).inspections == [["op": "key", "keys": "Enter"]])
        #expect(ControlCommand.type("hi", ref: nil).inspections == [["op": "type"]])
        #expect(ControlCommand.hover(.ref("e1")).inspections.isEmpty)
    }

    @Test func aFilePickerPointsAtFileUpload() {
        #expect(ControlInput.refusal(routing: "file_upload")?.contains("Use file_upload with its ref") == true)
        #expect(ControlInput.refusal(routing: "form_input")?.contains("form_input") == true)
        #expect(ControlInput.refusal(routing: nil) == nil)
    }
}
