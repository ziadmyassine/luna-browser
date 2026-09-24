import Foundation

/// `batch`: several tool calls in one round trip.
///
/// Not a `ControlCommand`. Each step is decoded and handed to the performer
/// on its own — in the app, `ControlService.perform` and its gate — so every
/// step is stopped, asked about, redacted and logged exactly as if the model
/// had sent it alone. A batch carries no permission of its own to lose.
extension ControlTools {

    static let batchLimit = 20

    static let batch: [JSONValue] = [
        tool("batch", """
        Run up to \(batchLimit) tool calls in order, each exactly as if called alone: a step that needs the \
        user's approval still waits for it. Stops at the first step that fails. A step's ref may be "$N", \
        the first ref in step N's result (steps count from 1). Batches do not nest. \(ControlUntrusted.rule)
        """, [
            "actions": [
                "type": "array",
                "maxItems": .int(batchLimit),
                "items": [
                    "type": "object",
                    "properties": [
                        "tool": ["type": "string"],
                        "args": ["type": "object", "description": "The tool's arguments."]
                    ],
                    "required": ["tool"]
                ]
            ]
        ], required: ["actions"], tabbed: false)
    ]
}

enum ControlBatch {

    typealias Step = (tool: String, args: [String: JSONValue])

    static func run(_ arguments: [String: JSONValue], client: ControlClient, perform: ControlPerformer) async -> ControlResult {
        let steps: [Step]
        switch self.steps(arguments) {
        case let .success(checked): steps = checked
        case let .failure(error): return .error(error.message)
        }
        var content: [ControlResult.Content] = []
        var refs: [String?] = []
        for (index, step) in steps.enumerated() {
            let number = index + 1
            content.append(.text("Step \(number): \(step.tool)"))
            let result: ControlResult
            do {
                let args = try substitute(step.args, refs: refs)
                switch ControlCall.parse(tool: step.tool, arguments: args) {
                case let .success(call)?: result = await perform(call, client)
                case let .failure(error)?: result = .error(error.message)
                case nil: result = .error("Luna has no tool called “\(step.tool)”.")
                }
            } catch {
                result = .error((error as? ControlError)?.message ?? error.localizedDescription)
            }
            content += result.content
            guard !result.isError else {
                let rest = steps.count - number
                content.append(.text("Stopped at step \(number); \(rest == 1 ? "1 step was" : "\(rest) steps were") not run."))
                return ControlResult(content, isError: true)
            }
            refs.append(firstRef(in: result))
        }
        return ControlResult(content)
    }

    /// Every step's tool is checked before any runs, so a typo in the last
    /// step does not leave the first ones done.
    private static func steps(_ arguments: [String: JSONValue]) -> Result<[Step], ControlError> {
        guard case let .array(actions)? = arguments["actions"], !actions.isEmpty else {
            return .failure(ControlError("actions is required: a list of {tool, args}."))
        }
        guard actions.count <= ControlTools.batchLimit else {
            return .failure(ControlError("A batch runs at most \(ControlTools.batchLimit) steps; this one has \(actions.count)."))
        }
        var steps: [Step] = []
        for (index, action) in actions.enumerated() {
            let tool = action["tool"]?.string ?? ""
            if tool == "batch" { return .failure(ControlError("Step \(index + 1) is a batch. Batches do not nest.")) }
            guard ControlTools.names.contains(tool) else {
                return .failure(ControlError("Step \(index + 1): Luna has no tool called “\(tool)”."))
            }
            var args: [String: JSONValue] = [:]
            if case let .object(object)? = action["args"] { args = object }
            steps.append((tool, args))
        }
        return .success(steps)
    }

    /// Only `ref` is substituted: text to type may well be "$1".
    private static func substitute(_ args: [String: JSONValue], refs: [String?]) throws -> [String: JSONValue] {
        guard let raw = args["ref"]?.string, raw.hasPrefix("$"), let step = Int(raw.dropFirst()) else { return args }
        guard step >= 1, step <= refs.count else {
            throw ControlError("ref \(raw) points at a step that has not run yet.")
        }
        guard let ref = refs[step - 1] else { throw ControlError("Step \(step)'s result has no ref for \(raw) to use.") }
        var args = args
        args["ref"] = .string(ref)
        return args
    }

    /// Refs appear as `[e12]` in `read_page` and `find`. The text is the
    /// page's, so a page could plant an earlier "[e3]" and steer "$N" to
    /// another element of its own; the step that uses it is gated regardless.
    private static func firstRef(in result: ControlResult) -> String? {
        for case let .text(text) in result.content {
            if let match = text.firstMatch(of: /\[(e\d+)\]/) { return String(match.1) }
        }
        return nil
    }
}
